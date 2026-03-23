// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassdeckBuild",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(
            name: "glassdeck-build",
            targets: ["glassdeck-build"]
        ),
        .library(
            name: "GlassdeckBuildCore",
            targets: ["GlassdeckBuildCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.0.5"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.96.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "glassdeck-build",
            dependencies: [
                "GlassdeckBuildCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/glassdeck-build"
        ),
        .target(
            name: "GlassdeckBuildCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Sources/GlassdeckBuildCore"
        ),
        .testTarget(
            name: "GlassdeckBuildCoreTests",
            dependencies: [
                "GlassdeckBuildCore",
            ],
            path: "Tests/GlassdeckBuildCoreTests"
        ),
    ]
)
