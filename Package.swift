// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PNLightSDK",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "PNLightSDK", targets: ["PNLightSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/divkit/divkit-ios", from: "32.32.0"),
    ],
    targets: [
        // Replace url and checksum during publish
        .binaryTarget(
            name: "PNLight",
            path: "PNLight.xcframework"
        ),
        .target(
            name: "PNLightSDK",
            dependencies: [
                "PNLight",
                .product(name: "DivKit", package: "divkit-ios"),
            ]
        ),
    ]
)
