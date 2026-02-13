import Foundation
import ApplicationServices

final class ScreenLockSensor: Sensor {
    let id = "screen_lock"
    let isEnabled: Bool
    let pollInterval: TimeInterval

    var onStateChange: (() -> Void)?

    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    init(config: SensorConfig) {
        self.isEnabled = config.enabled
        self.pollInterval = TimeInterval(config.pollInterval)
    }

    deinit {
        removeListeners()
    }

    // MARK: - Polling

    func poll() async throws -> [String: String] {
        let locked = Self.isScreenLocked()
        return ["screen_lock": locked ? "ON" : "OFF"]
    }

    // MARK: - Discovery

    func discoveryConfigs(deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) -> [MQTTDiscoveryConfig] {
        let device = MQTTDiscoveryConfig.deviceObject(deviceId: deviceId, deviceName: deviceName)
        let availability = "\(baseTopic)/\(deviceId)/availability"

        return [
            // Screen Lock binary sensor
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/binary_sensor/\(deviceId)_screen_lock/config",
                payload: [
                    "name": "Screen Locked",
                    "unique_id": "\(deviceId)_screen_lock",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/screen_lock/state",
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "device_class": "lock",
                    "icon": "mdi:monitor-lock",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
            // Lock Screen button
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/button/\(deviceId)_lock_screen/config",
                payload: [
                    "name": "Lock Screen",
                    "unique_id": "\(deviceId)_lock_screen",
                    "command_topic": "\(baseTopic)/\(deviceId)/command/lock/set",
                    "icon": "mdi:lock",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
        ]
    }

    // MARK: - Listeners

    func installListeners() {
        let center = DistributedNotificationCenter.default()

        lockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onStateChange?()
        }

        unlockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onStateChange?()
        }

        Log.info("Installed screen lock notification listeners", category: .sensor)
    }

    func removeListeners() {
        let center = DistributedNotificationCenter.default()
        if let obs = lockObserver {
            center.removeObserver(obs)
        }
        if let obs = unlockObserver {
            center.removeObserver(obs)
        }
        lockObserver = nil
        unlockObserver = nil
    }

    // MARK: - Detection

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
