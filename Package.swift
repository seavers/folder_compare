// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FolderCompare",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FolderCompare",
            targets: ["FolderCompare"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FolderCompare",
            path: "Sources/FolderCompare"
        )
    ]
)
