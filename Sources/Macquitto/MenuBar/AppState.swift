import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var config: AppConfig
    var mqttStatus: MQTTManagerState = .disconnected
    var isLaunchAtLoginEnabled = false
    var lastError: String?

    // Live sensor readings for the menu bar dropdown
    var sensorValues: [String: String] = [:]

    private var agent: AgentCore?
    private var statusPollTask: Task<Void, Never>?

    // Pre-loaded menu bar icons
    private let connectedIcon: NSImage?
    private let disconnectedIcon: NSImage?

    init(config: AppConfig) {
        self.config = config
        self.isLaunchAtLoginEnabled = LaunchAgentManager.isInstalled
        self.connectedIcon = Self.loadMenuBarIcon(named: "menu-connected")
        if let base = Self.loadMenuBarIcon(named: "menu-disconnected") {
            self.disconnectedIcon = Self.addRedDot(to: base)
        } else {
            self.disconnectedIcon = nil
        }
    }

    private static func loadMenuBarIcon(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }

    private static func addRedDot(to baseImage: NSImage) -> NSImage {
        let size = baseImage.size
        let result = NSImage(size: size, flipped: false) { rect in
            baseImage.draw(in: rect)
            let dotSize: CGFloat = 6
            let dotRect = NSRect(
                x: size.width - dotSize - 1,
                y: 1,
                width: dotSize,
                height: dotSize
            )
            NSColor.red.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        result.isTemplate = false
        return result
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try LaunchAgentManager.install()
            } else {
                try LaunchAgentManager.uninstall()
            }
            isLaunchAtLoginEnabled = enabled
        } catch {
            Log.error("Failed to \(enabled ? "install" : "uninstall") login item: \(error)", category: .general)
            isLaunchAtLoginEnabled = LaunchAgentManager.isInstalled
        }
    }

    func startAgent() async {
        if agent != nil {
            await stopAgent()
        }

        let newAgent = AgentCore(config: config)
        self.agent = newAgent

        await newAgent.start()
        startStatusPolling()
    }

    func stopAgent() async {
        statusPollTask?.cancel()
        statusPollTask = nil

        if let agent = agent {
            await agent.stop()
        }
        agent = nil
        mqttStatus = .disconnected
        sensorValues.removeAll()
    }

    func restartAgent() async {
        await stopAgent()
        await startAgent()
    }

    func saveConfig() {
        do {
            try config.save()
            Log.info("Config saved from settings UI", category: .config)
        } catch {
            Log.error("Failed to save config: \(error)", category: .config)
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Fetch MQTT status from the agent actor
                if let agent = self.agent {
                    self.mqttStatus = await agent.mqttState
                }

                // Read sensor values (lightweight CoreAudio/IOKit calls)
                self.pollSensorValues()

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollSensorValues() {
        if config.sensors.audio.enabled {
            if let vol = AudioSensor.getOutputVolume() {
                sensorValues["volume"] = "\(Int(vol * 100))%"
            }
            sensorValues["mute"] = AudioSensor.getOutputMute() ? "Muted" : nil
            sensorValues["audio_output"] = AudioSensor.getDefaultDeviceName(forInput: false)
        }

        if config.sensors.screenLock.enabled {
            sensorValues["screen_lock"] = ScreenLockSensor.isScreenLocked() ? "Locked" : "Unlocked"
        }

        if config.sensors.brightness.enabled {
            if let brightness = BrightnessSensor.getBuiltInDisplayBrightness() {
                sensorValues["brightness"] = "\(Int(brightness * 100))%"
            }
        }

        if config.sensors.focus.enabled {
            sensorValues["focus"] = FocusSensor.isFocusModeActive() ? "On" : "Off"
        }

        if config.sensors.battery.enabled {
            if let info = BatterySensor.getBatteryInfo() {
                sensorValues["battery_level"] = "\(info.level)%"
                sensorValues["battery_charging"] = info.isCharging ? "Charging" : nil
            }
        }
    }

    // MARK: - Display Helpers

    var statusText: String {
        switch mqttStatus {
        case .connected:
            return "Connected to \(config.mqtt.host)"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "MQTT Disconnected"
        }
    }

    var statusIcon: NSImage? {
        switch mqttStatus {
        case .connected: connectedIcon
        case .connecting, .reconnecting, .disconnected: disconnectedIcon
        }
    }
}
