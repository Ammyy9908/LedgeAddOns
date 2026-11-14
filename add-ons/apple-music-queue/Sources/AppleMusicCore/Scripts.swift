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
      const currentItem = items.objectAtIndex(current);
      const currentMetadata = read(currentItem, 'metadata');
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
      return { status: 'available', entries: entries, currentID: currentID,
        current: { id: currentID, title: text(read(currentMetadata, 'title')) || '',
          artist: (text(read(currentMetadata, 'trackArtistName')) || '').slice(0, 512) } };
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
        if (parsed.currentID === target) return JSON.stringify(Object.assign(parsed, { accepted: true, actionState: 'playing' }));
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
        if (updated && updated.status === 'available' && updated.currentID === target)
          return JSON.stringify(Object.assign(updated, { accepted: true, actionState: 'playing' }));
        if (updated && updated.status === 'available' && updated.entries.length > 0 && updated.entries[0].id === target)
          return JSON.stringify(Object.assign(updated, { accepted: true, actionState: 'queued' }));
        // Music can accept the move before MediaRemote publishes a new queue snapshot, or can start the track so
        // quickly that it has already left the upcoming list. The dispatch returned without an error and this id
        // was present in the validated queue, so report an accepted move instead of a false failure.
        const source = updated && updated.status === 'available' ? updated.entries : parsed.entries;
        const selected = source.find(function (entry) { return entry.id === target; }) || parsed.entries.find(function (entry) { return entry.id === target; });
        if (selected) {
          const entries = [selected].concat(source.filter(function (entry) { return entry.id !== target; }));
          return JSON.stringify({ status: 'available', entries: entries, currentID: parsed.currentID,
            current: parsed.current, accepted: true, actionState: 'queued' });
        }
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

    /// Favorites or unfavorites the current song, matching the Ledge player star and not requiring a library ID.
    static let setCurrentFavorite = #"""
    on cleanText(value)
        set AppleScript's text item delimiters to {tab, return, linefeed}
        set parts to text items of (value as text)
        set AppleScript's text item delimiters to " "
        set resultText to parts as text
        set AppleScript's text item delimiters to ""
        return resultText
    end cleanText
    on run argv
        set wanted to (item 1 of argv) is "true"
        tell application "Music"
            if player state is stopped then error "There is no song playing in Music."
            set targetTrack to current track
            set favorited of targetTrack to wanted
            return my cleanText(name of targetTrack) & tab & my cleanText(artist of targetTrack) & tab & (favorited of targetTrack as text)
        end tell
    end run
    """#

    /// Sets the favorite state of one library track selected by persistent ID and returns its details.
    static let setLibraryFavorite = #"""
    on cleanText(value)
        set AppleScript's text item delimiters to {tab, return, linefeed}
        set parts to text items of (value as text)
        set AppleScript's text item delimiters to " "
        set resultText to parts as text
        set AppleScript's text item delimiters to ""
        return resultText
    end cleanText
    on run argv
        set wantedID to item 1 of argv
        set wantedFavorite to (item 2 of argv) is "true"
        tell application "Music"
            set matches to (every track of library playlist 1 whose persistent ID is wantedID)
            if (count of matches) is not 1 then error "That song is no longer in your library. Search again."
            set targetTrack to item 1 of matches
            set favorited of targetTrack to wantedFavorite
            return (persistent ID of targetTrack) & tab & my cleanText(name of targetTrack) & tab & my cleanText(artist of targetTrack) & tab & (favorited of targetTrack as text)
        end tell
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

    /// Current song details as bounded TSV: persistent ID, title, artist, album, favorite, state, position.
    static let nowPlaying = #"""
    on run
        tell application "Music"
            if player state is stopped then return ""
            set t to current track
            return (persistent ID of t) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (favorited of t as text) & tab & (player state as text) & tab & (player position as text)
        end tell
    end run
    """#

    /// Searches the local library only. Results are bounded and IDs can be passed to playSong/addSongToPlaylist.
    static let searchLibrary = #"""
    on cleanText(value)
        set AppleScript's text item delimiters to {tab, return, linefeed}
        set parts to text items of (value as text)
        set AppleScript's text item delimiters to " "
        set resultText to parts as text
        set AppleScript's text item delimiters to ""
        return resultText
    end cleanText
    on run argv
        set queryText to item 1 of argv
        set output to {}
        tell application "Music"
            set foundTracks to search library playlist 1 for queryText only songs
            repeat with t in foundTracks
                if (count of output) is 10 then exit repeat
                set end of output to (persistent ID of t) & tab & my cleanText(name of t) & tab & my cleanText(artist of t) & tab & my cleanText(album of t)
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return output as text
    end run
    """#

    /// Plays one library track selected by its persistent ID from searchLibrary.
    static let playSong = #"""
    on run argv
        set wantedID to item 1 of argv
        tell application "Music"
            set matches to (every track of library playlist 1 whose persistent ID is wantedID)
            if (count of matches) is not 1 then error "That song is no longer in your library. Search again."
            play item 1 of matches
            return (persistent ID of item 1 of matches) & tab & (name of item 1 of matches) & tab & (artist of item 1 of matches)
        end tell
    end run
    """#

    /// Adds a selected local library track to Playing Next through Music's own Song > Play Next command.
    /// Music's AppleScript dictionary does not expose an add-to-queue command, so the UI command is invoked by
    /// System Events after revealing and selecting the exact track. This requires Accessibility approval.
    static let playLibrarySongNext = #"""
    on run argv
        set wantedID to item 1 of argv
        tell application "Music"
            if player state is stopped then error "Start a song before adding another song to Playing Next."
            set matches to (every track of library playlist 1 whose persistent ID is wantedID)
            if (count of matches) is not 1 then error "That song is no longer in your library. Search again."
            set targetTrack to item 1 of matches
            activate
            reveal targetTrack
            select targetTrack
        end tell
        delay 0.2
        tell application "System Events"
            tell process "Music"
                set frontmost to true
                click menu item "Play Next" of menu 1 of menu bar item "Song" of menu bar 1
            end tell
        end tell
        tell application "Music"
            return (persistent ID of targetTrack) & tab & (name of targetTrack) & tab & (artist of targetTrack)
        end tell
    end run
    """#

    /// Sets and reads back Music's global shuffle mode.
    static let setShuffle = #"""
    on run argv
        set wanted to (item 1 of argv) is "true"
        tell application "Music"
            set shuffle enabled to wanted
            return shuffle enabled as text
        end tell
    end run
    """#

    /// Adds the selected library track to a selected non-smart user playlist.
    static let addSongToPlaylist = #"""
    on run argv
        set wantedTrack to item 1 of argv
        set wantedPlaylist to item 2 of argv
        tell application "Music"
            set targetTracks to (every track of library playlist 1 whose persistent ID is wantedTrack)
            set targetPlaylists to (every user playlist whose persistent ID is wantedPlaylist and smart is false)
            if (count of targetTracks) is not 1 then error "That song is no longer in your library. Search again."
            if (count of targetPlaylists) is not 1 then error "That playlist is no longer available. List playlists again."
            duplicate item 1 of targetTracks to item 1 of targetPlaylists
            return true
        end tell
    end run
    """#

    /// Creates a regular user playlist and returns its persistent ID and name.
    static let createPlaylist = #"""
    on run argv
        set wantedName to item 1 of argv
        tell application "Music"
            set made to make new user playlist with properties {name:wantedName}
            return (persistent ID of made) & tab & (name of made)
        end tell
    end run
    """#

    /// Lists songs in a playlist by its persistent ID. Returns up to 50 tracks as bounded TSV.
    static let listPlaylistSongs = #"""
    on cleanText(value)
        set AppleScript's text item delimiters to {tab, return, linefeed}
        set parts to text items of (value as text)
        set AppleScript's text item delimiters to " "
        set resultText to parts as text
        set AppleScript's text item delimiters to ""
        return resultText
    end cleanText
    on run argv
        set wantedID to item 1 of argv
        set output to {}
        tell application "Music"
            set targetPlaylists to (every user playlist whose persistent ID is wantedID)
            if (count of targetPlaylists) is not 1 then error "That playlist is no longer available. List playlists again."
            set targetPlaylist to item 1 of targetPlaylists
            repeat with t in (every track of targetPlaylist)
                if (count of output) is 50 then exit repeat
                set end of output to (persistent ID of t) & tab & my cleanText(name of t) & tab & my cleanText(artist of t) & tab & my cleanText(album of t)
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return output as text
    end run
    """#
}
