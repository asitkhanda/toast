import Foundation
import Observation
import UserNotifications

struct ProjectDeploymentStatus: Identifiable, Sendable {
    let watched: WatchedProject
    let deployment: Deployment?
    let fetchedAt: Date

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
        didSet { UserDefaults.standard.set(showStatusText, forKey: Keys.showStatusText) }
    }
    var notificationsEnabled = true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    var selectedTeamId: String? = nil {
        didSet {
            persistSelectedTeamId()
        }
    }
    var watchedProjects: [WatchedProject] = []

    private(set) var teams: [Team] = []
    private(set) var projects: [Project] = []
    private(set) var projectStatuses: [ProjectDeploymentStatus] = []
    private(set) var isLoading = false
    private(set) var isFinishingOnboarding = false
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    private(set) var isConnected = false
    private(set) var connectedTeamName: String?

    var aggregateStatus: AggregateStatus {
        if !isConnected && hasCompletedOnboarding {
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

    private var pollTask: Task<Void, Never>?
    private var previousStatuses: [String: DeploymentState] = [:]
    private var token: String?

    private enum Keys {
        static let onboardingComplete = "onboardingComplete"
        static let showStatusText = "showStatusText"
        static let notificationsEnabled = "notificationsEnabled"
        static let selectedTeamId = "selectedTeamId"
        static let watchedProjects = "watchedProjects"
    }

    init() {
        loadPreferences()
    }

    func bootstrap() {
        token = KeychainStore.loadToken()
        isConnected = token != nil

        if hasCompletedOnboarding, token != nil {
            Task {
                await restoreSessionIfNeeded()
                startPolling()
            }
        } else if token != nil, !hasCompletedOnboarding {
            Task { await restoreSessionAfterTokenSaved() }
        }
    }

    /// Reloads teams and projects from the saved token (e.g. after app restart or opening Settings).
    func restoreSessionIfNeeded() async {
        guard let savedToken = KeychainStore.loadToken() else { return }
        token = savedToken

        guard teams.isEmpty || projects.isEmpty else {
            updateConnectedTeamName()
            isConnected = true
            return
        }

        do {
            let client = VercelAPIClient(token: savedToken)
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
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if case VercelAPIError.unauthorized = error {
                isConnected = false
            }
        }
    }

    func connect(token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let client = VercelAPIClient(token: trimmed)
        try await client.validateToken()
        try KeychainStore.saveToken(trimmed)
        self.token = trimmed
        isConnected = true
        lastError = nil

        teams = try await client.listTeams()
        if selectedTeamId == nil {
            selectedTeamId = teams.first?.id
            persistSelectedTeamId()
        }
        updateConnectedTeamName()
        if let teamId = selectedTeamId {
            projects = try await client.listProjects(teamId: teamId)
        }
    }

    func disconnect() {
        stopPolling()
        KeychainStore.deleteToken()
        token = nil
        isConnected = false
        connectedTeamName = nil
        hasCompletedOnboarding = false
        teams = []
        projects = []
        projectStatuses = []
        watchedProjects = []
        selectedTeamId = nil
        lastError = nil
        persistAllPreferences()
    }

    func completeOnboarding(watching selected: [WatchedProject]) async {
        guard !selected.isEmpty else { return }

        isFinishingOnboarding = true
        lastError = nil
        defer { isFinishingOnboarding = false }

        watchedProjects = selected
        hasCompletedOnboarding = true
        persistAllPreferences()

        startPolling()
        await refreshNow()
    }

    func reloadProjects() async {
        guard let token, let teamId = selectedTeamId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = VercelAPIClient(token: token)
            projects = try await client.listProjects(teamId: teamId)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
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
        guard let token = KeychainStore.loadToken() else { return }
        do {
            try await connect(token: token)
        } catch {
            lastError = error.localizedDescription
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
        guard let token else { return }
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

        isLoading = true
        defer { isLoading = false }

        let client = VercelAPIClient(token: token)
        var results: [ProjectDeploymentStatus] = []
        var fetchError: String?

        for watched in watchedProjects {
            do {
                let deployments = try await client.listDeployments(
                    projectId: watched.projectId,
                    teamId: watched.teamId,
                    limit: 1
                )
                let deployment = deployments.first
                results.append(ProjectDeploymentStatus(
                    watched: watched,
                    deployment: deployment,
                    fetchedAt: Date()
                ))
                await handleStatusTransition(watched: watched, deployment: deployment)
            } catch {
                fetchError = error.localizedDescription
                if case VercelAPIError.unauthorized = error {
                    isConnected = false
                }
                results.append(ProjectDeploymentStatus(
                    watched: watched,
                    deployment: nil,
                    fetchedAt: Date()
                ))
            }
        }

        projectStatuses = results
        lastRefresh = Date()
        lastError = fetchError
        if fetchError == nil {
            isConnected = true
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
            title = "\(watched.projectName) deployed"
            body = deployment.commitMessage ?? "Deployment is ready."
        case .error:
            title = "\(watched.projectName) failed"
            body = deployment.commitMessage ?? "Deployment failed."
        default:
            return
        }

        await NotificationManager.shared.notify(title: title, body: body)
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingComplete)
        showStatusText = defaults.object(forKey: Keys.showStatusText) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        selectedTeamId = defaults.string(forKey: Keys.selectedTeamId)
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
    }

    private func persistOnboardingComplete() {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboardingComplete)
    }

    private func persistWatchedProjects() {
        if let data = try? JSONEncoder().encode(watchedProjects) {
            UserDefaults.standard.set(data, forKey: Keys.watchedProjects)
        }
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
