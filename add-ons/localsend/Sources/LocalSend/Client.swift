import Foundation
import LocalSendCore
import Security

/// Talks to other devices' LocalSend servers. Their certificates are self-signed, so instead of a certificate
/// authority each request trusts exactly one: the one whose SHA-256 the device announced. LocalSend 1.18 asks every
/// client for a certificate too, so ours goes along.
final class Client: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let identity: Identity
    private lazy var session = URLSession(configuration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]   // a system proxy can't reach the local network
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 4
        return configuration
    }(), delegate: self, delegateQueue: nil)
    /// Host to the fingerprint its certificate must have. Only hosts we're talking to are in it.
    private let lock = NSLock()
    private var pins: [String: String] = [:]
    /// The fingerprint each host's certificate actually had, last time.
    private var seen: [String: String] = [:]

    /// What the host's certificate was, which is what a scanned device is known by.
    func certificateFingerprint(of host: String) -> String? { lock.withLock { seen[host] } }

    init(identity: Identity) { self.identity = identity }

    struct Failure: Error { let status: Int }

    /// Sends JSON and returns the answer's status and body.
    func post(_ url: URL, to peer: Peer?, json: Data?, timeout: TimeInterval = 30) async throws -> (Int, Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        if let json {
            request.httpBody = json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        pin(url, peer)
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// Uploads a file's bytes from disk, reporting progress.
    func upload(_ file: URL, to url: URL, peer: Peer, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        pin(url, peer)
        let watcher = UploadProgress(progress)
        let (_, response) = try await session.upload(for: request, fromFile: file, delegate: watcher)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private func pin(_ url: URL, _ peer: Peer?) {
        guard let host = url.host else { return }
        lock.withLock { pins[host] = peer?.fingerprint }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodClientCertificate:
            return (.useCredential, URLCredential(identity: identity.identity, certificates: nil, persistence: .forSession))
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = challenge.protectionSpace.serverTrust,
                  let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return (.cancelAuthenticationChallenge, nil) }
            let host = challenge.protectionSpace.host
            let actual = Identity.fingerprint(of: leaf)
            let expected = lock.withLock { seen[host] = actual; return pins[host] }
            // A device found by scanning hasn't told us its fingerprint yet; its register answer does, and from
            // then on it's pinned. Sending files always has one.
            if let expected, actual != expected { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, URLCredential(trust: trust))
        default:
            return (.performDefaultHandling, nil)
        }
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let report: @Sendable (Int64) -> Void
    init(_ report: @escaping @Sendable (Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        report(totalBytesSent)
    }
}
