import SwiftUI
import UIKit

struct CursorPad: View {
    let enabled: Bool
    let mode: TrackpadMode
    let direction: (String) -> Void
    let move: (Int, Int) -> Void
    let select: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(LinearGradient(colors: [RimokonPalette.surface, Color(white: 25.5 / 255)], startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: .black.opacity(0.55), radius: 4, x: 0, y: 2))
                .shadow(.inner(color: .white.opacity(0.045), radius: 1, x: 0, y: -1)))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(SurfaceGrain().clipShape(RoundedRectangle(cornerRadius: 22)))
            .overlay(PadInput(enabled: enabled, mode: mode, direction: direction, move: move, select: select))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cursor touchpad")
            .accessibilityHint(mode == .directional ? "Swipe to navigate. Tap for OK." : "Slide your finger to move the cursor. Tap to select.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { select() } }
    }
}

private struct PadInput: UIViewRepresentable {
    let enabled: Bool
    let mode: TrackpadMode
    let direction: (String) -> Void
    let move: (Int, Int) -> Void
    let select: () -> Void

    func makeUIView(context: Context) -> PadView { PadView() }
    func updateUIView(_ view: PadView, context: Context) {
        view.setMode(mode)
        view.direction = direction
        view.move = move
        view.select = select
        view.setEnabled(enabled)
    }
    static func dismantleUIView(_ view: PadView, coordinator: ()) { view.finish() }
}

private final class PadView: UIView {
    private var mode = TrackpadMode.cursor
    private var swipe = DirectionalSwipe()
    var direction: (String) -> Void = { _ in }
    var move: (Int, Int) -> Void = { _, _ in }
    var select: () -> Void = {}
    private var delta = TrackpadDelta()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped))

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        pan.maximumNumberOfTouches = 1
        tap.require(toFail: pan)
        addGestureRecognizer(pan)
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setEnabled(_ enabled: Bool) {
        if !enabled { finish() }
        if pan.isEnabled != enabled { pan.isEnabled = enabled; tap.isEnabled = enabled }
    }
    func setMode(_ next: TrackpadMode) {
        guard mode != next else { return }
        // Cancel an in-progress gesture so it cannot select in a different app.
        let wasEnabled = pan.isEnabled
        pan.isEnabled = false; tap.isEnabled = false
        finish(); mode = next
        pan.isEnabled = wasEnabled; tap.isEnabled = wasEnabled
    }
    @objc private func dragged() {
        switch pan.state {
        case .began, .changed, .ended:
            let translation = pan.translation(in: self)
            pan.setTranslation(.zero, in: self)
            if mode == .directional {
                for name in swipe.update(dx: translation.x, dy: translation.y) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    direction(name)
                }
            } else {
                let (dx, dy) = delta.update(x: translation.x, y: translation.y)
                if dx != 0 || dy != 0 { move(dx, dy) }
            }
            if pan.state == .ended { finish() }
        case .cancelled, .failed: finish()
        default: break
        }
    }
    @objc private func tapped() {
        guard tap.state == .ended else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        select()
    }
    func finish() { delta = TrackpadDelta(); swipe = DirectionalSwipe() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finish(); return }
        // Finger movement on the pad controls the TV, not the surrounding page.
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                scroll.panGestureRecognizer.require(toFail: pan)
                break
            }
            ancestor = view.superview
        }
    }
}
