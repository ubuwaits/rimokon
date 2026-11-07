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
                    TextField("MAC address (optional)", text: $mac).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("TV MAC address")
                } footer: {
                    Text("Find these in your TV’s network settings. The MAC address enables power on.")
                }
                Button("Save & connect") {
                    tv.configure(configuration)
                    dismiss()
                }.disabled(!configuration.valid)
                Toggle("Cursor mode", isOn: $cursorModeEnabled)
                if !tv.status.isEmpty { Text(tv.status).font(.system(.caption, design: .monospaced)) }
            }
            .navigationTitle(tv.host.isEmpty ? "Set up TV" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
