// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "uppod",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "uppod",
            path: "Sources/uppod",
            resources: [.process("Assets")],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "uppodTests",
            dependencies: ["uppod"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
