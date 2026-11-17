import CryptoKit
import Foundation
import LedgeKit
import LocalSendCore
import UniformTypeIdentifiers

// LocalSend: send files to phones and computers nearby that run LocalSend, and receive from them, without a cloud.
//
// The Mac announces itself on the local network and answers other devices' announcements (Multicast). Devices
// that answer show as rows on the add-on's notch page and under "Send with LocalSend" on shelf items; files
// dropped on a row or chosen from the menu go to that device over HTTPS (Client). Other devices send to this Mac's
// server (Server): the person accepts each transfer in the notch, the files land in the folder they chose, and on
// the shelf.

/// Runs work that starts outside the session, in a network callback, inside it: LedgeKit finds its session through
/// a task-local value, which only tasks started from the session's own tasks inherit.
private let (sessionJobs, sessionQueue) = AsyncStream<@Sendable () async -> Void>.makeStream()
func inSession(_ work: @escaping @Sendable () async -> Void) { sessionQueue.yield(work) }

actor LocalSend {
    private var identity: Identity?
    private var client: Client?
    private var server: Server?
    private var multicast: Multicast?
    private var port = LocalSendProtocol.port
    private var peers = PeerList(ownFingerprint: "")
    private var problem: String?
    /// macOS's local network privacy is stopping Ledge from reaching other devices.
    private var blocked = false
    /// A moment's word on the page, like "Sent 3 files to Pixel 9".
    private var notice: String?

    // Settings
    private var alias = Host.current().localizedName ?? "Mac"
    private var folderChoice = "downloads"
    private var pin = ""
    private var toShelf = true

    // Transfers
    private var receiving: Receiving?
    private var sending: Sending?
    private var sendTask: Task<Void, Never>?
    private var asking = false
    private var wrongPins: [String: Int] = [:]
    private var lastShown = Date.distantPast
    /// How the last transfer ended, beside the notch for a few seconds.
    private var ended: (text: String, symbol: String, until: Date)?

    struct Receiving {
        let id: String
        let sender: String
        let host: String
        let files: [String: FileInfo]
        let tokens: [String: String]
        var done: [String: URL] = [:]
        var bytes: Int64 = 0
        var lastActivity = Date()
        var total: Int64 { files.values.reduce(0) { $0 + $1.size } }
    }

    struct Sending {
        let peer: Peer
        var sessionID: String?
        var count: Int
        var index = 0
        var total: Int64
        var sentBefore: Int64 = 0
        var current: Int64 = 0
        var waiting = true
    }

    // MARK: Starting

    func start() async {
        Task { for await job in sessionJobs { Task { await job() } } }
        await loadSettings()
        do {
            let folder = try await LedgeHost.dataFolder()
            let identity = try Identity.load(from: folder)
            self.identity = identity
            peers = PeerList(ownFingerprint: identity.fingerprint)
            client = Client(identity: identity)
            let server = Server(identity: identity) { [weak self] head, host in
                await self?.route(head, from: host) ?? .respond(500)
            }
            port = try await server.start()
            self.server = server
        } catch {
            problem = "LocalSend couldn't start: \(error)"
            AddOnSession.log("Start failed: \(error)", level: .error)
            show()
            return
        }
        do {
            multicast = try Multicast { [weak self] info, host in inSession { await self?.heard(info, from: host) } }
        } catch {
            // Without discovery, the scan still finds devices.
            AddOnSession.log("No multicast: \(error)", level: .error)
        }
        show()
        Task { await self.keepFresh() }
    }

    func stop() {
        sendTask?.cancel()
        server?.stop()
        multicast?.stop()
    }

    /// Announces now and every two minutes, which has every device answer, and drops devices gone quiet. When nothing
    /// answers the first announcement, it scans the network, as LocalSend does where multicast is blocked.
    private func keepFresh() async {
        announce()
        try? await Task.sleep(for: .seconds(4))
        if peers.peers.isEmpty { await scan() }
        var tick = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            tick += 1
            // Sooner while nothing's found, so devices show up soon after macOS lets the network through.
            if tick % 4 == 0 || blocked || peers.peers.isEmpty { announce() }
            if peers.expire() { show() }
            if let receiving, Date().timeIntervalSince(receiving.lastActivity) > 120 { finishReceiving(cancelled: true) }
        }
    }

    private var ownInfo: DeviceInfo {
        DeviceInfo(alias: alias, deviceModel: "Mac", deviceType: "desktop", fingerprint: identity?.fingerprint, port: port)
    }

    private func announce() {
        var info = ownInfo
        info.announce = true
        if let multicast {
            let sent = multicast.send(info)
            if sent == blocked {
                blocked = !sent
                show()
            }
        }
        // LocalSend sends a short burst, since a device may not be listening yet.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            multicast?.send(info)
        }
    }

    // MARK: Finding devices

    private func heard(_ info: DeviceInfo, from host: String) async {
        guard info.fingerprint?.uppercased() != identity?.fingerprint, (info.scheme ?? "https") == "https" else { return }
        if peers.saw(info, fingerprint: info.fingerprint, host: host) { show() }
        guard info.announce == true, let client, let json = try? JSONEncoder().encode(ownInfo),
              let peer = peers.peers[info.fingerprint?.uppercased() ?? ""], let url = peer.url("register") else { return }
        // Answer by registering with it; if its server can't be reached, answer on the group instead.
        let status: Int
        do { status = try await client.post(url, to: peer, json: json, timeout: 5).0 } catch {
            AddOnSession.log("Couldn't register with \(peer.info.alias) at \(host): \(error.localizedDescription)", level: .error)
            status = 0
        }
        if status != 200 {
            var answer = ownInfo
            answer.announce = false
            multicast?.send(answer)
        }
    }

    /// Asks every address on this Mac's networks (up to a /24 each) whether it runs LocalSend.
    private func scan() async {
        guard let client, let json = try? JSONEncoder().encode(ownInfo) else { return }
        var hosts: [String] = []
        for (address, mask) in Multicast.addresses() {
            let ip = UInt32(bigEndian: address.s_addr), netmask = UInt32(bigEndian: mask.s_addr) | 0xFFFF_FF00
            let network = ip & netmask
            for n in 1..<255 where network | UInt32(n) != ip {
                let value = network | UInt32(n)
                hosts.append("\(value >> 24).\(value >> 16 & 255).\(value >> 8 & 255).\(value & 255)")
            }
        }
        let port = LocalSendProtocol.port
        await withTaskGroup(of: (String, DeviceInfo?).self) { group in
            for host in hosts.prefix(1024) {
                group.addTask {
                    guard let url = URL(string: "https://\(host):\(port)\(LocalSendProtocol.base)register"),
                          let (status, data) = try? await client.post(url, to: nil, json: json, timeout: 2), status == 200 else { return (host, nil) }
                    return (host, try? JSONDecoder().decode(DeviceInfo.self, from: data))
                }
            }
            for await (host, info) in group {
                // Known by its certificate, not by what it says.
                guard var info, let fingerprint = client.certificateFingerprint(of: host) else { continue }
                info.port = info.port ?? port
                if peers.saw(info, fingerprint: fingerprint, host: host) { show() }
            }
        }
    }

    // MARK: The server's routes

    func route(_ head: HTTPRequestHead, from host: String) -> Route {
        guard head.path.hasPrefix(LocalSendProtocol.base) else { return .respond(404) }
        switch (head.method, String(head.path.dropFirst(LocalSendProtocol.base.count))) {
        case ("GET", "info"):
            return .respond(200, try? JSONEncoder().encode(ownInfo))
        case ("POST", "register"):
            return .json(maximum: 64 * 1024) { body in
                await self.registered(body, from: host)
            }
        case ("POST", "prepare-upload"):
            if !pin.isEmpty {
                guard (wrongPins[host] ?? 0) < 5 else { return .respond(429) }
                guard head.query["pin"] == pin else {
                    if head.query["pin"] != nil { wrongPins[host, default: 0] += 1 }
                    return .respond(401)
                }
            }
            if let receiving, Date().timeIntervalSince(receiving.lastActivity) > 60 { finishReceiving(cancelled: true) }
            guard receiving == nil, !asking else { return .respond(409) }
            asking = true
            return .json(maximum: 8 * 1024 * 1024) { body in
                await self.prepare(body, from: host)
            }
        case ("POST", "upload"):
            return upload(head.query, from: host)
        case ("POST", "cancel"):
            if let receiving, receiving.id == head.query["sessionId"], receiving.host == host { finishReceiving(cancelled: true) }
            return .respond(200)
        default:
            return .respond(404)
        }
    }

    private func registered(_ body: Data, from host: String) -> (Int, Data?) {
        guard let info = try? JSONDecoder().decode(DeviceInfo.self, from: body) else { return (400, nil) }
        if (info.scheme ?? "https") == "https", peers.saw(info, fingerprint: info.fingerprint, host: host) { show() }
        return (200, try? JSONEncoder().encode(ownInfo))
    }

    private func prepare(_ body: Data, from host: String) async -> (Int, Data?) {
        defer { asking = false }
        guard let request = try? JSONDecoder().decode(PrepareUpload.self, from: body), request.isValid, request.files.count <= 10_000 else {
            return (400, nil)
        }
        wrongPins[host] = nil
        let sender = String(request.info.alias.prefix(60))
        if let text = request.message {
            let question = HostQuestion(title: "\(sender) sent a message", message: String(text.prefix(400)), accept: "Copy",
                                        decline: "Dismiss", timeout: 60)
            if (try? await LedgeHost.ask(question)) == true { try? await LedgeHost.copy(text) }
            return (204, nil)
        }
        let files = request.files.values.sorted { $0.fileName < $1.fileName }
        let size = ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file)
        var names = files.prefix(4).map { SafePath.components(of: $0.fileName).joined(separator: "/") }.joined(separator: ", ")
        if files.count > 4 { names += " and \(files.count - 4) more" }
        let title = files.count == 1 ? "Accept \(SafePath.components(of: files[0].fileName).last!) from \(sender)?"
                                     : "Accept \(files.count) files from \(sender)?"
        let question = HostQuestion(title: String(title.prefix(120)), message: "\(names) · \(size)\nSaved to \(folderName).",
                                    accept: "Accept", decline: "Decline", timeout: 60)
        guard (try? await LedgeHost.ask(question)) == true else { return (403, nil) }
        let id = UUID().uuidString
        var tokens: [String: String] = [:]
        for file in files { tokens[file.id] = Self.token() }
        receiving = Receiving(id: id, sender: sender, host: host, files: request.files, tokens: tokens)
        show()
        return (200, try? JSONEncoder().encode(PrepareUploadAnswer(sessionId: id, files: tokens)))
    }

    private func upload(_ query: [String: String], from host: String) -> Route {
        guard let id = query["sessionId"], let fileID = query["fileId"], let token = query["token"] else { return .respond(400) }
        guard var session = receiving, session.id == id, session.host == host, let file = session.files[fileID],
              session.tokens[fileID] == token else { return .respond(403) }
        guard session.done[fileID] == nil else { return .respond(409) }
        session.lastActivity = Date()
        receiving = session
        let destination = SafePath.destination(for: file.fileName, in: folder)
        return .upload(FileSink(file: file, destination: destination, owner: self))
    }

    /// A file arrived whole, or didn't.
    func received(_ fileID: String, at url: URL?, bytes: Int64) {
        guard var session = receiving else { return }
        session.lastActivity = Date()
        if let url { session.done[fileID] = url }
        session.bytes += bytes
        receiving = session
        if session.done.count == session.files.count { finishReceiving(cancelled: false) } else { showSoon() }
    }

    func receiving(_ bytes: Int64) {
        guard var session = receiving else { return }
        session.bytes += bytes
        session.lastActivity = Date()
        receiving = session
        showSoon()
    }

    private func finishReceiving(cancelled: Bool) {
        guard let session = receiving else { return }
        receiving = nil
        let got = session.done.count
        notice = got == 0 ? (cancelled ? "\(session.sender) cancelled" : nil)
            : "Received \(got) \(got == 1 ? "file" : "files") from \(session.sender)" + (cancelled ? ", then it stopped" : "")
        if let notice { ended = (notice, got == 0 ? "xmark.circle" : "checkmark.circle", Date().addingTimeInterval(5)) }
        show()
        guard got > 0, toShelf else { return }
        var items: [URL] = []
        for url in session.done.values.map({ SafePath.topItem(of: $0, in: folder) }) where !items.contains(url) { items.append(url) }
        Task { try? await LedgeHost.addToShelf(Array(items.prefix(Surface.maximumSharedFiles))) }
    }

    private static func token() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private var folder: URL {
        let directory: FileManager.SearchPathDirectory = switch folderChoice {
        case "desktop": .desktopDirectory
        case "documents": .documentDirectory
        default: .downloadsDirectory
        }
        return FileManager.default.urls(for: directory, in: .userDomainMask)[0]
    }

    private var folderName: String { folder.lastPathComponent }

    // MARK: Sending

    func share(_ shared: SharedFiles) {
        guard let peer = peers.peers[shared.destination] else {
            notice = "That device isn't nearby any more"
            show()
            return
        }
        guard sending == nil else {
            notice = "Still sending to \(sending!.peer.info.alias)"
            show()
            return
        }
        let files = Self.expand(shared.urls)
        guard !files.isEmpty else {
            notice = "Nothing to send"
            show()
            return
        }
        sending = Sending(peer: peer, count: files.count, total: files.reduce(0) { $0 + $1.info.size })
        notice = nil
        show()
        sendTask = Task { await self.send(files, to: peer) }
    }

    /// The files to send, a folder's files inside it named by their path from the folder, as LocalSend does.
    private static func expand(_ urls: [URL]) -> [(url: URL, info: FileInfo)] {
        var found: [(URL, FileInfo)] = []
        func add(_ url: URL, name: String) {
            guard found.count < 1000, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            found.append((url, FileInfo(id: UUID().uuidString, fileName: name, size: Int64(values.fileSize ?? 0), fileType: type)))
        }
        for url in urls {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else { add(url, name: url.lastPathComponent); continue }
            let base = url.deletingLastPathComponent().standardizedFileURL.path
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let file = walker?.nextObject() as? URL {
                add(file, name: String(file.standardizedFileURL.path.dropFirst(base.count + 1)))
            }
        }
        return found
    }

    private func send(_ files: [(url: URL, info: FileInfo)], to peer: Peer) async {
        guard let client else { return }
        let request = PrepareUpload(info: ownInfo, files: Dictionary(uniqueKeysWithValues: files.map { ($0.info.id, $0.info) }))
        do {
            guard let json = try? JSONEncoder().encode(request), let url = peer.url("prepare-upload") else { return }
            // The person on the other side has to accept, so this waits for them.
            let (status, data) = try await client.post(url, to: peer, json: json, timeout: 120)
            switch status {
            case 200: break
            case 204: return endSending("\(peer.info.alias) has them already")
            case 401: return endSending("\(peer.info.alias) wants a PIN. Turn it off in LocalSend there to send from Ledge.")
            case 403: return endSending("\(peer.info.alias) declined")
            case 409: return endSending("\(peer.info.alias) is busy with another transfer")
            default: return endSending("\(peer.info.alias) couldn't take them (\(status))")
            }
            let answer = try JSONDecoder().decode(PrepareUploadAnswer.self, from: data)
            sending?.sessionID = answer.sessionId
            sending?.waiting = false
            show()
            var sent = 0
            for file in files {
                try Task.checkCancellation()
                sending?.index += 1
                showSoon()
                guard let token = answer.files[file.info.id] else { continue }   // the receiver may skip some
                guard let target = peer.url("upload", ["sessionId": answer.sessionId, "fileId": file.info.id, "token": token]) else { continue }
                let status = try await client.upload(file.url, to: target, peer: peer) { bytes in
                    Task { await self.sent(bytes) }
                }
                guard status == 200 else { throw Client.Failure(status: status) }
                sending?.sentBefore += file.info.size
                sending?.current = 0
                sent += 1
            }
            endSending("Sent \(sent) \(sent == 1 ? "file" : "files") to \(peer.info.alias)")
        } catch {
            if let id = sending?.sessionID, let url = peer.url("cancel", ["sessionId": id]) {
                _ = try? await client.post(url, to: peer, json: nil, timeout: 5)
            }
            endSending(Task.isCancelled || error is CancellationError ? "Cancelled" : "Couldn't send to \(peer.info.alias)")
            AddOnSession.log("Send failed: \(error)", level: .error)
        }
    }

    private func sent(_ bytes: Int64) {
        sending?.current = bytes
        showSoon()
    }

    private func endSending(_ message: String) {
        let sent = message.hasPrefix("Sent ")
        sending = nil
        sendTask = nil
        notice = message
        ended = (message, sent ? "checkmark.circle" : "xmark.circle", Date().addingTimeInterval(5))
        show()
    }

    // MARK: Events

    func handle(_ event: SurfaceEvent) async {
        switch (event.surface, event.control, event.action) {
        case (Surface.settingsPage, "alias", .ended(let text)), (Surface.settingsPage, "alias", .edited(let text)):
            let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            guard !clean.isEmpty, clean != alias else { return }
            alias = clean
            try? await LedgeHost.set(clean, forKey: "alias")
            if case .ended = event.action { announce() }
        case (Surface.settingsPage, "pin", .ended(let text)), (Surface.settingsPage, "pin", .edited(let text)):
            pin = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            wrongPins = [:]
            try? await LedgeHost.set(pin, forKey: "pin")
        case (Surface.settingsPage, "folder", .picked(let choice)):
            folderChoice = choice
            try? await LedgeHost.set(choice, forKey: "folder")
        case (Surface.settingsPage, "shelf", .toggled(let on)):
            toShelf = on
            try? await LedgeHost.set(on, forKey: "shelf")
        case (Surface.notchPage, "refresh", .pressed):
            notice = "Looking for devices…"
            show()
            announce()
            await scan()
            notice = nil
        case (Surface.notchPage, "cancel", .pressed):
            sendTask?.cancel()
        case (Surface.notchPage, "devices", .pressed):
            if let peer = event.item.flatMap({ peers.peers[$0] }) { notice = "Drop files on \(peer.info.alias) to send them" }
        default:
            return
        }
        show()
    }

    private func loadSettings() async {
        if let saved = try? await LedgeHost.value(String.self, forKey: "alias"), !saved.isEmpty { alias = saved }
        if let saved = try? await LedgeHost.value(String.self, forKey: "folder") { folderChoice = saved }
        if let saved = try? await LedgeHost.value(String.self, forKey: "pin") { pin = saved }
        if let saved = try? await LedgeHost.value(Bool.self, forKey: "shelf") { toShelf = saved }
    }

    // MARK: What Ledge draws

    /// At most a few redraws a second while bytes move.
    private func showSoon() {
        guard Date().timeIntervalSince(lastShown) > 0.25 else { return }
        show()
    }

    private func show() {
        lastShown = Date()
        let nearby = peers.sorted.filter { $0.fingerprint.count <= 64 }.prefix(Surface.maximumShareDestinations)
        AddOnSession.show(shareTarget: ShareTarget(title: "LocalSend", symbol: "paperplane", destinations: nearby.map {
            ShareDestination($0.fingerprint, title: String($0.info.alias.prefix(60)), subtitle: $0.host, symbol: $0.symbol)
        }, emptyNote: "No devices nearby"))
        AddOnSession.show(notchPage: NotchPage(title: "LocalSend", symbol: "paperplane", screen: screen(Array(nearby))))
        AddOnSession.show(settingsPage())
        AddOnSession.show(activities: activities())
    }

    /// Beside the notch while a transfer runs, wherever the person is: who, how far, and how much of it.
    private func activities() -> [LiveActivity] {
        func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        func percent(_ fraction: Double) -> String { "\(Int(fraction * 100)) percent" }
        if let sending {
            let who = String(sending.peer.info.alias.prefix(24))
            if sending.waiting {
                return [LiveActivity("transfer", symbol: "arrow.up.circle", text: "Waiting for \(who)", progress: .indeterminate)]
            }
            let done = sending.sentBefore + sending.current
            let fraction = sending.total == 0 ? 0 : min(1, Double(done) / Double(sending.total))
            return [LiveActivity("transfer", symbol: "arrow.up.circle", text: "To \(who) · \(size(done)) of \(size(sending.total))",
                                 progress: .fraction(fraction), accessibilityValue: percent(fraction))]
        }
        if let receiving {
            let who = String(receiving.sender.prefix(24))
            let fraction = receiving.total == 0 ? 0 : min(1, Double(receiving.bytes) / Double(receiving.total))
            return [LiveActivity("transfer", symbol: "arrow.down.circle", text: "From \(who) · \(size(receiving.bytes)) of \(size(receiving.total))",
                                 progress: .fraction(fraction), accessibilityValue: percent(fraction))]
        }
        if let ended, ended.until > Date() {
            return [LiveActivity("transfer", symbol: ended.symbol, text: String(ended.text.prefix(60)),
                                 progress: ended.symbol == "checkmark.circle" ? .done : nil, lasts: ended.until.timeIntervalSinceNow)]
        }
        return []
    }

    private func screen(_ nearby: [Peer]) -> PageScreen {
        var parts: [PageNode] = []
        if let sending {
            let label = sending.waiting ? "Waiting for \(sending.peer.info.alias) to accept"
                : "Sending to \(sending.peer.info.alias) · \(sending.index) of \(sending.count)"
            let done = sending.sentBefore + sending.current
            parts.append(.progress(sending.waiting || sending.total == 0 ? 0 : Double(done) / Double(sending.total), label: label))
        }
        if let receiving {
            let total = max(receiving.total, 1)
            parts.append(.progress(Double(receiving.bytes) / Double(total),
                                   label: "Receiving from \(receiving.sender) · \(receiving.done.count) of \(receiving.files.count)"))
        }
        if let problem {
            parts.append(.empty(symbol: "exclamationmark.triangle", title: problem, detail: nil))
        } else if blocked {
            parts.append(.empty(symbol: "network.slash", title: "macOS is blocking the local network",
                                detail: "Turn on Ledge in System Settings, Privacy & Security, Local Network"))
        } else if nearby.isEmpty {
            parts.append(.empty(symbol: "wifi", title: "No devices nearby",
                                detail: "Open LocalSend on your phone or computer, on the same network"))
        } else {
            parts.append(.list(id: "devices", rows: nearby.map {
                ListRow($0.fingerprint, title: String($0.info.alias.prefix(60)),
                        subtitle: [$0.info.deviceModel, $0.host].compactMap { $0 }.joined(separator: " · "),
                        symbol: $0.symbol, acceptsFiles: true)
            }))
        }
        var actions = [PageAction("refresh", symbol: "arrow.clockwise", label: "Look for devices")]
        if sending != nil { actions.insert(PageAction("cancel", symbol: "xmark", label: "Cancel sending", destructive: true), at: 0) }
        return PageScreen("main", title: "LocalSend", caption: notice, actions: actions,
                          content: parts.count == 1 ? parts[0] : .vstack(spacing: 12, children: parts))
    }

    private func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("mac", title: "This Mac",
                            footer: "Other devices see this name. Ledge answers on port \(port), on this Mac's local network only.",
                            rows: [.textField("alias", "Name", text: alias, placeholder: "Mac")]),
            SettingsSection("receiving", title: "Receiving",
                            footer: "You accept every transfer in the notch; no answer in a minute declines it. With a PIN, the sender has to enter it first.",
                            rows: [
                                .picker("folder", "Save to", options: [.init("downloads", "Downloads"), .init("desktop", "Desktop"),
                                                                       .init("documents", "Documents")], selected: folderChoice),
                                .toggle("shelf", "Put received files on the shelf", isOn: toShelf),
                                .textField("pin", "PIN", text: pin, placeholder: "None"),
                            ]),
        ], keywords: ["localsend", "airdrop", "share", "send", "phone", "android", "transfer"])
    }
}

