// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoleShell",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MoleShell", targets: ["MoleShell"])],
    targets: [
        .target(name: "MoleAdapter"),
        .executableTarget(name: "MoleShell", dependencies: ["MoleAdapter"]),
        .testTarget(name: "MoleAdapterTests", dependencies: ["MoleAdapter"])
    ]
)
