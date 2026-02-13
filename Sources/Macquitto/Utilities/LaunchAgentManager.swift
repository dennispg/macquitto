import Foundation
import ServiceManagement

enum LaunchAgentManager {
    private static let appService = SMAppService.mainApp

    static var isInstalled: Bool {
        appService.status == .enabled
    }

    static func install() throws {
        try appService.register()
        Log.info("Registered as login item", category: .general)
    }

    static func uninstall() throws {
        try appService.unregister()
        Log.info("Unregistered login item", category: .general)
    }
}
