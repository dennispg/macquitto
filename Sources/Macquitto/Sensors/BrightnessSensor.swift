import Foundation
import IOKit

final class BrightnessSensor: Sensor {
    let id = "brightness"
    let isEnabled: Bool
    let pollInterval: TimeInterval

    init(config: SensorConfig) {
        self.isEnabled = config.enabled
        self.pollInterval = TimeInterval(config.pollInterval)
    }

    // MARK: - Polling

    func poll() async throws -> [String: String] {
        if let brightness = Self.getBuiltInDisplayBrightness() {
            return ["brightness": String(Int(brightness * 100))]
        }
        return [:]
    }

    // MARK: - Discovery

    func discoveryConfigs(deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) -> [MQTTDiscoveryConfig] {
        let device = MQTTDiscoveryConfig.deviceObject(deviceId: deviceId, deviceName: deviceName)
        let availability = "\(baseTopic)/\(deviceId)/availability"

        return [
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/number/\(deviceId)_brightness/config",
                payload: [
                    "name": "Display Brightness",
                    "unique_id": "\(deviceId)_brightness",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/brightness/state",
                    "command_topic": "\(baseTopic)/\(deviceId)/command/brightness/set",
                    "min": 0,
                    "max": 100,
                    "step": 1,
                    "unit_of_measurement": "%",
                    "icon": "mdi:brightness-6",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
        ]
    }

    // MARK: - IOKit Brightness

    static func getBuiltInDisplayBrightness() -> Float? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var brightness: Float = 0
            let err = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)

            if err == kIOReturnSuccess {
                return max(0, min(1, brightness))
            }

            service = IOIteratorNext(iterator)
        }

        return nil
    }

    static func setBuiltInDisplayBrightness(_ value: Float) -> Bool {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return false }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let err = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, max(0, min(1, value)))
            IOObjectRelease(service)

            if err == kIOReturnSuccess {
                return true
            }

            service = IOIteratorNext(iterator)
        }

        return false
    }
}
