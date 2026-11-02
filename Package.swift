// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserZero",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BrowserZero", targets: ["BrowserZero"]),
    ],
    targets: [
        .target(
            name: "BrowserZeroCore"
        ),
        .executableTarget(
            name: "BrowserZero",
            dependencies: ["BrowserZeroCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BrowserZeroCoreTests",
            dependencies: ["BrowserZeroCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
