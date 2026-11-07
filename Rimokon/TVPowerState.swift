import Foundation

enum TVPowerState {
    static func isOn(state: String, processing: String?) -> Bool {
        let transition = (processing ?? "").lowercased()
        if transition.contains("power off") || transition.contains("standby") || transition.contains("suspend") { return false }
        return ["active", "screen saver", "screen off"].contains(state.lowercased())
    }
}
