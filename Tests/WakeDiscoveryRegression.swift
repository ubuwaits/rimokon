import Foundation

@main struct WakeDiscoveryRegression {
    actor Scenario {
        var probes = 0
        var scans = 0
        let tv = DiscoveredTV(id: "saved-tv", host: "192.0.2.10", name: "TV")
        func booting() -> DiscoveredTV? {
            probes += 1
            return probes >= 5 ? tv : nil
        }
        func moved() -> [DiscoveredTV] {
            scans += 1
            return scans >= 2 ? [tv] : []
        }
    }
    static func main() async {
        let pause: @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(5)) }
        let startup = Scenario()
        let recovered = await TVDiscovery.resolve(host: "192.0.2.10", identity: "saved-tv",
            probe: { _ in await startup.booting() }, scan: { _ in [] }, pause: pause)
        precondition(recovered?.id == "saved-tv", "An empty scan must not end retries during startup")

        let moved = Scenario()
        let wrongTV = DiscoveredTV(id: "another-tv", host: "192.0.2.10", name: "Other TV")
        let rediscovered = await TVDiscovery.resolve(host: "192.0.2.10", identity: "saved-tv",
            probe: { _ in wrongTV }, scan: { _ in await moved.moved() }, pause: pause)
        precondition(rediscovered?.id == "saved-tv", "Retry discovery after a startup miss; reject wrong identity")

        let unavailable = await TVDiscovery.resolve(host: "192.0.2.10", identity: "saved-tv",
            probe: { _ in nil }, scan: { _ in [] }, pause: pause, timeout: .milliseconds(20))
        precondition(unavailable == nil, "Unavailable TVs must time out")
        let cancelled = Task {
            await TVDiscovery.resolve(host: "192.0.2.10", identity: "saved-tv",
                probe: { _ in nil }, scan: { _ in [] }, pause: pause)
        }
        cancelled.cancel()
        let result = await cancelled.value
        precondition(result == nil, "Background cancellation must not reconnect")
        print("PASS: delayed startup, empty discovery, changed address, identity filtering, timeout, cancellation")
    }
}
