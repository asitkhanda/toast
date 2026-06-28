import AppKit
import Foundation
import ServiceManagement
import Shared

enum BackgroundBehavior {
    static let launcherBundleID = "com.toast.app.launcher"

    static var launchAtLoginRequiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static var relaunchHelperRequiresApproval: Bool {
        loginItemService.status == .requiresApproval
    }

    private static var loginItemService: SMAppService {
        SMAppService.loginItem(identifier: launcherBundleID)
    }

    static func markAppRunning() {
        RuntimeState.shared.markAppRunning()
    }

    static func markUserQuit() {
        RuntimeState.shared.markUserQuit()
    }

    static func applyRunInBackground(_ enabled: Bool) {
        NSApp.setActivationPolicy(enabled ? .accessory : .regular)
    }

    static func sync(
        launchAtLogin: Bool,
        runInBackground: Bool,
        relaunchOnCrash: Bool
    ) {
        RuntimeState.shared.relaunchOnCrashEnabled = relaunchOnCrash
        applyRunInBackground(runInBackground)
        syncLaunchAtLogin(launchAtLogin)
        syncRelaunchHelper(relaunchOnCrash)
    }

    static func syncFromStoredPreferences(
        launchAtLogin: Bool,
        runInBackground: Bool,
        relaunchOnCrash: Bool
    ) {
        let launchRegistered = SMAppService.mainApp.status == .enabled
        let helperRegistered = loginItemService.status == .enabled

        RuntimeState.shared.relaunchOnCrashEnabled = relaunchOnCrash
        applyRunInBackground(runInBackground)

        if launchAtLogin != launchRegistered {
            setLaunchAtLogin(launchAtLogin)
        }
        if relaunchOnCrash != helperRegistered {
            setRelaunchHelper(relaunchOnCrash)
        }
    }

    @discardableResult
    static func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func setRelaunchHelper(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    private static func syncLaunchAtLogin(_ enabled: Bool) {
        let registered = SMAppService.mainApp.status == .enabled
        guard enabled != registered else { return }
        setLaunchAtLogin(enabled)
    }

    private static func syncRelaunchHelper(_ enabled: Bool) {
        let registered = loginItemService.status == .enabled
        guard enabled != registered else { return }
        setRelaunchHelper(enabled)
    }
}
