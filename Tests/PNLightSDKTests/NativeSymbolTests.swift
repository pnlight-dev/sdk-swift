import UIKit
import XCTest
@testable import PNLightSDK

final class NativeSymbolTests: XCTestCase {
    /// A 1x1 PNG.
    private let fallbackDataURL = "data:image/png;base64,"
        + "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    func testKnownSymbolIsTintedTemplateByDefault() throws {
        let content = try XCTUnwrap(NativeSymbolBlockFactory.content(
            from: ["name": "lock.shield.fill", "color": "#FF007AFF"],
            frameHeight: 22
        ))

        XCTAssertTrue(content.isSymbol)
        XCTAssertEqual(content.image.renderingMode, .alwaysTemplate)
        XCTAssertEqual(content.tintColor, CustomPropReader.color("#FF007AFF"))
    }

    func testPointSizeDefaultsToFrameHeight() throws {
        let fromFrame = try XCTUnwrap(NativeSymbolBlockFactory.content(
            from: ["name": "circle.fill"],
            frameHeight: 40
        ))
        let explicit = try XCTUnwrap(NativeSymbolBlockFactory.content(
            from: ["name": "circle.fill", "point_size": 40],
            frameHeight: nil
        ))
        let unsized = try XCTUnwrap(NativeSymbolBlockFactory.content(
            from: ["name": "circle.fill"],
            frameHeight: nil
        ))

        XCTAssertEqual(fromFrame.image.size, explicit.image.size)
        XCTAssertLessThan(unsized.image.size.height, fromFrame.image.size.height)
        XCTAssertEqual(unsized.tintColor, .label)
    }

    func testColoredRenderingModesDrawOriginalImages() throws {
        for rendering in ["hierarchical", "palette"] {
            let content = try XCTUnwrap(NativeSymbolBlockFactory.content(
                from: [
                    "name": "lock.shield.fill",
                    "rendering": rendering,
                    "secondary_color": "#FF8E8E93",
                ],
                frameHeight: 22
            ))
            XCTAssertEqual(content.image.renderingMode, .alwaysOriginal, rendering)
            XCTAssertNil(content.tintColor, rendering)
        }
    }

    func testUnknownSymbolUsesDataURLFallback() throws {
        let content = try XCTUnwrap(NativeSymbolBlockFactory.content(
            from: ["name": "not.a.real.symbol", "fallback": fallbackDataURL],
            frameHeight: 22
        ))

        XCTAssertFalse(content.isSymbol)
        XCTAssertNil(content.tintColor)
        XCTAssertEqual(content.image.size, CGSize(width: 1, height: 1))
    }

    func testUnknownSymbolWithoutUsableFallbackYieldsNothing() {
        XCTAssertNil(NativeSymbolBlockFactory.content(
            from: ["name": "not.a.real.symbol"],
            frameHeight: 22
        ))
        XCTAssertNil(NativeSymbolBlockFactory.content(
            from: ["name": "not.a.real.symbol", "fallback": "https://example.com/missing.png"],
            frameHeight: 22
        ))
        XCTAssertNil(NativeSymbolBlockFactory.content(from: [:], frameHeight: 22))
    }

    func testFallbackSizeDoesNotDependOnWhetherThePictureIsHeld() throws {
        let held = try XCTUnwrap(NativeSymbolBlockFactory.content(
            from: ["name": "not.a.real.symbol", "fallback": fallbackDataURL],
            frameHeight: nil
        ))
        let props: [String: Any] = ["name": "not.a.real.symbol", "point_size": 24]

        XCTAssertEqual(
            NativeSymbolBlockFactory.intrinsicSize(of: held, props: props, frameHeight: nil),
            NativeSymbolBlockFactory.intrinsicSize(of: nil, props: props, frameHeight: nil)
        )
        XCTAssertEqual(
            NativeSymbolBlockFactory.intrinsicSize(of: nil, props: [:], frameHeight: nil),
            CGSize(width: 17, height: 17)
        )
    }

    func testFallbackNotHeldYetLoadsOverTheNetwork() {
        XCTAssertEqual(
            NativeSymbolBlockFactory.remoteFallbackURL("https://example.com/missing.png"),
            URL(string: "https://example.com/missing.png")
        )
        XCTAssertNil(NativeSymbolBlockFactory.remoteFallbackURL(fallbackDataURL))
        XCTAssertNil(NativeSymbolBlockFactory.remoteFallbackURL("file:///tmp/icon.png"))
        XCTAssertNil(NativeSymbolBlockFactory.remoteFallbackURL(nil))
    }
}
