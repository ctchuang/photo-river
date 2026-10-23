// swift-tools-version:5.10
// Photo River for macOS. Build with `make app` from the repository root; see README.md.
import PackageDescription

let package = Package(
    name: "PhotoRiver",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PhotoRiver", path: "Sources/PhotoRiver"),
        // Swift Testing ships with the Command Line Tools; run with `make test`.
        .testTarget(name: "PhotoRiverTests", dependencies: ["PhotoRiver"], path: "Tests/PhotoRiverTests"),
    ]
)
