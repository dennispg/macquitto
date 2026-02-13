import Foundation
import Yams

struct DeviceConfig: Codable {
    var id: String
    var name: String

    static var `default`: DeviceConfig {
        DeviceConfig(
            id: Self.hardwareUUID(),
            name: Host.current().localizedName ?? "My Mac"
        )
    }

    private static func hardwareUUID() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0,
              let uuidCF = IORegistryEntryCreateCFProperty(
                  platformExpert,
                  kIOPlatformUUIDKey as CFString,
                  kCFAllocatorDefault,
                  0
              )?.takeRetainedValue() as? String
        else {
            return UUID().uuidString
        }
        return uuidCF.lowercased()
    }
}

struct MQTTConfig: Codable {
    var host: String
    var port: Int
    var tls: Bool
    var tlsPort: Int?
    var caCert: String?
    var clientCert: String?
    var clientKey: String?
    var username: String?
    var discoveryPrefix: String
    var baseTopic: String
    var keepalive: Int

    enum CodingKeys: String, CodingKey {
        case host, port, tls, username, keepalive
        case tlsPort = "tls_port"
        case caCert = "ca_cert"
        case clientCert = "client_cert"
        case clientKey = "client_key"
        case discoveryPrefix = "discovery_prefix"
        case baseTopic = "base_topic"
    }

    static var `default`: MQTTConfig {
        MQTTConfig(
            host: "homeassistant.local",
            port: 1883,
            tls: false,
            tlsPort: nil,
            caCert: nil,
            clientCert: nil,
            clientKey: nil,
            username: nil,
            discoveryPrefix: "homeassistant",
            baseTopic: "macquitto",
            keepalive: 60
        )
    }

    var effectivePort: Int {
        tls ? (tlsPort ?? 8883) : port
    }
}

struct SensorConfig: Codable {
    var enabled: Bool
    var pollInterval: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case pollInterval = "poll_interval"
    }
}

struct SensorsConfig: Codable {
    var audio: SensorConfig
    var screenLock: SensorConfig
    var brightness: SensorConfig
    var focus: SensorConfig
    var battery: SensorConfig

    enum CodingKeys: String, CodingKey {
        case audio
        case screenLock = "screen_lock"
        case brightness, focus, battery
    }

    static var `default`: SensorsConfig {
        SensorsConfig(
            audio: SensorConfig(enabled: true, pollInterval: 2),
            screenLock: SensorConfig(enabled: true, pollInterval: 5),
            brightness: SensorConfig(enabled: true, pollInterval: 10),
            focus: SensorConfig(enabled: true, pollInterval: 10),
            battery: SensorConfig(enabled: true, pollInterval: 60)
        )
    }
}

struct GeneralConfig: Codable {
    var showMenuBarIcon: Bool
    var logLevel: String

    enum CodingKeys: String, CodingKey {
        case showMenuBarIcon = "show_menu_bar_icon"
        case logLevel = "log_level"
    }

    static var `default`: GeneralConfig {
        GeneralConfig(showMenuBarIcon: true, logLevel: "info")
    }
}

struct AppConfig: Codable {
    var device: DeviceConfig
    var mqtt: MQTTConfig
    var sensors: SensorsConfig
    var general: GeneralConfig

    static var `default`: AppConfig {
        AppConfig(
            device: .default,
            mqtt: .default,
            sensors: .default,
            general: .default
        )
    }

    static let defaultConfigDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/macquitto")
    }()

    static let defaultConfigPath: URL = {
        defaultConfigDir.appendingPathComponent("config.yaml")
    }()

    struct LoadResult {
        let config: AppConfig
        /// Non-nil if the config was malformed and defaults were used.
        let error: String?
    }

    static func load(from path: URL? = nil) throws -> AppConfig {
        return try loadWithFallback(from: path).config
    }

    /// Load config, falling back to defaults if the file is malformed.
    static func loadWithFallback(from path: URL? = nil) throws -> LoadResult {
        let configPath = path ?? defaultConfigPath

        if !FileManager.default.fileExists(atPath: configPath.path) {
            let config = AppConfig.default
            try config.save(to: configPath)
            Log.info("Created default config at \(configPath.path)", category: .config)
            return LoadResult(config: config, error: nil)
        }

        do {
            let data = try Data(contentsOf: configPath)
            let yamlString = String(data: data, encoding: .utf8) ?? ""
            let decoder = YAMLDecoder()
            let config = try decoder.decode(AppConfig.self, from: yamlString)
            Log.info("Loaded config from \(configPath.path)", category: .config)
            return LoadResult(config: config, error: nil)
        } catch {
            Log.error("Config file is malformed, using defaults: \(error)", category: .config)
            // Back up the corrupted file
            let backupPath = configPath.appendingPathExtension("backup")
            try? FileManager.default.removeItem(at: backupPath)
            try? FileManager.default.moveItem(at: configPath, to: backupPath)
            // Write fresh defaults
            let config = AppConfig.default
            try? config.save(to: configPath)
            return LoadResult(config: config, error: "Config file was malformed — using defaults. Backup saved.")
        }
    }

    func save(to path: URL? = nil) throws {
        let configPath = path ?? Self.defaultConfigPath
        let dir = configPath.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(self)
        try yamlString.write(to: configPath, atomically: true, encoding: .utf8)
        Log.info("Saved config to \(configPath.path)", category: .config)
    }

    func redactedDescription() -> String {
        """
        device:
          id: \(device.id)
          name: \(device.name)
        mqtt:
          host: \(mqtt.host)
          port: \(mqtt.port)
          tls: \(mqtt.tls)
          username: \(mqtt.username ?? "(not set)")
          password: ********
          discovery_prefix: \(mqtt.discoveryPrefix)
          base_topic: \(mqtt.baseTopic)
          keepalive: \(mqtt.keepalive)
        sensors:
          audio: enabled=\(sensors.audio.enabled), poll_interval=\(sensors.audio.pollInterval)s
          screen_lock: enabled=\(sensors.screenLock.enabled), poll_interval=\(sensors.screenLock.pollInterval)s
          brightness: enabled=\(sensors.brightness.enabled), poll_interval=\(sensors.brightness.pollInterval)s
          focus: enabled=\(sensors.focus.enabled), poll_interval=\(sensors.focus.pollInterval)s
          battery: enabled=\(sensors.battery.enabled), poll_interval=\(sensors.battery.pollInterval)s
        general:
          show_menu_bar_icon: \(general.showMenuBarIcon)
          log_level: \(general.logLevel)
        """
    }
}
