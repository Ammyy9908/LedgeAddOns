import Foundation

// Just enough HTTP/1.1 for LocalSend's few routes: a request's head, a body by Content-Length or in chunks, and a
// short response. One request per connection; every response closes it.

public struct HTTPRequestHead: Sendable, Equatable {
    public var method: String
    public var path: String
    public var query: [String: String]
    /// Header names in lowercase.
    public var headers: [String: String]

    public static let maximumSize = 16 * 1024

    public enum Body: Sendable, Equatable {
        case none
        case length(Int64)
        case chunked
    }

    public var body: Body {
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { return .chunked }
        if let length = headers["content-length"].flatMap({ Int64($0.trimmingCharacters(in: .whitespaces)) }), length > 0 { return .length(length) }
        return .none
    }

    public enum ParseError: Error { case malformed, tooLarge }

    /// The head at the start of `data` and how many bytes it took, or nil while it hasn't all arrived.
    public static func parse(_ data: Data) throws -> (head: HTTPRequestHead, length: Int)? {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maximumSize { throw ParseError.tooLarge }
            return nil
        }
        let length = end.upperBound - data.startIndex
        guard length <= maximumSize, let text = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { throw ParseError.malformed }
        var lines = text.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard start.count == 3, start[2].hasPrefix("HTTP/1."), let target = URLComponents(string: String(start[1])) else { throw ParseError.malformed }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var query: [String: String] = [:]
        for item in target.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return (HTTPRequestHead(method: String(start[0]), path: target.path, query: query, headers: headers), length)
    }
}

/// Undoes chunked transfer encoding as bytes arrive.
public struct ChunkedDecoder: Sendable {
    private var buffer = Data()
    /// Bytes left in the chunk being read; nil while reading a size line.
    private var remaining: Int?
    private var skipLineEnd = false
    public private(set) var isFinished = false

    public init() {}

    public enum DecodeError: Error { case malformed }

    /// Feeds bytes in and returns the payload they complete.
    public mutating func feed(_ data: Data) throws -> Data {
        buffer.append(data)
        var payload = Data()
        while !isFinished {
            if skipLineEnd {
                guard buffer.count >= 2 else { break }
                guard buffer.prefix(2) == Data("\r\n".utf8) else { throw DecodeError.malformed }
                buffer.removeFirst(2)
                skipLineEnd = false
            }
            if let left = remaining {
                guard !buffer.isEmpty else { break }
                let take = min(left, buffer.count)
                payload.append(buffer.prefix(take))
                buffer.removeFirst(take)
                remaining = left - take == 0 ? nil : left - take
                if remaining == nil { skipLineEnd = true }
                continue
            }
            guard let end = buffer.firstRange(of: Data("\r\n".utf8)) else {
                if buffer.count > 1024 { throw DecodeError.malformed }
                break
            }
            let line = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            guard let size = Int(line.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "", radix: 16),
                  size >= 0 else { throw DecodeError.malformed }
            // The last chunk: trailers, if any, end with an empty line, which is all LocalSend's senders send.
            if size == 0 { isFinished = true } else { remaining = size }
        }
        return payload
    }
}

public enum HTTPResponse {
    public static func make(_ status: Int, json: Data? = nil) -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                      409: "Conflict", 413: "Payload Too Large", 422: "Unprocessable Entity", 429: "Too Many Requests",
                      500: "Internal Server Error"][status] ?? "Status"
        var head = "HTTP/1.1 \(status) \(reason)\r\nConnection: close\r\nContent-Length: \(json?.count ?? 0)\r\n"
        if json != nil { head += "Content-Type: application/json\r\n" }
        var data = Data((head + "\r\n").utf8)
        if let json { data.append(json) }
        return data
    }
}
