import AppKit

final class ToastAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BackgroundBehavior.markAppRunning()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        BackgroundBehavior.markUserQuit()
        return .terminateNow
    }
}
