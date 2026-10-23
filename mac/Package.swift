// swift-tools-version:5.10
// Photo River for macOS. Build with `make app` from the repository root; see README.md.
import PackageDescription

let package = Package(
    name: "PhotoRiver",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PhotoRiver", path: "Sources/PhotoRiver"),
    ]
)
