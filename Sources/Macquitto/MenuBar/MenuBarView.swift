import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status line
        Text(appState.statusText)
            .font(.headline)

        if let error = appState.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }

        Divider()

        // Quick sensor readings
        sensorReadings

        Divider()

        Button("Settings...") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("About Macquitto") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "about")
            NSApp.activate()
        }

        Divider()

        Button("Quit Macquitto") {
            Task {
                await appState.stopAgent()
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private var sensorReadings: some View {
        if let volume = appState.sensorValues["volume"] {
            let muteText = appState.sensorValues["mute"].map { " (\($0))" } ?? ""
            Label("Volume: \(volume)\(muteText)", systemImage: "speaker.wave.2.fill")
        }

        if let screenLock = appState.sensorValues["screen_lock"] {
            Label("Screen: \(screenLock)", systemImage: "lock.fill")
        }

        if let brightness = appState.sensorValues["brightness"] {
            Label("Brightness: \(brightness)", systemImage: "sun.max.fill")
        }

        if let focus = appState.sensorValues["focus"] {
            Label("Focus: \(focus)", systemImage: "moon.fill")
        }

        if let battery = appState.sensorValues["battery_level"] {
            let chargingText = appState.sensorValues["battery_charging"].map { " (\($0))" } ?? ""
            Label("Battery: \(battery)\(chargingText)", systemImage: "battery.100percent")
        }
    }
}
