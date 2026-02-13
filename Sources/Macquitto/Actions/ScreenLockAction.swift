import Foundation

final class ScreenLockAction: Action {
    let id = "lock_screen"
    let commandTopic = "lock"

    func execute(payload: String) async throws {
        Log.info("Locking screen", category: .action)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            Log.info("Screen locked successfully", category: .action)
        } else {
            Log.error("Screen lock command failed with exit code \(process.terminationStatus)", category: .action)
        }
    }
}
