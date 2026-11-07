@main struct RecoveryRegression {
    static func main() {
        navigationRecovery()
        wakeSurvivesReconnect()
        cancelledWakeCannotResume()
        print("PASS: navigation recovery, wake across reconnects, wake cancellation")
    }

    static func navigationRecovery() {
        var navigation = NavigationState.ready
        let started = navigation.beginMovement()
        precondition(started && navigation.isReady)
        let overlapping = navigation.beginMovement()
        precondition(!overlapping, "Only one cursor movement may be in flight")

        for interrupted in [NavigationState.recovering, .unavailable] {
            navigation = interrupted
            navigation.finishMovement()
            precondition(navigation == interrupted, "Late completion must not restore failed controls")
        }
        navigation = .ready
        let resumed = navigation.beginMovement()
        precondition(resumed, "Movement must resume after socket recovery")
    }

    static func wakeSurvivesReconnect() {
        var power = PowerState()
        power.startWake()
        power.attempt(1)
        power.disconnected(cancelWake: false)
        power.report(isOn: false)
        precondition(power.isWaking, "Reconnect and standby reports must not stop wake retries")
        power.attempt(2)
        precondition(power.wake == .attempting(2))
        power.report(isOn: true)
        power.finishWake()
        precondition(power.isOn && !power.isWaking, "Confirmed power-on must finish the wake operation")
    }

    static func cancelledWakeCannotResume() {
        var power = PowerState()
        power.startWake()
        power.disconnected(cancelWake: true)
        power.attempt(2)
        power.finishWake()
        precondition(power.wake == .idle, "A cancelled wake must ignore further attempts and completion")
    }
}
