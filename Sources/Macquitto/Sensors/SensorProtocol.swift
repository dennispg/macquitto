import Foundation

struct MQTTDiscoveryConfig {
    let topic: String
    let payload: [String: Any]

    func jsonPayload() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func deviceObject(deviceId: String, deviceName: String) -> [String: Any] {
        [
            "identifiers": ["macquitto_\(deviceId)"],
            "name": deviceName,
            "manufacturer": "Macquitto",
            "model": "macOS Agent",
            "sw_version": "1.0.0",
        ]
    }
}

protocol Sensor: AnyObject {
    var id: String { get }
    var isEnabled: Bool { get }
    var pollInterval: TimeInterval { get }

    func poll() async throws -> [String: String]
    func discoveryConfigs(deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) -> [MQTTDiscoveryConfig]
}
