#import "QueueBridge.h"
#import <dlfcn.h>
#import <unistd.h>
@interface NSObject (QueueAPI)
+ (id)localDestination;
+ (id)defaultPlaybackQueueRequestWithRange:(NSRange)range;
- (id)initWithDestination:(id)destination;
- (id)initWithConfiguration:(id)configuration;
- (void)beginLoadingUpdates;
- (void)endLoadingUpdates;
- (void)sendCommand:(unsigned int)command options:(NSDictionary *)options completion:(void (^)(id))completion;
@end
static id Read(id object, NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *e) { return nil; }
}
static NSDictionary *Unavailable(NSString *message) {
    return @{ @"protocolVersion": @1, @"status": @"unavailable", @"message": message, @"entries": @[] };
}
static NSDictionary *Parse(id response) {
    if (![Read(Read(Read(response, @"playerPath"), @"client"), @"bundleIdentifier") isEqual:@"com.apple.Music"])
        return Unavailable(@"Apple Music is not the active media source.");
    id queue = Read(response, @"playbackQueue");
    NSArray *items = Read(queue, @"contentItems");
    NSDictionary *info = Read(queue, @"nowPlayingInfo");
    if (![items isKindOfClass:NSArray.class] || items.count > 100 || ![info isKindOfClass:NSDictionary.class])
        return Unavailable(@"Unsupported queue response.");
    NSString *currentID = info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"];
    if (![currentID isKindOfClass:NSString.class] || currentID.length == 0)
        return Unavailable(@"The queue did not identify the current song.");
    NSInteger current = -1;
    for (NSUInteger i = 0; i < items.count; i++) {
        if ([Read(items[i], @"identifier") isEqual:currentID]) {
            if (current >= 0) return Unavailable(@"Ambiguous current queue item.");
            current = (NSInteger)i;
        }
    }
    if (current < 0) return Unavailable(@"The current song was not present in the returned queue.");
    NSMutableArray *entries = [NSMutableArray array];
    for (NSUInteger i = (NSUInteger)current + 1; i < items.count && entries.count < 12; i++) {
        id metadata = Read(items[i], @"metadata");
        NSString *title = Read(metadata, @"title"), *artist = Read(metadata, @"trackArtistName");
        if (![title isKindOfClass:NSString.class] || title.length == 0 || title.length > 512)
            return Unavailable(@"Queue item metadata is incomplete.");
        if (![artist isKindOfClass:NSString.class]) artist = @"";
        if (artist.length > 512) artist = [artist substringToIndex:512];
        NSMutableDictionary *entry = [@{ @"title": title, @"artist": artist } mutableCopy];
        id identifier = Read(items[i], @"identifier");
        if ([identifier isKindOfClass:NSString.class] && [identifier length] <= 1024) entry[@"id"] = identifier;
        id artworks = Read(items[i], @"remoteArtworks");
        id remote = [artworks isKindOfClass:NSDictionary.class] ? artworks[@"MRContentItemArtworkFormatStandard"] : nil;
        id url = Read(remote, @"artworkURLString");
        if ([url isKindOfClass:NSURL.class]) url = [url absoluteString];
        if ([url isKindOfClass:NSString.class] && [url length] <= 4096 &&
            [[[NSURL URLWithString:url] scheme] isEqual:@"https"])
            entry[@"artworkURL"] = url;
        // Library queue items can advertise artwork without providing remoteArtworks.
        // Preserve the exact catalog identity for the host's artwork fallback.
        id storeID = Read(metadata, @"iTunesStoreIdentifier");
        if (![storeID respondsToSelector:@selector(unsignedLongLongValue)] || [storeID unsignedLongLongValue] == 0)
            storeID = Read(metadata, @"iTunesStoreSubscriptionIdentifier");
        if ([storeID respondsToSelector:@selector(unsignedLongLongValue)] && [storeID unsignedLongLongValue] > 0)
            entry[@"storeID"] = [NSString stringWithFormat:@"%llu", [storeID unsignedLongLongValue]];
        [entries addObject:entry];
    }
    return @{ @"protocolVersion": @1, @"status": @"available", @"message": @"", @"entries": entries };
}
static NSData *RunQueue(NSString *targetID) {
    NSDictionary *result = nil;
    id controller = nil;
    @try {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        Class configClass = NSClassFromString(@"MRNowPlayingControllerConfiguration");
        Class controllerClass = NSClassFromString(@"MRNowPlayingController");
        Class requestClass = NSClassFromString(@"MRPlaybackQueueRequest");
        Class destinationClass = NSClassFromString(@"MRDestination");
        if (!configClass || !controllerClass ||
            ![requestClass respondsToSelector:@selector(defaultPlaybackQueueRequestWithRange:)] ||
            ![destinationClass respondsToSelector:@selector(localDestination)]) {
            result = Unavailable(@"This macOS version does not expose the queue adapter.");
        } else {
            id config = [[configClass alloc] initWithDestination:[destinationClass localDestination]];
            [config setValue:@YES forKey:@"requestPlaybackQueue"];
            [config setValue:@YES forKey:@"requestSupportedCommands"];
            id request = [requestClass defaultPlaybackQueueRequestWithRange:NSMakeRange(0, 20)];
            if ([request respondsToSelector:NSSelectorFromString(@"setRequestedRemoteArtworkFormats:")])
                [request setValue:@[@"MRContentItemArtworkFormatStandard"] forKey:@"requestedRemoteArtworkFormats"];
            [config setValue:request forKey:@"playbackQueueRequest"];
            controller = [[controllerClass alloc] initWithConfiguration:config];
            [controller beginLoadingUpdates];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            id response;
            while (!(response = Read(controller, @"response")) && !Read(controller, @"lastError") && deadline.timeIntervalSinceNow > 0)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            if (response && targetID) {
                NSDictionary *parsed = Parse(response);
                NSArray *entries = parsed[@"entries"];
                BOOL found = NO, supported = NO;
                for (NSDictionary *entry in entries) if ([entry[@"id"] isEqual:targetID]) found = YES;
                for (id command in Read(response, @"supportedCommands"))
                    if ([Read(command, @"command") unsignedIntValue] == 130 && [Read(command, @"isEnabled") boolValue]) supported = YES;
                NSString *currentID = Read(Read(response, @"playbackQueue"), @"nowPlayingInfo")[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"];
                if (!found || !supported || !currentID) {
                    result = Unavailable(@"The song is no longer upcoming or queue editing is unavailable.");
                } else {
                    __block BOOL finished = NO;
                    [controller sendCommand:130 options:@{@"kMRMediaRemoteOptionContentItemID":targetID,
                        @"kMRMediaRemoteOptionInsertAfterContentItemID":currentID} completion:^(id reply) { finished = YES; }];
                    NSDate *actionDeadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
                    while (actionDeadline.timeIntervalSinceNow > 0) {
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                        NSDictionary *updated = Parse(Read(controller, @"response"));
                        if (finished && [updated[@"entries"] count] && [updated[@"entries"][0][@"id"] isEqual:targetID]) {
                            result = updated; break;
                        }
                    }
                    if (!result) result = Unavailable(@"Apple Music did not confirm the queue change. Refresh and try again.");
                }
            } else result = response ? Parse(response) : Unavailable(@"The system queue is unavailable. Check that Apple Music is playing.");
        }
    } @catch (NSException *e) {
        result = Unavailable(@"The system queue adapter is incompatible with this macOS version.");
    } @finally {
        if ([controller respondsToSelector:@selector(endLoadingUpdates)]) [controller endLoadingUpdates];
    }
    return [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

// Apple Music-specific automation belongs to the installed adapter.
static NSDictionary *RunMusicAction(NSDictionary *request) {
    NSString *action = request[@"action"], *script = nil;
    if ([action isEqual:@"readFavorite"]) script = @"tell application \"Music\" to get favorited of current track";
    else if ([action isEqual:@"setFavorite"] && [request[@"value"] isKindOfClass:NSNumber.class])
        script = [NSString stringWithFormat:@"tell application \"Music\"\nset favorited of current track to %@\nreturn %@\nend tell", [request[@"value"] boolValue] ? @"true" : @"false", [request[@"value"] boolValue] ? @"true" : @"false"];
    else if ([action isEqual:@"toggleShuffle"]) script = @"tell application \"Music\"\nset shuffle enabled to not shuffle enabled\nreturn true\nend tell";
    else if ([action isEqual:@"toggleRepeat"]) script = @"tell application \"Music\"\nif song repeat is off then\nset song repeat to all\nelse\nset song repeat to off\nend if\nreturn true\nend tell";
    else if ([action isEqual:@"playlists"]) script = @"tell application \"Music\" to get name of every user playlist";
    else if ([action isEqual:@"addToPlaylist"] && [request[@"name"] isKindOfClass:NSString.class] && [request[@"name"] length] > 0 && [request[@"name"] length] <= 512) {
        NSString *name = [request[@"name"] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        name = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        script = [NSString stringWithFormat:@"tell application \"Music\"\nduplicate current track to user playlist \"%@\"\nreturn true\nend tell", name];
    }
    if (!script) return Unavailable(@"Unsupported Music action.");
    NSDictionary *error = nil;
    NSAppleEventDescriptor *answer = [[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&error];
    if (error || !answer) return Unavailable(@"Apple Music could not complete the action. Check Automation permission.");
    NSMutableDictionary *result = [@{@"protocolVersion":@1, @"status":@"available", @"message":@"", @"entries":@[]} mutableCopy];
    if ([action isEqual:@"playlists"]) {
        NSMutableArray *names = [NSMutableArray array];
        for (NSInteger i = 1; i <= answer.numberOfItems && i <= 500; i++) {
            NSString *name = [answer descriptorAtIndex:i].stringValue;
            if (name.length && name.length <= 512) [names addObject:name];
        }
        result[@"playlists"] = names;
    } else result[@"value"] = (answer.booleanValue ? @YES : @NO);
    return result;
}

NSData *LedgeReadMusicQueue(void) { return RunQueue(nil); }

// Called once by the host's Perl loader. Exit instead of returning through the
// Perl XS ABI. Input and output retain the same bounded JSON protocol.
__attribute__((visibility("default"))) void LedgeQueueMain(void) {
    @autoreleasepool {
        char bytes[4097]; size_t count = fread(bytes, 1, sizeof(bytes), stdin);
        if (count == sizeof(bytes) || ferror(stdin)) exit(1);
        NSData *data = [NSData dataWithBytes:bytes length:count];
        id request = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![request isKindOfClass:NSDictionary.class] ||
            ![request[@"protocolVersion"] isEqual:@1] || ![@[@"readQueue", @"playNext", @"readFavorite", @"setFavorite", @"toggleShuffle", @"toggleRepeat", @"playlists", @"addToPlaylist"] containsObject:request[@"action"]]) exit(1);
        NSString *target = [request[@"action"] isEqual:@"playNext"] ? request[@"id"] : nil;
        if ([request[@"action"] isEqual:@"playNext"] && (![target isKindOfClass:NSString.class] || target.length == 0 || target.length > 1024)) exit(1);
        NSData *response = [@[@"readQueue", @"playNext"] containsObject:request[@"action"]] ? RunQueue(target) : [NSJSONSerialization dataWithJSONObject:RunMusicAction(request) options:0 error:nil];
        if (!response || response.length > 65536) exit(1);
        fwrite(response.bytes, 1, response.length, stdout);
        fflush(stdout);
        exit(0);
    }
}
