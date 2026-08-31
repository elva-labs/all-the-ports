// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AllThePorts",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/elva-labs/KeyboardShortcuts", exact: "2.4.0-elva.1")
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
