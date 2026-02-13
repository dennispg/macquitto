import Foundation
import MQTTNIO
import NIO
import Logging

enum MQTTManagerState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

actor MQTTManager {
    private var client: MQTTClient?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let config: MQTTConfig
    private let deviceId: String
    private let password: String?
    private(set) var state: MQTTManagerState = .disconnected

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private static let maxReconnectDelay: TimeInterval = 60

    /// Called after a successful (re)connect so the agent can re-publish discovery and re-subscribe.
    private var onReconnect: (@Sendable () async -> Void)?

    func setOnReconnect(_ handler: @escaping @Sendable () async -> Void) {
        self.onReconnect = handler
    }

    var baseTopic: String { config.baseTopic }
    var availabilityTopic: String { "\(config.baseTopic)/\(deviceId)/availability" }

    init(config: MQTTConfig, deviceId: String, password: String?) {
        self.config = config
        self.deviceId = deviceId
        self.password = password
    }

    func connect() async throws {
        state = .connecting
        Log.info("Connecting to MQTT broker \(config.host):\(config.effectivePort)", category: .mqtt)

        let clientId = "macquitto-\(deviceId)"

        let mqttConfig = MQTTClient.Configuration(
            version: .v3_1_1,
            keepAliveInterval: .seconds(Int64(config.keepalive)),
            connectTimeout: .seconds(10),
            userName: config.username,
            password: password,
            useSSL: config.tls
        )

        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = elg
        let logger = Logging.Logger(label: "com.macquitto.mqtt")

        let newClient = MQTTClient(
            host: config.host,
            port: config.effectivePort,
            identifier: clientId,
            eventLoopGroupProvider: .shared(elg),
            logger: logger,
            configuration: mqttConfig
        )

        self.client = newClient

        // Set up close listener for reconnection
        newClient.addCloseListener(named: "reconnect") { [weak self] result in
            Task { [weak self] in
                await self?.handleDisconnect(result: result)
            }
        }

        // Connect with LWT (Last Will and Testament)
        let willPayload = ByteBuffer(string: "offline")
        _ = try await newClient.connect(
            cleanSession: true,
            will: (topicName: availabilityTopic, payload: willPayload, qos: MQTTQoS.atLeastOnce, retain: true)
        )

        state = .connected
        reconnectAttempt = 0
        Log.info("Connected to MQTT broker", category: .mqtt)
    }

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil

        guard let client = self.client else { return }

        // Remove the close listener so we don't trigger reconnect
        client.removeCloseListener(named: "reconnect")

        // Publish offline availability
        do {
            try await publish(topic: availabilityTopic, payload: "offline", retain: true)
        } catch {
            Log.warning("Failed to publish offline availability: \(error)", category: .mqtt)
        }

        do {
            try await client.disconnect()
        } catch {
            Log.warning("Error during MQTT disconnect: \(error)", category: .mqtt)
        }

        do {
            try await client.shutdown()
        } catch {
            Log.warning("Error during MQTT shutdown: \(error)", category: .mqtt)
        }

        self.client = nil

        if let elg = eventLoopGroup {
            try? await elg.shutdownGracefully()
            self.eventLoopGroup = nil
        }

        state = .disconnected
        Log.info("Disconnected from MQTT broker", category: .mqtt)
    }

    /// Ensure client is shut down if the manager is being destroyed without a clean disconnect.
    /// This prevents the MQTTClient precondition failure.
    func forceShutdown() {
        reconnectTask?.cancel()
        reconnectTask = nil

        if let client = self.client {
            client.removeCloseListener(named: "reconnect")
            try? client.syncShutdownGracefully()
            self.client = nil
        }

        if let elg = eventLoopGroup {
            try? elg.syncShutdownGracefully()
            self.eventLoopGroup = nil
        }

        state = .disconnected
    }

    func publish(topic: String, payload: String, retain: Bool = false, qos: MQTTQoS = .atLeastOnce) async throws {
        guard let client = self.client, state == .connected else {
            Log.warning("Cannot publish — not connected to MQTT", category: .mqtt)
            return
        }

        let buffer = ByteBuffer(string: payload)
        try await client.publish(to: topic, payload: buffer, qos: qos, retain: retain)
        Log.debug("Published to \(topic): \(payload)", category: .mqtt)
    }

    func subscribe(topic: String, qos: MQTTQoS = .atLeastOnce) async throws {
        guard let client = self.client, state == .connected else {
            Log.warning("Cannot subscribe — not connected to MQTT", category: .mqtt)
            return
        }

        _ = try await client.subscribe(to: [MQTTSubscribeInfo(topicFilter: topic, qos: qos)])
        Log.info("Subscribed to \(topic)", category: .mqtt)
    }

    func addPublishListener(named name: String, handler: @escaping @Sendable (Result<MQTTPublishInfo, Error>) -> Void) {
        client?.addPublishListener(named: name, handler)
    }

    func publishAvailability(online: Bool) async throws {
        try await publish(topic: availabilityTopic, payload: online ? "online" : "offline", retain: true)
    }

    // MARK: - Reconnection

    private func handleDisconnect(result: Result<Void, Error>) {
        guard state != .disconnected else { return }
        Log.warning("Disconnected from MQTT broker, will attempt reconnect", category: .mqtt)
        scheduleReconnect()
    }

    func scheduleReconnect() {
        state = .reconnecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let attempt = await self.reconnectAttempt
                let delay = min(pow(2.0, Double(attempt)), Self.maxReconnectDelay)
                Log.info("Reconnecting in \(Int(delay))s (attempt \(attempt + 1))", category: .mqtt)

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }

                do {
                    try await self.reconnect()
                    return
                } catch {
                    Log.warning("Reconnect failed: \(error)", category: .mqtt)
                    await self.incrementReconnectAttempt()
                }
            }
        }
    }

    private func reconnect() async throws {
        guard let client = self.client else {
            throw MQTTReconnectError.noClient
        }

        state = .connecting

        let willPayload = ByteBuffer(string: "offline")
        _ = try await client.connect(
            cleanSession: true,
            will: (topicName: availabilityTopic, payload: willPayload, qos: MQTTQoS.atLeastOnce, retain: true)
        )

        state = .connected
        reconnectAttempt = 0
        Log.info("Reconnected to MQTT broker", category: .mqtt)

        // Notify agent to re-publish discovery and re-subscribe
        if let onReconnect = onReconnect {
            await onReconnect()
        }
    }

    private func incrementReconnectAttempt() {
        reconnectAttempt += 1
    }
}

enum MQTTReconnectError: Error {
    case noClient
}
