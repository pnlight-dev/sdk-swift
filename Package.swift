// swift-tools-version:5.7
import PackageDescription
import Foundation

// Released binary artifact. Both lines are rewritten by scripts/publish_spm.sh
// at release time; the .xcframework itself is not committed — it is attached as
// a zip asset to the matching GitHub Release and fetched here by checksum.
let releaseVersion = "0.9.1"
let releaseChecksum = "dd063a15a93eb4ebf51919314d638d830923f06a8af39225c74995d2fa2463a6"

// Local development: when the xcframework is present next to this manifest,
// resolve against the on-disk copy instead of the published release.
// scripts/build_xcframework.sh stages it here (a symlink into Artifacts/), so the
// in-repo Examples/ app builds without a published release — no env var needed.
// Set PNLIGHT_LOCAL=1 to force local mode even when the file is absent.
let localXCFramework = "PNLight.xcframework"
let manifestDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let useLocalXCFramework =
    FileManager.default.fileExists(atPath: manifestDir.appendingPathComponent(localXCFramework).path)
    || ProcessInfo.processInfo.environment["PNLIGHT_LOCAL"] == "1"

let binaryTarget: Target = useLocalXCFramework
    ? .binaryTarget(
        name: "PNLight",
        path: localXCFramework
      )
    : .binaryTarget(
        name: "PNLight",
        url: "https://github.com/pnlight-dev/sdk-swift/releases/download/\(releaseVersion)/PNLight.xcframework.zip",
        checksum: releaseChecksum
      )

let package = Package(
    name: "PNLightSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PNLightSDK", targets: ["PNLightSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/divkit/divkit-ios", from: "32.32.0"),
        // Airbnb's lightweight SPM mirror avoids cloning the large lottie-ios
        // development repository into every host application's package graph.
        // 4.5.2 is built with Swift 5.9 and keeps PNLightSDK compatible with
        // the package's Xcode 15 / Swift 5.9 baseline.
        .package(url: "https://github.com/airbnb/lottie-spm", exact: "4.5.2"),
    ],
    targets: [
        binaryTarget,
        .target(
            name: "PNLightSDK",
            dependencies: [
                "PNLight",
                // The renderer imports LayoutKit for DivCustomBlockFactory. divkit-ios does not
                // expose LayoutKit as a standalone SwiftPM product, so it is supplied through
                // the public DivKit product's target dependencies and cannot be listed directly.
                .product(name: "DivKit", package: "divkit-ios"),
                .product(name: "DivKitExtensions", package: "divkit-ios"),
                .product(name: "Lottie", package: "lottie-spm"),
            ]
        ),
    ]
)
