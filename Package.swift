// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuraRim",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AuraRim", targets: ["AuraRim"])
    ],
    targets: [
        .executableTarget(
            name: "AuraRim",
            path: "Sources/AuraRim",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AuraRimTests",
            dependencies: ["AuraRim"],
            path: "Tests/AuraRimTests"
        )
    ]
)
