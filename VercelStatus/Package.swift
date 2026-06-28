// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VercelStatus",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "VercelStatus", targets: ["VercelStatus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "VercelStatus",
            dependencies: ["Sparkle"],
            path: "Sources/VercelStatus"
        ),
    ]
)
