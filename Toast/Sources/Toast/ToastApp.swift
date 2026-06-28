import AppKit
import SwiftUI

@main
struct ToastApp: App {
    @NSApplicationDelegateAdaptor(ToastAppDelegate.self) private var appDelegate
    @State private var store = DeploymentStore()
    @State private var updater = SparkleUpdater()

    init() {
        NSApp.setActivationPolicy(.accessory)
    }

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
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
        }
        .windowResizability(.contentSize)
    }
}
