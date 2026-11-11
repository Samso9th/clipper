// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipper",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ClipperKit", targets: ["ClipperKit"]),
        .executable(name: "Clipper", targets: ["Clipper"])
    ],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.1.0"),
        .package(url: "https://github.com/jaywcjlove/ffmpeg-kit.git", revision: "0243a6a262944e2e6cd1dd9603122108594d182a")
    ],
    targets: [
        .target(name: "ClipperKit", dependencies: [
            .product(name: "ffmpegkit", package: "ffmpeg-kit"),
            .product(name: "Clips", package: "desert-ant-core"),
            .product(name: "Transcript", package: "desert-ant-core"),
            .product(name: "Voz", package: "desert-ant-core")
        ]),
        .executableTarget(name: "Clipper", dependencies: ["ClipperKit"]),
        .testTarget(name: "ClipperKitTests", dependencies: ["ClipperKit"])
    ]
)
