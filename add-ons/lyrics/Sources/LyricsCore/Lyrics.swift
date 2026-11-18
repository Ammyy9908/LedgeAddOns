import Foundation

/// What Ledge sends with the `lyrics` request: the playing song.
public struct LyricsRequest: Codable, Sendable {
    public var title: String
    public var artist: String
}

/// One line of lyrics. `time` is where it starts, in seconds, or -1 when the lyrics aren't timed.
public struct LyricLine: Codable, Sendable, Equatable {
    public var time: Double
    public var text: String
    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

/// Lyrics from LRCLIB (lrclib.net), a free, open database of timed lyrics. Only the title and artist are sent.
public enum LRCLib {
    /// Timed lyrics when LRCLIB has them, else plain ones, else none.
    public static func lines(title: String, artist: String) async throws -> [LyricLine] {
        var parts = URLComponents(string: "https://lrclib.net/api/get")!
        parts.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        var request = URLRequest(url: parts.url!, timeoutInterval: 8)
        request.setValue("Ledge Lyrics add-on (https://github.com/Ammyy9908/LedgeAddOns)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return lines(from: try JSONDecoder().decode(Payload.self, from: data))
    }

    struct Payload: Decodable {
        var syncedLyrics: String?
        var plainLyrics: String?
    }

    static func lines(from payload: Payload) -> [LyricLine] {
        if let synced = payload.syncedLyrics, !synced.isEmpty { return parseSynced(synced) }
        return (payload.plainLyrics ?? "").split(separator: "\n")
            .map { LyricLine(time: -1, text: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }
    }

    /// `[mm:ss.xx] words`, including a line that carries more than one stamp.
    public static func parseSynced(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let end = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<end].split(separator: ":")
                guard stamp.count >= 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { break }
                times.append(minutes * 60 + seconds)
                rest = rest[rest.index(after: end)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            guard !words.isEmpty else { continue }
            lines += times.isEmpty ? [LyricLine(time: -1, text: words)] : times.map { LyricLine(time: $0, text: words) }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
