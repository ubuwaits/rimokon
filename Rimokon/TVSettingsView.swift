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
                    if !tv.host.isEmpty {
                        HStack {
                            Text(tv.name)
                            Spacer()
                            Text(tv.status).font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Button(tv.searching ? "Searching…" : (tv.host.isEmpty ? "Find TV" : "Find another TV")) {
                        tv.findTVs()
                    }.disabled(tv.searching)
                    ForEach(tv.discoveredTVs) { device in
                        Button {
                            tv.selectTV(device)
                            dismiss()
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text(device.host).foregroundStyle(.secondary)
                                if tv.isSelected(device) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if tv.host.isEmpty && !tv.discoveryStatus.isEmpty && !tv.searching {
                        Text(tv.discoveryStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Cursor mode", isOn: $cursorModeEnabled)
                DisclosureGroup("Advanced") {
                    TextField("TV IP address", text: $host).keyboardType(.decimalPad).autocorrectionDisabled()
                        .accessibilityLabel("TV IP address")
                    TextField("MAC address", text: $mac).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("TV MAC address")
                    Button("Connect") {
                        tv.configure(configuration)
                        dismiss()
                    }.disabled(!configuration.valid)
                    Button("Retrieve MAC again") { tv.refreshMACPermission() }.disabled(!tv.connected)
                }
            }
            .navigationTitle(tv.host.isEmpty ? "Set up TV" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
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
