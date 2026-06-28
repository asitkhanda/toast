import SwiftUI

struct DeploymentRow: View {
    let status: ProjectDeploymentStatus
    let showProjectName: Bool

    init(status: ProjectDeploymentStatus, showProjectName: Bool = true) {
        self.status = status
        self.showProjectName = showProjectName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if showProjectName {
                        Text(status.watched.projectName)
                            .font(.headline)
                    }
                    timestampLine
                }
                Spacer()
                if showProjectName {
                    StatusBadge(state: status.status)
                }
            }

            if let deployment = status.deployment {
                HStack(spacing: 8) {
                    if deployment.isProduction {
                        Tag(text: "Production", color: .purple)
                    }
                    if let branch = deployment.branch {
                        Tag(text: branch, color: .secondary)
                    }
                    if let sha = deployment.commitSHA {
                        Text(sha)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = deployment.commitMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    if let url = deployment.previewURL {
                        Link("Open preview", destination: url)
                            .font(.caption)
                    }
                    Link(
                        "Vercel dashboard",
                        destination: dashboardURL(for: status.watched, deployment: deployment)
                    )
                    .font(.caption)
                }
            } else {
                Text("No deployment data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var timestampLine: some View {
        if showProjectName {
            VStack(alignment: .leading, spacing: 2) {
                if let deployment = status.deployment, let deployed = deployment.deployedDate {
                    Text(RelativeDateFormat.label(for: deployed, prefix: "Deployed"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if status.deployment == nil {
                    Text("No deployment yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(RelativeDateFormat.label(for: status.fetchedAt, prefix: "Checked"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dashboardURL(for watched: WatchedProject, deployment: Deployment) -> URL {
        URL(string: "https://vercel.com/\(watched.teamId)/\(watched.projectName)/\(deployment.uid)")!
    }
}

struct StatusBadge: View {
    let state: DeploymentState

    var body: some View {
        Text(state.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch state {
        case .ready: .green
        case .building, .initializing, .queued: .blue
        case .error, .canceled, .blocked: .red
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .clipShape(Capsule())
    }
}
