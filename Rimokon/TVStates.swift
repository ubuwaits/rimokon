import Foundation

enum ConnectionState: Equatable {
    enum Purpose { case normal, networkPermission }
    enum Failure { case unreachable, timedOut, rejected }
    case offline, needsConfiguration, invalidAddress
    case connecting(Purpose), awaitingApproval(Purpose), connected, failed(Failure)

    var isConnected: Bool { self == .connected }
    var upgradingPermission: Bool {
        self == .connecting(.networkPermission) || self == .awaitingApproval(.networkPermission)
    }
    mutating func awaitApproval() {
        if case .connecting(let purpose) = self { self = .awaitingApproval(purpose) }
    }
    var status: String {
        switch self {
        case .offline: return "OFFLINE"
        case .needsConfiguration: return "SET UP TV"
        case .invalidAddress: return "CHECK IP ADDRESS"
        case .connecting: return "CONNECTING"
        case .awaitingApproval: return "ACCEPT ON TV"
        case .connected: return "CONNECTED"
        case .failed(.unreachable): return "TV UNREACHABLE"
        case .failed(.timedOut): return "CONNECTION TIMED OUT"
        case .failed(.rejected): return "PAIRING REJECTED"
        }
    }
}

enum NavigationState: Equatable {
    case unavailable, requesting, ready, sendingMovement, recovering
    var isReady: Bool { self == .ready || self == .sendingMovement }
    mutating func beginMovement() -> Bool {
        guard self == .ready else { return false }
        self = .sendingMovement
        return true
    }
    mutating func finishMovement() {
        if self == .sendingMovement { self = .ready }
    }
}

struct PowerState: Equatable {
    enum Observed { case unknown, on, standby, turningOff }
    enum Wake: Equatable {
        case idle, attempting(Int), succeeded, failed(Failure)
        enum Failure { case missingAddress, sendFailed, timedOut }
        var isActive: Bool { if case .attempting = self { return true }; return false }
    }
    private(set) var observed: Observed = .unknown
    private(set) var wake: Wake = .idle
    var isOn: Bool { observed == .on }
    var isWaking: Bool { wake.isActive }
    mutating func disconnected(cancelWake: Bool) {
        observed = .unknown
        if cancelWake || !isWaking { wake = .idle }
    }
    mutating func report(isOn: Bool) { observed = isOn ? .on : .standby }
    mutating func turnOff() { observed = .turningOff }
    mutating func startWake() { wake = .attempting(0) }
    mutating func attempt(_ number: Int) {
        guard isWaking else { return }
        wake = .attempting(number)
    }
    mutating func finishWake() { if isWaking { wake = .succeeded } }
    mutating func failWake(_ reason: Wake.Failure) { wake = .failed(reason) }
    var status: String? {
        switch wake {
        case .attempting: return "WAKING"
        case .failed(.missingAddress): return "CHECK MAC ADDRESS"
        case .failed(.sendFailed): return "WAKE SEND FAILED"
        case .failed(.timedOut): return "TV DID NOT WAKE"
        default: break
        }
        switch observed {
        case .turningOff: return "TURNING OFF"
        case .standby: return "STANDBY"
        default: return nil
        }
    }
}

enum MACRetrievalState: Equatable {
    case idle, reading, requestingPermission, retrieved, unavailable, permissionDenied
    mutating func disconnected() {
        if self == .reading || self == .requestingPermission { self = .idle }
    }
    var status: String {
        switch self {
        case .idle: return ""
        case .reading: return "Reading MAC address…"
        case .requestingPermission: return "Accept network permission on TV"
        case .retrieved: return "MAC retrieved automatically"
        case .unavailable: return "Automatic MAC unavailable; saved address kept"
        case .permissionDenied: return "MAC permission not granted"
        }
    }
}
