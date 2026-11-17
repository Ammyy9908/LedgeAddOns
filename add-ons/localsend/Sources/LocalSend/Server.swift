import Foundation
import LocalSendCore
import Network

/// What the server does with a request, decided from its head.
enum Route {
    case respond(Int, Data? = nil)
    /// Reads a JSON body of at most `maximum` bytes, then answers.
    case json(maximum: Int, (Data) async -> (Int, Data?))
    /// Streams the body into a file.
    case upload(UploadSink)
}

/// Where an upload's bytes go.
protocol UploadSink: AnyObject, Sendable {
    func write(_ data: Data) throws
    /// The body ended: check it and answer with a status.
    func finish() async -> Int
    /// The sender went away or sent too much.
    func abort() async
}

/// LocalSend's HTTPS server. Other devices register with it and send files to it.
final class Server: @unchecked Sendable {
    private let identity: Identity
    private let route: @Sendable (HTTPRequestHead, String) async -> Route
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "localsend.server")
    private var open = 0
    private static let maximumConnections = 32

    init(identity: Identity, route: @escaping @Sendable (HTTPRequestHead, String) async -> Route) {
        self.identity = identity
        self.route = route
    }

    /// Listens on LocalSend's port, or the next free one when the LocalSend app has it. Returns the port.
    func start() async throws -> UInt16 {
        var lastError: Error?
        for port in LocalSendProtocol.port..<(LocalSendProtocol.port + 6) {
            do {
                try await listen(on: port)
                return port
            } catch { lastError = error }
        }
        throw lastError ?? NWError.posix(.EADDRINUSE)
    }

    func stop() { listener?.cancel() }

    private func listen(on port: UInt16) async throws {
        let tls = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity.identity) else { throw NWError.tls(errSecParam) }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; continuation.resume()
                case .failed(let error), .waiting(let error):
                    resumed = true
                    listener.cancel()
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        guard open < Self.maximumConnections else { connection.cancel(); return }
        open += 1
        connection.start(queue: queue)
        inSession {
            await self.serve(connection)
            connection.cancel()
            self.queue.async { self.open -= 1 }
        }
    }

    private func serve(_ connection: NWConnection) async {
        var buffer = Data()
        let head: HTTPRequestHead
        do {
            while true {
                if let parsed = try HTTPRequestHead.parse(buffer) {
                    head = parsed.head
                    buffer.removeFirst(parsed.length)
                    break
                }
                guard let chunk = try await connection.read() else { return }
                buffer.append(chunk)
            }
        } catch {
            await connection.write(HTTPResponse.make(400))
            return
        }
        let status: Int
        var json: Data?
        switch await route(head, connection.remoteHost) {
        case .respond(let code, let body):
            (status, json) = (code, body)
        case .json(let maximum, let answer):
            var body = Data()
            do {
                try await connection.readBody(head.body, leftover: buffer) { chunk in
                    body.append(chunk)
                    if body.count > maximum { throw HTTPRequestHead.ParseError.tooLarge }
                }
                (status, json) = await answer(body)
            } catch {
                (status, json) = (error is HTTPRequestHead.ParseError ? 413 : 400, nil)
            }
        case .upload(let sink):
            do {
                try await connection.readBody(head.body, leftover: buffer) { try sink.write($0) }
                status = await sink.finish()
            } catch {
                await sink.abort()
                status = 400
            }
        }
        await connection.write(HTTPResponse.make(status, json: json))
    }
}

extension NWConnection {
    /// The next bytes, or nil once the other side has finished.
    func read() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if complete { continuation.resume(returning: nil) }
                else { continuation.resume(returning: Data()) }
            }
        }
    }

    func write(_ data: Data) async {
        await withCheckedContinuation { continuation in
            send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    /// Hands the body to `each` as it arrives, by Content-Length or chunked. Throws if it ends early.
    func readBody(_ body: HTTPRequestHead.Body, leftover: Data, each: (Data) throws -> Void) async throws {
        switch body {
        case .none:
            return
        case .length(let length):
            var left = length
            var pending = leftover
            while left > 0 {
                if pending.isEmpty {
                    guard let chunk = try await read() else { throw NWError.posix(.ECONNRESET) }
                    pending = chunk
                }
                let take = Int(min(Int64(pending.count), left))
                try each(pending.prefix(take))
                pending.removeFirst(take)
                left -= Int64(take)
            }
        case .chunked:
            var decoder = ChunkedDecoder()
            var pending = leftover
            while true {
                let payload = try decoder.feed(pending)
                if !payload.isEmpty { try each(payload) }
                if decoder.isFinished { return }
                guard let chunk = try await read() else { throw NWError.posix(.ECONNRESET) }
                pending = chunk
            }
        }
    }

    /// The other side's IP address, without an interface suffix.
    var remoteHost: String {
        guard case .hostPort(let host, _) = endpoint else { return "" }
        var text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = address.asIPv4.map { "\($0)" } ?? "\(address)"
        case .name(let name, _): text = name
        @unknown default: text = "\(host)"
        }
        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
        return text
    }
}
