import Foundation

// The LocalSend protocol, v2: https://github.com/localsend/protocol
//
// Devices announce themselves to a multicast group; whoever hears one registers back over HTTPS. To send, the sender
// posts the files' names and sizes to `prepare-upload`, the receiver's person accepts or not, and the sender uploads
// each file with the token it got. Over HTTPS a device's fingerprint is the SHA-256 of its certificate, in uppercase
// hex, and that's what each side pins.

public enum LocalSendProtocol {
    public static let version = "2.1"
    public static let port: UInt16 = 53317
    public static let multicastGroup = "224.0.0.167"
    public static let base = "/api/localsend/v2/"
}

/// A device as it describes itself: in an announcement, a register request or answer, and a prepare-upload.
public struct DeviceInfo: Codable, Sendable, Equatable {
    public var alias: String
    public var version: String?
    public var deviceModel: String?
    /// mobile, desktop, web, headless or server.
    public var deviceType: String?
    public var fingerprint: String?
    public var port: UInt16?
    /// http or https.
    public var scheme: String?
    public var download: Bool?
    /// Only in multicast messages: true asks everyone who hears it to answer.
    public var announce: Bool?

    enum CodingKeys: String, CodingKey {
        case alias, version, deviceModel, deviceType, fingerprint, port, download, announce
        case scheme = "protocol"
    }

    public init(alias: String, version: String? = LocalSendProtocol.version, deviceModel: String? = nil, deviceType: String? = nil,
                fingerprint: String?, port: UInt16? = nil, scheme: String? = "https", download: Bool? = false, announce: Bool? = nil) {
        self.alias = alias
        self.version = version
        self.deviceModel = deviceModel
        self.deviceType = deviceType
        self.fingerprint = fingerprint
        self.port = port
        self.scheme = scheme
        self.download = download
        self.announce = announce
    }
}

/// One file offered in a prepare-upload.
public struct FileInfo: Codable, Sendable, Equatable {
    public var id: String
    public var fileName: String
    public var size: Int64
    public var fileType: String
    public var sha256: String?
    /// For a text message, the text itself.
    public var preview: String?

    public init(id: String, fileName: String, size: Int64, fileType: String, sha256: String? = nil, preview: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.size = size
        self.fileType = fileType
        self.sha256 = sha256
        self.preview = preview
    }
}

public struct PrepareUpload: Codable, Sendable, Equatable {
    public var info: DeviceInfo
    public var files: [String: FileInfo]

    public init(info: DeviceInfo, files: [String: FileInfo]) {
        self.info = info
        self.files = files
    }

    /// A message rather than files: one text file whose text came along as its preview. It needs no upload.
    public var message: String? {
        guard files.count == 1, let file = files.values.first, file.fileType.hasPrefix("text/"), let text = file.preview else { return nil }
        return text
    }

    /// Whether every file is well formed: a unique id under its own key, a name, and a size that isn't negative.
    public var isValid: Bool {
        !files.isEmpty && files.allSatisfy { key, file in
            key == file.id && !key.isEmpty && key.count <= 128 && !file.fileName.isEmpty && file.fileName.utf8.count <= 1024 && file.size >= 0
        }
    }
}

public struct PrepareUploadAnswer: Codable, Sendable, Equatable {
    public var sessionId: String
    /// File id to the token its upload must carry.
    public var files: [String: String]

    public init(sessionId: String, files: [String: String]) {
        self.sessionId = sessionId
        self.files = files
    }
}

/// A device found on the network.
public struct Peer: Sendable, Equatable {
    public var fingerprint: String
    public var info: DeviceInfo
    public var host: String
    public var lastSeen: Date

    public init(fingerprint: String, info: DeviceInfo, host: String, lastSeen: Date = Date()) {
        self.fingerprint = fingerprint
        self.info = info
        self.host = host
        self.lastSeen = lastSeen
    }

    public var port: UInt16 { info.port ?? LocalSendProtocol.port }
    public var https: Bool { (info.scheme ?? "https") == "https" }

    /// An SF Symbol for its kind of device.
    public var symbol: String {
        switch info.deviceType {
        case "mobile": "iphone"
        case "web": "globe"
        case "headless", "server": "server.rack"
        default: "desktopcomputer"
        }
    }

    public func url(_ route: String, _ query: [String: String] = [:]) -> URL? {
        var parts = URLComponents()
        parts.scheme = https ? "https" : "http"
        parts.host = host
        parts.port = Int(port)
        parts.path = LocalSendProtocol.base + route
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return parts.url
    }
}

/// The devices heard from lately. Ones not heard from for a while drop off; a device that's still there answers the
/// next announcement.
public struct PeerList: Sendable {
    public private(set) var peers: [String: Peer] = [:]
    public let ownFingerprint: String
    public static let lifetime: TimeInterval = 5 * 60

    public init(ownFingerprint: String) { self.ownFingerprint = ownFingerprint }

    /// Adds or refreshes a device. Returns whether the list as shown changed. Our own announcements are ignored.
    @discardableResult
    public mutating func saw(_ info: DeviceInfo, fingerprint: String?, host: String, at now: Date = Date()) -> Bool {
        guard let fingerprint = (fingerprint ?? info.fingerprint)?.uppercased(), !fingerprint.isEmpty, fingerprint != ownFingerprint.uppercased() else { return false }
        let old = peers[fingerprint]
        peers[fingerprint] = Peer(fingerprint: fingerprint, info: info, host: host, lastSeen: now)
        return old?.info != info || old?.host != host
    }

    /// Drops devices not heard from within `lifetime`. Returns whether any went.
    @discardableResult
    public mutating func expire(now: Date = Date()) -> Bool {
        let before = peers.count
        peers = peers.filter { now.timeIntervalSince($0.value.lastSeen) < Self.lifetime }
        return peers.count != before
    }

    /// Alphabetical, for the menu and the page.
    public var sorted: [Peer] {
        peers.values.sorted { ($0.info.alias.localizedLowercase, $0.fingerprint) < ($1.info.alias.localizedLowercase, $1.fingerprint) }
    }
}
