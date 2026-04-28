// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Autotyper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Autotyper",
            path: "Sources/Autotyper",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
