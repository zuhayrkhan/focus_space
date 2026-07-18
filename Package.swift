// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FocusSpace",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FocusSpace", targets: ["FocusSpace"])
    ],
    targets: [
        .executableTarget(
            name: "FocusSpace",
            path: "Sources/FocusSpace"
        ),
        .testTarget(
            name: "FocusSpaceTests",
            dependencies: ["FocusSpace"],
            path: "Tests/FocusSpaceTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
