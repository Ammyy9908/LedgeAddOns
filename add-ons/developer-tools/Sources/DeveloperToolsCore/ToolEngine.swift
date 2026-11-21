import Foundation
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

public enum DeveloperTool: String, CaseIterable, Codable, Sendable {
    case base64, json, hash, uuid, jwt, url, qr
    public var title: String {
        switch self { case .base64: "Base64"; case .json: "JSON"; case .hash: "Hash"; case .uuid: "UUID"; case .jwt: "JWT"; case .url: "URL"; case .qr: "QR code" }
    }
    public var detail: String {
        switch self {
        case .base64: "Encode or decode UTF-8 text"
        case .json: "Format or minify JSON without changing number precision"
        case .hash: "SHA-256, SHA-512 and legacy checksums"
        case .uuid: "Generate a random version 4 identifier"
        case .jwt: "Decode header and payload; does not verify signatures"
        case .url: "Percent-encode or decode a URL component"
        case .qr: "Generate a QR image and send its PNG to the shelf"
        }
    }
    public var symbol: String {
        switch self { case .base64: "textformat.abc"; case .json: "curlybraces"; case .hash: "number"; case .uuid: "number.square"; case .jwt: "key"; case .url: "link"; case .qr: "qrcode" }
    }
    public var operations: [(id: String, title: String)] {
        switch self {
        case .base64, .url: [("encode", "Encode"), ("decode", "Decode")]
        case .json: [("format", "Format"), ("minify", "Minify")]
        case .hash: [("sha256", "SHA-256"), ("sha512", "SHA-512"), ("sha1", "SHA-1"), ("md5", "MD5")]
        case .uuid, .qr: [("generate", "Generate")]
        case .jwt: [("decode", "Decode")]
        }
    }
}

public struct ToolResult: Sendable {
    public var text: String
    public var image: Data?
    public var note: String?
    public init(_ text: String, image: Data? = nil, note: String? = nil) { self.text = text; self.image = image; self.note = note }
}

public struct ToolError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Bounded local processing only. Input is never executed, fetched, logged or saved.
public enum ToolEngine {
    public static let maximumInputBytes = 8_192

    public static func run(_ tool: DeveloperTool, operation: String, input: String) throws -> ToolResult {
        guard input.utf8.count <= maximumInputBytes else { throw ToolError("Input is limited to 8 KB. Use a shorter passage.") }
        guard tool.operations.contains(where: { $0.id == operation }) else { throw ToolError("Choose an operation for this tool.") }
        let result = try process(tool, operation: operation, input: input)
        guard result.text.utf8.count <= 40_000 else { throw ToolError("Result exceeds 40 KB. Use a smaller input or minify the JSON.") }
        return result
    }

    private static func process(_ tool: DeveloperTool, operation: String, input: String) throws -> ToolResult {
        let data = Data(input.utf8)
        switch tool {
        case .base64:
            if operation == "encode" { return ToolResult(data.base64EncodedString()) }
            let cleaned = input.filter { !$0.isWhitespace }
            guard let decoded = Data(base64Encoded: cleaned), let text = String(data: decoded, encoding: .utf8) else {
                throw ToolError("Enter valid Base64 containing UTF-8 text. Binary data cannot be shown as text.")
            }
            return ToolResult(text)
        case .json: return ToolResult(try json(input, pretty: operation == "format"))
        case .hash:
            let text: String
            switch operation {
            case "sha256": text = hex(SHA256.hash(data: data))
            case "sha512": text = hex(SHA512.hash(data: data))
            case "sha1": text = hex(Insecure.SHA1.hash(data: data))
            default: text = hex(Insecure.MD5.hash(data: data))
            }
            return ToolResult(text, note: ["sha1", "md5"].contains(operation) ? "Legacy checksum. Do not use for passwords or security." : nil)
        case .uuid: return ToolResult(UUID().uuidString.lowercased())
        case .jwt: return try jwt(input)
        case .url:
            if operation == "encode" {
                let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
                guard let encoded = input.addingPercentEncoding(withAllowedCharacters: allowed) else { throw ToolError("This text cannot be URL-encoded.") }
                return ToolResult(encoded, note: "Encodes a URL component, including / and ?. Plus signs remain literal when decoding.")
            }
            guard let decoded = input.removingPercentEncoding else { throw ToolError("Enter valid percent-encoded UTF-8 text.") }
            return ToolResult(decoded, note: "Plus signs are literal + characters, not form-encoded spaces.")
        case .qr:
            guard !input.isEmpty, data.count <= 1_800 else { throw ToolError("Enter between 1 and 1,800 UTF-8 bytes for a QR code.") }
            return ToolResult(input, image: try qr(data), note: "Copy text copies the original content. To shelf creates a PNG you can drag anywhere.")
        }
    }

