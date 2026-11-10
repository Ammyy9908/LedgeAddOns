// Compiles the bridge as one translation unit to exercise the private parser without IPC.
#import <XCTest/XCTest.h>
#import "../../Sources/QueueBridge/QueueBridge.m"

@interface Fixture : NSObject
@property NSDictionary *values;
+ (id)with:(NSDictionary *)values;
@end
@implementation Fixture
+ (id)with:(NSDictionary *)values { Fixture *f = [self new]; f.values = values; return f; }
- (BOOL)respondsToSelector:(SEL)s { return self.values[NSStringFromSelector(s)] != nil || [super respondsToSelector:s]; }
- (id)valueForKey:(NSString *)key { return self.values[key]; }
@end

static id Item(NSString *identifier, NSString *title) {
    return [Fixture with:@{@"identifier":identifier, @"metadata":[Fixture with:@{@"title":title,@"trackArtistName":@"Artist",@"isCurrentlyPlaying":@NO}]}];
}
static id Response(NSArray *items, NSString *current, NSString *source) {
    return [Fixture with:@{
        @"playerPath":[Fixture with:@{@"client":[Fixture with:@{@"bundleIdentifier":source}]}],
        @"playbackQueue":[Fixture with:@{@"contentItems":items,@"nowPlayingInfo":@{@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier":current}}]
    }];
}

@interface QueueParsingTests : XCTestCase
@end
@implementation QueueParsingTests

- (void)testReturnsOnlyFollowingTracks {
    NSArray *items = @[Item(@"past",@"Past"),Item(@"current",@"Current"),Item(@"next",@"Next")];
    NSDictionary *r = Parse(Response(items,@"current",@"com.apple.Music"));
    XCTAssertEqualObjects(r[@"status"], @"available");
    XCTAssertEqual([r[@"entries"] count], 1u);
    XCTAssertEqualObjects(r[@"entries"][0][@"title"], @"Next", @"Identity, not metadata boolean");
    XCTAssertEqual([Parse(Response(items,@"next",@"com.apple.Music"))[@"entries"] count], 0u, @"End of queue");
}

- (void)testRejectsMissingCurrentWrongSourceAndDuplicates {
    NSArray *items = @[Item(@"past",@"Past"),Item(@"current",@"Current"),Item(@"next",@"Next")];
    XCTAssertEqualObjects(Parse(Response(items,@"missing",@"com.apple.Music"))[@"status"], @"unavailable");
    XCTAssertEqualObjects(Parse(Response(items,@"current",@"com.spotify.client"))[@"status"], @"unavailable");
    XCTAssertEqualObjects(Parse(Response(@[Item(@"x",@"One"),Item(@"x",@"Two")],@"x",@"com.apple.Music"))[@"status"], @"unavailable");
}

- (void)testBoundsOutput {
    NSMutableArray *many = [NSMutableArray arrayWithObject:Item(@"current",@"Current")];
    for (int i = 0; i < 30; i++) [many addObject:Item([NSString stringWithFormat:@"%d",i],@"Next")];
    XCTAssertEqual([Parse(Response(many,@"current",@"com.apple.Music"))[@"entries"] count], 12u);
}

- (void)testKeepsOnlyHTTPSArtwork {
    Fixture *artItem = Item(@"next", @"Next");
    NSMutableDictionary *values = [artItem.values mutableCopy];
    values[@"remoteArtworks"] = @{@"MRContentItemArtworkFormatStandard": [Fixture with:@{@"artworkURLString":@"https://example.com/cover.jpg"}]};
    artItem.values = values;
    NSDictionary *art = Parse(Response(@[Item(@"current", @"Current"), artItem], @"current", @"com.apple.Music"));
    XCTAssertEqualObjects(art[@"entries"][0][@"artworkURL"], @"https://example.com/cover.jpg");
    values[@"remoteArtworks"] = @{@"MRContentItemArtworkFormatStandard": [Fixture with:@{@"artworkURLString":@"file:///tmp/private"}]};
    artItem.values = values;
    art = Parse(Response(@[Item(@"current", @"Current"), artItem], @"current", @"com.apple.Music"));
    XCTAssertNil(art[@"entries"][0][@"artworkURL"]);
}

- (void)testRejectsUnsupportedMusicActions {
    XCTAssertEqualObjects(RunMusicAction(@{@"action":@"deleteLibrary"})[@"status"], @"unavailable");
    XCTAssertEqualObjects(RunMusicAction(@{@"action":@"setFavorite"})[@"status"], @"unavailable", @"Missing value");
    XCTAssertEqualObjects(RunMusicAction(@{@"action":@"addToPlaylist", @"name":@""})[@"status"], @"unavailable", @"Empty playlist name");
}

@end
