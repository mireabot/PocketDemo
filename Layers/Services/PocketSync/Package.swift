// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PocketSync",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "PocketSync",
            targets: ["PocketSync"]
        ),
    ],
    dependencies: [
        .package(path: "../../Foundation/Domain"),
        .package(path: "../../Foundation/PocketNetworking"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", .upToNextMajor(from: "1.9.4")),
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.6.1")),
    ],
    targets: [
        .target(
            name: "PocketSync",
            dependencies: [
                "Domain",
                "PocketNetworking",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
