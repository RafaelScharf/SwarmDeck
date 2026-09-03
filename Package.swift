// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwarmDeckPrototype",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwarmDeckPrototype",
            dependencies: [
                .product(name: "GhosttyKit", package: "libghostty-spm"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "ShellCraftKit", package: "libghostty-spm"),
            ]
        ),
    ]
)
