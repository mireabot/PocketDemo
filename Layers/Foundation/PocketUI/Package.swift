// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PocketUI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "PocketUI",
            targets: ["PocketUI"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "PocketUI",
            dependencies: [
            ]
        ),
    ]
)
