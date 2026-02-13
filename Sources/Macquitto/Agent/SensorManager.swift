import Foundation

actor SensorManager {
    private var sensors: [Sensor] = []
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private let mqttManager: MQTTManager
    private let deviceId: String
    private let baseTopic: String
    private let discoveryPrefix: String
    private let deviceName: String

    /// Consecutive failure count per sensor ID.
    private var failureCounts: [String: Int] = [:]
    /// Sensors marked unavailable after exceeding the failure threshold.
    private var unavailableSensors: Set<String> = []
    private static let failureThreshold = 3

    init(mqttManager: MQTTManager, deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) {
        self.mqttManager = mqttManager
        self.deviceId = deviceId
        self.baseTopic = baseTopic
        self.discoveryPrefix = discoveryPrefix
        self.deviceName = deviceName
    }

    func register(_ sensor: Sensor) {
        sensors.append(sensor)
        Log.info("Registered sensor: \(sensor.id) (enabled=\(sensor.isEnabled), interval=\(sensor.pollInterval)s)", category: .sensor)
    }

    func publishDiscoveryConfigs() async {
        for sensor in sensors where sensor.isEnabled {
            let configs = sensor.discoveryConfigs(
                deviceId: deviceId,
                baseTopic: baseTopic,
                discoveryPrefix: discoveryPrefix,
                deviceName: deviceName
            )
            for config in configs {
                do {
                    let json = try config.jsonPayload()
                    try await mqttManager.publish(topic: config.topic, payload: json, retain: true)
                    Log.debug("Published discovery config: \(config.topic)", category: .sensor)
                } catch {
                    Log.error("Failed to publish discovery config for \(config.topic): \(error)", category: .sensor)
                }
            }
        }
        Log.info("Published all discovery configs", category: .sensor)
    }

    func startPolling() async {
        for sensor in sensors where sensor.isEnabled {
            startPollingLoop(for: sensor)
        }
        Log.info("Started polling for \(sensors.filter { $0.isEnabled }.count) sensors", category: .sensor)
    }

    func stopPolling() {
        for (id, task) in pollingTasks {
            task.cancel()
            Log.debug("Stopped polling for \(id)", category: .sensor)
        }
        pollingTasks.removeAll()
    }

    /// Publish current state for a sensor immediately (used by event-driven listeners)
    func publishSensorState(_ sensor: Sensor) async {
        do {
            let values = try await sensor.poll()
            for (subSensor, value) in values {
                let topic = "\(baseTopic)/\(deviceId)/sensor/\(subSensor)/state"
                try await mqttManager.publish(topic: topic, payload: value)
            }
            recordSuccess(for: sensor.id)
        } catch {
            Log.error("Failed to publish state for sensor \(sensor.id): \(error)", category: .sensor)
        }
    }

    // MARK: - Failure Tracking

    private func recordSuccess(for sensorId: String) {
        if failureCounts[sensorId] != nil {
            failureCounts[sensorId] = 0
        }
        if unavailableSensors.remove(sensorId) != nil {
            Log.info("Sensor \(sensorId) is available again", category: .sensor)
        }
    }

    private func recordFailure(for sensorId: String) {
        let count = (failureCounts[sensorId] ?? 0) + 1
        failureCounts[sensorId] = count

        if count >= Self.failureThreshold && !unavailableSensors.contains(sensorId) {
            unavailableSensors.insert(sensorId)
            Log.error("Sensor \(sensorId) marked unavailable after \(count) consecutive failures", category: .sensor)
        }
    }

    // MARK: - Polling Loop

    private func startPollingLoop(for sensor: Sensor) {
        let baseTopic = self.baseTopic
        let deviceId = self.deviceId
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let values = try await sensor.poll()
                    for (subSensor, value) in values {
                        let topic = "\(baseTopic)/\(deviceId)/sensor/\(subSensor)/state"
                        try await self?.mqttManager.publish(topic: topic, payload: value)
                    }
                    await self?.recordSuccess(for: sensor.id)
                } catch {
                    Log.warning("Poll failed for sensor \(sensor.id): \(error)", category: .sensor)
                    await self?.recordFailure(for: sensor.id)
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(sensor.pollInterval * 1_000_000_000))
                } catch {
                    return
                }
            }
        }

        pollingTasks[sensor.id] = task
    }
}
