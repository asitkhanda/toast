import SwiftUI
import Shared

struct CrashReportPrompt: View {
    @Environment(DeploymentStore.self) private var store

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Toast quit unexpectedly", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
                .accessibilityAddTraits(.isHeader)

            Text("Would you like to send an anonymous report so the problem can be fixed? It never includes your tokens, project names or personal information.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Don't ask again") {
                    RuntimeState.shared.crashPromptSuppressed = true
                    onDismiss()
                }
                Spacer()
                Button("Not Now") {
                    onDismiss()
                }
                Button("Send report") {
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
