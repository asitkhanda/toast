// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Toast",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Toast", targets: ["Toast"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.59.0"),
    ],
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "Toast",
            dependencies: [
                "Sparkle",
                "Shared",
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            path: "Sources/Toast"
        ),
        .executableTarget(
            name: "ToastLauncher",
            dependencies: ["Shared"],
            path: "Sources/ToastLauncher"
        ),
    ]
)
