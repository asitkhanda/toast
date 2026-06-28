import Foundation
import Sparkle

@MainActor
@Observable
final class SparkleUpdater {
    private var controller: SPUStandardUpdaterController?

    func startIfNeeded() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    func checkForUpdates() {
        startIfNeeded()
        controller?.checkForUpdates(nil)
    }
}
