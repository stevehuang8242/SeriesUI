// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeriesUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SeriesUI", targets: ["SeriesUI"]),
    ],
    targets: [
        .target(name: "SeriesUI", path: "Sources/SeriesUI"),
        .testTarget(
            name: "SeriesUITests",
            dependencies: ["SeriesUI"],
            path: "Tests/SeriesUITests"
        ),
    ]
)
