import SwiftUI

@main struct RimokonApp: App {
    var body: some Scene { WindowGroup { RimokonView() } }
}

enum RimokonPalette {
    static let background = Color(white: 16.5 / 255)
    static let surface = Color(white: 30.5 / 255)
    static let text = Color(white: 237.0 / 255)
    static let buttonTop = Color(white: 56.2 / 255)
    static let buttonBottom = Color(white: 42.3 / 255)
    static let muted = Color(white: 187.5 / 255)
}

struct RimokonView: View {
    @StateObject private var tv = TV()
    @AppStorage("cursorModeEnabled") private var cursorModeEnabled = false
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    @State private var confirmPower = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        key("power", tv.isTVOn ? "Power off" : "Power on", requiresConnection: false) {
                            if tv.isTVOn { confirmPower = true } else if tv.mac.isEmpty || tv.host.isEmpty { settings = true } else { tv.powerOn() }
                        }.disabled(tv.waking)
                        Button { feedback(); settings = true } label: {
                            Circle()
                                .fill(LinearGradient(colors: [RimokonPalette.buttonTop, RimokonPalette.buttonBottom], startPoint: .top, endPoint: .bottom))
                                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 0.5))
                                .frame(width: 18, height: 18)
                                .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 1)
                                .frame(width: 44, height: 48)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Rimokon settings")
                        key("speaker.slash", "Mute", selected: tv.muted) {
                            tv.request("audio/setMute", payload: ["mute": !tv.muted])
                        }
                    }
                    CursorPad(enabled: pointerAllowed, mode: trackpadMode, direction: { tv.button($0) }, move: { tv.moveCursor(dx: $0, dy: $1) },
                              select: { if trackpadMode == .directional { tv.button("ENTER") } else { tv.clickCursor() } })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            key("arrow.uturn.backward", "Back") { tv.button("BACK") }
                            key("house", "Home") { tv.button("HOME") }
                            key("gearshape", "TV settings") { tv.button("MENU") }
                        }
                        HStack(spacing: 12) {
                            VStack(spacing: 8) {
                                key("plus", "Volume up") { tv.request("audio/volumeUp") }
                                controlLabel("VOL")
                                key("minus", "Volume down") { tv.request("audio/volumeDown") }
                            }
                            VStack(spacing: 8) {
                                key("chevron.up", "Channel up") { tv.request("tv/channelUp") }
                                controlLabel("CH")
                                key("chevron.down", "Channel down") { tv.request("tv/channelDown") }
                            }
                        }
                    }
                }
                .frame(height: max(geometry.size.height - 40, 544))
                .padding(20)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
        .foregroundStyle(RimokonPalette.text).background { RimokonPalette.background.overlay(SurfaceGrain()).ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .tint(RimokonPalette.text)
        .sheet(isPresented: $settings, onDismiss: {
            guard phase == .active, !tv.host.isEmpty else { return }
            switch tv.connection {
            case .offline, .failed: tv.connect()
            default: break
            }
        }) {
            TVSettingsView(tv: tv, cursorModeEnabled: $cursorModeEnabled)
        }

        .confirmationDialog("Turn off TV?", isPresented: $confirmPower, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) { tv.powerOff() }
        }
        .onChange(of: phase) { _, value in
            if value == .active && !tv.host.isEmpty { tv.connect() }
            else if value == .background { tv.disconnect() }
        }
        .task {
            if tv.host.isEmpty { settings = true } else { tv.connect() }
        }
    }
    private func controlLabel(_ text: String) -> some View {
        // Space only between letters, so trailing tracking cannot bias centering.
        HStack(spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(RimokonPalette.muted)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var trackpadMode: TrackpadMode { cursorModeEnabled ? .cursor : .directional }
    private var pointerAllowed: Bool {
        phase == .active && tv.navigationReady && !settings && !confirmPower
    }
    private func feedback() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func key(_ symbol: String, _ label: String, selected: Bool = false, requiresConnection: Bool = true, action: @escaping () -> Void) -> some View {
        Button { feedback(); action() } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 48)
        }.buttonStyle(RimokonKey(selected: selected)).disabled(requiresConnection && !tv.connected).accessibilityLabel(label)
    }
}

struct RimokonKey: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : RimokonPalette.text)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [selected ? Color(white: 77.2 / 255) : RimokonPalette.buttonTop,
                                                  selected ? Color(white: 60.2 / 255) : RimokonPalette.buttonBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(SurfaceGrain().opacity(0.55).clipShape(RoundedRectangle(cornerRadius: 10)))
            }
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
            .compositingGroup()
            .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: configuration.isPressed ? 0 : 2)
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: configuration.isPressed ? 0 : 3)
            .offset(y: configuration.isPressed ? 1.5 : 0)
    }
}
