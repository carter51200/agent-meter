// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentMeter", targets: ["AgentMeter"])],
    targets: [
        .target(name: "MenuBarCore"),
        .executableTarget(name: "AgentMeter", dependencies: ["MenuBarCore"]),
        .executableTarget(name: "ParserChecks", dependencies: ["MenuBarCore"], path: "Tests/MenuBarCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
