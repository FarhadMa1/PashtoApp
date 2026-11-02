// swift-tools-version: 6.0

import PackageDescription

// Apple-only. SwiftData is not on Linux, so the Linux CI job must not build
// this package. The macOS workflow runs `swift test` here.
let package = Package(
    name: "PashtoPersistence",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PashtoPersistence", targets: ["PashtoPersistence"]),
    ],
    dependencies: [
        .package(path: "../PashtoCore"),
    ],
    targets: [
        .target(
            name: "PashtoPersistence",
            dependencies: [
                .product(name: "PashtoCore", package: "PashtoCore"),
            ]
        ),
        .testTarget(
            name: "PashtoPersistenceTests",
            dependencies: [
                "PashtoPersistence",
                .product(name: "PashtoCore", package: "PashtoCore"),
                .product(name: "PashtoCoreTesting", package: "PashtoCore"),
            ]
        ),
    ]
)
