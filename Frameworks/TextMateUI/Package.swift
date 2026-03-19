// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextMateUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TextMateUI", targets: ["TextMateUI"]),
        .library(name: "TextMateBridge", targets: ["TextMateBridge"]),
    ],
    targets: [
        .target(
            name: "TextMateBridge",
            path: "Sources/TextMateBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TextMateUI",
            dependencies: ["TextMateBridge"],
            path: "Sources/TextMateUI"
        ),
    ]
)
