// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OXOMetal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OXOMetal",
            path: "Sources/OXOMetal",
            linkerSettings: [.linkedFramework("AVFoundation")]
        )
    ]
)
