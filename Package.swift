// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoidReaderCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoidReaderCore",
            targets: ["VoidReaderCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "VoidReaderCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/VoidReaderCore"
        ),
        .testTarget(
            name: "VoidReaderCoreTests",
            dependencies: ["VoidReaderCore"],
            path: "Tests/VoidReaderCoreTests"
        ),
    ]
)
