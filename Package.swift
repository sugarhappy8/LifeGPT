// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LifeGPT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LifeGPT", targets: ["LifeGPT"]),
        .library(name: "LifeGPTCore", targets: ["LifeGPTCore"]),
    ],
    targets: [
        // Platform-neutral game engine: state, prompt assembly, history compaction, providers.
        .target(name: "LifeGPTCore"),
        // The macOS SwiftUI app. Packaged into LifeGPT.app / LifeGPT.dmg by Packaging/build_dmg.sh.
        .executableTarget(name: "LifeGPT", dependencies: ["LifeGPTCore"]),
        .testTarget(name: "LifeGPTCoreTests", dependencies: ["LifeGPTCore"]),
    ]
)
