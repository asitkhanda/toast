import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
@Observable
final class SparkleUpdater {
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif

    var supportsManualUpdates: Bool {
        AppDistribution.supportsSparkleUpdates
    }

    func startIfNeeded() {
        #if canImport(Sparkle)
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        startIfNeeded()
        controller?.checkForUpdates(nil)
        #endif
    }
}
