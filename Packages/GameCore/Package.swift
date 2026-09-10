// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "GameCore", targets: ["GameCore"])],
    targets: [
        .target(name: "GameCore"),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ]
)
