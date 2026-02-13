import Foundation

actor AgentCore {
    private let config: AppConfig
    private var mqttManager: MQTTManager?
    private var sensorManager: SensorManager?
    private var actionManager: ActionManager?
    private var isRunning = false
    private var mqttConnectTask: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
    }

    func start() async {
        guard !isRunning else {
            Log.warning("Agent is already running", category: .general)
            return
        }

        Log.info("Starting agent for device: \(config.device.id) (\(config.device.name))", category: .general)

        // Set log level from config
        if let level = LogLevel(rawValue: config.general.logLevel) {
            Log.level = level
        }

        // Read MQTT password from Keychain
        let password: String?
        do {
            password = try KeychainHelper.readPassword()
        } catch {
            Log.error("Failed to read MQTT password from Keychain: \(error)", category: .config)
            password = nil
        }

        // Initialize MQTT manager
        let mqtt = MQTTManager(
            config: config.mqtt,
            deviceId: config.device.id,
            password: password
        )
        self.mqttManager = mqtt

        // Initialize sensor manager
        let sensors = SensorManager(
            mqttManager: mqtt,
            deviceId: config.device.id,
            baseTopic: config.mqtt.baseTopic,
            discoveryPrefix: config.mqtt.discoveryPrefix,
            deviceName: config.device.name
        )
        self.sensorManager = sensors

        // Register sensors
        let audioSensor = AudioSensor(config: config.sensors.audio)
        await sensors.register(audioSensor)

        let screenLockSensor = ScreenLockSensor(config: config.sensors.screenLock)
        await sensors.register(screenLockSensor)

        let brightnessSensor = BrightnessSensor(config: config.sensors.brightness)
        await sensors.register(brightnessSensor)

        let focusSensor = FocusSensor(config: config.sensors.focus)
        await sensors.register(focusSensor)

        let batterySensor = BatterySensor(config: config.sensors.battery)
        await sensors.register(batterySensor)

        // Install event-driven listeners for instant change detection
        audioSensor.onStateChange = { [weak sensors, weak audioSensor] in
            guard let sensors = sensors, let audioSensor = audioSensor else { return }
            Task { await sensors.publishSensorState(audioSensor) }
        }
        audioSensor.installListeners()

        screenLockSensor.onStateChange = { [weak sensors, weak screenLockSensor] in
            guard let sensors = sensors, let screenLockSensor = screenLockSensor else { return }
            Task { await sensors.publishSensorState(screenLockSensor) }
        }
        screenLockSensor.installListeners()

        // Start sensor polling — sensors run regardless of MQTT state
        await sensors.startPolling()

        // Initialize action manager
        let actions = ActionManager(
            mqttManager: mqtt,
            deviceId: config.device.id,
            baseTopic: config.mqtt.baseTopic
        )
        self.actionManager = actions

        // Register actions (local only, no MQTT needed)
        await actions.register(SetVolumeAction())
        await actions.register(SetMuteAction())
        await actions.register(ScreenLockAction())
        await actions.register(SetBrightnessAction())

        // Set up reconnect callback so discovery/subscriptions are restored after reconnect
        await mqtt.setOnReconnect { [weak self] in
            await self?.onMQTTConnected()
        }

        isRunning = true
        Log.info("Agent started (sensors polling)", category: .general)

        // Attempt MQTT connection in the background — failure is non-fatal
        mqttConnectTask = Task { [weak self] in
            await self?.connectMQTT()
        }
    }

    func stop() async {
        Log.info("Stopping agent...", category: .general)

        mqttConnectTask?.cancel()
        mqttConnectTask = nil

        if let sensors = sensorManager {
            await sensors.stopPolling()
        }

        if let mqtt = mqttManager {
            let currentState = await mqtt.state
            if currentState == .connected {
                await mqtt.disconnect()
            } else {
                await mqtt.forceShutdown()
            }
        }

        sensorManager = nil
        actionManager = nil
        mqttManager = nil
        isRunning = false
        Log.info("Agent stopped", category: .general)
    }

    var mqttState: MQTTManagerState {
        get async {
            if let mqtt = mqttManager {
                return await mqtt.state
            }
            return .disconnected
        }
    }

    // MARK: - MQTT Connection

    /// Attempt to connect MQTT and set up discovery/subscriptions.
    /// On failure, MQTTManager's reconnect logic will keep retrying.
    private func connectMQTT() async {
        guard let mqtt = mqttManager else { return }

        do {
            try await mqtt.connect()
            await onMQTTConnected()
        } catch {
            Log.warning("MQTT connection failed, will retry: \(error)", category: .mqtt)
            // connect() failed before establishing a connection, so the close listener
            // won't fire. We need to trigger reconnect manually.
            await mqtt.scheduleReconnect()
        }
    }

    /// Called when MQTT connection is established (initial or reconnect).
    /// Publishes discovery configs, availability, and subscribes to actions.
    func onMQTTConnected() async {
        guard let mqtt = mqttManager else { return }

        do {
            try await mqtt.publishAvailability(online: true)
        } catch {
            Log.warning("Failed to publish availability: \(error)", category: .mqtt)
        }

        if let sensors = sensorManager {
            await sensors.publishDiscoveryConfigs()
        }

        if let actions = actionManager {
            await actions.subscribeAll()
        }

        Log.info("MQTT connected — discovery and subscriptions active", category: .general)
    }
}
