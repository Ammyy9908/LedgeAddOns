/// The programs this add-on runs with `/usr/bin/osascript`. They're fixed text; anything that varies (a song or
/// playlist id) is passed as an argument, never written into a script.
enum Scripts {
    /// Reads Playing Next through MediaRemote, and with an argument plays that upcoming song next first.
    ///
    /// macOS answers queue requests only from Apple's own programs, so this runs in `osascript` rather than in the
    /// add-on. It asks for 20 items, checks that Music is the source, finds the playing song by the id in the same
    /// answer, and returns up to 12 songs after it. It never falls back to playlist order. Prints JSON:
    /// `{"status": "available", "entries": [...]}` or `{"status": "unavailable", "message": "..."}`.
    static let queue = #"""
    ObjC.import('Foundation');
    function read(object, key) {
      if (!object || object.isNil()) return null;
      try {
        if (!object.respondsToSelector($.NSSelectorFromString(key))) return null;
        const value = object.valueForKey(key);
        return value.isNil() ? null : value;
      } catch (e) { return null; }
    }
    function text(value) {
      if (!value || value.isNil() || !value.isKindOfClass($.NSString)) return null;
      return ObjC.unwrap(value);
    }
    function number(value) {
      if (!value || value.isNil() || !value.isKindOfClass($.NSNumber)) return 0;
      return ObjC.unwrap(value);
    }
    function unavailable(message) { return { status: 'unavailable', message: message, entries: [] }; }
    function parse(response) {
      if (text(read(read(read(response, 'playerPath'), 'client'), 'bundleIdentifier')) !== 'com.apple.Music')
        return unavailable('Apple Music isn’t the app playing right now.');
      const queue = read(response, 'playbackQueue');
      const items = read(queue, 'contentItems');
      const info = read(queue, 'nowPlayingInfo');
      if (!items || !items.isKindOfClass($.NSArray) || items.count > 100 || !info || !info.isKindOfClass($.NSDictionary))
        return unavailable('Music answered in a way this add-on doesn’t understand.');
      const currentID = text(info.objectForKey('kMRMediaRemoteNowPlayingInfoContentItemIdentifier'));
      if (!currentID) return unavailable('Music didn’t say which song is playing.');
      let current = -1;
      for (let i = 0; i < items.count; i++) {
        if (text(read(items.objectAtIndex(i), 'identifier')) === currentID) {
          if (current >= 0) return unavailable('Music listed the playing song twice.');
          current = i;
        }
      }
      if (current < 0) return unavailable('The playing song wasn’t in Music’s queue.');
      const entries = [];
      for (let i = current + 1; i < items.count && entries.length < 12; i++) {
        const item = items.objectAtIndex(i);
        const metadata = read(item, 'metadata');
        const title = text(read(metadata, 'title'));
        if (!title || title.length > 512) return unavailable('A song in Playing Next has no title.');
        const entry = { title: title, artist: (text(read(metadata, 'trackArtistName')) || '').slice(0, 512) };
        const id = text(read(item, 'identifier'));
        if (id && id.length <= 1024) entry.id = id;
        const artworks = read(item, 'remoteArtworks');
        const remote = artworks && artworks.isKindOfClass($.NSDictionary) ? artworks.objectForKey('MRContentItemArtworkFormatStandard') : null;
        let url = read(remote, 'artworkURLString');
        if (url && url.isKindOfClass($.NSURL)) url = url.absoluteString;
        url = text(url);
        if (url && url.length <= 4096 && url.startsWith('https://')) entry.artworkURL = url;
        // Library songs can have artwork without remote artworks; the store id lets Ledge find it.
        let store = number(read(metadata, 'iTunesStoreIdentifier'));
        if (!store) store = number(read(metadata, 'iTunesStoreSubscriptionIdentifier'));
        if (store > 0) entry.storeID = String(store);
        entries.push(entry);
      }
      return { status: 'available', entries: entries, currentID: currentID };
    }
    function wait(seconds, done) {
      const deadline = $.NSDate.dateWithTimeIntervalSinceNow(seconds);
      while (deadline.timeIntervalSinceNow > 0) {
        if (done()) return true;
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.05));
      }
      return done();
    }
    function run(argv) {
      const target = argv.length > 0 ? argv[0] : null;
      let controller = null;
      try {
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework').load;
        const Configuration = $.NSClassFromString('MRNowPlayingControllerConfiguration');
        const Controller = $.NSClassFromString('MRNowPlayingController');
        const Request = $.NSClassFromString('MRPlaybackQueueRequest');
        const Destination = $.NSClassFromString('MRDestination');
        if (!Configuration || Configuration.isNil() || !Controller || Controller.isNil() || !Request || Request.isNil() || !Destination || Destination.isNil())
          return JSON.stringify(unavailable('This version of macOS doesn’t share Music’s queue.'));
        const configuration = Configuration.alloc.initWithDestination(Destination.localDestination);
        configuration.setValueForKey($.NSNumber.numberWithBool(true), 'requestPlaybackQueue');
        configuration.setValueForKey($.NSNumber.numberWithBool(true), 'requestSupportedCommands');
        const request = Request.defaultPlaybackQueueRequestWithRange($.NSMakeRange(0, 20));
        if (request.respondsToSelector($.NSSelectorFromString('setRequestedRemoteArtworkFormats:')))
          request.setValueForKey($(['MRContentItemArtworkFormatStandard']), 'requestedRemoteArtworkFormats');
        configuration.setValueForKey(request, 'playbackQueueRequest');
        controller = Controller.alloc.initWithConfiguration(configuration);
        controller.beginLoadingUpdates;
        wait(5, function () { return read(controller, 'response') || read(controller, 'lastError'); });
        const response = read(controller, 'response');
        if (!response) return JSON.stringify(unavailable('Music’s queue isn’t available. Check that Apple Music is playing.'));
        const parsed = parse(response);
        if (!target || parsed.status !== 'available') return JSON.stringify(parsed);
        // Play next: only a song that's upcoming now, and only when Music offers the command (130).
        const commands = read(response, 'supportedCommands');
        let supported = false;
        for (let i = 0; commands && i < commands.count; i++) {
          const command = commands.objectAtIndex(i);
          if (number(read(command, 'command')) === 130 && number(read(command, 'isEnabled'))) supported = true;
        }
        if (!supported || !parsed.entries.some(function (entry) { return entry.id === target; }))
          return JSON.stringify(unavailable('That song isn’t upcoming any more, or Music can’t reorder Playing Next now.'));
        let finished = false;
        controller.sendCommandOptionsCompletion(130, $({
          kMRMediaRemoteOptionContentItemID: target,
          kMRMediaRemoteOptionInsertAfterContentItemID: parsed.currentID
        }), function (reply) { finished = true; });
        let updated = null;
        wait(1.5, function () {
          const now = read(controller, 'response');
          updated = now ? parse(now) : null;
          return finished && updated && updated.status === 'available' && updated.entries.length > 0 && updated.entries[0].id === target;
        });
        if (finished && updated && updated.entries.length > 0 && updated.entries[0].id === target) return JSON.stringify(updated);
        return JSON.stringify(unavailable('Music didn’t confirm the change. Refresh and try again.'));
      } catch (e) {
        return JSON.stringify(unavailable('Music’s queue isn’t available on this version of macOS.'));
      } finally {
        if (controller && controller.respondsToSelector($.NSSelectorFromString('endLoadingUpdates'))) controller.endLoadingUpdates;
      }
    }
    """#

    /// Whether the playing song is a favourite: prints true or false.
    static let readFavorite = #"tell application "Music" to return favorited of current track"#

    /// Favourites or unfavourites the playing song: the first argument is "true" or "false".
    static let setFavorite = #"""
    on run argv
        set wanted to (item 1 of argv) is "true"
        tell application "Music" to set favorited of current track to wanted
        return wanted
    end run
    """#

    /// The user's playlists, one per line: persistent id, a tab, the name.
    static let playlists = #"""
    set output to {}
    tell application "Music"
        repeat with aPlaylist in (every user playlist whose smart is false)
            set end of output to (persistent ID of aPlaylist) & tab & (name of aPlaylist)
        end repeat
    end tell
    set AppleScript's text item delimiters to linefeed
    return output as text
    """#

    /// Adds the playing song to the playlist whose persistent id is the first argument.
    static let addToPlaylist = #"""
    on run argv
        tell application "Music"
            set target to first user playlist whose persistent ID is (item 1 of argv)
            duplicate current track to target
        end tell
        return true
    end run
    """#
}
