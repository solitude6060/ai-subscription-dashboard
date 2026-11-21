// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AisubdashMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AisubdashMac", targets: ["AisubdashMac"]),
    ],
    targets: [
        .target(name: "AisubdashCore"),
        .executableTarget(name: "AisubdashMac", dependencies: ["AisubdashCore"]),
        .testTarget(name: "AisubdashCoreTests", dependencies: ["AisubdashCore", "AisubdashMac"]),
    ]
)
