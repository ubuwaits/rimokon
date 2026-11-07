import Foundation
@main struct ConfigurationRegression {
    static func main() {
        let name = "rimokon-config-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        assert(TVConfiguration.load(from: defaults).host.isEmpty)
        assert(TVConfiguration.load(from: defaults).mac.isEmpty)
        // Documentation-only IP and locally administered test MAC, not a real TV.
        defaults.set("192.0.2.10", forKey: "tvHost")
        defaults.set("02:00:00:00:00:01", forKey: "tvMAC")
        let existing = TVConfiguration.load(from: defaults)
        assert(existing.host == "192.0.2.10" && existing.mac == "02:00:00:00:00:01")
        assert(existing.valid)
        let changed = TVConfiguration(host: " 192.0.2.20 ", mac: "02-00-00-00-00-AA")
        changed.save(to: defaults)
        assert(TVConfiguration.load(from: defaults).mac == "02:00:00:00:00:aa")
        assert(TVConfiguration(host: "192.0.2.10").valid)
        for host in ["", "192..2.10", "192.0.2.300", "192.0.2.10.", "hostname"] {
            assert(!TVConfiguration(host: host).valid)
        }
        assert(!TVConfiguration(host: "192.0.2.10", mac: "bad").valid)
        print("PASS: empty first run, existing preferences, persistence, normalization, optional MAC, invalid values")
    }
}
