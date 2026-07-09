import Foundation

struct DiagnosticSnapshot: Sendable {
    let appVersion: String
    let build: String
    let osVersion: String
    let arch: String
    let onboardingCompleted: Bool
    let projectsWatchedBucket: String
    let launchAtLogin: Bool
    let runInBackground: Bool
    let relaunchOnCrash: Bool
    let notificationsEnabled: Bool
    let showStatusText: Bool
    let analyticsEnabled: Bool
    let launcherRelaunch: Bool

    var properties: [String: Any] {
        [
            "app_version": appVersion,
            "build": build,
            "os_version": osVersion,
            "arch": arch,
            "onboarding_completed": onboardingCompleted,
            "projects_watched_bucket": projectsWatchedBucket,
            "launch_at_login": launchAtLogin,
            "run_in_background": runInBackground,
            "relaunch_on_crash": relaunchOnCrash,
            "notifications_enabled": notificationsEnabled,
            "show_status_text": showStatusText,
            "analytics_enabled": analyticsEnabled,
            "launcher_relaunch": launcherRelaunch,
        ]
    }
}

enum Diagnostics {
    static func projectsWatchedBucket(count: Int) -> String {
        switch count {
        case 0: "0"
        case 1: "1"
        case 2...5: "2-5"
        default: "6+"
        }
    }

    @MainActor
    static func snapshot(
        from store: DeploymentStore,
        launcherRelaunch: Bool = false
    ) -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: currentArchitecture,
            onboardingCompleted: store.hasCompletedOnboarding,
            projectsWatchedBucket: projectsWatchedBucket(count: store.watchedProjects.count),
            launchAtLogin: store.launchAtLoginEnabled,
            runInBackground: store.runInBackgroundEnabled,
            relaunchOnCrash: store.relaunchOnCrashEnabled,
            notificationsEnabled: store.notificationsEnabled,
            showStatusText: store.showStatusText,
            analyticsEnabled: AnalyticsService.shared.isEnabled,
            launcherRelaunch: launcherRelaunch
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
