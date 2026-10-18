// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PocketRecordings",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "PocketRecordings",
            targets: ["PocketRecordings"]
        ),
    ],
    dependencies: [
        .package(path: "../../Foundation/Domain"),
        .package(path: "../../Services/PocketSync"),
        .package(path: "../../Foundation/PocketUI"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", .upToNextMajor(from: "1.9.4")),
    ],
    targets: [
        .target(
            name: "PocketRecordings",
            dependencies: [
                "Domain",
                "PocketSync",
                "PocketUI",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
