import SwiftUI

struct AnalyticsRolloutNotice: View {
    @Environment(\.openSettings) private var openSettings
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's New in Toast")
                .font(.title3.weight(.semibold))

            Text("Anonymous analytics")
                .font(.headline)

            Text("Toast now sends anonymous usage data and crash reports to help fix bugs and improve the app. This is on by default.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label("We collect app version, feature usage, and crash diagnostics", systemImage: "checkmark.circle")
                Label("We never collect your Vercel token, project names, or personal information", systemImage: "xmark.circle")
                Label("Turn off anytime in Settings → Privacy", systemImage: "gearshape")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Link("Read the Privacy Policy", destination: URL(string: "https://toast.asit.space/privacy")!)

            HStack {
                Button("Open Settings") {
                    AppActivation.openSettings(openSettings)
                    onDismiss()
                }
                Spacer()
                Button("Got It") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
