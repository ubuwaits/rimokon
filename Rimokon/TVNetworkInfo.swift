import Foundation

enum TVNetworkInfo {
    static func macAddresses(from payload: [String: Any], host: String) -> [String] {
        guard payload["returnValue"] as? Bool != false else { return [] }
        let interfaces = ["wiredInfo", "wifiInfo"].compactMap { payload[$0] as? [String: Any] }
        let ordered = interfaces.filter { ($0["ipAddress"] as? String) == host }
            + interfaces.filter { ($0["ipAddress"] as? String) != host }
        var result: [String] = []
        for info in ordered {
            guard let raw = info["macAddress"] as? String else { continue }
            let normalized = TVConfiguration(mac: raw)
            guard normalized.validMAC, let first = UInt8(normalized.mac.prefix(2), radix: 16),
                  first & 1 == 0, normalized.mac != "00:00:00:00:00:00",
                  !result.contains(normalized.mac) else { continue }
            result.append(normalized.mac)
        }
        return result
    }
}
