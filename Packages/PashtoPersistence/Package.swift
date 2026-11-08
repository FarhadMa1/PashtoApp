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
                "PashtoSQLite",
                .product(name: "PashtoCore", package: "PashtoCore"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "PashtoSQLite",
            path: "Sources/PashtoSQLite",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreData"),
            ]
        ),
        .testTarget(
            name: "PashtoPersistenceTests",
            dependencies: [
                "PashtoPersistence",
                "PashtoSQLite",
                .product(name: "PashtoCore", package: "PashtoCore"),
                .product(name: "PashtoCoreTesting", package: "PashtoCore"),
            ],
            resources: [
                .copy("Fixtures/SchemaV1.store"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
