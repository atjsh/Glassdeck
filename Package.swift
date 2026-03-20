// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Glassdeck",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "Glassdeck",
            targets: ["Glassdeck"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        .package(url: "https://github.com/gaetanzanella/swift-ssh-client.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "Glassdeck",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "SSHClient", package: "swift-ssh-client"),
            ],
            path: "Glassdeck"
        )
    ]
)
