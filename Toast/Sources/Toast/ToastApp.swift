import AppKit
import SwiftUI
import Shared

@main
struct ToastApp: App {
    @NSApplicationDelegateAdaptor(ToastAppDelegate.self) private var appDelegate
    @State private var store = DeploymentStore()
    @State private var updater = SparkleUpdater()
    @State private var showCrashReportPrompt = false
    @State private var showAnalyticsRolloutNotice = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                showCrashReportPrompt: $showCrashReportPrompt,
                showAnalyticsRolloutNotice: $showAnalyticsRolloutNotice
            )
            .environment(store)
            .environment(updater)
            .id(store.hasCompletedOnboarding)
            .onAppear {
                store.bootstrap()
                if AnalyticsService.shared.handlePendingCrashReport(from: store) {
                    showCrashReportPrompt = true
                } else if store.hasCompletedOnboarding,
                          AnalyticsService.shared.shouldShowAnalyticsRolloutNotice
                {
                    showAnalyticsRolloutNotice = true
                }
            }
        } label: {
            MenuBarLabel()
                .environment(store)
                .environment(updater)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
                .task {
                    if updater.supportsManualUpdates {
                        updater.startIfNeeded()
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}

/// Prompts are shown inline rather than as `.sheet`s: on macOS 27 a sheet hosted by the
/// MenuBarExtra window crashes SwiftUI while resolving its environment, which killed the app
/// as soon as the popover opened.
private struct MenuBarContent: View {
    @Environment(DeploymentStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Binding var showCrashReportPrompt: Bool
    @Binding var showAnalyticsRolloutNotice: Bool

    var body: some View {
        if showCrashReportPrompt {
            CrashReportPrompt {
                showCrashReportPrompt = false
            }
        } else if showAnalyticsRolloutNotice {
            AnalyticsRolloutNotice(
                onOpenSettings: {
                    AppActivation.openSettings(openSettings)
                },
                onDismiss: {
                    AnalyticsService.shared.markAnalyticsRolloutNoticeSeen()
                    showAnalyticsRolloutNotice = false
                }
            )
        } else if store.hasCompletedOnboarding {
            MenuBarPopover()
        } else {
            OnboardingView()
        }
    }
}
