import AppKit
import SwiftUI

private enum SettingsTab: Hashable {
    case general, accounts, projects, notifications, privacy, about
}

struct SettingsView: View {
    @Environment(DeploymentStore.self) private var store
    @Environment(SparkleUpdater.self) private var updater

    @State private var tab: SettingsTab = .accounts

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            ProjectsTab(goToAccounts: { tab = .accounts })
                .tabItem { Label("Projects", systemImage: "folder") }
                .tag(SettingsTab.projects)
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 600, height: 560)
        .task {
            await store.restoreSessionIfNeeded()
        }
        .onDisappear {
            if store.runInBackgroundEnabled {
                AppActivation.restoreMenuBarOnlyPolicy()
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(DeploymentStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Open Toast when I log in", isOn: $store.launchAtLoginEnabled)
                Text("Starts Toast automatically so it's always in your menu bar.")
                    .settingsHelp()
                Toggle("Keep Toast out of the Dock", isOn: $store.runInBackgroundEnabled)
                Text("Toast lives only in the menu bar, with no Dock icon.")
                    .settingsHelp()
                Toggle("Restart Toast if it quits unexpectedly", isOn: $store.relaunchOnCrashEnabled)
                Text("A small helper brings Toast back so you don't miss a failed deploy.")
                    .settingsHelp()
                if BackgroundBehavior.launchAtLoginRequiresApproval || BackgroundBehavior.relaunchHelperRequiresApproval {
                    InlineNotice(
                        kind: .info,
                        title: "macOS needs your approval",
                        message: "Open System Settings → General → Login Items and allow Toast."
                    )
                }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Show status text next to the icon", isOn: $store.showStatusText)
                Text("Adds a short word such as BUILD or ERR beside the menu bar icon.")
                    .settingsHelp()
            } header: {
                Text("Menu bar")
            }

            Section {
                Text("Toast checks every minute, and every 5 seconds while something is building.")
                    .settingsHelp()
            } header: {
                Text("How often Toast checks")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accounts

private struct AccountsTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect the services where your projects are deployed. Toast only reads status.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(DeploymentProvider.allCases) { provider in
                    AccountCard(provider: provider)
                }
            }
            .padding(20)
        }
    }
}

private struct AccountCard: View {
    @Environment(DeploymentStore.self) private var store

    let provider: DeploymentProvider

    @State private var token = ""
    @State private var showToken = false
    @State private var isEditingToken = false
    @State private var hasStoredToken = false
    @State private var isWorking = false
    @State private var failure: UserFacingError?
    @State private var successMessage: String?
    @State private var showInstructions = false

    private var isConnected: Bool { hasStoredToken && store.isConnected(to: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: provider.symbolName)
                    .font(.title2)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.headline)
                    statusLine
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            if hasStoredToken && !isEditingToken {
                connectedActions
            } else {
                tokenEntry
            }

