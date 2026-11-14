import Foundation
import Testing
import LedgeKit
import SpotifyLikesCore

private func device(_ id: JSONValue = .string("phone"), active: Bool = true, restricted: Bool = false) -> JSONValue {
    .object(["id": id, "name": .string("My iPhone"), "type": .string("Smartphone"),
             "is_active": .bool(active), "is_restricted": .bool(restricted)])
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
            if method == "GET" { return list([device()]) }
            #expect(method == "PUT" && path == "/v1/me/player")
            #expect(body == .object(["device_ids": .array([.string("phone")]), "play": .bool(play)]))
            return HostResponse(status: 204, body: nil)
        }
        var args: [String: JSONValue] = ["device_id": .string("phone")]
        if play { args["play"] = .bool(true) }
        #expect(try await songs.call(ToolCall(tool: "transfer_playback", arguments: args)) == .json(.object([
            "device_id": .string("phone"), "name": .string("My iPhone"), "accepted": .bool(true), "active_confirmed": .bool(true)
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
    let songs = SpotifySongs { method, _, _, _ in
        method == "GET" ? list([device(active: false)]) : HostResponse(status: 204, body: nil)
    }
    let result = try await songs.call(ToolCall(tool: "transfer_playback", arguments: ["device_id": .string("phone")]))
    guard case .json(.object(let fields)) = result else { Issue.record("Expected structured result"); return }
    #expect(fields["active_confirmed"] == .bool(false))
}

@Test func failedTransfersAndMalformedListsAreErrors() async {
    for status in [401, 403, 404, 429, 500] {
        let songs = SpotifySongs { method, _, _, _ in
            method == "GET" ? list([device()]) : HostResponse(status: status, body: nil)
        }
        await #expect(throws: AddOnError.self) { try await songs.call(ToolCall(tool: "transfer_playback", arguments: ["device_id": .string("phone")])) }
    }
    let malformed = SpotifySongs { _, _, _, _ in HostResponse(status: 200, body: .object([:])) }
    await #expect(throws: AddOnError.self) { try await malformed.call(ToolCall(tool: "list_devices")) }
}
