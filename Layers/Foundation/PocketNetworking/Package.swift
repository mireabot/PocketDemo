// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PocketNetworking",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "PocketNetworking",
            targets: ["PocketNetworking"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "PocketNetworking",
            dependencies: [
            ]
        ),
    ]
)
