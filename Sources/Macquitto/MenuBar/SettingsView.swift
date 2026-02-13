import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case mqtt = "MQTT"
    case sensors = "Sensors"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .mqtt: return "network"
        case .sensors: return "sensor"
        }
    }
}

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(appState: appState)
                case .mqtt:
                    MQTTSettingsView(appState: appState)
                case .sensors:
                    SensorSettingsView(appState: appState)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
