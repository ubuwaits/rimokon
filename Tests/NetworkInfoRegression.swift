import Foundation
@main struct NetworkInfoRegression {
    static func main() {
        let wired = "02:00:00:00:00:01", wifi = "02:00:00:00:00:02"
        let response: [String: Any] = ["returnValue": true,
            "wiredInfo": ["macAddress": wired],
            "wifiInfo": ["macAddress": wifi, "ipAddress": "192.0.2.10"],
            "p2pInfo": ["macAddress": "02:00:00:00:00:03"]]
        assert(TVNetworkInfo.macAddresses(from: response, host: "192.0.2.10") == [wifi,wired])
        assert(TVNetworkInfo.macAddresses(from: [:], host: "192.0.2.10").isEmpty)
        assert(TVNetworkInfo.macAddresses(from: ["returnValue": false, "wiredInfo": ["macAddress": wired]], host: "192.0.2.10").isEmpty)
        for invalid in ["00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "invalid"] {
            assert(TVNetworkInfo.macAddresses(from: ["wifiInfo": ["macAddress": invalid]], host: "192.0.2.10").isEmpty)
        }
        assert(TVNetworkInfo.macAddresses(from: ["wiredInfo": ["macAddress": wired], "wifiInfo": ["macAddress": wired]], host: "192.0.2.10") == [wired])
        print("PASS: interface selection, fallback addresses, deduplication, invalid MACs, errors, P2P exclusion")
    }
}
