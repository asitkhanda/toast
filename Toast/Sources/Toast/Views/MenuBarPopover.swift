import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @Environment(DeploymentStore.self) private var store
    @Environment(SparkleUpdater.self) private var updater
    @Environment(\.openSettings) private var openSettings

    @State private var showFeedbackSheet = false
    @State private var selectedProvider: DeploymentProvider?

    var body: some View {
        Group {
            if showFeedbackSheet {
                FeedbackSheet {
                    showFeedbackSheet = false
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    content
                    Divider()
                    footer
                }
            }
        }
        .frame(width: Theme.popoverWidth)
        .task {
            await store.refreshNow()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.summary.headline)
                    .font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            headerIcon
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.summary.headline). \(headerSubtitle)")
        .accessibilityAddTraits(.isHeader)
    }

    private var headerSubtitle: String {
        if store.isLoading && store.projectStatuses.isEmpty {
            return "Checking your deployments…"
        }
        if let lastRefresh = store.lastRefresh {
            return RelativeDateFormat.label(for: lastRefresh, prefix: "Checked")
        }
        return "Toast checks every minute, and every 5 seconds while something builds."
    }

    @ViewBuilder
    private var headerIcon: some View {
        if store.isLoading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Refreshing")
        } else {
            let status = store.aggregateStatus
            Image(systemName: status.menuBarSymbol)
                .font(.title2)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure = store.lastFailure {
                InlineNotice(
                    kind: .error,
                    title: failure.title,
                    message: failure.message,
                    actionTitle: actionTitle(for: failure),
                    action: action(for: failure)
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }

            if store.watchedProjects.isEmpty {
                emptyState
            } else if store.projectStatuses.isEmpty {
                loadingState
            } else {
                projectList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Choose what to watch")
                .font(.headline)
            Text("Pick the projects you want Toast to keep an eye on. Their status will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose projects…") {
                AppActivation.openSettings(openSettings)
            }
            .toastButtonStyle(prominent: true)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Checking your deployments…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(24)
    }

    private var providerGroups: [(provider: DeploymentProvider, statuses: [ProjectDeploymentStatus])] {
        DeploymentProvider.allCases.compactMap { provider in
            let statuses = store.projectStatuses.filter { $0.watched.provider == provider }
            return statuses.isEmpty ? nil : (provider, statuses)
        }
    }

    private var activeProvider: DeploymentProvider {
        if let selectedProvider, providerGroups.contains(where: { $0.provider == selectedProvider }) {
            return selectedProvider
        }
        // Open on the first service that has a problem, otherwise the first one.
        let withProblem = providerGroups.first { group in
            group.statuses.contains { $0.status == .error || $0.status == .blocked }
        }
        return (withProblem ?? providerGroups.first)?.provider ?? .vercel
    }

    private var projectList: some View {
        let groups = providerGroups
        let active = activeProvider
        let visible = groups.first { $0.provider == active }?.statuses ?? []
        return VStack(alignment: .leading, spacing: 0) {
            if groups.count > 1 {
                Picker("Service", selection: Binding(
                    get: { active },
                    set: { selectedProvider = $0 }
                )) {
                    ForEach(groups, id: \.provider) { group in
                        Text("\(group.provider.displayName) (\(group.statuses.count))")
                            .tag(group.provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Service")
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { status in
                        DeploymentRow(status: status)
                        if status.id != visible.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .frame(
                minHeight: min(CGFloat(visible.count) * 130, 300),
                maxHeight: 400
            )
        }
    }

    // MARK: Errors

    private func actionTitle(for failure: UserFacingError) -> String? {
        switch failure.action {
        case .replaceToken: "Fix in Settings"
        case .openSettings: "Open Settings"
        case .retry: "Try again"
        case nil: nil
        }
    }

    private func action(for failure: UserFacingError) -> (() -> Void)? {
        switch failure.action {
        case .replaceToken, .openSettings:
            return { AppActivation.openSettings(openSettings) }
        case .retry:
            return { Task { await store.refreshNow() } }
        case nil:
            return nil
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.refreshNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Check your deployments now")
            .keyboardShortcut("r")
            .toastButtonStyle()

            Button {
                AppActivation.openSettings(openSettings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Accounts, projects and preferences")
            .keyboardShortcut(",")
            .toastButtonStyle()

            Spacer()

            Menu {
                if updater.supportsManualUpdates {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                }
                Button("Send Feedback…") { showFeedbackSheet = true }
                Divider()
                Button("Quit Toast") {
                    BackgroundBehavior.markUserQuit()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .toastButtonStyle()
            .fixedSize()
            .help("Updates, feedback and quit")
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.regular)
        .padding(12)
    }
}
