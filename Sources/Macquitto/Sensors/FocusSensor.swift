import Foundation

final class FocusSensor: Sensor {
    let id = "focus"
    let isEnabled: Bool
    let pollInterval: TimeInterval

    init(config: SensorConfig) {
        self.isEnabled = config.enabled
        self.pollInterval = TimeInterval(config.pollInterval)
    }

    // MARK: - Polling

    func poll() async throws -> [String: String] {
        let active = Self.isFocusModeActive()
        return ["focus": active ? "ON" : "OFF"]
    }

    // MARK: - Discovery

    func discoveryConfigs(deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) -> [MQTTDiscoveryConfig] {
        let device = MQTTDiscoveryConfig.deviceObject(deviceId: deviceId, deviceName: deviceName)
        let availability = "\(baseTopic)/\(deviceId)/availability"

        return [
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/binary_sensor/\(deviceId)_focus/config",
                payload: [
                    "name": "Focus Mode",
                    "unique_id": "\(deviceId)_focus",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/focus/state",
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "icon": "mdi:moon-waning-crescent",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
        ]
    }

    // MARK: - Focus Detection

    /// Checks if any Focus mode is active by reading the DND assertions file.
    /// This is the most reliable cross-version approach on macOS 12+.
    static func isFocusModeActive() -> Bool {
        // Primary: check the assertions JSON file
        let assertionsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

        if let data = try? Data(contentsOf: assertionsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let store = json["data"] as? [[String: Any]]
        {
            // If there are any active assertions with a non-empty storeAssertionRecords, focus is on
            for entry in store {
                if let records = entry["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty {
                    return true
                }
            }
            return false
        }

        // Fallback: use `defaults read` to check control center state
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.controlcenter", "NSStatusItem Visible FocusModes"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // "1" means the focus icon is visible in the menu bar, indicating active focus
            return output == "1"
        } catch {
            Log.debug("Focus mode detection via defaults failed: \(error)", category: .sensor)
            return false
        }
    }
}
