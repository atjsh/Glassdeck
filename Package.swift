// swift-tools-version: 6.2
import PackageDescription

let cGhosttyVTPath = "Frameworks/CGhosttyVT.xcframework"

var glassdeckCoreDependencies: [Target.Dependency] = [
    .product(name: "NIOSSH", package: "swift-nio-ssh"),
    .product(name: "SSHClient", package: "swift-ssh-client"),
    .target(name: "CGhosttyVT", condition: .when(platforms: [.iOS])),
]

var targets: [Target] = [
    .target(
        name: "GlassdeckCore",
        dependencies: glassdeckCoreDependencies,
        path: "GlassdeckCore"
    ),
    .target(
        name: "Glassdeck",
        dependencies: [
            "GlassdeckCore",
        ],
        path: "Glassdeck",
        exclude: [
            "App/Info.plist"
        ],
        resources: [
            .process("Resources/Assets.xcassets")
        ]
    ),
    .binaryTarget(
        name: "CGhosttyVT",
        path: cGhosttyVTPath
    ),
    .testTarget(
        name: "GlassdeckCoreTests",
        dependencies: [
            "GlassdeckCore",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
        ],
        path: "Tests/GlassdeckCoreTests"
    ),
    .testTarget(
        name: "GlassdeckHostIntegrationTests",
        dependencies: [
            "GlassdeckCore",
            .product(name: "SSHClient", package: "swift-ssh-client"),
        ],
        path: "Tests/GlassdeckHostIntegrationTests"
    ),
]

let package = Package(
    name: "Glassdeck",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "GlassdeckCore",
            targets: ["GlassdeckCore"]
        ),
        .library(
            name: "Glassdeck",
            targets: ["Glassdeck"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        .package(path: "Vendor/swift-ssh-client"),
    ],
    targets: targets
)
