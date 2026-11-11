import SwiftUI

struct DeploymentRow: View {
    let status: ProjectDeploymentStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(status.watched.projectName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    StatusPill(state: status.status)
                }

                timestampLine

                if let deployment = status.deployment {
                    detailLine(deployment)
                    if let message = deployment.commitMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenSummary)

            if let deployment = status.deployment {
                HStack(spacing: 14) {
                    if let url = deployment.previewURL {
                        Link("Open site", destination: url)
                            .help("Open the deployed site in your browser")
                    }
                    Link("View in \(status.watched.provider.displayName)", destination: dashboardURL(for: status.watched, deployment: deployment))
                        .help("Open this deployment in the \(status.watched.provider.displayName) dashboard")
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var timestampLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let deployed = status.deployment?.deployedDate {
                Text(RelativeDateFormat.label(for: deployed, prefix: status.status.isInProgress ? "Started" : "Deployed"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No deployments yet. Push a commit and it will show up here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if status.isStale {
                Label("Couldn't refresh. Showing the last known status.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.multicolor)
            }
        }
    }

    private func detailLine(_ deployment: Deployment) -> some View {
        HStack(spacing: 8) {
            if deployment.isProduction {
                MetaChip(text: "Production", symbol: "shield.fill")
            }
            if let branch = deployment.branch {
                MetaChip(text: branch, symbol: "arrow.triangle.branch")
            }
            if let sha = deployment.commitSHA {
                Text(sha)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            if status.status == .ready, let seconds = deployment.durationSeconds, seconds > 0 {
                Text("Built in \(Self.format(duration: seconds))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var spokenSummary: String {
        var parts = ["\(status.watched.projectName), \(status.status.spokenName)"]
        if let deployed = status.deployment?.deployedDate {
            parts.append(RelativeDateFormat.label(for: deployed, prefix: status.status.isInProgress ? "started" : "deployed"))
        }
        if let branch = status.deployment?.branch { parts.append("branch \(branch)") }
        if let message = status.deployment?.commitMessage { parts.append(message) }
        if status.isStale { parts.append("could not refresh, showing last known status") }
        return parts.joined(separator: ", ")
    }

    static func format(duration seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m \(total % 60)s"
    }

    private func dashboardURL(for watched: WatchedProject, deployment: Deployment) -> URL {
        switch watched.provider {
        case .vercel:
            return URL(string: "https://vercel.com/\(watched.teamId)/\(watched.projectName)/\(deployment.uid)")!
        case .cloudflare:
            let name = CloudflareProjectKind.name(fromProjectID: watched.projectId)
            switch CloudflareProjectKind(projectID: watched.projectId) ?? .pages {
            case .pages:
                return URL(string: "https://dash.cloudflare.com/\(watched.teamId)/pages/view/\(name)/\(deployment.uid)")!
            case .worker:
                return URL(string: "https://dash.cloudflare.com/\(watched.teamId)/workers/services/view/\(name)/production")!
            }
        }
    }
}

struct MetaChip: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
