// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PNLightSDK",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "PNLightSDK", targets: ["PNLightSDK"]),
    ],
    targets: [
        // Replace url and checksum during publish
        .binaryTarget(
            name: "PNLight",
            path: "PNLight.xcframework"
        ),
        .target(
            name: "PNLightSDK",
            dependencies: ["PNLight"]
        ),
    ]
)
