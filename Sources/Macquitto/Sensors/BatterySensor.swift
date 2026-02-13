import Foundation
import IOKit.ps

final class BatterySensor: Sensor {
    let id = "battery"
    let isEnabled: Bool
    let pollInterval: TimeInterval

    private var hasBattery: Bool?

    init(config: SensorConfig) {
        self.isEnabled = config.enabled
        self.pollInterval = TimeInterval(config.pollInterval)
    }

    // MARK: - Polling

    func poll() async throws -> [String: String] {
        guard let info = Self.getBatteryInfo() else {
            if hasBattery == nil {
                hasBattery = false
                Log.info("No battery detected (desktop Mac?), battery sensor unavailable", category: .sensor)
            }
            return [:]
        }

        hasBattery = true
        var results: [String: String] = [:]
        results["battery_level"] = String(info.level)
        results["battery_charging"] = info.isCharging ? "ON" : "OFF"
        return results
    }

    // MARK: - Discovery

    func discoveryConfigs(deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) -> [MQTTDiscoveryConfig] {
        let device = MQTTDiscoveryConfig.deviceObject(deviceId: deviceId, deviceName: deviceName)
        let availability = "\(baseTopic)/\(deviceId)/availability"

        return [
            // Battery Level sensor
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/sensor/\(deviceId)_battery_level/config",
                payload: [
                    "name": "Battery Level",
                    "unique_id": "\(deviceId)_battery_level",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/battery_level/state",
                    "unit_of_measurement": "%",
                    "device_class": "battery",
                    "state_class": "measurement",
                    "icon": "mdi:battery",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
            // Battery Charging binary sensor
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/binary_sensor/\(deviceId)_battery_charging/config",
                payload: [
                    "name": "Battery Charging",
                    "unique_id": "\(deviceId)_battery_charging",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/battery_charging/state",
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "device_class": "battery_charging",
                    "icon": "mdi:battery-charging",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
        ]
    }

    // MARK: - IOKit Power Source

    struct BatteryInfo {
        let level: Int
        let isCharging: Bool
    }

    static func getBatteryInfo() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty
        else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Only look at internal batteries
            guard let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType
            else {
                continue
            }

            let level = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            return BatteryInfo(level: level, isCharging: isCharging)
        }

        return nil
    }
}
