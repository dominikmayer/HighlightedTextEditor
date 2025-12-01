// swift-tools-version:6.2

import PackageDescription

public let package = Package(
    name: "HighlightedTextEditor",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "HighlightedTextEditor",
            targets: ["HighlightedTextEditor"]
        )
    ],
    targets: [
        .target(
            name: "HighlightedTextEditor",
            dependencies: []
        )
    ]
)
