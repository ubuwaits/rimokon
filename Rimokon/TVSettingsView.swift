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
                    Button(tv.searching ? "Searching…" : "Find TV") { tv.findTVs() }
                        .disabled(tv.searching)
                    ForEach(tv.discoveredTVs) { device in
                        Button {
                            tv.selectTV(device)
                            dismiss()
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text(device.host).foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("TV IP address", text: $host).keyboardType(.decimalPad).autocorrectionDisabled()
                        .accessibilityLabel("TV IP address")
                } footer: {
                    Text("Turn the TV on to find it. You can also enter its IP address.")
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
        .task { if tv.host.isEmpty && !tv.searching { tv.findTVs() } }
        .onChange(of: tv.host) { _, new in host = new; mac = tv.mac }
        .onChange(of: tv.mac) { old, new in
            if host == tv.host && mac == old { mac = new }
        }
        .onChange(of: host) { _, new in
            mac = new.trimmingCharacters(in: .whitespacesAndNewlines) == tv.host ? tv.mac : ""
        }
        .presentationDetents([.medium, .large])
    }
}