    private static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Validate JSON, then format its original tokens: Foundation number serialization can round large integers.
    private static func json(_ input: String, pretty: Bool) throws -> String {
        let chars = Array(input)
        var depth = 0, quoted = false, escaped = false
        for c in chars {
            if quoted {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true }
            else if c == "{" || c == "[" { depth += 1; if depth > 64 { throw ToolError("JSON nesting is limited to 64 levels.") } }
            else if c == "}" || c == "]" { depth -= 1 }
        }
        do { _ = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]) }
        catch { throw ToolError("Invalid JSON. Check quotes, commas and matching brackets.") }
        var result = "", indent = 0
        quoted = false; escaped = false
        var previous: Character?
        for (index, c) in chars.enumerated() {
            if quoted {
                result.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
                continue
            }
            if c.isWhitespace { continue }
            if c == "\"" { quoted = true; result.append(c) }
            else if c == "{" || c == "[" {
                result.append(c); indent += 1
                if pretty, let next = chars[(index + 1)...].first(where: { !$0.isWhitespace }), next != "}" && next != "]" {
                    result += "\n" + String(repeating: "  ", count: indent)
                }
            } else if c == "}" || c == "]" {
                indent -= 1
                if pretty, previous != "{" && previous != "[" { result += "\n" + String(repeating: "  ", count: max(0, indent)) }
                result.append(c)
            } else if c == "," { result += pretty ? ",\n" + String(repeating: "  ", count: indent) : "," }
            else if c == ":" { result += pretty ? ": " : ":" }
            else { result.append(c) }
            previous = c
        }
        return result
    }

    private static func jwt(_ input: String) throws -> ToolResult {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw ToolError("A JWT has three dot-separated parts. Encrypted tokens are not supported.") }
        func decode(_ part: Substring) throws -> String {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }), part.count % 4 != 1 else {
                throw ToolError("The JWT header or payload is not valid Base64URL.")
            }
            var text = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            text += String(repeating: "=", count: (4 - text.count % 4) % 4)
            guard let bytes = Data(base64Encoded: text), let value = String(data: bytes, encoding: .utf8),
                  (try? JSONSerialization.jsonObject(with: bytes)) is [String: Any] else { throw ToolError("The JWT header and payload must be JSON objects.") }
            return value
        }
        let header = try decode(parts[0]), payload = try decode(parts[1])
        return ToolResult(try json("{\"header\":\(header),\"payload\":\(payload)}", pretty: true), note: "Decoded only. Signature not verified; do not trust these claims for authentication.")
    }

    private static func qr(_ data: Data) throws -> Data {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data; filter.correctionLevel = "M"
        guard let code = filter.outputImage else { throw ToolError("A QR code could not be generated for this content.") }
        let bounds = code.extent.insetBy(dx: -4, dy: -4)
        let background = CIImage(color: .white).cropped(to: bounds)
        let image = code.composited(over: background).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let context = CIContext(options: [.cacheIntermediates: false])
        let output = NSMutableData()
        guard let cg = context.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ToolError("The QR image could not be prepared.")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 32_768 else { throw ToolError("This QR preview is too large. Use shorter text.") }
        return output as Data
    }
}
