// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "docsorter",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "docsorter",
            // path: "Sources/docsorter"
        )
    ]
)
