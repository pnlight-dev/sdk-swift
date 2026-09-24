import XCTest
@testable import PNLightSDK

final class DocumentImageCompatibilityTests: XCTestCase {
    func testDocumentImagesRequireSchemaSeven() {
        let policy = PNLightDocumentImagePolicy()

        for schemaVersion in 1...6 {
            policy.schemaVersion = schemaVersion
            XCTAssertFalse(
                policy.isEnabled,
                "schema v\(schemaVersion) must preserve DivKit's legacy image loading"
            )
        }

        policy.schemaVersion = 7
        XCTAssertTrue(policy.isEnabled)
    }
}
