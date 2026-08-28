// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiceTrajectory",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "DiceTrajectory", targets: ["DiceTrajectory"])],
    targets: [
        .target(name: "DiceTrajectory"),
        .testTarget(name: "DiceTrajectoryTests", dependencies: ["DiceTrajectory"]),
    ]
)
