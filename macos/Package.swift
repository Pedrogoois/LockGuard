// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LockGuard",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "LockGuard",
            path: "Sources/LockGuard"
        )
    ]
)
