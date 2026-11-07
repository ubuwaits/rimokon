import Foundation

enum TrackpadMode: Equatable {
    case cursor, directional
}

struct DirectionalSwipe {
    private var x = 0.0
    private var y = 0.0
    private var horizontal: Bool?
    private var remainder = 0.0
    private var threshold = 22.0

    mutating func update(dx: Double, dy: Double) -> [String] {
        guard dx.isFinite, dy.isFinite else { return [] }
        if horizontal == nil {
            x += dx; y += dy
            guard max(abs(x), abs(y)) >= threshold else { return [] }
            horizontal = abs(x) > abs(y)
            remainder = horizontal == true ? x : y
        } else {
            remainder += horizontal == true ? dx : dy
        }
        var steps: [String] = []
        while abs(remainder) >= threshold {
            let positive = remainder > 0
            steps.append(horizontal == true ? (positive ? "RIGHT" : "LEFT") : (positive ? "DOWN" : "UP"))
            remainder -= positive ? threshold : -threshold
            threshold = 36
        }
        return steps
    }
}
