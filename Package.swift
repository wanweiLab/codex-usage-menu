// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexUsageMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageMenu", targets: ["CodexUsageMenu"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageMenu",
            path: "Sources/CodexUsageMenu"
        ),
        .testTarget(
            name: "CodexUsageMenuTests",
            dependencies: ["CodexUsageMenu"],
            path: "Tests/CodexUsageMenuTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
