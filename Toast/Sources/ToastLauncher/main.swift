import AppKit
import Shared

private let mainBundleID = "com.toast.app"
private let pollInterval: TimeInterval = 15

private func mainAppIsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).isEmpty
}

private func launchMainApp() {
    let mainURL: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainBundleID)
        ?? Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

    guard let mainURL else { return }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: mainURL, configuration: configuration) { _, _ in }
}

private func checkAndRelaunchIfNeeded() {
    let state = RuntimeState.shared
    guard state.relaunchOnCrashEnabled, !state.userInitiatedQuit, !mainAppIsRunning() else { return }
    state.pendingCrashReport = true
    launchMainApp()
}

final class LauncherDelegate: NSObject, NSApplicationDelegate {
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAndRelaunchIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            checkAndRelaunchIfNeeded()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LauncherDelegate()
app.delegate = delegate
app.run()