            if let failure {
                InlineNotice(
                    kind: .error,
                    title: failure.title,
                    message: failure.message
                )
            }
            if let successMessage {
                InlineNotice(kind: .success, title: successMessage)
            }
            if let warning = store.scopeWarning(for: provider), hasStoredToken, !isEditingToken {
                InlineNotice(kind: .warning, title: "This token can do more than Toast needs", message: warning)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .task {
            hasStoredToken = KeychainStore.hasToken(for: provider)
        }
        .onDisappear {
            token = ""
            showToken = false
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if isConnected {
            Label(
                store.connectedAccountName(for: provider).map { "Connected to \($0)" } ?? "Connected",
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout)
            .symbolRenderingMode(.multicolor)
        } else if hasStoredToken {
            Label("Needs attention. Toast can't reach \(provider.displayName).", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .symbolRenderingMode(.multicolor)
        } else {
            Label("Not connected", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var connectedActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Token saved in your Keychain", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Test connection") { Task { await test() } }
                    .disabled(isWorking)
                Button("Replace token…") {
                    isEditingToken = true
                    token = ""
                    failure = nil
                    successMessage = nil
                }
                Spacer()
                Button("Disconnect", role: .destructive) { disconnect() }
                    .help("Removes the token and stops watching \(provider.displayName) projects")
            }
            if isWorking {
                ProgressView("Checking…").controlSize(.small)
            }
        }
    }

    private var tokenEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("How to get a token", isExpanded: $showInstructions) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(provider.tokenSteps.enumerated()), id: \.offset) { index, text in
                        Text("\(index + 1). \(text)")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !provider.requiredPermissions.isEmpty {
                        Text("Permissions to add:").font(.callout.weight(.semibold)).padding(.top, 4)
                        ForEach(provider.requiredPermissions) { permission in
                            Text("• \(permission.label)\(permission.isOptional ? " (optional)" : "")")
                                .font(.callout)
                        }
                    }
                    Button(provider.tokenPageButtonTitle) {
                        NSWorkspace.shared.open(provider.tokensURL)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 6)
            }

