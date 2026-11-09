import Foundation
import Security

@MainActor final class TV: ObservableObject {
    @Published var host: String
    @Published var mac: String
    @Published private(set) var connection: ConnectionState = .offline
    @Published private(set) var navigation: NavigationState = .unavailable
    @Published private(set) var power = PowerState()
    @Published private(set) var macRetrieval: MACRetrievalState = .idle
    @Published private var commandNotice: String?
    @Published var muted = false
    @Published private(set) var discoveredTVs: [DiscoveredTV] = []
    @Published private(set) var discoveryStatus = ""
    @Published private(set) var searching = false
    private var discoveryTask: Task<Void, Never>?
    private var identity: String? = UserDefaults.standard.string(forKey: "tvIdentity")
    private var pendingIdentity: String?
    private var permissionRequested = false
    private var wakeTask: Task<Void, Never>?
    private var wakeGeneration = UUID()
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?

    var connected: Bool { connection.isConnected }
    var navigationReady: Bool { navigation.isReady }
    var waking: Bool { power.isWaking }
    var isTVOn: Bool { power.isOn }
    var macStatus: String { macRetrieval.status }
    var status: String {
        if !discoveryStatus.isEmpty { return discoveryStatus }
        if let commandNotice { return commandNotice }
        if waking { return "WAKING" }
        if case .awaitingApproval = connection { return connection.status }
        if let status = power.status { return status }
        if connected && navigation == .recovering { return "RECONNECTING" }
        return connection.status
    }
    private var heartbeat: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var serial = 0

    init() {
        let configuration = TVConfiguration.load()
        host = configuration.host
        mac = configuration.mac
    }

    func configure(_ configuration: TVConfiguration) {
        guard configuration.valid else { return }
        disconnect()
        if configuration.host != host {
            identity = nil
            UserDefaults.standard.removeObject(forKey: "tvIdentity")
        }
        configuration.save()
        host = configuration.host
        mac = configuration.mac
        connect()
    }

    func findTVs() {
        disconnect()
        discoveredTVs = []
        searching = true
        discoveryStatus = "Searching…"
        let token = generation
        discoveryTask = Task { [weak self] in
            do {
                let found = try await TVDiscovery.scan()
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.discoveredTVs = found
                self.discoveryStatus = found.isEmpty ? "No TVs found. Turn the TV on and try again." : ""
                self.searching = false; self.discoveryTask = nil
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.discoveryFailed(error)
            }
        }
    }

    func selectTV(_ tv: DiscoveredTV) {
        disconnect()
        if identity != tv.id {
            mac = ""
            identity = nil
            UserDefaults.standard.removeObject(forKey: "tvIdentity")
        }
        host = tv.host
        TVConfiguration(host: host, mac: mac).save()
        connect()
    }

    private func discoveryFailed(_ error: Error) {
        searching = false; discoveryTask = nil
        discoveryStatus = (error as? TVDiscovery.Failure) == .networkTooLarge
            ? "Network too large to scan. Enter the TV IP address."
            : "Connect to Wi-Fi and allow Local Network access."
        connection = .failed(.unreachable)
    }

    func connect(requestNetworkPermission: Bool = false) {
        disconnect(stopWake: false)
        let configuration = TVConfiguration(host: host, mac: mac)
        guard configuration.validHost else {
            if host.isEmpty { findTVs() } else { connection = .invalidAddress }
            return
        }
        host = configuration.host
        connection = .connecting(requestNetworkPermission ? .networkPermission : .normal)
        let token = generation
        discoveredTVs = []
        let oldHost = host
        let expected = identity
        discoveryTask = Task { [weak self] in
            var candidate = await TVDiscovery.probe(oldHost)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            if candidate == nil || (expected != nil && candidate?.id != expected) {
                self.searching = true; self.discoveryStatus = "Searching…"
                do {
                    let found = try await TVDiscovery.scan(matching: expected)
                    guard !Task.isCancelled, self.generation == token else { return }
                    self.discoveredTVs = found
                    // A legacy setup with no saved identity must choose explicitly.
                    candidate = expected == nil ? nil : found.first
                } catch {
                    guard !Task.isCancelled, self.generation == token else { return }
                    self.discoveryFailed(error); return
                }
            }
            self.searching = false; self.discoveryTask = nil
            guard let candidate else {
                self.discoveryStatus = self.discoveredTVs.isEmpty ? "No TV found. Turn it on and try again." : "Choose your TV in settings."
                self.connection = .failed(.unreachable); return
            }
            self.discoveryStatus = ""
            self.open(candidate, requestNetworkPermission: requestNetworkPermission)
        }
    }