/// Writes one upload to a hidden file beside where it goes, checks its size and checksum, then gives it its name.
final class FileSink: UploadSink, @unchecked Sendable {
    private let file: FileInfo
    private let destination: URL
    private let temporary: URL
    private weak var owner: LocalSend?
    private var handle: FileHandle?
    private var hash = SHA256()
    private var written: Int64 = 0
    private var reported: Int64 = 0
    private let lock = NSLock()

    struct TooLong: Error {}

    init(file: FileInfo, destination: URL, owner: LocalSend) {
        self.file = file
        self.destination = destination
        self.temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).localsend")
        self.owner = owner
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            if handle == nil {
                try FileManager.default.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: temporary.path, contents: nil)
                handle = try FileHandle(forWritingTo: temporary)
            }
            written += Int64(data.count)
            guard written <= file.size else { throw TooLong() }
            try handle?.write(contentsOf: data)
            if file.sha256 != nil { hash.update(data: data) }
        }
        let progress = lock.withLock { () -> Int64? in
            guard written - reported > 1_000_000 else { return nil }
            defer { reported = written }
            return written - reported
        }
        if let progress, let owner { Task { await owner.receiving(progress) } }
    }

    func finish() async -> Int {
        let (count, digest, rest) = lock.withLock { () -> (Int64, String, Int64) in
            try? handle?.close()
            handle = nil
            return (written, hash.finalize().map { String(format: "%02x", $0) }.joined(), written - reported)
        }
        if count == 0 { FileManager.default.createFile(atPath: temporary.path, contents: nil) }   // an empty file
        guard count == file.size else { await abort(); return 400 }
        if let expected = file.sha256, expected.lowercased() != digest { await abort(); return 422 }
        // The name may have been taken while it arrived.
        let place = FileManager.default.fileExists(atPath: destination.path)
            ? SafePath.destination(for: destination.lastPathComponent, in: destination.deletingLastPathComponent()) : destination
        do { try FileManager.default.moveItem(at: temporary, to: place) } catch { await abort(); return 500 }
        await owner?.received(file.id, at: place, bytes: rest)
        return 200
    }

    func abort() async {
        lock.withLock {
            try? handle?.close()
            handle = nil
        }
        try? FileManager.default.removeItem(at: temporary)
    }
}

let addOn = LocalSend()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.deactivate = { await addOn.stop() }
handlers.onEvent = { event in await addOn.handle(event) }
handlers.onShare = { shared in await addOn.share(shared) }
exit(await AddOnSession.run(id: "localsend", handlers: handlers))
