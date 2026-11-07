import Foundation
@main struct PowerRegression {
    static func main() {
        assert(TVPowerState.isOn(state: "Active", processing: nil))
        for transition in ["Request Power Off", "Request Active Standby", "Request Suspend", "Prepare Suspend"] {
            assert(!TVPowerState.isOn(state: "Active", processing: transition))
        }
        for state in ["Active Standby", "Suspend", "Power Off", "Unknown"] {
            assert(!TVPowerState.isOn(state: state, processing: nil))
        }
        assert(TVPowerState.isOn(state: "Active", processing: ""))
        print("PASS: real TV shutdown messages, standby, and wake state")
    }
}
