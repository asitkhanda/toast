import AppKit

final class ToastAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BackgroundBehavior.markAppRunning()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        BackgroundBehavior.markUserQuit()
        return .terminateNow
    }
}
