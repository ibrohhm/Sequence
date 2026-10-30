// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlantUMLStudio",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PlantUMLStudio", targets: ["PlantUMLStudio"])],
    targets: [
        .target(name: "StudioCore"),
        .executableTarget(name: "PlantUMLStudio", dependencies: ["StudioCore"], path: "App", exclude: ["Resources"]),
        .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
    ]
)
