// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JurinKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "JurinKit", targets: ["JurinKit"])
    ],
    targets: [
        .target(
            name: "JurinKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "JurinKitTests",
            dependencies: ["JurinKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