    private func open(_ tv: DiscoveredTV, requestNetworkPermission: Bool) {
        if identity == tv.id, host != tv.host {
            var cache = UserDefaults.standard.dictionary(forKey: "learnedTVMACs") as? [String: [String]] ?? [:]
            cache[tv.host] = cache[host]
            UserDefaults.standard.set(cache, forKey: "learnedTVMACs")
            var attempted = UserDefaults.standard.stringArray(forKey: "networkPermissionAttemptedHosts") ?? []
            if attempted.contains(host), !attempted.contains(tv.host) {
                attempted.append(tv.host)
                UserDefaults.standard.set(attempted, forKey: "networkPermissionAttemptedHosts")
            }
        }
        host = tv.host
        TVConfiguration(host: host, mac: mac).save()
        pendingIdentity = tv.id
        permissionRequested = requestNetworkPermission
        connection = .connecting(requestNetworkPermission ? .networkPermission : .normal)
        if requestNetworkPermission { macRetrieval = .requestingPermission }
        let token = generation
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://\(host):3000")!)
        socket = task
        task.resume()
        receive(task, token: token)
        // Verify again on the control socket before sharing any pairing credential.
        send(["id": "hello", "type": "hello", "payload": [:]])
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.generation == token, !self.connected else { return }
            if self.connection.upgradingPermission { self.connect(); self.macRetrieval = .permissionDenied; return }
            self.disconnect(); self.connection = .failed(.timedOut)
        }
    }

    private func register() {
        let requestNetworkPermission = permissionRequested
        var payload: [String: Any] = ["pairingType": "PROMPT", "forcePairing": requestNetworkPermission,
            "manifest": ["manifestVersion": 1, "appVersion": "1.0", "permissions": ["READ_NETWORK_STATE", "READ_AUDIO_VOLUME", "CONTROL_AUDIO", "CONTROL_INPUT_JOYSTICK", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "LAUNCH", "CONTROL_POWER"]]]
        if !requestNetworkPermission, let key = storedKey() { payload["client-key"] = key }
        send(["id": "register", "type": "register", "payload": payload])
    }

    func disconnect(stopWake: Bool = true) {
        if stopWake { wakeGeneration = UUID(); wakeTask?.cancel(); wakeTask = nil }
        discoveryTask?.cancel(); discoveryTask = nil
        searching = false; discoveryStatus = ""
        pendingIdentity = nil
        heartbeat?.cancel(); heartbeat = nil
        generation = UUID(); timeout?.cancel(); timeout = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        pointer?.cancel(with: .goingAway, reason: nil); pointer = nil
        navigation = .unavailable
        power.disconnected(cancelWake: stopWake)
        macRetrieval.disconnected()
        connection = .offline
        commandNotice = nil
    }

    private func receive(_ task: URLSessionWebSocketTask, token: UUID) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch result {
                case .failure:
                    if self.connection.upgradingPermission { self.connect(); return }
                    self.disconnect(stopWake: false); self.connection = .failed(.unreachable)
                case .success(let message):
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: return
                    }
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.handle(object) }
                    if self.generation == token { self.receive(task, token: token) }
                }
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        let type = message["type"] as? String
        let id = message["id"] as? String
        let payload = message["payload"] as? [String: Any] ?? [:]
        if type == "hello" {
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let tv = DiscoveredTV.parse(data, host: host), tv.id == pendingIdentity else {
                disconnect(); connection = .failed(.rejected); return
            }
            register()
            return
        }
        if type == "registered" {
            // Copy the existing host-keyed credential on the first successful upgrade.
            let key = payload["client-key"] as? String ?? storedKey()
            identity = pendingIdentity
            UserDefaults.standard.set(identity, forKey: "tvIdentity")
            if let key { saveKey(key) }
            timeout?.cancel(); timeout = nil; connection = .connected; commandNotice = nil
            send(["id": "volume", "type": "subscribe", "uri": "ssap://audio/getVolume"])
            requestPointer()
            send(["id": "power", "type": "subscribe", "uri": "ssap://com.webos.service.tvpower/power/getPowerState"])
            macRetrieval = .reading
            request("com.webos.service.connectionmanager/getinfo", id: "networkInfo")
            monitorConnection()
        } else if id == "register", payload["pairingType"] != nil { connection.awaitApproval() }
        if id == "networkInfo" {
            if type == "error" {
                macRetrieval = .unavailable
                let attempted = UserDefaults.standard.stringArray(forKey: "networkPermissionAttemptedHosts") ?? []
                if (message["error"] as? String)?.hasPrefix("401") == true, !attempted.contains(host) {
                    refreshMACPermission()
                }
            } else {
                let learned = TVNetworkInfo.macAddresses(from: payload, host: host)
                if !learned.isEmpty {
                    var cache = UserDefaults.standard.dictionary(forKey: "learnedTVMACs") as? [String: [String]] ?? [:]
                    cache[host] = learned
                    UserDefaults.standard.set(cache, forKey: "learnedTVMACs")
                    if mac.isEmpty { mac = learned[0] }
                    TVConfiguration(host: host, mac: mac).save()
                    macRetrieval = .retrieved
                } else { macRetrieval = .unavailable }
            }
            return
        }
        if id == "power", type != "error", let state = payload["state"] as? String {
            power.report(isOn: TVPowerState.isOn(state: state, processing: payload["processing"] as? String))
            commandNotice = nil
        }
        if id == "volume" {
            muted = payload["muted"] as? Bool ?? false
        }
        if id == "pointer", let path = payload["socketPath"] as? String, let url = URL(string: path), url.host == host {
            pointer?.cancel(with: .goingAway, reason: nil)
            pointer = URLSession.shared.webSocketTask(with: url); pointer?.resume(); navigation = .ready; commandNotice = nil
        }
        if type == "error" {
            if id == "register" {
                if connection.upgradingPermission { connect(); macRetrieval = .permissionDenied }
                else { disconnect(); connection = .failed(.rejected) }
            }
            else { commandNotice = "COMMAND FAILED" }
        }
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return }
        let token = generation
        socket?.send(.string(text)) { [weak self] error in
            if error != nil { Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.disconnect(stopWake: false); self.connection = .failed(.unreachable)
            } }
        }
    }

    func request(_ uri: String, payload: [String: Any] = [:], id: String? = nil) {
        guard connected else { return }
        serial += 1
        send(["id": id ?? "cmd\(serial)", "type": "request", "uri": "ssap://\(uri)", "payload": payload])
    }
    func button(_ name: String) {
        guard connected, let pointer else { commandNotice = "CONTROLS NOT READY"; return }
        sendInput("type:button\nname:\(name)\n\n", to: pointer)
    }
    func moveCursor(dx: Int, dy: Int) {
        guard let pointer, navigation.beginMovement() else { return }
        let token = generation
        pointer.send(.string("type:move\ndx:\(dx)\ndy:\(dy)\ndown:0\n\n")) { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == token, self.pointer === pointer else { return }
                self.navigation.finishMovement()
                if error != nil { self.recoverPointer(pointer) }
            }
        }
    }

    func clickCursor() {
        guard navigationReady, let pointer else { return }
        sendInput("type:click\n\n", to: pointer)
    }

    private func sendInput(_ command: String, to pointer: URLSessionWebSocketTask) {
        let token = generation
        pointer.send(.string(command)) { [weak self] error in
            if error != nil { Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.recoverPointer(pointer)
            } }
        }
    }

    private func requestPointer() {
        guard connected else { return }
        if navigation != .recovering { navigation = .requesting }
        request("com.webos.service.networkinput/getPointerInputSocket", id: "pointer")
    }

    private func recoverPointer(_ failed: URLSessionWebSocketTask) {
        guard pointer === failed else { return }
        navigation = .recovering
        failed.cancel(with: .goingAway, reason: nil)
        pointer = nil
        requestPointer()
    }

    private func monitorConnection() {
        heartbeat?.cancel()
        let token = generation
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.socket?.sendPing { [weak self] error in
                    if error != nil { Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.connect()
                    } }
                }
                if let input = self.pointer {
                    input.sendPing { [weak self] error in
                        if error != nil { Task { @MainActor in
                            guard let self, self.generation == token else { return }
                            self.recoverPointer(input)
                        } }
                    }
                } else {
                    self.requestPointer()
                }
            }
        }
    }

    func refreshMACPermission() {
        var attempted = UserDefaults.standard.stringArray(forKey: "networkPermissionAttemptedHosts") ?? []
        if !attempted.contains(host) { attempted.append(host) }
        UserDefaults.standard.set(attempted, forKey: "networkPermissionAttemptedHosts")
        connect(requestNetworkPermission: true)
    }

    func powerOn() {
        guard !waking else { return }
        let learned = (UserDefaults.standard.dictionary(forKey: "learnedTVMACs") as? [String: [String]])?[host] ?? []
        let packets = Array(Set([mac] + learned)).compactMap { WakeOnLAN.packet(mac: $0) }
        guard !packets.isEmpty else { power.failWake(.missingAddress); return }
        UserDefaults.standard.set(mac, forKey: "tvMAC")
        disconnect()
        power.startWake()
        let wakeToken = wakeGeneration
        wakeTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.wakeGeneration == wakeToken { self.wakeTask = nil } }
            var sentAny = false
            for attempt in 1...8 {
                guard !Task.isCancelled else { return }
                self.power.attempt(attempt)
                let sent = packets.map { WakeOnLAN.send(packet: $0, host: self.host) }.contains(true)
                sentAny = sentAny || sent
                // A failed wake packet must not prevent finding an already-on TV.
                if self.discoveryTask == nil {
                    switch self.connection {
                    case .offline, .failed: self.connect()
                    default: break
                    }
                }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                if self.isTVOn { self.power.finishWake(); return }
            }
            self.disconnect(stopWake: false)
            self.power.failWake(sentAny ? .timedOut : .sendFailed)
        }
    }
    func powerOff() { request("system/turnOff"); power.turnOff(); commandNotice = nil }
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "is.chad.remote.v3", kSecAttrAccount as String: identity.map { "tv:\($0)" } ?? host]
    }
    private func storedKey() -> String? {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func saveKey(_ key: String) {
        var query = keyQuery
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}
