import Foundation
import Security

@MainActor final class TV: ObservableObject {
    @Published var host = TVConfiguration.load().host
    @Published var mac = TVConfiguration.load().mac
    @Published var waking = false
    private var wakeTask: Task<Void, Never>?
    @Published var status = "OFFLINE"
    @Published var connected = false
    @Published var isTVOn = false
    @Published var navigationReady = false
    @Published var volume: Int?
    @Published var muted = false
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var cursorSendInFlight = false
    private var heartbeat: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var serial = 0

    func configure(_ configuration: TVConfiguration) {
        guard configuration.valid else { return }
        disconnect()
        configuration.save()
        host = configuration.host
        mac = configuration.mac
        connect()
    }

    func connect() {
        disconnect(stopWake: false)
        let configuration = TVConfiguration(host: host, mac: mac)
        guard configuration.validHost,
              let url = URL(string: "ws://\(configuration.host):3000") else {
            status = host.isEmpty ? "SET UP TV" : "CHECK IP ADDRESS"
            return
        }
        host = configuration.host
        UserDefaults.standard.set(host, forKey: "tvHost")
        status = "CONNECTING"
        let token = generation
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(task, token: token)
        var payload: [String: Any] = ["pairingType": "PROMPT", "forcePairing": false,
            "manifest": ["manifestVersion": 1, "appVersion": "1.0", "permissions": ["READ_AUDIO_VOLUME", "CONTROL_AUDIO", "CONTROL_INPUT_JOYSTICK", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "LAUNCH", "CONTROL_POWER"]]]
        if let key = storedKey() { payload["client-key"] = key }
        send(["id": "register", "type": "register", "payload": payload])
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.generation == token, !self.connected else { return }
            self.disconnect(); self.status = "CONNECTION TIMED OUT"
        }
    }

    func disconnect(stopWake: Bool = true) {
        if stopWake { wakeTask?.cancel(); wakeTask = nil; waking = false }
        heartbeat?.cancel(); heartbeat = nil
        generation = UUID(); timeout?.cancel(); timeout = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        pointer?.cancel(with: .goingAway, reason: nil); pointer = nil
        cursorSendInFlight = false
        navigationReady = false
        isTVOn = false
        connected = false; volume = nil; status = "OFFLINE"
    }

    private func receive(_ task: URLSessionWebSocketTask, token: UUID) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch result {
                case .failure:
                    self.disconnect(stopWake: false); self.status = self.waking ? "WAKING" : "TV UNREACHABLE"
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
        if type == "registered" {
            if let key = payload["client-key"] as? String { saveKey(key) }
            timeout?.cancel(); connected = true; status = "CONNECTED"
            send(["id": "volume", "type": "subscribe", "uri": "ssap://audio/getVolume"])
            request("com.webos.service.networkinput/getPointerInputSocket", id: "pointer")
            send(["id": "power", "type": "subscribe", "uri": "ssap://com.webos.service.tvpower/power/getPowerState"])
            monitorConnection()
        } else if id == "register", payload["pairingType"] != nil { status = "ACCEPT ON TV" }
        if id == "power", type != "error", let state = payload["state"] as? String {
            isTVOn = TVPowerState.isOn(state: state, processing: payload["processing"] as? String)
            if isTVOn { status = "CONNECTED" }
            else if !waking { status = "STANDBY" }
        }
        if id == "volume" {
            volume = payload["volume"] as? Int
            muted = payload["muted"] as? Bool ?? false
        }
        if id == "pointer", let path = payload["socketPath"] as? String, let url = URL(string: path), url.host == host {
            pointer?.cancel(with: .goingAway, reason: nil)
            pointer = URLSession.shared.webSocketTask(with: url); pointer?.resume(); navigationReady = true; status = "CONNECTED"
        }
        if type == "error" {
            if id == "register" { disconnect(); status = "PAIRING REJECTED" }
            else { status = "COMMAND FAILED" }
        }
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return }
        let token = generation
        socket?.send(.string(text)) { [weak self] error in
            if error != nil { Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.disconnect(stopWake: false); self.status = self.waking ? "WAKING" : "TV UNREACHABLE"
            } }
        }
    }

    func request(_ uri: String, payload: [String: Any] = [:], id: String? = nil) {
        guard connected else { return }
        serial += 1
        send(["id": id ?? "cmd\(serial)", "type": "request", "uri": "ssap://\(uri)", "payload": payload])
    }
    func button(_ name: String) {
        guard connected, let pointer else { status = "CONTROLS NOT READY"; return }
        let token = generation
        pointer.send(.string("type:button\nname:\(name)\n\n")) { [weak self] error in
            if error != nil { Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.recoverPointer(pointer)
            } }
        }
    }
    func moveCursor(dx: Int, dy: Int) {
        guard navigationReady, !cursorSendInFlight, let pointer else { return }
        cursorSendInFlight = true
        let token = generation
        pointer.send(.string("type:move\ndx:\(dx)\ndy:\(dy)\ndown:0\n\n")) { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == token, self.pointer === pointer else { return }
                self.cursorSendInFlight = false
                if error != nil { self.recoverPointer(pointer) }
            }
        }
    }

    func clickCursor() {
        guard navigationReady, let pointer else { return }
        let token = generation
        pointer.send(.string("type:click\n\n")) { [weak self] error in
            if error != nil { Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.recoverPointer(pointer)
            } }
        }
    }

    private func recoverPointer(_ failed: URLSessionWebSocketTask) {
        guard pointer === failed else { return }
        cursorSendInFlight = false
        navigationReady = false
        failed.cancel(with: .goingAway, reason: nil)
        pointer = nil
        status = "RECONNECTING"
        request("com.webos.service.networkinput/getPointerInputSocket", id: "pointer")
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
                    self.request("com.webos.service.networkinput/getPointerInputSocket", id: "pointer")
                }
            }
        }
    }

    func powerOn() {
        guard !waking else { return }
        guard let packet = WakeOnLAN.packet(mac: mac) else { status = "CHECK MAC ADDRESS"; return }
        UserDefaults.standard.set(mac, forKey: "tvMAC")
        disconnect()
        waking = true; status = "WAKING"
        wakeTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<8 {
                guard !Task.isCancelled else { return }
                guard WakeOnLAN.send(packet: packet, host: self.host) else {
                    self.waking = false; self.status = "WAKE SEND FAILED"; return
                }
                self.connect()
                if !self.isTVOn { self.status = "WAKING" }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                if self.isTVOn { self.waking = false; return }
            }
            self.disconnect(stopWake: false)
            self.waking = false; self.status = "TV DID NOT WAKE"
        }
    }
    func powerOff() { request("system/turnOff"); isTVOn = false; status = "TURNING OFF" }
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "is.chad.remote.v3", kSecAttrAccount as String: host]
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
