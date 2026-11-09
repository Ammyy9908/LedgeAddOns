import Foundation
import Testing
import LedgeKit
import SpotifyLikesCore

@Test func readsLikedState() async throws {
    let library = SpotifyLibrary { http in
        #expect(http.httpMethod == "GET")
        #expect(http.url?.path == "/v1/me/library/contains")
        #expect(URLComponents(url: http.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "spotify:track:abc123")
        #expect(http.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        return (Data("[true]".utf8), HTTPURLResponse(url: http.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let response = try await library.handle(.init(operation: "read", trackID: "abc123", liked: nil, accessToken: "fixture"))
    #expect(response.value == true)
}

@Test func likesAndUnlikes() async throws {
    for liked in [true, false] {
        let library = SpotifyLibrary { http in
            #expect(http.httpMethod == (liked ? "PUT" : "DELETE"))
            #expect(http.url?.path == "/v1/me/library")
            #expect(http.httpBody == nil)
            return (Data(), HTTPURLResponse(url: http.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let response = try await library.handle(.init(operation: "write", trackID: "abc123", liked: liked, accessToken: "fixture"))
        #expect(response.value == liked)
    }
}

@Test func rejectsInvalidInputBeforeNetworking() async {
    let library = SpotifyLibrary { _ in
        Issue.record("Invalid request reached network")
        throw SpotifyLibrary.Failure.invalidRequest
    }
    for request in [
        AddOnRequest(operation: "read", trackID: "١", liked: nil, accessToken: "fixture"),
        AddOnRequest(operation: "write", trackID: "abc", liked: nil, accessToken: "fixture"),
        AddOnRequest(operation: "read", trackID: "abc", liked: nil, accessToken: ""),
        AddOnRequest(operation: "delete", trackID: "abc", liked: nil, accessToken: "fixture")
    ] {
        do { _ = try await library.handle(request); Issue.record("Expected rejection") }
        catch {}
    }
}

@Test func rejectsProviderFailuresAndMalformedResponses() async {
    for (status, body) in [(401, "{}"), (403, "{}"), (429, "{}"), (200, "[]"), (200, "[true,false]"), (200, "{}")] {
        let library = SpotifyLibrary { http in
            (Data(body.utf8), HTTPURLResponse(url: http.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await library.handle(.init(operation: "read", trackID: "abc", liked: nil, accessToken: "fixture"))
            Issue.record("Expected provider failure")
        } catch {}
    }
}
