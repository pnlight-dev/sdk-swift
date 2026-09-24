import UIKit
import XCTest
@testable import PNLightSDK

@MainActor
final class HomeGestureDeferralTests: XCTestCase {
    func testPreferenceTracksVisibleRemoteUIView() {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        let remoteUI = PNLightRemoteUiRendererView(frame: host.view.bounds)
        host.view.addSubview(remoteUI)

        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), [])

        remoteUI.deferHomeGesture = true
        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), .bottom)

        remoteUI.isHidden = true
        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), [])

        remoteUI.isHidden = false
        remoteUI.removeFromSuperview()
        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), [])

        host.view.addSubview(remoteUI)
        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), .bottom)

        remoteUI.deferHomeGesture = false
        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), [])
    }
}
