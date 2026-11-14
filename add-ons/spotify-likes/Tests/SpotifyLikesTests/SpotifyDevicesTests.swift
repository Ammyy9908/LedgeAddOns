import Foundation
import Testing
import LedgeKit
import SpotifyLikesCore

private func device(_ id: JSONValue = .string("phone"), active: Bool = true, restricted: Bool = false) -> JSONValue {
    .object(["id": id, "name": .string("My iPhone"), "type": .string("Smartphone"),
             "is_active": .bool(active), "is_restricted": .bool(restricted)])
}
private func state(playing: Bool, id: String = "phone") -> HostResponse {
    HostResponse(status: 200, body: .object(["device": .object(["id": .string(id)]), "is_playing": .bool(playing)]))
}
private func list(_ items: [JSONValue]) -> HostResponse {
    HostResponse(status: 200, body: .object(["devices": .array(items)]))
}

@Test func deviceListingDoesNotChangePlaybackAndKeepsUnaddressableDevices() async throws {
    let songs = SpotifySongs { method, path, query, body in
        #expect(method == "GET" && path == "/v1/me/player/devices")
        #expect(query.isEmpty && body == nil)
        return list([device(.null)])
    }
    #expect(try await songs.call(ToolCall(tool: "list_devices")) == .json(.object(["devices": .array([device(.null)])])))
}

@Test func transferPreservesPlaybackUnlessExplicitlyAskedToPlay() async throws {
    for play in [false, true] {
        let songs = SpotifySongs { method, path, _, body in
            if method == "GET" { return path == "/v1/me/player" ? state(playing: play) : list([device()]) }
            #expect(method == "PUT" && path == "/v1/me/player")
            #expect(body == .object(["device_ids": .array([.string("phone")]), "play": .bool(play)]))
            return HostResponse(status: 204, body: nil)
        }
        var args: [String: JSONValue] = ["device_id": .string("phone")]
        if play { args["play"] = .bool(true) }
        #expect(try await songs.call(ToolCall(tool: "transfer_playback", arguments: args)) == .json(.object([
            "device_id": .string("phone"), "name": .string("My iPhone"), "accepted": .bool(true), "active_confirmed": .bool(true), "requested_playing": .bool(play), "playing": .bool(play), "playback_confirmed": .bool(true)
        ])))
    }
}

@Test func unavailableAndRestrictedDevicesNeverReceiveTransfer() async {
    for items in [[], [device(restricted: true)], [device(.null)]] {
        let songs = SpotifySongs { method, _, _, _ in
            #expect(method == "GET")
            return list(items)
        }
        await #expect(throws: AddOnError.self) {
            try await songs.call(ToolCall(tool: "transfer_playback", arguments: ["device_id": .string("phone")]))
        }
    }
}

@Test func acceptedTransferIsNotReportedAsConfirmedWithoutActiveDestination() async throws {
    let songs = SpotifySongs { method, path, _, _ in
        if path == "/v1/me/player" && method == "GET" { return state(playing: false, id: "other") }
        return method == "GET" ? list([device(active: false)]) : HostResponse(status: 204, body: nil)
    }
    let result = try await songs.call(ToolCall(tool: "transfer_playback", arguments: ["device_id": .string("phone")]))
    guard case .json(.object(let fields)) = result else { Issue.record("Expected structured result"); return }
    #expect(fields["active_confirmed"] == .bool(false))
}

@Test func failedTransfersAndMalformedListsAreErrors() async {
    for status in [401, 403, 404, 429, 500] {
        let songs = SpotifySongs { method, path, _, _ in
            if path == "/v1/me/player" && method == "GET" { return state(playing: false) }
            return method == "GET" ? list([device()]) : HostResponse(status: status, body: nil)
        }
        await #expect(throws: AddOnError.self) { try await songs.call(ToolCall(tool: "transfer_playback", arguments: ["device_id": .string("phone")])) }
    }
    let malformed = SpotifySongs { _, _, _, _ in HostResponse(status: 200, body: .object([:])) }
    await #expect(throws: AddOnError.self) { try await malformed.call(ToolCall(tool: "list_devices")) }
}


private actor PausingTransfer {
    var transferred = false
    var resumed = false
    let resumeWorks: Bool
    init(resumeWorks: Bool) { self.resumeWorks = resumeWorks }
    func request(_ method: String, _ path: String, _ query: [String: String], _ body: JSONValue?) -> HostResponse {
        if path == "/v1/me/player/devices" { return list([device()]) }
        if method == "GET" {
            return state(playing: !transferred || (resumed && resumeWorks), id: transferred ? "phone" : "mac")
        }
        if path == "/v1/me/player" {
            #expect(body == .object(["device_ids": .array([.string("phone")]), "play": .bool(true)]))
            transferred = true
        } else {
            #expect(transferred)
            #expect(path == "/v1/me/player/play" && query == ["device_id": "phone"] && body == nil)
            resumed = true
        }
        return HostResponse(status: 204, body: nil)
    }
}

@Test func pausedDestinationGetsTargetedResumeAndPlayingStateIsVerified() async throws {
    for resumeWorks in [true, false] {
        let api = PausingTransfer(resumeWorks: resumeWorks)
        let songs = SpotifySongs { method, path, query, body in await api.request(method, path, query, body) }
        let result = try await songs.call(ToolCall(tool: "transfer_playback", arguments: ["device_id": .string("phone")]))
        guard case .json(.object(let fields)) = result else { Issue.record("Expected result"); return }
        #expect(await api.resumed)
        #expect(fields["active_confirmed"] == .bool(true))
        #expect(fields["playing"] == .bool(resumeWorks))
        #expect(fields["playback_confirmed"] == .bool(resumeWorks))
    }
}
