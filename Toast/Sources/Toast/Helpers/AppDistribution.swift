import Foundation

enum AppDistribution {
    static var isMacAppStore: Bool {
        #if APPSTORE
        return true
        #else
        return false
        #endif
    }

    static var supportsSparkleUpdates: Bool {
        !isMacAppStore
    }

    static var updatesLabel: String {
        isMacAppStore ? "Updates via Mac App Store" : "Check for Updates…"
    }
}
