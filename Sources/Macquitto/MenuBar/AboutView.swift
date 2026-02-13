import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("Macquitto")
                .font(.title.bold())

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Text("A native macOS agent that exposes system sensors and actions to Home Assistant via MQTT.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360, height: 280)
    }
}
