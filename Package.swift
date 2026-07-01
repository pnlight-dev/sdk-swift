// swift-tools-version:5.7
import PackageDescription
import Foundation

// Released binary artifact. Both lines are rewritten by scripts/publish_spm.sh
// at release time; the .xcframework itself is not committed — it is attached as
// a zip asset to the matching GitHub Release and fetched here by checksum.
let releaseVersion = "0.8.0"
let releaseChecksum = "33cd984e2f7139dbc857252977acf91937f739df0ced60cf33e70175a794e06b"

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
    ],
    targets: [
        binaryTarget,
        .target(
            name: "PNLightSDK",
            dependencies: [
                "PNLight",
                .product(name: "DivKit", package: "divkit-ios"),
            ]
        ),
    ]
)
