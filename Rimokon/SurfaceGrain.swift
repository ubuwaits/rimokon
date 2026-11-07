import SwiftUI
import UIKit

struct SurfaceGrain: View {
    private static let tile: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var seed: UInt64 = 0x734192
        return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
            for y in 0..<96 {
                for x in 0..<96 {
                    seed = seed &* 6364136223846793005 &+ 1
                    let value = Double((seed >> 32) & 255) / 255
                    context.cgContext.setFillColor(UIColor(white: value > 0.5 ? 1 : 0, alpha: abs(value - 0.5) * 0.035).cgColor)
                    context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
    var body: some View {
        Image(uiImage: Self.tile).resizable(resizingMode: .tile)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
