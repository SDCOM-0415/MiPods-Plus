// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiPodsPlus",
    platforms: [.macOS("12.0")],
    products: [
        .executable(name: "MiPodsPlus", targets: ["MiPodsPlusApp"]),
        .library(name: "MiPodsPlusCore", targets: ["MiPodsPlusCore"])
    ],
    targets: [
        .target(name: "MiPodsPlusCore", path: "MiPodsPlusCore"),
        .executableTarget(
            name: "MiPodsPlusApp",
            dependencies: ["MiPodsPlusCore"],
            path: "MiPodsPlusApp"
        ),
        .testTarget(
            name: "MiPodsPlusCoreTests",
            dependencies: ["MiPodsPlusCore"],
            path: "Tests"
        )
    ]
)
