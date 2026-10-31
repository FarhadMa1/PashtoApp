// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PashtoContentTool",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PashtoContentTool", targets: ["PashtoContentTool"]),
        .executable(name: "pashto-content", targets: ["pashto-content"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PashtoCore"),
    ],
    targets: [
        .target(
            name: "PashtoContentTool",
            dependencies: ["PashtoCore"]
        ),
        .executableTarget(
            name: "pashto-content",
            dependencies: ["PashtoContentTool"]
        ),
        .testTarget(
            name: "PashtoContentToolTests",
            dependencies: ["PashtoContentTool"]
        ),
    ]
)
