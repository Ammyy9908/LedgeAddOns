import Darwin
import Foundation

/// A Unix socket only this user can open, where Claude Code's hooks deliver events. Each hook connects, writes one
/// JSON event and waits for the answer, which `answer` gives and is usually empty.
final class HookServer: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private let fd: Int32
    private let path: String

    init(path: String, answer: @escaping @Sendable (Data) async -> Data) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw Failure(description: "The socket's path is too long for macOS: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(description: "socket failed: \(String(cString: strerror(errno)))") }
        unlink(path)   // left behind by a session that didn't stop cleanly
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw Failure(description: "Couldn't listen at \(path): \(reason)")
        }
        self.fd = fd
        self.path = path
        Thread.detachNewThread { [fd] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    return   // closed by stop()
                }
                Thread.detachNewThread { Self.serve(client, answer: answer) }
            }
        }
    }

    func stop() {
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(path)
    }

    private static func serve(_ client: Int32, answer: @escaping @Sendable (Data) async -> Data) {
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        // nc doesn't close its side after the event, so the event ends where it parses as JSON.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < 1_048_576 {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if (try? JSONSerialization.jsonObject(with: data)) != nil { break }
        }
        let event = data
        inSession {
            let reply = await answer(event)
            reply.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var sent = 0
                while sent < raw.count {
                    let count = write(client, base + sent, raw.count - sent)
                    if count <= 0 { break }
                    sent += count
                }
            }
            close(client)
        }
    }
}
