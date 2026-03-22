// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "docsorter",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "docsorter",
            path: "Sources/docsorter"
        )
    ]
)
