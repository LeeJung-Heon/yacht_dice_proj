// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YachtCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "YachtCore", targets: ["YachtCore"])],
    targets: [
        .target(name: "YachtCore"),
        .testTarget(name: "YachtCoreTests", dependencies: ["YachtCore"]),
    ]
)
