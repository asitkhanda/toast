import SwiftUI

@main
struct ToastApp: App {
    @State private var store = DeploymentStore()
    @State private var updater = SparkleUpdater()

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
