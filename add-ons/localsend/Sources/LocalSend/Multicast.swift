import Darwin
import Foundation
import LocalSendCore

/// LocalSend's discovery: JSON announcements on 224.0.0.167:53317. A plain BSD socket, shared with the LocalSend app
/// if it runs on this Mac too (SO_REUSEPORT), since Network.framework's multicast needs an entitlement an add-on
/// can't have.
final class Multicast: @unchecked Sendable {
    private let socket: Int32
    private let queue = DispatchQueue(label: "localsend.multicast")
    private var source: DispatchSourceRead?

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// `heard` gets each message and the address it came from.
    init(heard: @escaping @Sendable (DeviceInfo, String) -> Void) throws {
        socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else { throw Failure(description: "No UDP socket.") }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socket, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = LocalSendProtocol.port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { close(socket); throw Failure(description: "Port \(LocalSendProtocol.port) is taken.") }
        // Join the group on every IPv4 interface that's up, so Wi-Fi and Ethernet both hear it.
        for interface in Self.interfaces() {
            var request = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(LocalSendProtocol.multicastGroup)), imr_interface: interface)
            setsockopt(socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size))
        }
        var loop: UInt8 = 0
        setsockopt(socket, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        let socket = socket
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(socket, &buffer, buffer.count, 0, $0, &fromLength) }
            }
            guard count > 0, let info = try? JSONDecoder().decode(DeviceInfo.self, from: Data(buffer[0..<count])) else { return }
            heard(info, String(cString: inet_ntoa(from.sin_addr)))
        }
        source.setCancelHandler { close(socket) }
        source.resume()
        self.source = source
    }

    /// Sends a message to the group from every interface. Returns false when macOS refused every send, which is what
    /// local network privacy does to an app the person hasn't allowed.
    @discardableResult
    func send(_ info: DeviceInfo) -> Bool {
        guard let data = try? JSONEncoder().encode(info) else { return true }
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = LocalSendProtocol.port.bigEndian
        target.sin_addr.s_addr = inet_addr(LocalSendProtocol.multicastGroup)
        return queue.sync { [socket] in
            var sent = false
            for var interface in Self.interfaces() {
                setsockopt(socket, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size))
                let count = data.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &target) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(socket, bytes.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                    }
                }
                if count >= 0 { sent = true }
            }
            return sent
        }
    }

    func stop() { source?.cancel() }

    /// The IPv4 addresses of interfaces that are up and can multicast, loopback left out.
    static func interfaces() -> [in_addr] { addresses().map(\.address) }

    /// Each IPv4 interface's address and netmask, for scanning the network when multicast doesn't get through.
    static func addresses() -> [(address: in_addr, mask: in_addr)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var found: [(in_addr, in_addr)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = entry.pointee.ifa_netmask,
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_MULTICAST != 0 else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            found.append((ip, netmask))
        }
        return found
    }
}
