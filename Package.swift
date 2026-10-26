// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ACControl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ACControl", targets: ["ACControl"])],
    targets: [
        .target(name: "ACControlCore"),
        .executableTarget(name: "ACControl", dependencies: ["ACControlCore"]),
        .testTarget(name: "ACControlCoreTests", dependencies: ["ACControlCore"])
    ]
)
