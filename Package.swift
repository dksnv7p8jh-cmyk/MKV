// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MKVHomeVideo",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MKVHomeVideoCore", targets: ["MKVHomeVideoCore"]),
        .executable(name: "MKVHomeVideoApp", targets: ["MKVHomeVideoApp"]),
    ],
    targets: [
        .target(name: "MKVHomeVideoCore"),
        .executableTarget(name: "MKVHomeVideoApp", dependencies: ["MKVHomeVideoCore"]),
        .testTarget(name: "MKVHomeVideoCoreTests", dependencies: ["MKVHomeVideoCore"]),
    ]
)
