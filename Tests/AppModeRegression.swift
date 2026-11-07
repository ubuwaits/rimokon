import Foundation
@main struct AppModeRegression {
    static func main() {
        for (x,y,name) in [(25.0,0.0,"RIGHT"),(-25.0,0.0,"LEFT"),(0.0,25.0,"DOWN"),(0.0,-25.0,"UP")] {
            var swipe = DirectionalSwipe()
            assert(swipe.update(dx: x / 2, dy: y / 2).isEmpty)
            assert(swipe.update(dx: x / 2, dy: y / 2) == [name])
            assert(swipe.update(dx: x * 5, dy: y * 5) == Array(repeating: name, count: 3))
            assert(swipe.update(dx: 0, dy: 0).isEmpty)
        }
        var fast = DirectionalSwipe(), slow = DirectionalSwipe()
        let fastSteps = fast.update(dx: 202, dy: 0)
        var slowSteps: [String] = []
        for _ in 0..<202 { slowSteps += slow.update(dx: 1, dy: 0) }
        assert(fastSteps == slowSteps && fastSteps.count == 6)
        var diagonal = DirectionalSwipe()
        assert(diagonal.update(dx: 22, dy: 12) == ["RIGHT"])
        assert(diagonal.update(dx: 0, dy: 100).isEmpty)
        assert(diagonal.update(dx: -36, dy: 0) == ["LEFT"])
        var fresh = DirectionalSwipe()
        assert(fresh.update(dx: 10, dy: 0).isEmpty)
        print("PASS: short and long swipes, all directions, sample-rate independence, axis lock, reversal, reset")
    }
}
