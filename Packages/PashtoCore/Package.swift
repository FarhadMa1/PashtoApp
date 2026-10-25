// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PashtoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PashtoCore", targets: ["PashtoCore"]),
    ],
    targets: [
        .target(name: "PashtoCore"),
        .testTarget(
            name: "PashtoCoreTests",
            dependencies: ["PashtoCore"]
        ),
    ]
)
