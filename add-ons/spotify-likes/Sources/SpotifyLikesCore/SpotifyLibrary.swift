import Foundation
import LedgeKit

/// Spotify-specific behavior. LedgeKit owns transport; Ledge owns OAuth.
public struct SpotifyLibrary: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.transport = transport
    }

    public func handle(_ request: AddOnRequest) async throws -> AddOnResponse {
        guard request.protocolVersion == 1, ["read", "write"].contains(request.operation),
              !request.trackID.isEmpty, request.trackID.count <= 128,
              request.trackID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !request.accessToken.isEmpty,
              !request.accessToken.contains("\r"), !request.accessToken.contains("\n"),
              request.operation != "write" || request.liked != nil else {
            throw Failure.invalidRequest
        }
        var url = URLComponents(string: "https://api.spotify.com/v1/me/library" +
            (request.operation == "read" ? "/contains" : ""))!
        url.queryItems = [URLQueryItem(name: "uris", value: "spotify:track:" + request.trackID)]
        var http = URLRequest(url: url.url!)
        http.timeoutInterval = 20
        http.httpMethod = request.operation == "read" ? "GET" : (request.liked == true ? "PUT" : "DELETE")
        http.setValue("Bearer " + request.accessToken, forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport(http)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { throw Failure.providerRejected }
        if request.operation == "read" {
            let values = try JSONDecoder().decode([Bool].self, from: data)
            guard values.count == 1 else { throw Failure.invalidResponse }
            return AddOnResponse(value: values[0])
        }
        return AddOnResponse(value: request.liked)
    }

    public enum Failure: Error {
        case invalidRequest, providerRejected, invalidResponse
    }
}
