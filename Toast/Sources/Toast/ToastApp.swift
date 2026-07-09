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
            Group {
                if store.hasCompletedOnboarding {
                    MenuBarPopover()
                } else {
                    OnboardingView()
                }
            }
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
            .sheet(isPresented: $showCrashReportPrompt) {
                CrashReportPrompt {
                    showCrashReportPrompt = false
                }
            }
            .sheet(isPresented: $showAnalyticsRolloutNotice) {
                AnalyticsRolloutNotice {
                    AnalyticsService.shared.markAnalyticsRolloutNoticeSeen()
                    showAnalyticsRolloutNotice = false
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
                .task { updater.startIfNeeded() }
        }
        .windowResizability(.contentSize)
    }
}
