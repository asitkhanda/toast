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
    ],
    targets: [
        .executableTarget(
            name: "Toast",
            dependencies: ["Sparkle"],
            path: "Sources/Toast"
        ),
    ]
)
