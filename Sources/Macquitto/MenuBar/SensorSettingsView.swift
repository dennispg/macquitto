import SwiftUI

struct SensorSettingsView: View {
    @Bindable var appState: AppState
    @State private var hasChanges = false

    var body: some View {
        Form {
            Section("Sensors") {
                sensorRow(
                    name: "Audio",
                    detail: "Volume, Mute, Output/Input Device",
                    icon: "speaker.wave.2.fill",
                    config: $appState.config.sensors.audio,
                    currentValues: audioValues
                )

                sensorRow(
                    name: "Screen Lock",
                    detail: "Lock state detection",
                    icon: "lock.fill",
                    config: $appState.config.sensors.screenLock,
                    currentValues: appState.sensorValues["screen_lock"].map { [$0] } ?? []
                )

                sensorRow(
                    name: "Display Brightness",
                    detail: "Built-in display",
                    icon: "sun.max.fill",
                    config: $appState.config.sensors.brightness,
                    currentValues: appState.sensorValues["brightness"].map { [$0] } ?? []
                )

                sensorRow(
                    name: "Focus Mode",
                    detail: "Do Not Disturb / Focus",
                    icon: "moon.fill",
                    config: $appState.config.sensors.focus,
                    currentValues: appState.sensorValues["focus"].map { [$0] } ?? []
                )

                sensorRow(
                    name: "Battery",
                    detail: "Level and charging state",
                    icon: "battery.100percent",
                    config: $appState.config.sensors.battery,
                    currentValues: batteryValues
                )
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save & Restart") {
                        appState.saveConfig()
                        hasChanges = false
                        Task { await appState.restartAgent() }
                    }
                    .disabled(!hasChanges)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var audioValues: [String] {
        var vals: [String] = []
        if let vol = appState.sensorValues["volume"] {
            vals.append("Vol: \(vol)")
        }
        if let mute = appState.sensorValues["mute"] {
            vals.append(mute)
        }
        if let output = appState.sensorValues["audio_output"] {
            vals.append(output)
        }
        return vals
    }

    private var batteryValues: [String] {
        var vals: [String] = []
        if let level = appState.sensorValues["battery_level"] {
            vals.append(level)
        }
        if let charging = appState.sensorValues["battery_charging"] {
            vals.append(charging)
        }
        return vals
    }

    @ViewBuilder
    private func sensorRow(
        name: String,
        detail: String,
        icon: String,
        config: Binding<SensorConfig>,
        currentValues: [String]
    ) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: config.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
                .onChange(of: config.wrappedValue.enabled) { _, _ in hasChanges = true }

            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(config.wrappedValue.enabled ? .primary : .tertiary)
            }

            Spacer()

            // Live values
            if !currentValues.isEmpty && config.wrappedValue.enabled {
                Text(currentValues.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            // Poll interval
            HStack(spacing: 4) {
                TextField("", value: config.pollInterval, format: .number)
                    .frame(width: 40)
                    .multilineTextAlignment(.trailing)
                Text("s")
                    .foregroundStyle(.secondary)
                Stepper("", value: config.pollInterval, in: 1...300)
                    .labelsHidden()
            }
            .onChange(of: config.wrappedValue.pollInterval) { _, _ in hasChanges = true }
        }
    }
}
