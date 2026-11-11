import SwiftUI

struct AnalyticsRolloutNotice: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's new in Toast")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Text("Anonymous analytics")
                .font(.headline)

            Text("Toast now sends anonymous usage data and crash reports to help fix bugs and improve the app. It's on by default, and you can turn it off any time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label("We collect app version, feature usage, and crash diagnostics", systemImage: "checkmark.circle")
                Label("We never collect your API tokens, project names, or personal information", systemImage: "xmark.circle")
                Label("Turn off anytime in Settings → Privacy", systemImage: "gearshape")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Link("Read the privacy policy", destination: URL(string: "https://toast.asit.space/privacy")!)

            HStack {
                Button("Review in Settings") {
                    onOpenSettings()
                    onDismiss()
                }
                Spacer()
                Button("Got it") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .toastButtonStyle(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
