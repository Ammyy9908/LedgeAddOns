import Testing
@testable import AudioControlCore

@Test func theMiddleOfTheSliderIsAboutHalfAsLoud() {
    #expect(Mixer.gain(0) == 0)
    #expect(Mixer.gain(0.5) == 0.25)
    #expect(Mixer.gain(1) == 1)
    #expect(Mixer.gain(2) == 4)
    #expect(Mixer.gain(3) == 4)
    #expect(Mixer.gain(0.5, curve: .linear) == 0.5)
    #expect(Mixer.gain(2, curve: .linear) == 2)
    #expect(Mixer.isFull(1) && Mixer.isFull(1.004) && !Mixer.isFull(0.99) && !Mixer.isFull(1.2))
    #expect(Mixer.gain(-1) == 0)
}

@Test func aHelperPlaysForTheAppItBelongsTo() {
    let apps = ["com.google.Chrome", "com.google.Chrome.canary", "com.spotify.client"]
    #expect(Mixer.owner(of: "com.google.Chrome.helper", among: apps) == "com.google.Chrome")
    #expect(Mixer.owner(of: "com.google.Chrome.canary.helper", among: apps) == "com.google.Chrome.canary")
    #expect(Mixer.owner(of: "com.spotify.client", among: apps) == "com.spotify.client")
    // A shared start of a name isn't ownership.
    #expect(Mixer.owner(of: "com.spotify.clientele", among: apps) == nil)
    #expect(Mixer.owner(of: "com.apple.WebKit.WebContent", among: apps) == nil)
}

@Test func copyingRampsTheGainAndSpreadsStereoOverEveryChannel() {
    let input: [Float] = [1, -1, 1, -1]  // two stereo frames
    var output = [Float](repeating: 9, count: 12)  // three frames of four channels
    input.withUnsafeBufferPointer { inBuffer in
        output.withUnsafeMutableBufferPointer { outBuffer in
            Mixer.copy(inBuffer.baseAddress!, channels: 2, frames: 2, into: outBuffer.baseAddress!, channels: 4, frames: 3,
                       from: 0, to: 0.75)
        }
    }
    #expect(output == [0.25, -0.25, 0.25, -0.25,  0.5, -0.5, 0.5, -0.5,  0, 0, 0, 0])
}

@Test func aBoostStaysWithinFullScale() {
    let input: [Float] = [0.8, -0.8]
    var output = [Float](repeating: 0, count: 2)
    input.withUnsafeBufferPointer { inBuffer in
        output.withUnsafeMutableBufferPointer { outBuffer in
            Mixer.copy(inBuffer.baseAddress!, channels: 2, frames: 1, into: outBuffer.baseAddress!, channels: 2, frames: 1,
                       from: 4, to: 4)
        }
    }
    #expect(output == [1, -1])
}

@Test func aPreferredDeviceTakesOverOnlyWhenOneConnects() {
    let ranking = ["airpods", "studio", "speakers"]
    // AirPods connect while the Mac plays to its speakers: switch to them.
    #expect(Preferred.switchTo(ranking: ranking, connected: ["airpods", "speakers"], appeared: ["airpods"], current: "speakers") == "airpods")
    // The studio monitors connect while AirPods, ranked higher, are on: stay.
    #expect(Preferred.switchTo(ranking: ranking, connected: ["airpods", "studio"], appeared: ["studio"], current: "airpods") == nil)
    // Nothing connected: a device picked by hand stays.
    #expect(Preferred.switchTo(ranking: ranking, connected: ["airpods", "speakers"], appeared: [], current: "speakers") == nil)
    // A device not on the list connecting changes nothing.
    #expect(Preferred.switchTo(ranking: ranking, connected: ["speakers", "tv"], appeared: ["tv"], current: "tv") == nil)
}
