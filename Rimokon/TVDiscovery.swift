import Foundation
import Darwin

struct DiscoveredTV: Identifiable, Equatable, Sendable {
    let id: String
    let host: String
    let name: String

    static func parse(_ data: Data, host: String) -> Self? {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["type"] as? String == "hello",
              let payload = message["payload"] as? [String: Any],
              payload["deviceType"] as? String == "tv", payload["deviceOS"] as? String == "webOS",
              let id = payload["deviceUUID"] as? String, UUID(uuidString: id) != nil else { return nil }
        return Self(id: id.lowercased(), host: host, name: payload["modelName"] as? String ?? "LG webOS TV")
    }
}

enum TVDiscovery {
    enum Failure: Error { case noWiFi, networkTooLarge }

    // Only directly attached Wi-Fi/Ethernet IPv4 networks; never VPN or cellular.
    static func localHosts() throws -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { throw Failure.noWiFi }
        defer { freeifaddrs(interfaces) }
        var hosts = Set<String>()
        var oversized = false
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            let item = interface.pointee
            guard String(cString: item.ifa_name).hasPrefix("en"),
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let mask = item.ifa_netmask else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
            let netmask = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
            do { hosts.formUnion(try hostsInSubnet(address: ip, mask: netmask)) }
            catch { oversized = true }
        }
        guard !hosts.isEmpty else { throw oversized ? Failure.networkTooLarge : Failure.noWiFi }
        return hosts.sorted()
    }

    static func hostsInSubnet(address: UInt32, mask: UInt32) throws -> [String] {
        let size = ~mask
        guard size <= 1023 else { throw Failure.networkTooLarge }
        guard size > 1, size & (size + 1) == 0 else { return [] }
        let network = address & mask
        return (1..<size).map { network + $0 }.filter { $0 != address }.map { ip in
            [24, 16, 8, 0].map { String((ip >> $0) & 255) }.joined(separator: ".")
        }
    }

    static func probe(_ host: String) async -> DiscoveredTV? {
        guard !Task.isCancelled, TVConfiguration(host: host, mac: "").validHost,
              let url = URL(string: "ws://\(host):3000") else { return nil }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 16384
        let deadline = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { deadline.cancel(); socket.cancel(with: .goingAway, reason: nil) }
        return await withTaskCancellationHandler {
            do {
                socket.resume()
                try Task.checkCancellation()
                try await socket.send(.string("{\"id\":\"hello\",\"type\":\"hello\",\"payload\":{}}"))
                let message = try await socket.receive()
                try Task.checkCancellation()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: return nil
                }
                return DiscoveredTV.parse(data, host: host)
            } catch { return nil }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }

    private enum Resolution { case found(DiscoveredTV), exhausted, expired }

    // The TV's control server can disappear briefly between standby and startup.
    // Keep retrying its saved address while discovery checks for a changed address.
    static func resolve(
        host: String, identity: String,
        probe: @escaping @Sendable (String) async -> DiscoveredTV? = { await TVDiscovery.probe($0) },
        scan: @escaping @Sendable (String) async throws -> [DiscoveredTV] = { try await TVDiscovery.scan(matching: $0) },
        pause: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(2)) },
        timeout: Duration = .seconds(60)
    ) async -> DiscoveredTV? {
        await withTaskGroup(of: Resolution.self) { group in
            group.addTask {
                for _ in 0..<30 {
                    guard !Task.isCancelled else { return .exhausted }
                    if let tv = await probe(host), tv.id == identity { return .found(tv) }
                    do { try await pause() } catch { return .exhausted }
                }
                return .exhausted
            }
            group.addTask {
                // Allow a normal startup a few direct retries before scanning.
                for _ in 0..<2 {
                    do {
                        for _ in 0..<3 { try await pause() }
                        guard !Task.isCancelled else { return .exhausted }
                        if let tv = try await scan(identity).first(where: { $0.id == identity }) {
                            return .found(tv)
                        }
                    } catch {
                        // A missing Wi-Fi interface must not cancel direct retries.
                        if Task.isCancelled { return .exhausted }
                    }
                }
                return .exhausted
            }
            group.addTask {
                do { try await Task.sleep(for: timeout) } catch { return .exhausted }
                return .expired
            }
            var exhausted = 0
            while let result = await group.next() {
                if Task.isCancelled { break }
                switch result {
                case .found(let tv): group.cancelAll(); return tv
                case .expired: group.cancelAll(); return nil
                case .exhausted:
                    exhausted += 1
                    if exhausted == 2 { group.cancelAll(); return nil }
                }
            }
            group.cancelAll()
            return nil
        }
    }

    static func scan(matching identity: String? = nil) async throws -> [DiscoveredTV] {
        let hosts = try localHosts()
        return await withTaskGroup(of: DiscoveredTV?.self) { group in
            var remaining = hosts.makeIterator()
            for _ in 0..<24 {
                if let host = remaining.next() { group.addTask { await probe(host) } }
            }
            var found: [DiscoveredTV] = []
            while let result = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                if let tv = result, identity == nil || tv.id == identity {
                    if !found.contains(where: { $0.id == tv.id }) { found.append(tv) }
                    if identity != nil { group.cancelAll(); break }
                }
                if let host = remaining.next() { group.addTask { await probe(host) } }
            }
            return found.sorted { $0.host < $1.host }
        }
    }
}
