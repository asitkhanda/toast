// swift-tools-version: 5.9
import Foundation
import PackageDescription

let appStoreBuild = ProcessInfo.processInfo.environment["APPSTORE"] == "1"

let packageDependencies: [Package.Dependency] = {
    var dependencies: [Package.Dependency] = [
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.59.0"),
    ]
    if !appStoreBuild {
        dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"))
    }
    return dependencies
}()

let toastDependencies: [Target.Dependency] = {
    var dependencies: [Target.Dependency] = [
        "Shared",
        .product(name: "PostHog", package: "posthog-ios"),
    ]
    if !appStoreBuild {
        dependencies.append("Sparkle")
    }
    return dependencies
}()

let toastSwiftSettings: [SwiftSetting] = appStoreBuild
    ? [.define("APPSTORE")]
    : []

let package = Package(
    name: "Toast",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Toast", targets: ["Toast"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "Toast",
            dependencies: toastDependencies,
            path: "Sources/Toast",
            swiftSettings: toastSwiftSettings
        ),
        .executableTarget(
            name: "ToastLauncher",
            dependencies: ["Shared"],
            path: "Sources/ToastLauncher"
        ),
    ]
)