            HStack {
                Group {
                    if showToken {
                        TextField("Token", text: $token, prompt: Text(provider.tokenPlaceholder))
                    } else {
                        SecureField("Token", text: $token, prompt: Text(provider.tokenPlaceholder))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(provider.displayName) token")
                .onSubmit { Task { await save() } }
                Button(showToken ? "Hide" : "Show") { showToken.toggle() }
            }

            Label(provider.privacyReassurance, systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button(hasStoredToken ? "Save new token" : "Connect") { Task { await save() } }
                    .toastButtonStyle(prominent: true)
                    .disabled(isWorking || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isEditingToken {
                    Button("Cancel") {
                        isEditingToken = false
                        token = ""
                        failure = nil
                    }
                }
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func save() async {
        isWorking = true
        failure = nil
        successMessage = nil
        defer { isWorking = false }
        do {
            try await store.connect(token: token, provider: provider)
            hasStoredToken = true
            isEditingToken = false
            token = ""
            showToken = false
            successMessage = "Connected to \(store.connectedAccountName(for: provider) ?? provider.displayName). Next, choose projects in the Projects tab."
        } catch {
            AnalyticsService.shared.captureTokenFailed(error)
            failure = UserFacingError.from(error)
        }
    }

    private func test() async {
        isWorking = true
        failure = nil
        successMessage = nil
        defer { isWorking = false }
        do {
            try await store.testConnection(provider)
            successMessage = "Connection works."
        } catch {
            failure = UserFacingError.from(error)
        }
    }

    private func disconnect() {
        store.disconnect(provider: provider)
        hasStoredToken = false
        isEditingToken = false
        token = ""
        failure = nil
        successMessage = "Disconnected from \(provider.displayName)."
    }
}

// MARK: - Projects

private struct ProjectsTab: View {
    @Environment(DeploymentStore.self) private var store

    let goToAccounts: () -> Void

    var body: some View {
        let connected = DeploymentProvider.allCases.filter { KeychainStore.hasToken(for: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if connected.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Connect an account first")
                            .font(.headline)
                        Text("Add a Vercel or Cloudflare token to choose which projects Toast watches.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Go to Accounts", action: goToAccounts)
                            .toastButtonStyle(prominent: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    Text("Tick the projects Toast should watch, then save.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(connected) { provider in
                        ProviderProjects(provider: provider)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct ProviderProjects: View {
    @Environment(DeploymentStore.self) private var store

    let provider: DeploymentProvider

    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var statusMessage: String?

    private var watchedIDs: Set<String> {
        Set(store.watchedProjects.filter { $0.provider == provider }.map(\.projectId))
    }

    private var filtered: [Project] {
        let all = store.projects(for: provider)
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(provider.displayName, systemImage: provider.symbolName)
                    .font(.headline)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Button("Reload") {
                    Task { await store.reloadProjects(for: provider) }
                }
                .help("Fetch the latest list of projects")
            }

            if store.accounts(for: provider).count > 1 {
                Picker(provider.accountNoun, selection: Binding(
                    get: { store.selectedAccountId(for: provider) },
                    set: { newValue in
                        store.selectAccount(newValue, for: provider)
                        selected = watchedIDs
                        Task { await store.reloadProjects(for: provider) }
                    }
                )) {
                    Text("Select").tag(Optional<String>.none)
                    ForEach(store.accounts(for: provider)) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
            }

            if let notice = store.projectNotice(for: provider) {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }

            if store.projects(for: provider).isEmpty {
                InlineNotice(
                    kind: .info,
                    title: "No projects to show",
                    message: "Try Reload. If this stays empty, check the token's permissions in the Accounts tab."
                )
            } else {
                HStack {
                    TextField("Search projects", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search \(provider.displayName) projects")
                    Button("Select all") { selected.formUnion(filtered.map(\.id)) }
                    Button("None") { selected.subtract(filtered.map(\.id)) }
                }
                .controlSize(.small)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { project in
                            ProjectToggleRow(project: project, isSelected: selected.contains(project.id)) { isOn in
                                if isOn { selected.insert(project.id) } else { selected.remove(project.id) }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 100, maxHeight: 200)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Save watched projects") { save() }
                        .toastButtonStyle(prominent: true)
                        .disabled(store.selectedAccountId(for: provider) == nil)
                    Text(statusMessage ?? "\(selected.count) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .task { selected = watchedIDs }
    }

    private func save() {
        guard let accountId = store.selectedAccountId(for: provider) else { return }
        let chosen = store.projects(for: provider)
            .filter { selected.contains($0.id) }
            .map { WatchedProject(projectId: $0.id, projectName: $0.name, teamId: accountId, provider: provider) }
        store.updateWatchedProjects(chosen, for: provider)
        statusMessage = "Saved. Watching \(chosen.count) project\(chosen.count == 1 ? "" : "s")."
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @Environment(DeploymentStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Notify me when a deploy finishes", isOn: $store.notificationsEnabled)
                Text("A notification appears when a build you're watching succeeds or fails.")
                    .settingsHelp()
                Text("If you don't see them, allow notifications for Toast in System Settings → Notifications.")
                    .settingsHelp()
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Deploy notifications")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @State private var analyticsEnabled = AnalyticsService.shared.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Help improve Toast", isOn: $analyticsEnabled)
                    .onChange(of: analyticsEnabled) { _, enabled in
                        AnalyticsService.shared.isEnabled = enabled
                    }
                Text("Sends anonymous usage data and crash reports to help fix bugs. It never includes your tokens, project names, account names or personal information.")
                    .settingsHelp()
                Link("Read the privacy policy", destination: URL(string: "https://toast.asit.space/privacy")!)
            } header: {
                Text("Analytics")
            }

            Section {
                Text("Tokens are stored in this Mac's Keychain and are only sent to Vercel or Cloudflare to read your deployment status.")
                    .settingsHelp()
            } header: {
                Text("Your tokens")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutTab: View {
    @Environment(SparkleUpdater.self) private var updater

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text("\(updater.currentVersion) (\(updater.currentBuild))")
                }
                if updater.supportsManualUpdates {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                } else {
                    Text("Updates are delivered by the Mac App Store.")
                        .settingsHelp()
                }
            } header: {
                Text("Toast")
            }

            Section {
                Link("Website", destination: URL(string: "https://toast.asit.space")!)
                Link("Privacy policy", destination: URL(string: "https://toast.asit.space/privacy")!)
                Link("Terms", destination: URL(string: "https://toast.asit.space/terms")!)
            } header: {
                Text("Links")
            }
        }
        .formStyle(.grouped)
    }
}

private extension Text {
    func settingsHelp() -> some View {
        self
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
