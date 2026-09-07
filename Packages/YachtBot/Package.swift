// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YachtBot",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "YachtBot", targets: ["YachtBot"])],
    dependencies: [.package(path: "../YachtCore")],
    targets: [
        .target(name: "YachtBot", dependencies: ["YachtCore"]),
        .testTarget(name: "YachtBotTests", dependencies: ["YachtBot"]),
    ]
)
