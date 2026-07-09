import Foundation
import PostHog
import Shared

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private static let host = "https://us.i.posthog.com"
    private static let enabledKey = "analyticsEnabled"
    private static let hasReportedFirstLaunchKey = "hasReportedFirstLaunch"
    private static let lastAppOpenedDayKey = "lastAppOpenedDay"
    private static let lastPollErrorTimestampKey = "lastPollErrorTimestamp"
    private static let lastTrackedVersionKey = "lastTrackedAppVersion"
    private static let hasSeenAnalyticsRolloutNoticeKey = "hasSeenAnalyticsRolloutNotice"

    private var isStarted = false

    var hasProjectToken: Bool { projectToken != nil }

    var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                startIfNeeded()
            } else {
                stop()
            }
        }
    }

    private var projectToken: String? {
        guard let key = Bundle.main.infoDictionary?["PostHogAPIKey"] as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private init() {}

    func startIfNeeded() {
        guard isEnabled, let token = projectToken else { return }

        if isStarted {
            PostHogSDK.shared.optIn()
            return
        }

        let config = PostHogConfig(projectToken: token, host: Self.host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.errorTrackingConfig.autoCapture = true

        PostHogSDK.shared.setup(config)
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        PostHogSDK.shared.optOut()
        isStarted = false
    }

    func trackAppLaunch() {
        startIfNeeded()
        guard isStarted else { return }

        trackVersionChangeIfNeeded()

        if !UserDefaults.standard.bool(forKey: Self.hasReportedFirstLaunchKey) {
            capture("first_launch")
            UserDefaults.standard.set(true, forKey: Self.hasReportedFirstLaunchKey)
        }

        let today = dayIdentifier(for: Date())
        if UserDefaults.standard.string(forKey: Self.lastAppOpenedDayKey) != today {
            capture("app_opened")
            UserDefaults.standard.set(today, forKey: Self.lastAppOpenedDayKey)
        }
    }

    @discardableResult
    func handlePendingCrashReport(from store: DeploymentStore) -> Bool {
        guard RuntimeState.shared.pendingCrashReport else { return false }

        RuntimeState.shared.pendingCrashReport = false
        capture("launcher_relaunch", properties: Diagnostics.snapshot(from: store, launcherRelaunch: true).properties)

        guard isEnabled, !RuntimeState.shared.crashPromptSuppressed else { return false }
        return true
    }

    func capture(_ event: String, properties: [String: Any]? = nil) {
        guard isStarted else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    func captureSettingChanged(_ setting: String, value: Bool) {
        capture("setting_changed", properties: [
            "setting": setting,
            "value": value,
        ])
    }

    func capturePollError(_ error: Error) {
        guard isStarted else { return }

        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Self.lastPollErrorTimestampKey) as? Date,
           now.timeIntervalSince(last) < 3600
        {
            return
        }
        UserDefaults.standard.set(now, forKey: Self.lastPollErrorTimestampKey)

        var properties: [String: Any] = ["error_type": analyticsErrorType(for: error)]
        if let vercelError = error as? VercelAPIError, let statusCode = vercelError.httpStatusCode {
            properties["status_code"] = statusCode
        }
        capture("poll_error", properties: properties)
    }

    func captureTokenFailed(_ error: Error) {
        capture("token_failed", properties: ["error_type": analyticsErrorType(for: error)])
    }

    func captureFeedback(message: String?, from store: DeploymentStore) {
        var properties = Diagnostics.snapshot(from: store).properties
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            properties["message"] = trimmed
        }
        properties["has_message"] = !trimmed.isEmpty
        capture("feedback_submitted", properties: properties)
    }

    func captureCrashReportAccepted(from store: DeploymentStore) {
        capture("crash_report_accepted", properties: Diagnostics.snapshot(from: store, launcherRelaunch: true).properties)
    }

    func markAnalyticsRolloutNoticeSeen() {
        UserDefaults.standard.set(true, forKey: Self.hasSeenAnalyticsRolloutNoticeKey)
    }

    var shouldShowAnalyticsRolloutNotice: Bool {
        !UserDefaults.standard.bool(forKey: Self.hasSeenAnalyticsRolloutNoticeKey)
    }

    private func trackVersionChangeIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let previousVersion = UserDefaults.standard.string(forKey: Self.lastTrackedVersionKey)

        if let previousVersion, previousVersion != currentVersion {
            capture("update_installed", properties: [
                "from_version": previousVersion,
                "to_version": currentVersion,
            ])
        }

        UserDefaults.standard.set(currentVersion, forKey: Self.lastTrackedVersionKey)
    }

    private func dayIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func analyticsErrorType(for error: Error) -> String {
        if let vercelError = error as? VercelAPIError {
            switch vercelError {
            case .unauthorized: return "unauthorized"
            case .forbidden: return "forbidden"
            case .notFound: return "not_found"
            case .rateLimited: return "rate_limited"
            case .serverError: return "server_error"
            case .decodingFailed: return "decoding_failed"
            case .network: return "network"
            case .invalidURL: return "invalid_url"
            }
        }
        return String(describing: type(of: error))
    }
}

private extension VercelAPIError {
    var httpStatusCode: Int? {
        switch self {
        case .unauthorized: 401
        case .forbidden: 403
        case .notFound: 404
        case .rateLimited: 429
        case .serverError(let code): code
        case .decodingFailed, .network, .invalidURL: nil
        }
    }
}
