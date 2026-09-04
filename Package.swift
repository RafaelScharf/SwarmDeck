// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwarmDeck",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwarmDeck",
            dependencies: [
                .product(name: "GhosttyKit", package: "libghostty-spm"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
                .product(name: "ShellCraftKit", package: "libghostty-spm"),
            ],
            path: "Sources/SwarmDeck"
        ),
        .executableTarget(
            name: "SwarmDeckPrototype",
            dependencies: [
                .product(name: "GhosttyKit", package: "libghostty-spm"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
                .product(name: "ShellCraftKit", package: "libghostty-spm"),
            ],
            path: "Sources/SwarmDeckPrototype"
        ),
    ]
)
