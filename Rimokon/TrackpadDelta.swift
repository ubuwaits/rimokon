import Foundation

struct TrackpadDelta {
    private var remainderX = 0.0
    private var remainderY = 0.0
    mutating func update(x: Double, y: Double) -> (Int, Int) {
        remainderX += x * 3
        remainderY += y * 3
        let dx = Int(remainderX), dy = Int(remainderY)
        remainderX -= Double(dx); remainderY -= Double(dy)
        return (dx, dy)
    }
}
