// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AllThePorts",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .target(name: "PortsCore", path: "Sources/PortsCore"),
        .executableTarget(
            name: "AllThePorts",
            dependencies: [
                "PortsCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/AllThePorts"
        ),
        .testTarget(name: "PortsCoreTests", dependencies: ["PortsCore"], path: "Tests/PortsCoreTests"),
    ]
)
