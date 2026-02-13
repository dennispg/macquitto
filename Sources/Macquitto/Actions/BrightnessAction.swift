import Foundation

final class SetBrightnessAction: Action {
    let id = "set_brightness"
    let commandTopic = "brightness"

    func execute(payload: String) async throws {
        guard let value = Int(payload.trimmingCharacters(in: .whitespaces)),
              value >= 0, value <= 100
        else {
            Log.warning("Invalid brightness payload: \(payload)", category: .action)
            return
        }

        let brightness = Float(value) / 100.0
        if BrightnessSensor.setBuiltInDisplayBrightness(brightness) {
            Log.info("Set brightness to \(value)%", category: .action)
        } else {
            Log.error("Failed to set brightness", category: .action)
        }
    }
}
