import Foundation

@main struct DiscoveryRegression {
    static func main() async throws {
        // Respect the real subnet, excluding self, network and broadcast addresses.
        let hosts = try TVDiscovery.hostsInSubnet(address: 0xc0000202, mask: 0xfffffffc)
        assert(hosts == ["192.0.2.1"])
        let wider = try TVDiscovery.hostsInSubnet(address: 0xc0000202, mask: 0xfffffe00)
        assert(wider.count == 509 && wider.contains("192.0.3.254"))
        assert(!wider.contains("192.0.2.2") && !wider.contains("192.0.3.255"))
        do {
            _ = try TVDiscovery.hostsInSubnet(address: 0xc0000202, mask: 0xffff0000)
            assertionFailure("Unbounded scan")
        } catch TVDiscovery.Failure.networkTooLarge {}

        let payload: [String: Any] = ["deviceType": "tv", "deviceOS": "webOS",
            "deviceUUID": "12345678-1234-1234-ABCD-123456789012"]
        func parse(_ payload: [String: Any], type: String = "hello") throws -> DiscoveredTV? {
            DiscoveredTV.parse(try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload]), host: "192.0.2.1")
        }
        let tv = try parse(payload)
        assert(tv?.id == "12345678-1234-1234-abcd-123456789012")
        for field in ["deviceType", "deviceOS", "deviceUUID"] {
            var invalid = payload; invalid[field] = "other"
            let result = try parse(invalid)
            assert(result == nil, "Must not treat arbitrary services as TVs")
        }
        let error = try parse(payload, type: "error")
        assert(error == nil)
        assert(DiscoveredTV.parse(Data("Hello world".utf8), host: "192.0.2.1") == nil)
        let cancelled = Task { await TVDiscovery.probe("192.0.2.1") }
        cancelled.cancel()
        let result = await cancelled.value
        assert(result == nil)
        print("PASS: subnet boundaries, scan limits, TV identity validation and cancellation")
    }
}
