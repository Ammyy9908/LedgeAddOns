import Testing
@testable import LyricsCore

@Test func timedLinesAreSortedAndALineWithTwoStampsAppearsTwice() {
    let lines = LRCLib.parseSynced("[00:12.50] Second\n[00:01.00][01:02.00] Chorus\n\n[00:05.00]   \nNo stamp")
    #expect(lines == [
        LyricLine(time: -1, text: "No stamp"),
        LyricLine(time: 1, text: "Chorus"),
        LyricLine(time: 12.5, text: "Second"),
        LyricLine(time: 62, text: "Chorus")
    ])
}

@Test func aBrokenStampKeepsTheLineAsText() {
    #expect(LRCLib.parseSynced("[ar:Someone] Words") == [LyricLine(time: -1, text: "[ar:Someone] Words")])
}

@Test func plainLyricsAreUsedOnlyWithoutTimedOnes() {
    #expect(LRCLib.lines(from: .init(syncedLyrics: "[00:01.00] Timed", plainLyrics: "Plain")) == [LyricLine(time: 1, text: "Timed")])
    #expect(LRCLib.lines(from: .init(syncedLyrics: "", plainLyrics: "One\n\n Two ")) ==
            [LyricLine(time: -1, text: "One"), LyricLine(time: -1, text: "Two")])
    #expect(LRCLib.lines(from: .init(syncedLyrics: nil, plainLyrics: nil)).isEmpty)
}
