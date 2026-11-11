import SwiftUI

struct FeedbackSheet: View {
    @Environment(DeploymentStore.self) private var store

    let onDismiss: () -> Void

    @State private var message = ""
    @State private var didSend = false

    private var analyticsEnabled: Bool {
        AnalyticsService.shared.isEnabled && AnalyticsService.shared.hasProjectToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send feedback")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Text("Tell us what happened or what could be better. Anonymous diagnostics (app version, macOS version, error types) are included. Never your tokens or project names.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !analyticsEnabled {
                InlineNotice(
                    kind: .info,
                    title: "Feedback is turned off",
                    message: "Turn on “Help improve Toast” in Settings → Privacy to send feedback."
                )
            }

            TextField("What happened? (optional)", text: $message, axis: .vertical)
                .accessibilityLabel("Your feedback")
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .disabled(!analyticsEnabled)

            if didSend {
                InlineNotice(kind: .success, title: "Thanks, your feedback was sent.")
            }

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send feedback") {
                    sendFeedback()
                }
                .toastButtonStyle(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(!analyticsEnabled || didSend)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func sendFeedback() {
        AnalyticsService.shared.captureFeedback(message: message, from: store)
        didSend = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onDismiss()
        }
    }
}
