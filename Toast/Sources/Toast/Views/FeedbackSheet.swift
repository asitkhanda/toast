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
            Text("Send Feedback")
                .font(.title3.weight(.semibold))

            Text("Help us improve Toast. Diagnostics are included automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !analyticsEnabled {
                Label("Enable “Help improve Toast” in Settings to send feedback.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            TextField("What happened? (optional)", text: $message, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .disabled(!analyticsEnabled)

            if didSend {
                Label("Thanks — feedback sent.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button("Send") {
                    sendFeedback()
                }
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
