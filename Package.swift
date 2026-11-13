// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoTriageMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "PhotoTriageCore", targets: ["PhotoTriageCore"]),
        .library(name: "PhotoTriageUI", targets: ["PhotoTriageUI"]),
        .executable(name: "PhotoTriageMac", targets: ["PhotoTriageMac"]),
    ],
    targets: [
        .target(
            name: "PhotoTriageCore"
        ),
        .target(
            name: "PhotoTriageUI",
            dependencies: ["PhotoTriageCore"]
        ),
        .executableTarget(
            name: "PhotoTriageMac",
            dependencies: ["PhotoTriageCore", "PhotoTriageUI"]
        ),
        .testTarget(
            name: "PhotoTriageCoreTests",
            dependencies: ["PhotoTriageCore"]
        ),
        .testTarget(
            name: "PhotoTriageUITests",
            dependencies: ["PhotoTriageUI"]
        ),
    ]
)
