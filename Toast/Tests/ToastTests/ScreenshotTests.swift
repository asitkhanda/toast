import AppKit
import SwiftUI
import XCTest
@testable import Toast

/// Renders the real app views with sample data into PNGs for the website.
/// Run: TOAST_SCREENSHOT_DIR=/path swift test --filter ScreenshotTests
@MainActor
final class ScreenshotTests: XCTestCase {
    private func render<V: View>(_ view: V, name: String, dark: Bool, directory: URL) throws {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let background = Color(nsColor: .windowBackgroundColor)
        let host = NSHostingView(rootView: view.background(background))
        host.appearance = appearance

        let size = host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        // Off-screen but active, so prominent buttons and controls draw as they do in the real window.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = host
        window.orderFrontRegardless()
        window.makeKey()
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return XCTFail("no bitmap") }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)

        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    func testRenderMarketingScreenshots() throws {
        guard let path = ProcessInfo.processInfo.environment["TOAST_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TOAST_SCREENSHOT_DIR to render screenshots.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for dark in [false, true] {
            KeychainStore.debugPretendTokenSaved = true
            let store = DeploymentStore()
            store.applySampleData()
            let updater = SparkleUpdater()

            try render(MenuBarPopover().environment(store).environment(updater),
                       name: "popover", dark: dark, directory: directory)
            try render(MenuBarPopover(initialProvider: .cloudflare).environment(store).environment(updater),
                       name: "popover-cloudflare", dark: dark, directory: directory)
            try render(AccountsTab().environment(store).environment(updater).frame(width: 600, height: 470),
                       name: "accounts", dark: dark, directory: directory)

            KeychainStore.debugPretendTokenSaved = false
            let fresh = DeploymentStore()
            try render(OnboardingView(initialStep: 3, initialProvider: .cloudflare).environment(fresh),
                       name: "onboarding", dark: dark, directory: directory)
            try render(OnboardingView(initialStep: 2).environment(fresh),
                       name: "onboarding-service", dark: dark, directory: directory)
        }
    }
}
