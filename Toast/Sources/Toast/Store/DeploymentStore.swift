import Foundation
import Observation
import SwiftUI
import UserNotifications

struct BackgroundPreferences: Sendable {
    var launchAtLogin: Bool
    var runInBackground: Bool
    var relaunchOnCrash: Bool

    static let defaults = BackgroundPreferences(
        launchAtLogin: true,
        runInBackground: true,
        relaunchOnCrash: true
    )
}

struct ProjectDeploymentStatus: Identifiable, Sendable {
    let watched: WatchedProject
    let deployment: Deployment?
    let fetchedAt: Date
    let isStale: Bool

    var id: String { watched.id }

    var status: DeploymentState {
        deployment?.status ?? .queued
    }
}

enum AggregateStatus: Sendable {
    case idle
    case building
    case ready
    case error
    case disconnected

    var menuBarSymbol: String {
        switch self {
        case .idle: "triangle.fill"
        case .building: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .disconnected: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: .secondary
        case .building: .blue
        case .ready: .green
        case .error: .red
        case .disconnected: .orange
        }
    }

    var shortLabel: String? {
        switch self {
        case .building: "BUILD"
        case .error: "ERR"
        default: nil
        }
    }
}

@MainActor
@Observable
final class DeploymentStore {
    var hasCompletedOnboarding = false
    var showStatusText = true {
        didSet {
            UserDefaults.standard.set(showStatusText, forKey: Keys.showStatusText)
            trackSettingChanged("show_status_text", value: showStatusText, oldValue: oldValue)
        }
    }
    var notificationsEnabled = true {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            trackSettingChanged("notifications_enabled", value: notificationsEnabled, oldValue: oldValue)
        }
    }
    var launchAtLoginEnabled = true {
        didSet {
            persistBackgroundPreferenceChange()
            trackSettingChanged("launch_at_login", value: launchAtLoginEnabled, oldValue: oldValue)
        }
    }
    var runInBackgroundEnabled = true {
        didSet {
            persistBackgroundPreferenceChange()
            trackSettingChanged("run_in_background", value: runInBackgroundEnabled, oldValue: oldValue)
        }
    }
    var relaunchOnCrashEnabled = true {
        didSet {
            persistBackgroundPreferenceChange()
            trackSettingChanged("relaunch_on_crash", value: relaunchOnCrashEnabled, oldValue: oldValue)
        }
    }
    var selectedTeamId: String? = nil {
        didSet {
            persistSelectedTeamId()
        }
    }
    var selectedCloudflareAccountId: String? = nil {
        didSet {
            persistSelectedCloudflareAccountId()
        }
    }
    var watchedProjects: [WatchedProject] = []
    /// Shows the "You're all set" screen once, right after onboarding finishes.
    var showSetupComplete = false

    private(set) var teams: [Team] = []
    private(set) var projects: [Project] = []
    private(set) var projectStatuses: [ProjectDeploymentStatus] = []
    private(set) var isLoading = false
    private(set) var isFinishingOnboarding = false
    private(set) var lastError: String?
    /// The same problem as `lastError`, in plain language with a suggested next step.
    private(set) var lastFailure: UserFacingError?
    private(set) var tokenScopeWarning: String?
    private(set) var lastRefresh: Date?
    private(set) var isConnected = false
    private(set) var connectedTeamName: String?
    private(set) var cloudflareAccounts: [Team] = []
    private(set) var cloudflareProjects: [Project] = []
    private(set) var isCloudflareConnected = false
    private(set) var connectedCloudflareAccountName: String?
    private(set) var cloudflareScopeWarning: String?
    private(set) var cloudflareProjectNotice: String?

    var summary: StatusSummary {
        StatusSummary.make(states: projectStatuses.map(\.status), isDisconnected: hasDisconnectedProvider)
    }

    var aggregateStatus: AggregateStatus {
        if hasDisconnectedProvider {
            return .disconnected
        }
        let statuses = projectStatuses.map(\.status)
        if statuses.contains(where: { $0 == .error || $0 == .canceled || $0 == .blocked }) {
            return .error
        }
        if statuses.contains(where: \.isInProgress) {
            return .building
        }
        if statuses.contains(where: { $0 == .ready }) {
            return .ready
        }
        return .idle
    }

    // MARK: Provider-generic accessors used by onboarding and Settings

    func accounts(for provider: DeploymentProvider) -> [Team] {
        provider == .vercel ? teams : cloudflareAccounts
    }

    func projects(for provider: DeploymentProvider) -> [Project] {
        provider == .vercel ? projects : cloudflareProjects
    }

    func selectedAccountId(for provider: DeploymentProvider) -> String? {
        provider == .vercel ? selectedTeamId : selectedCloudflareAccountId
    }

    func selectAccount(_ id: String?, for provider: DeploymentProvider) {
        if provider == .vercel {
            selectedTeamId = id
        } else {
            selectedCloudflareAccountId = id
        }
    }

    func connectedAccountName(for provider: DeploymentProvider) -> String? {
        provider == .vercel ? connectedTeamName : connectedCloudflareAccountName
    }

    func projectNotice(for provider: DeploymentProvider) -> String? {
        provider == .cloudflare ? cloudflareProjectNotice : nil
    }

    func scopeWarning(for provider: DeploymentProvider) -> String? {
        provider == .vercel ? tokenScopeWarning : cloudflareScopeWarning
    }

    func connect(token: String, provider: DeploymentProvider) async throws {
        switch provider {
        case .vercel: try await connect(token: token)
        case .cloudflare: try await connectCloudflare(token: token)
        }
    }

    /// Makes a quick read-only call to confirm the saved token still works.
    func testConnection(_ provider: DeploymentProvider) async throws {
        switch provider {
        case .vercel:
            guard let client = makeAPIClient() else { throw VercelAPIError.unauthorized }
            _ = try await client.listTeams()
            isConnected = true
        case .cloudflare:
            guard let client = makeCloudflareClient() else { throw CloudflareAPIError.unauthorized }
            _ = try await client.listAccounts()
            isCloudflareConnected = true
        }
    }

    func disconnect(provider: DeploymentProvider) {
        switch provider {
        case .vercel: disconnect()
        case .cloudflare: disconnectCloudflare()
        }
    }

    func reloadProjects(for provider: DeploymentProvider) async {
        switch provider {
        case .vercel: await reloadProjects()
        case .cloudflare: await reloadCloudflareProjects()
        }
    }

    func isConnected(to provider: DeploymentProvider) -> Bool {
        switch provider {
        case .vercel: isConnected
        case .cloudflare: isCloudflareConnected
        }
    }

    /// True when onboarding is done but a provider that Toast needs is not reachable.
    private var hasDisconnectedProvider: Bool {
        guard hasCompletedOnboarding else { return false }
        let watchedProviders = Set(watchedProjects.map(\.provider))
        if watchedProviders.isEmpty {
            return !isConnected && !isCloudflareConnected
        }
        return watchedProviders.contains { !isConnected(to: $0) }
    }

    #if DEBUG
    private var isSampleMode = false

    /// Fills the store with made-up projects so the real views can be rendered for the website.
    func applySampleData(now: Date = Date()) {
        isSampleMode = true
        hasCompletedOnboarding = true
        isConnected = true
        isCloudflareConnected = true
        teams = [Team(id: "team", slug: "acme", name: "Acme")]
        cloudflareAccounts = [Team(id: "acct", slug: nil, name: "Acme Studio")]
        selectedTeamId = "team"
        selectedCloudflareAccountId = "acct"
        connectedTeamName = "Acme"
        connectedCloudflareAccountName = "Acme Studio"
        lastRefresh = now
        lastError = nil
        lastFailure = nil

        func deployment(_ name: String, state: DeploymentState, minutesAgo: Double, message: String,
                        sha: String, production: Bool = true) -> Deployment {
            let seconds = Double(18 + name.utf8.reduce(0) { ($0 &+ Int($1)) % 47 })
            let created = now.addingTimeInterval(-minutesAgo * 60)
            let ms = created.timeIntervalSince1970 * 1000
            return Deployment(
                uid: "dpl_\(name)", name: name, url: "\(name).example.com", state: state, readyState: nil,
                target: production ? "production" : "preview", createdAt: ms, buildingAt: ms,
                ready: state == .ready ? ms + seconds * 1000 : nil,
                meta: DeploymentMeta(githubCommitMessage: message, githubCommitRef: "main",
                                     githubCommitSha: sha, githubCommitAuthorName: nil),
                creator: nil
            )
        }

        let vercel: [(String, DeploymentState, Double, String, String)] = [
            ("marketing-site", .ready, 18, "Update pricing page", "a41f9c2d"),
            ("web-app", .building, 0.6, "Add dark mode to settings", "7be03d11"),
            ("docs", .ready, 180, "Fix broken link in quickstart", "c9d2e480"),
            ("api", .ready, 1500, "Bump rate limits", "2f6a77b3"),
            ("blog", .ready, 4300, "Publish launch post", "e18b5a09"),
        ]
        let cloudflare: [(String, String, DeploymentState, Double, String, String)] = [
            ("pages:storefront", "storefront", .ready, 42, "Refresh product photos", "5d0c8a71"),
            ("worker:edge-api", "edge-api", .ready, 95, "Add caching headers", "90be41f6"),
            ("worker:image-resizer", "image-resizer", .ready, 2900, "Support AVIF output", "13a9d7c4"),
        ]

        var statuses: [ProjectDeploymentStatus] = []
        var watched: [WatchedProject] = []
        for item in vercel {
            let w = WatchedProject(projectId: "prj_\(item.0)", projectName: item.0, teamId: "team", provider: .vercel)
            watched.append(w)
            statuses.append(ProjectDeploymentStatus(
                watched: w,
                deployment: deployment(item.0, state: item.1, minutesAgo: item.2, message: item.3, sha: item.4),
                fetchedAt: now, isStale: false))
        }
        for item in cloudflare {
            let w = WatchedProject(projectId: item.0, projectName: item.1, teamId: "acct", provider: .cloudflare)
            watched.append(w)
            statuses.append(ProjectDeploymentStatus(
                watched: w,
                deployment: deployment(item.1, state: item.2, minutesAgo: item.3, message: item.4, sha: item.5),
                fetchedAt: now, isStale: false))
        }
        watchedProjects = watched
        projectStatuses = statuses
        projects = vercel.map { Project(id: "prj_\($0.0)", name: $0.0, accountId: nil, updatedAt: nil, link: nil) }
        cloudflareProjects = cloudflare.map {
            Project(id: $0.0, name: $0.1, accountId: nil, updatedAt: nil, link: nil)
        }
    }
    #endif

    private var pollTask: Task<Void, Never>?
    /// Worker name → script tag, keyed "<accountId>/<name>"; needed for Workers Builds.
    private var cloudflareWorkerTags: [String: String] = [:]
    private var previousStatuses: [String: DeploymentState] = [:]
    private var lastSuccessfulDeployments: [String: Deployment] = [:]
    private var isLoadingPreferences = false

    private func makeAPIClient() -> VercelAPIClient? {
        guard let token = KeychainStore.loadToken() else { return nil }
        return VercelAPIClient(token: token)
    }

    private func makeCloudflareClient() -> CloudflareAPIClient? {
        guard let token = KeychainStore.loadToken(for: .cloudflare) else { return nil }
        return CloudflareAPIClient(token: token)
    }

    private enum Keys {
        static let onboardingComplete = "onboardingComplete"
        static let showStatusText = "showStatusText"
        static let notificationsEnabled = "notificationsEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let runInBackground = "runInBackground"
        static let relaunchOnCrash = "relaunchOnCrash"
        static let backgroundBehaviorConfigured = "backgroundBehaviorConfigured"
        static let selectedTeamId = "selectedTeamId"
        static let watchedProjects = "watchedProjects"
        static let selectedCloudflareAccountId = "selectedCloudflareAccountId"
    }

    init() {
        loadPreferences()
    }

    func bootstrap() {
        BackgroundBehavior.markAppRunning()
        applyDefaultBackgroundBehaviorIfNeeded()
        syncBackgroundBehavior()
        isConnected = KeychainStore.hasToken()
        isCloudflareConnected = KeychainStore.hasToken(for: .cloudflare)

        if hasCompletedOnboarding, isConnected || isCloudflareConnected {
            Task {
                await restoreSessionIfNeeded()
                startPolling()
            }
        } else if KeychainStore.hasToken(), !hasCompletedOnboarding {
            Task { await restoreSessionAfterTokenSaved() }
        }
    }

    /// Reloads teams and projects from the saved token (e.g. after app restart or opening Settings).
    func restoreSessionIfNeeded() async {
        await restoreVercelSessionIfNeeded()
        await restoreCloudflareSessionIfNeeded()
    }

    private func restoreVercelSessionIfNeeded() async {
        guard KeychainStore.hasToken() else { return }

        guard teams.isEmpty || projects.isEmpty else {
            updateConnectedTeamName()
            isConnected = true
            return
        }

        guard let client = makeAPIClient() else { return }

        do {
            teams = try await client.listTeams()
            if selectedTeamId == nil {
                selectedTeamId = teams.first?.id
                persistSelectedTeamId()
            }
            updateConnectedTeamName()
            if let teamId = selectedTeamId {
                projects = try await client.listProjects(teamId: teamId)
            }
            isConnected = true
            clearFailure()
        } catch {
            record(error)
            if case VercelAPIError.unauthorized = error {
                isConnected = false
            }
        }
    }

    private func restoreCloudflareSessionIfNeeded() async {
        guard KeychainStore.hasToken(for: .cloudflare) else { return }

        guard cloudflareAccounts.isEmpty || cloudflareProjects.isEmpty else {
            updateConnectedCloudflareAccountName()
            isCloudflareConnected = true
            return
        }

        guard let client = makeCloudflareClient() else { return }

        do {
            cloudflareAccounts = try await client.listAccounts()
            if selectedCloudflareAccountId == nil {
                selectedCloudflareAccountId = cloudflareAccounts.first?.id
            }
            updateConnectedCloudflareAccountName()
            if let accountId = selectedCloudflareAccountId {
                let listing = try await client.listProjectsWithNotice(accountId: accountId)
                cloudflareProjects = listing.projects
                cloudflareProjectNotice = listing.notice
            }
            isCloudflareConnected = true
            clearFailure()
        } catch {
            record(error)
            if case CloudflareAPIError.unauthorized = error {
                isCloudflareConnected = false
            }
        }
    }

    func connectCloudflare(token: String) async throws {
        let trimmed = CloudflareAPIClient.sanitizedToken(token)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let client = CloudflareAPIClient(token: trimmed)
        let validation = try await client.validateToken()
        try KeychainStore.saveToken(trimmed, for: .cloudflare)
        isCloudflareConnected = true
        cloudflareScopeWarning = validation.scopeWarning
        clearFailure()

        cloudflareAccounts = try await client.listAccounts()
        if selectedCloudflareAccountId == nil
            || !cloudflareAccounts.contains(where: { $0.id == selectedCloudflareAccountId })
        {
            selectedCloudflareAccountId = cloudflareAccounts.first?.id
        }
        updateConnectedCloudflareAccountName()
        if let accountId = selectedCloudflareAccountId {
            let listing = try await client.listProjectsWithNotice(accountId: accountId)
            cloudflareProjects = listing.projects
            cloudflareProjectNotice = listing.notice
        }
        AnalyticsService.shared.capture("token_connected", properties: ["provider": DeploymentProvider.cloudflare.rawValue])
    }

    func reloadCloudflareProjects() async {
        guard KeychainStore.hasToken(for: .cloudflare) else {
            cloudflareProjectNotice = "No Cloudflare token is saved. Add one above."
            return
        }
        guard let client = makeCloudflareClient() else {
            cloudflareProjectNotice = "Toast couldn't read the saved Cloudflare token from the Keychain. Choose “Replace token…” and paste it again."
            return
        }
        guard let accountId = selectedCloudflareAccountId else {
            cloudflareProjectNotice = "Select a Cloudflare account first."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let listing = try await client.listProjectsWithNotice(accountId: accountId)
            cloudflareProjects = listing.projects
            cloudflareProjectNotice = listing.notice
            clearFailure()
        } catch {
            cloudflareProjectNotice = error.localizedDescription
            record(error)
        }
    }

    func disconnectCloudflare() {
        KeychainStore.deleteToken(for: .cloudflare)
        isCloudflareConnected = false
        connectedCloudflareAccountName = nil
        cloudflareAccounts = []
        cloudflareProjects = []
        cloudflareScopeWarning = nil
        selectedCloudflareAccountId = nil
        removeWatchedProjects(for: .cloudflare)
    }

    /// Drops one provider's watched projects; resets to onboarding when nothing is left to watch.
    private func removeWatchedProjects(for provider: DeploymentProvider) {
        let removed = Set(watchedProjects.filter { $0.provider == provider }.map(\.id))
        watchedProjects.removeAll { $0.provider == provider }
        projectStatuses.removeAll { removed.contains($0.id) }
        for id in removed {
            previousStatuses[id] = nil
            lastSuccessfulDeployments[id] = nil
        }
        clearFailure()

        if watchedProjects.isEmpty {
            stopPolling()
            hasCompletedOnboarding = false
        }
        persistAllPreferences()
    }

    func connect(token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let client = VercelAPIClient(token: trimmed)
        let validation = try await client.validateToken()
        try KeychainStore.saveToken(trimmed)
        isConnected = true
        tokenScopeWarning = validation.scopeWarning
        clearFailure()

        teams = try await client.listTeams()
        if selectedTeamId == nil {
            selectedTeamId = teams.first?.id
            persistSelectedTeamId()
        }
        updateConnectedTeamName()
        if let teamId = selectedTeamId {
            projects = try await client.listProjects(teamId: teamId)
        }
        AnalyticsService.shared.capture("token_connected")
    }

    func disconnect() {
        KeychainStore.deleteToken()
        isConnected = false
        connectedTeamName = nil
        teams = []
        projects = []
        selectedTeamId = nil
        tokenScopeWarning = nil
        removeWatchedProjects(for: .vercel)
    }

    func completeOnboarding(
        watching selected: [WatchedProject],
        background preferences: BackgroundPreferences = .defaults
    ) async {
        guard !selected.isEmpty else { return }

        isFinishingOnboarding = true
        clearFailure()
        defer { isFinishingOnboarding = false }

        watchedProjects = selected
        hasCompletedOnboarding = true
        showSetupComplete = true
        configureBackgroundBehavior(preferences)
        persistAllPreferences()
        AnalyticsService.shared.markAnalyticsRolloutNoticeSeen()

        startPolling()
        await refreshNow()
        AnalyticsService.shared.capture("onboarding_completed", properties: [
            "projects_watched_bucket": Diagnostics.projectsWatchedBucket(count: selected.count),
        ])
    }

    func configureBackgroundBehavior(_ preferences: BackgroundPreferences) {
        isLoadingPreferences = true
        launchAtLoginEnabled = preferences.launchAtLogin
        runInBackgroundEnabled = preferences.runInBackground
        relaunchOnCrashEnabled = preferences.relaunchOnCrash
        isLoadingPreferences = false

        UserDefaults.standard.set(true, forKey: Keys.backgroundBehaviorConfigured)
        syncBackgroundBehavior()
    }

    func reloadProjects() async {
        guard KeychainStore.hasToken(), let teamId = selectedTeamId else { return }
        isLoading = true
        defer { isLoading = false }
        guard let client = makeAPIClient() else { return }
        do {
            projects = try await client.listProjects(teamId: teamId)
            clearFailure()
        } catch {
            record(error)
        }
    }

    /// Replaces the watched projects for one provider and leaves the others untouched.
    func updateWatchedProjects(_ selected: [WatchedProject], for provider: DeploymentProvider) {
        updateWatchedProjects(watchedProjects.filter { $0.provider != provider } + selected)
    }

    func updateWatchedProjects(_ selected: [WatchedProject]) {
        watchedProjects = selected
        persistWatchedProjects()
        startPolling()
        Task { await refreshNow() }
    }

    func refreshNow() async {
        await refresh(minIntervalSinceLastSuccess: 0)
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func restoreSessionAfterTokenSaved() async {
        guard KeychainStore.hasToken(), let token = KeychainStore.loadToken() else { return }
        do {
            try await connect(token: token)
        } catch {
            record(error)
            isConnected = false
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh(minIntervalSinceLastSuccess: 0)
            let interval = pollIntervalSeconds
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private var pollIntervalSeconds: TimeInterval {
        projectStatuses.contains(where: { $0.status.isInProgress }) ? 5 : 60
    }

    private func refresh(minIntervalSinceLastSuccess: TimeInterval) async {
        #if DEBUG
        if isSampleMode { return }
        #endif
        guard !watchedProjects.isEmpty else {
            projectStatuses = []
            return
        }

        if minIntervalSinceLastSuccess > 0,
           let lastRefresh,
           Date().timeIntervalSince(lastRefresh) < minIntervalSinceLastSuccess
        {
            return
        }

        let vercelClient = makeAPIClient()
        let cloudflareClient = makeCloudflareClient()
        await loadMissingWorkerTags(using: cloudflareClient)

        isLoading = true
        defer { isLoading = false }

        var results: [ProjectDeploymentStatus] = []
        var fetchError: String?
        var pollError: Error?
        var failedProviders: Set<DeploymentProvider> = []

        for watched in watchedProjects {
            do {
                let deployment = try await fetchLatestDeployment(
                    for: watched,
                    vercel: vercelClient,
                    cloudflare: cloudflareClient
                )
                if let deployment {
                    lastSuccessfulDeployments[watched.id] = deployment
                }
                results.append(ProjectDeploymentStatus(
                    watched: watched,
                    deployment: deployment,
                    fetchedAt: Date(),
                    isStale: false
                ))
                await handleStatusTransition(watched: watched, deployment: deployment)
            } catch {
                fetchError = error.localizedDescription
                pollError = error
                failedProviders.insert(watched.provider)
                if isUnauthorized(error) {
                    setConnected(false, for: watched.provider)
                }
                results.append(ProjectDeploymentStatus(
                    watched: watched,
                    deployment: lastSuccessfulDeployments[watched.id],
                    fetchedAt: Date(),
                    isStale: true
                ))
            }
        }

        projectStatuses = results
        lastRefresh = Date()
        lastError = fetchError
        lastFailure = pollError.map(UserFacingError.from)
        if let pollError {
            AnalyticsService.shared.capturePollError(pollError)
        }
        for provider in Set(watchedProjects.map(\.provider)) where !failedProviders.contains(provider) {
            setConnected(true, for: provider)
        }
    }

    private func fetchLatestDeployment(
        for watched: WatchedProject,
        vercel: VercelAPIClient?,
        cloudflare: CloudflareAPIClient?
    ) async throws -> Deployment? {
        switch watched.provider {
        case .vercel:
            guard let vercel else { throw VercelAPIError.unauthorized }
            return try await vercel.listDeployments(
                projectId: watched.projectId,
                teamId: watched.teamId,
                limit: 1
            ).first
        case .cloudflare:
            guard let cloudflare else { throw CloudflareAPIError.unauthorized }
            let workerName = CloudflareProjectKind.name(fromProjectID: watched.projectId)
            return try await cloudflare.latestDeployment(
                accountId: watched.teamId,
                projectID: watched.projectId,
                workerTag: cloudflareWorkerTags["\(watched.teamId)/\(workerName)"]
            )
        }
    }

    private func loadMissingWorkerTags(using client: CloudflareAPIClient?) async {
        guard let client else { return }
        let accounts = Set(watchedProjects.compactMap { watched -> String? in
            guard watched.provider == .cloudflare,
                  CloudflareProjectKind(projectID: watched.projectId) == .worker,
                  cloudflareWorkerTags["\(watched.teamId)/\(CloudflareProjectKind.name(fromProjectID: watched.projectId))"] == nil
            else { return nil }
            return watched.teamId
        })
        for accountId in accounts {
            // Best effort: without tags Workers fall back to deployment info.
            guard let tags = try? await client.workerTags(accountId: accountId) else { continue }
            for (name, tag) in tags {
                cloudflareWorkerTags["\(accountId)/\(name)"] = tag
            }
        }
    }

    private func record(_ error: Error) {
        lastError = error.localizedDescription
        lastFailure = UserFacingError.from(error)
    }

    private func clearFailure() {
        lastError = nil
        lastFailure = nil
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        if case VercelAPIError.unauthorized = error { return true }
        if case CloudflareAPIError.unauthorized = error { return true }
        return false
    }

    private func setConnected(_ connected: Bool, for provider: DeploymentProvider) {
        switch provider {
        case .vercel: isConnected = connected
        case .cloudflare: isCloudflareConnected = connected
        }
    }

    private func handleStatusTransition(watched: WatchedProject, deployment: Deployment?) async {
        guard notificationsEnabled, let deployment else { return }

        let key = watched.id
        let newStatus = deployment.status
        let oldStatus = previousStatuses[key]
        previousStatuses[key] = newStatus

        guard let oldStatus, oldStatus.isInProgress, newStatus.isTerminal else { return }

        let title: String
        let body: String
        switch newStatus {
        case .ready:
            title = "\(watched.projectName) is live"
            body = deployment.commitMessage ?? "Your latest deployment finished successfully."
        case .error:
            title = "\(watched.projectName) failed to deploy"
            body = deployment.commitMessage.map { "\($0) Open Toast for details." } ?? "Open Toast to see what went wrong."
        default:
            return
        }

        await NotificationManager.shared.notify(title: title, body: body)
    }

    private func loadPreferences() {
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }

        let defaults = UserDefaults.standard
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingComplete)
        showStatusText = defaults.object(forKey: Keys.showStatusText) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        launchAtLoginEnabled = Self.loadBool(forKey: Keys.launchAtLogin, default: true)
        runInBackgroundEnabled = Self.loadBool(forKey: Keys.runInBackground, default: true)
        relaunchOnCrashEnabled = Self.loadBool(forKey: Keys.relaunchOnCrash, default: true)
        selectedTeamId = defaults.string(forKey: Keys.selectedTeamId)
        selectedCloudflareAccountId = defaults.string(forKey: Keys.selectedCloudflareAccountId)
        if let data = defaults.data(forKey: Keys.watchedProjects),
           let projects = try? JSONDecoder().decode([WatchedProject].self, from: data)
        {
            watchedProjects = projects
        }
    }

    private func persistAllPreferences() {
        persistOnboardingComplete()
        persistWatchedProjects()
        persistSelectedTeamId()
        persistSelectedCloudflareAccountId()
    }

    private func persistOnboardingComplete() {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboardingComplete)
    }

    private func persistWatchedProjects() {
        if let data = try? JSONEncoder().encode(watchedProjects) {
            UserDefaults.standard.set(data, forKey: Keys.watchedProjects)
        }
    }

    private func persistSelectedCloudflareAccountId() {
        if let selectedCloudflareAccountId {
            UserDefaults.standard.set(selectedCloudflareAccountId, forKey: Keys.selectedCloudflareAccountId)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedCloudflareAccountId)
        }
        updateConnectedCloudflareAccountName()
    }

    private func updateConnectedCloudflareAccountName() {
        connectedCloudflareAccountName = cloudflareAccounts
            .first(where: { $0.id == selectedCloudflareAccountId })?.displayName
    }

    private func persistSelectedTeamId() {
        if let selectedTeamId {
            UserDefaults.standard.set(selectedTeamId, forKey: Keys.selectedTeamId)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedTeamId)
        }
        updateConnectedTeamName()
    }

    private func updateConnectedTeamName() {
        connectedTeamName = teams.first(where: { $0.id == selectedTeamId })?.displayName
    }

    private func applyDefaultBackgroundBehaviorIfNeeded() {
        guard hasCompletedOnboarding else { return }
        guard !UserDefaults.standard.bool(forKey: Keys.backgroundBehaviorConfigured) else { return }

        configureBackgroundBehavior(
            BackgroundPreferences(
                launchAtLogin: Self.loadBool(forKey: Keys.launchAtLogin, default: true),
                runInBackground: Self.loadBool(forKey: Keys.runInBackground, default: true),
                relaunchOnCrash: Self.loadBool(forKey: Keys.relaunchOnCrash, default: true)
            )
        )
    }

    private func syncBackgroundBehavior() {
        BackgroundBehavior.syncFromStoredPreferences(
            launchAtLogin: launchAtLoginEnabled,
            runInBackground: runInBackgroundEnabled,
            relaunchOnCrash: relaunchOnCrashEnabled
        )
    }

    private func persistBackgroundPreferenceChange() {
        guard !isLoadingPreferences else { return }

        UserDefaults.standard.set(launchAtLoginEnabled, forKey: Keys.launchAtLogin)
        UserDefaults.standard.set(runInBackgroundEnabled, forKey: Keys.runInBackground)
        UserDefaults.standard.set(relaunchOnCrashEnabled, forKey: Keys.relaunchOnCrash)
        UserDefaults.standard.set(true, forKey: Keys.backgroundBehaviorConfigured)
        syncBackgroundBehavior()
    }

    private static func loadBool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func trackSettingChanged(_ setting: String, value: Bool, oldValue: Bool) {
        guard !isLoadingPreferences, value != oldValue else { return }
        AnalyticsService.shared.captureSettingChanged(setting, value: value)
    }
}

enum OnboardingError: LocalizedError {
    case noProjectsSelected

    var errorDescription: String? {
        switch self {
        case .noProjectsSelected:
            "Select at least one project to watch."
        }
    }
}

@MainActor
enum NotificationManager {
    static let shared = NotificationManagerImpl()
}

final class NotificationManagerImpl: @unchecked Sendable {
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    @MainActor
    func notify(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
