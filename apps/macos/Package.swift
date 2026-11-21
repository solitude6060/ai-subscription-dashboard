// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AisubdashMac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AisubdashCore"),
        .testTarget(name: "AisubdashCoreTests", dependencies: ["AisubdashCore"]),
    ]
)
