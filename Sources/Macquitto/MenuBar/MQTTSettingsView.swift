import SwiftUI

struct MQTTSettingsView: View {
    @Bindable var appState: AppState
    @State private var password: String = ""
    @State private var hasChanges = false
    @State private var testResult: TestConnectionResult?
    @State private var isTesting = false
    @State private var keychainError: String?

    enum TestConnectionResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Host", text: $appState.config.mqtt.host)
                    .onChange(of: appState.config.mqtt.host) { _, _ in hasChanges = true }

                TextField("Port", text: Binding(
                    get: { String(appState.config.mqtt.port) },
                    set: { if let v = Int($0) { appState.config.mqtt.port = v } }
                ))
                .onChange(of: appState.config.mqtt.port) { _, _ in hasChanges = true }

                Toggle("Use TLS", isOn: $appState.config.mqtt.tls)
                    .onChange(of: appState.config.mqtt.tls) { _, _ in hasChanges = true }

                if appState.config.mqtt.tls {
                    TextField("TLS Port", text: Binding(
                        get: { String(appState.config.mqtt.tlsPort ?? 8883) },
                        set: { if let v = Int($0) { appState.config.mqtt.tlsPort = v } }
                    ))
                    .onChange(of: appState.config.mqtt.tlsPort) { _, _ in hasChanges = true }

                    TextField("CA Certificate Path", text: Binding(
                        get: { appState.config.mqtt.caCert ?? "" },
                        set: { appState.config.mqtt.caCert = $0.isEmpty ? nil : $0 }
                    ))
                    .onChange(of: appState.config.mqtt.caCert) { _, _ in hasChanges = true }

                    TextField("Client Certificate Path", text: Binding(
                        get: { appState.config.mqtt.clientCert ?? "" },
                        set: { appState.config.mqtt.clientCert = $0.isEmpty ? nil : $0 }
                    ))
                    .onChange(of: appState.config.mqtt.clientCert) { _, _ in hasChanges = true }

                    TextField("Client Key Path", text: Binding(
                        get: { appState.config.mqtt.clientKey ?? "" },
                        set: { appState.config.mqtt.clientKey = $0.isEmpty ? nil : $0 }
                    ))
                    .onChange(of: appState.config.mqtt.clientKey) { _, _ in hasChanges = true }
                }
            }

            Section("Authentication") {
                TextField("Username", text: Binding(
                    get: { appState.config.mqtt.username ?? "" },
                    set: { appState.config.mqtt.username = $0.isEmpty ? nil : $0 }
                ))
                .onChange(of: appState.config.mqtt.username) { _, _ in hasChanges = true }

                SecureField("Password (Keychain)", text: $password)
                    .onChange(of: password) { _, _ in hasChanges = true }

                if let keychainError {
                    Label(keychainError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Topics") {
                TextField("Discovery Prefix", text: $appState.config.mqtt.discoveryPrefix)
                    .onChange(of: appState.config.mqtt.discoveryPrefix) { _, _ in hasChanges = true }

                TextField("Base Topic", text: $appState.config.mqtt.baseTopic)
                    .onChange(of: appState.config.mqtt.baseTopic) { _, _ in hasChanges = true }
            }

            Section {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mqttStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.statusText)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if appState.mqttStatus == .connected {
                        Button("Disconnect") {
                            Task { await appState.stopAgent() }
                        }
                    } else {
                        Button("Connect") {
                            Task { await appState.restartAgent() }
                        }
                    }

                    Button("Save") {
                        save()
                    }
                    .disabled(!hasChanges)
                    .keyboardShortcut(.defaultAction)
                }

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            do {
                password = try KeychainHelper.readPassword() ?? ""
            } catch {
                password = ""
                keychainError = "Could not read password from Keychain: \(error.localizedDescription)"
                Log.warning("Keychain read failed: \(error)", category: .config)
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let pw = password.isEmpty ? nil : password
            let mqtt = MQTTManager(
                config: appState.config.mqtt,
                deviceId: "test",
                password: pw
            )

            do {
                try await mqtt.connect()
                await mqtt.disconnect()
                testResult = .success
            } catch {
                await mqtt.forceShutdown()
                testResult = .failure(error.localizedDescription)
            }

            isTesting = false
        }
    }

    private var mqttStatusColor: Color {
        switch appState.mqttStatus {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .red
        }
    }

    private func save() {
        if !password.isEmpty {
            try? KeychainHelper.savePassword(password)
        }

        appState.saveConfig()
        hasChanges = false
    }
}
