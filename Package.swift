// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeGPT",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LifeCore", targets: ["LifeCore"]),
        .executable(name: "lifelab", targets: ["lifelab"]),
        .executable(name: "LifeGPT", targets: ["LifeGPT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "LifeCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "lifelab",
            dependencies: ["LifeCore"]
        ),
        .executableTarget(name: "LifeGPT", dependencies: ["LifeCore"]),
        .testTarget(
            name: "LifeCoreTests",
            dependencies: ["LifeCore"]
        ),
        .testTarget(name: "LifeGPTTests", dependencies: ["LifeGPT", "LifeCore"]),
    ]
)
