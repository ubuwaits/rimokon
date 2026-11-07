import Foundation
@main struct TrackpadRegression {
    static func main() {
        var pad = TrackpadDelta()
        assert(pad.update(x: 10, y: -5) == (30, -15))
        assert(pad.update(x: -10, y: 5) == (-30, 15))
        assert(pad.update(x: 0, y: 0) == (0, 0))
        assert(pad.update(x: 0.2, y: 0) == (0, 0))
        assert(pad.update(x: 0.2, y: 0) == (1, 0))
        pad = TrackpadDelta()
        assert(pad.update(x: 0, y: 0) == (0, 0))
        print("PASS: finger direction, gain, fractional movement, no movement on touch/release reset")
    }
}
