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
        .library(name: "PashtoCoreTesting", targets: ["PashtoCoreTesting"]),
    ],
    targets: [
        .target(name: "PashtoCore"),
        .target(name: "PashtoCoreTesting", dependencies: ["PashtoCore"]),
        .testTarget(
            name: "PashtoCoreTests",
            dependencies: ["PashtoCore", "PashtoCoreTesting"],
            exclude: ["Fixtures"]
        ),
    ]
)
