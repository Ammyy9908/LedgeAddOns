import Foundation
import Testing
import LedgeKit
import SpotifyLikesCore

private actor Calls {
    var all: [String] = []
    func add(_ call: String) { all.append(call) }
}

@Test func readsLikedStateThroughLedge() async throws {
    let calls = Calls()
    let library = SpotifyLibrary { method, path, query in
        await calls.add("\(method) \(path) \(query["uris"] ?? "")")
        return HostResponse(status: 200, body: .array([.bool(true)]))
    }
    #expect(try await library.isLiked("abc123"))
    #expect(await calls.all == ["GET /v1/me/library/contains spotify:track:abc123"])
}

@Test func likesAndUnlikesThroughLedge() async throws {
    for liked in [true, false] {
        let calls = Calls()
        let library = SpotifyLibrary { method, path, _ in
            await calls.add("\(method) \(path)")
            return HostResponse(status: 200, body: nil)
        }
        #expect(try await library.setLiked(liked, trackID: "abc123") == liked)
        #expect(await calls.all == ["\(liked ? "PUT" : "DELETE") /v1/me/library"])
    }
}

@Test func refusalsAndBadInputBecomeReadableErrors() async {
    let notConnected = SpotifyLibrary { _, _, _ in throw LedgeHostError("Spotify isn't connected.") }
    do {
        _ = try await notConnected.isLiked("abc123")
        Issue.record("Expected a refusal")
    } catch let error as AddOnError {
        #expect(error.message == "Spotify isn't connected.")
    } catch { Issue.record("Unexpected \(error)") }

    let rejected = SpotifyLibrary { _, _, _ in HostResponse(status: 401, body: nil) }
    await #expect(throws: AddOnError.self) { _ = try await rejected.isLiked("abc123") }
    let never = SpotifyLibrary { _, _, _ in Issue.record("Bad input reached Ledge"); return HostResponse(status: 200, body: nil) }
    await #expect(throws: AddOnError.self) { _ = try await never.isLiked("../../me") }
}
