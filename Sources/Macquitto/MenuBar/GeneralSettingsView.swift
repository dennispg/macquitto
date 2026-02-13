import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var appState: AppState
    @State private var hasChanges = false
    var body: some View {
        Form {
            Section("Device") {
                TextField("Device ID", text: $appState.config.device.id)
                    .onChange(of: appState.config.device.id) { _, _ in hasChanges = true }

                TextField("Device Name", text: $appState.config.device.name)
                    .onChange(of: appState.config.device.name) { _, _ in hasChanges = true }
            }

            Section("Appearance") {
                Toggle("Show Menu Bar Icon", isOn: $appState.config.general.showMenuBarIcon)
                    .onChange(of: appState.config.general.showMenuBarIcon) { _, _ in hasChanges = true }

                Toggle("Start at Login", isOn: Binding(
                    get: { appState.isLaunchAtLoginEnabled },
                    set: { appState.setLaunchAtLogin($0) }
                ))
            }

            Section("Logging") {
                Picker("Log Level", selection: $appState.config.general.logLevel) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(level.rawValue.capitalized).tag(level.rawValue)
                    }
                }
                .onChange(of: appState.config.general.logLevel) { _, newValue in
                    hasChanges = true
                    if let level = LogLevel(rawValue: newValue) {
                        Log.level = level
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") {
                        appState.saveConfig()
                        hasChanges = false
                    }
                    .disabled(!hasChanges)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
    }
}
