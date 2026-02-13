import Foundation

final class SetVolumeAction: Action {
    let id = "set_volume"
    let commandTopic = "volume"

    func execute(payload: String) async throws {
        guard let value = Int(payload.trimmingCharacters(in: .whitespaces)),
              value >= 0, value <= 100
        else {
            Log.warning("Invalid volume payload: \(payload)", category: .action)
            return
        }

        let volume = Float(value) / 100.0
        if AudioSensor.setOutputVolume(volume) {
            Log.info("Set volume to \(value)%", category: .action)
        } else {
            Log.error("Failed to set volume", category: .action)
        }
    }
}

final class SetMuteAction: Action {
    let id = "set_mute"
    let commandTopic = "mute"

    func execute(payload: String) async throws {
        let trimmed = payload.trimmingCharacters(in: .whitespaces).uppercased()
        let mute: Bool
        switch trimmed {
        case "ON":
            mute = true
        case "OFF":
            mute = false
        default:
            Log.warning("Invalid mute payload: \(payload)", category: .action)
            return
        }

        if AudioSensor.setOutputMute(mute) {
            Log.info("Set mute to \(mute ? "ON" : "OFF")", category: .action)
        } else {
            Log.error("Failed to set mute", category: .action)
        }
    }
}
