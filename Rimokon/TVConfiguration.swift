import Foundation

struct TVConfiguration {
    var host: String
    var mac: String

    init(host: String = "", mac: String = "") {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mac = mac.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: ":").lowercased()
    }

    var validHost: Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && Int($0).map { (0...255).contains($0) } == true
        }
    }
    var validMAC: Bool {
        let parts = mac.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 6 && parts.allSatisfy { $0.count == 2 && UInt8($0, radix: 16) != nil }
    }
    var valid: Bool { validHost && (mac.isEmpty || validMAC) }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(host: defaults.string(forKey: "tvHost") ?? "", mac: defaults.string(forKey: "tvMAC") ?? "")
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: "tvHost")
        defaults.set(mac, forKey: "tvMAC")
    }
}
