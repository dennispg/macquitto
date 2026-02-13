import Foundation
import SwiftUI
import ArgumentParser

@main
struct MacquittoApp {
    static func main() {
        // Parse CLI arguments
        let options: CLIOptions
        do {
            options = try CLIOptions.parse()
        } catch {
            CLIOptions.exit(withError: error)
        }

        // Handle one-shot commands
        if options.version {
            print("Macquitto 1.0.0")
            return
        }

        if options.setPassword {
            handleSetPassword()
            return
        }

        let configURL = options.config.map { URL(fileURLWithPath: $0) }

        if options.showConfig {
            handleShowConfig(configURL: configURL)
            return
        }

        // Load config
        let loadResult: AppConfig.LoadResult
        do {
            loadResult = try AppConfig.loadWithFallback(from: configURL)
        } catch {
            Log.error("Failed to load config: \(error)", category: .config)
            print("Error: Failed to load config: \(error)")
            Foundation.exit(1)
        }

        if let level = LogLevel(rawValue: loadResult.config.general.logLevel) {
            Log.level = level
        }

        if options.headless {
            runHeadless(config: loadResult.config)
        } else {
            MacquittoGUIApp.initialConfig = loadResult.config
            MacquittoGUIApp.initialConfigError = loadResult.error
            MacquittoGUIApp.main()
        }
    }

    private static func runHeadless(config: AppConfig) {
        Log.info("Running in headless mode", category: .general)

        let agent = AgentCore(config: config)
        let semaphore = DispatchSemaphore(value: 0)

        // Set up signal handling
        let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let sigtermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        Foundation.signal(SIGINT, SIG_IGN)
        Foundation.signal(SIGTERM, SIG_IGN)

        sigintSrc.setEventHandler { semaphore.signal() }
        sigtermSrc.setEventHandler { semaphore.signal() }
        sigintSrc.resume()
        sigtermSrc.resume()

        // Start agent on a background task
        Task {
            await agent.start()
        }

        // Block main thread until signal
        semaphore.wait()

        Log.info("Shutdown signal received", category: .general)
        let stopSemaphore = DispatchSemaphore(value: 0)
        Task {
            await agent.stop()
            stopSemaphore.signal()
        }
        stopSemaphore.wait()
    }

    private static func handleSetPassword() {
        print("Enter MQTT password: ", terminator: "")
        guard let password = readLine(strippingNewline: true), !password.isEmpty else {
            print("Error: No password entered")
            Foundation.exit(1)
        }
        do {
            try KeychainHelper.savePassword(password)
            print("MQTT password saved to Keychain")
        } catch {
            print("Error saving password: \(error)")
            Foundation.exit(1)
        }
    }

    private static func handleShowConfig(configURL: URL?) {
        do {
            let config = try AppConfig.load(from: configURL)
            print(config.redactedDescription())
        } catch {
            print("Error loading config: \(error)")
            Foundation.exit(1)
        }
    }
}

// MARK: - SwiftUI App (GUI mode)

struct MacquittoGUIApp: App {
    static var initialConfig: AppConfig = .default
    static var initialConfigError: String?

    @State private var appState: AppState

    init() {
        let state = AppState(config: Self.initialConfig)
        if let error = Self.initialConfigError {
            state.lastError = error
        }
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .task {
                    // Set app icon once NSApp is available
                    if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        icon.setName("AppIcon")
                        NSApp.applicationIconImage = icon
                    }
                    await appState.startAgent()
                }
        } label: {
            if let icon = appState.statusIcon {
                Image(nsImage: icon)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 600, height: 450)

        Window("About Macquitto", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
