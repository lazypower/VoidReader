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
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "VoidReaderCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlightr", package: "Highlightr"),
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
