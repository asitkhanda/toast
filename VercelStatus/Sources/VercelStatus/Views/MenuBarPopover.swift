import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @Environment(DeploymentStore.self) private var store
    @Environment(SparkleUpdater.self) private var updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .task {
            await store.refreshNow()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.headline)
                headerSubtitle
            }
            Spacer()
            statusIcon
        }
        .padding()
    }

    private var headerTitle: String {
        let count = store.watchedProjects.count
        if count == 1, let name = store.watchedProjects.first?.projectName {
            return name
        }
        if count > 1 {
            return "\(count) projects"
        }
        return "No projects"
    }

    @ViewBuilder
    private var headerSubtitle: some View {
        if store.isLoading, store.projectStatuses.isEmpty {
            Text("Fetching deployments…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if store.projectStatuses.count == 1, let status = store.projectStatuses.first {
            singleProjectHeaderTimestamps(status)
        } else if let lastRefresh = store.lastRefresh {
            Text(RelativeDateFormat.label(for: lastRefresh, prefix: "Checked"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func singleProjectHeaderTimestamps(_ status: ProjectDeploymentStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let deployed = status.deployment?.deployedDate {
                Text(RelativeDateFormat.label(for: deployed, prefix: "Deployed"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(RelativeDateFormat.label(for: status.fetchedAt, prefix: "Checked"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if store.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            switch store.aggregateStatus {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .building:
                ProgressView()
                    .controlSize(.small)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .disconnected:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .idle:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.watchedProjects.isEmpty {
            emptyState(
                title: "No projects watched",
                actionTitle: "Choose projects…"
            )
        } else if store.projectStatuses.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading deployments…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(24)
        } else if store.projectStatuses.count == 1, let status = store.projectStatuses.first {
            // Single project: details live in header; show metadata below
            singleProjectContent(status)
        } else {
            multiProjectContent
        }

        if let error = store.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func singleProjectContent(_ status: ProjectDeploymentStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DeploymentRow(status: status, showProjectName: false)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
    }

    private var multiProjectContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.projectStatuses) { status in
                    DeploymentRow(status: status)
                        .padding(.horizontal)
                    if status.id != store.projectStatuses.last?.id {
                        Divider()
                            .padding(.leading)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(
            minHeight: min(CGFloat(store.projectStatuses.count) * 110, 330),
            maxHeight: 420
        )
    }

    private func emptyState(title: String, actionTitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Button(actionTitle) {
                AppActivation.openSettings(openSettings)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(24)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                Task { await store.refreshNow() }
            }
            Button("Settings…") {
                AppActivation.openSettings(openSettings)
            }
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .padding(10)
    }
}
