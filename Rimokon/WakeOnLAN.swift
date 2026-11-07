import Foundation
import Darwin

enum WakeOnLAN {
    static func packet(mac: String) -> Data? {
        let parts = mac.replacingOccurrences(of: "-", with: ":").split(separator: ":")
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { $0.count == 2 ? UInt8($0, radix: 16) : nil }
        guard bytes.count == 6 else { return nil }
        return Data(Array(repeating: UInt8(255), count: 6) + Array(repeating: bytes, count: 16).flatMap { $0 })
    }

    // Unicast avoids the restricted iOS multicast/broadcast entitlement.
    // The TV must retain its network presence during standby.
    static func send(packet: Data, host: String) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }
        return packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == bytes.count
                }
            }
        }
    }
}
