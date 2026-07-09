import SwiftUI
import Shared

struct CrashReportPrompt: View {
    @Environment(DeploymentStore.self) private var store

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Toast quit unexpectedly", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Send an anonymous diagnostic report to help fix this? No personal information is included.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Don't Ask Again") {
                    RuntimeState.shared.crashPromptSuppressed = true
                    onDismiss()
                }
                Spacer()
                Button("Not Now") {
                    onDismiss()
                }
                Button("Send Report") {
                    AnalyticsService.shared.captureCrashReportAccepted(from: store)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
