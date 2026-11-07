import SwiftUI

struct TVSettingsView: View {
    @ObservedObject var tv: TV
    @Binding var cursorModeEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var host: String
    @State private var mac: String

    init(tv: TV, cursorModeEnabled: Binding<Bool>) {
        self.tv = tv
        self._cursorModeEnabled = cursorModeEnabled
        _host = State(initialValue: tv.host)
        _mac = State(initialValue: tv.mac)
    }
    private var configuration: TVConfiguration { TVConfiguration(host: host, mac: mac) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("TV IP address", text: $host).keyboardType(.decimalPad).autocorrectionDisabled()
                        .accessibilityLabel("TV IP address")

                } footer: {
                    Text("Enter the IP from your TV’s network settings. The wake address is retrieved after pairing.")
                }
                Button("Save & connect") {
                    tv.configure(configuration)
                    dismiss()
                }.disabled(!configuration.valid)
                DisclosureGroup("Power-on settings") {
                    TextField("MAC address (automatic)", text: $mac).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("TV MAC address")
                    if !tv.macStatus.isEmpty { Text(tv.macStatus).font(.caption) }
                    Button("Retrieve MAC again") { tv.refreshMACPermission() }.disabled(!tv.connected)
                }
                Toggle("Cursor mode", isOn: $cursorModeEnabled)
                if !tv.status.isEmpty { Text(tv.status).font(.system(.caption, design: .monospaced)) }
            }
            .navigationTitle(tv.host.isEmpty ? "Set up TV" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: tv.mac) { old, new in
            if host == tv.host && mac == old { mac = new }
        }
        .onChange(of: host) { old, new in
            if old != new { mac = new.trimmingCharacters(in: .whitespacesAndNewlines) == tv.host ? tv.mac : "" }
        }
        .presentationDetents([.medium, .large])
    }
}
