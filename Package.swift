// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MenuBarManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarManager",
            path: "Sources/MenuBarManager"
        )
    ]
)
