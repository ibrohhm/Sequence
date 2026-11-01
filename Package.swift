// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SequenceApp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SequenceApp", targets: ["SequenceApp"])],
    targets: [
        .target(name: "StudioCore"),
        .executableTarget(name: "SequenceApp", dependencies: ["StudioCore"], path: "App", exclude: ["Resources"]),
        .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
    ]
)
