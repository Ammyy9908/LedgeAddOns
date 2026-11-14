import Foundation
import LedgeKit

/// Search results from Apple's public song-store catalog endpoint, kept separate from Music's local library IDs.
struct AppleMusicCatalogSong: Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let storefront: String
    let viewURL: String
}

enum AppleMusicCatalog {
    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let kind: String?
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let trackViewUrl: String?
    }

    static func search(_ query: String, storefront: String) async throws -> [AppleMusicCatalogSong] {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else {
            throw AddOnError("Apple Music catalog search is unavailable.")
        }
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: storefront)
        ]
        guard let url = components.url else { throw AddOnError("That catalog search couldn't be formed.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AddOnError("Apple's song catalog couldn't be reached.")
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count <= 1_000_000 else {
            throw AddOnError("Apple's song catalog returned an invalid response.")
        }

        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw AddOnError("Apple's song catalog returned data this add-on couldn't read.")
        }

        return decoded.results.compactMap { result in
            guard result.kind == "song", let trackID = result.trackId, trackID > 0,
                  let title = result.trackName, !title.isEmpty,
                  let artist = result.artistName, !artist.isEmpty,
                  let viewURL = result.trackViewUrl, isSafeMusicURL(viewURL) else { return nil }
            return AppleMusicCatalogSong(
                id: String(trackID),
                title: String(title.prefix(512)),
                artist: String(artist.prefix(512)),
                album: String((result.collectionName ?? "").prefix(512)),
                storefront: storefront,
                viewURL: viewURL
            )
        }.prefix(10).map { $0 }
    }

    static func storefront(_ input: String?) throws -> String {
        let value = (input ?? Locale.current.region?.identifier ?? "US").lowercased()
        guard value.count == 2, value.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw AddOnError("Use a two-letter Apple Music storefront code, such as us or in.")
        }
        return value
    }

    static func isSafeMusicURL(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "music.apple.com" || host == "itunes.apple.com"
    }
}
