import AppKit
import SwiftUI

enum AppActivation {
    static func openSettings(_ openSettings: OpenSettingsAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    static func restoreMenuBarOnlyPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }
}
