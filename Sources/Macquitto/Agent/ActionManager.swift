import Foundation
import MQTTNIO
import NIO

actor ActionManager {
    private var actions: [String: Action] = [:]
    private let mqttManager: MQTTManager
    private let deviceId: String
    private let baseTopic: String

    init(mqttManager: MQTTManager, deviceId: String, baseTopic: String) {
        self.mqttManager = mqttManager
        self.deviceId = deviceId
        self.baseTopic = baseTopic
    }

    func register(_ action: Action) {
        let fullTopic = "\(baseTopic)/\(deviceId)/command/\(action.commandTopic)/set"
        actions[fullTopic] = action
        Log.info("Registered action: \(action.id) on topic \(fullTopic)", category: .action)
    }

    func subscribeAll() async {
        // Subscribe to all command topics
        for topic in actions.keys {
            do {
                try await mqttManager.subscribe(topic: topic)
            } catch {
                Log.error("Failed to subscribe to \(topic): \(error)", category: .action)
            }
        }

        // Set up listener for incoming messages
        await mqttManager.addPublishListener(named: "actions") { [weak self] result in
            Task { [weak self] in
                await self?.handleMessage(result: result)
            }
        }

        Log.info("Subscribed to \(actions.count) command topics", category: .action)
    }

    private func handleMessage(result: Result<MQTTPublishInfo, Error>) {
        switch result {
        case .success(let publishInfo):
            let topic = publishInfo.topicName
            guard let action = actions[topic] else { return }

            let payload = String(buffer: publishInfo.payload)

            Log.info("Received command on \(topic): \(payload)", category: .action)

            Task {
                do {
                    try await action.execute(payload: payload)
                    Log.info("Executed action \(action.id)", category: .action)
                } catch {
                    Log.error("Failed to execute action \(action.id): \(error)", category: .action)
                }
            }

        case .failure(let error):
            Log.error("Error receiving MQTT message: \(error)", category: .action)
        }
    }
}
