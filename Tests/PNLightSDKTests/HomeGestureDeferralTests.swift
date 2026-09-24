import SwiftUI
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

    func testRendererReportsEffectiveDeferral() {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        let remoteUI = PNLightRemoteUiRendererView(frame: host.view.bounds)
        var reports: [Bool] = []
        remoteUI.onHomeGestureDeferralChange = { reports.append($0) }

        remoteUI.deferHomeGesture = true
        XCTAssertEqual(reports.last, false, "a detached view does not defer")

        host.view.addSubview(remoteUI)
        XCTAssertEqual(reports.last, true)

        remoteUI.isHidden = true
        XCTAssertEqual(reports.last, false)

        remoteUI.isHidden = false
        XCTAssertEqual(reports.last, true)

        remoteUI.removeFromSuperview()
        XCTAssertEqual(reports.last, false)
    }

    func testReportFollowsAncestorVisibility() {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        let container = UIView(frame: host.view.bounds)
        host.view.addSubview(container)
        let remoteUI = PNLightRemoteUiRendererView(frame: container.bounds)
        container.addSubview(remoteUI)
        var reports: [Bool] = []
        remoteUI.onHomeGestureDeferralChange = { reports.append($0) }
        remoteUI.deferHomeGesture = true
        XCTAssertEqual(reports.last, true)

        container.isHidden = true
        XCTAssertFalse(remoteUI.isDeferringHomeGesture)
        XCTAssertEqual(PNLightHomeGestureDeferral.preferredEdges(for: host), [])
        waitForVisibilityPoll()
        XCTAssertEqual(reports.last, false, "hiding an ancestor is picked up without a layout pass")

        container.isHidden = false
        waitForVisibilityPoll()
        XCTAssertEqual(reports.last, true)

        container.alpha = 0
        waitForVisibilityPoll()
        XCTAssertEqual(reports.last, false)
        container.alpha = 1
        waitForVisibilityPoll()
        XCTAssertEqual(reports.last, true)

        remoteUI.deferHomeGesture = false
        container.isHidden = true
        container.isHidden = false
        let reportCount = reports.count
        waitForVisibilityPoll()
        XCTAssertEqual(reports.count, reportCount, "polling stops once the flag is cleared")
        remoteUI.deferHomeGesture = true

        remoteUI.alpha = 0
        XCTAssertEqual(reports.last, false, "the view's own alpha reports immediately")
        remoteUI.alpha = 1
        XCTAssertEqual(reports.last, true)
    }

    func testReportStopsWhenTabIsDeselected() {
        let first = UIViewController()
        let second = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [first, second]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.isHidden = false
        defer { window.isHidden = true }
        tabs.view.layoutIfNeeded()

        let remoteUI = PNLightRemoteUiRendererView(frame: first.view.bounds)
        first.view.addSubview(remoteUI)
        var reports: [Bool] = []
        remoteUI.onHomeGestureDeferralChange = { reports.append($0) }
        remoteUI.deferHomeGesture = true
        XCTAssertEqual(reports.last, true)

        tabs.selectedIndex = 1
        tabs.view.layoutIfNeeded()
        XCTAssertFalse(remoteUI.isDeferringHomeGesture)
        XCTAssertEqual(reports.last, false)

        tabs.selectedIndex = 0
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(reports.last, true)
    }

    func testSwiftUIStateCombinesRemoteUIViews() {
        let state = PNLightHomeGestureDeferralState()
        let first = NSObject()
        let second = NSObject()

        state.setDeferring(true, for: ObjectIdentifier(first))
        state.setDeferring(true, for: ObjectIdentifier(second))
        drainMainQueue()
        XCTAssertTrue(state.isDeferring)

        state.setDeferring(false, for: ObjectIdentifier(first))
        drainMainQueue()
        XCTAssertTrue(state.isDeferring, "another view still defers")

        state.setDeferring(false, for: ObjectIdentifier(second))
        drainMainQueue()
        XCTAssertFalse(state.isDeferring)
    }

    func testSwiftUICoordinatorForwardsRendererDeferral() {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        let remoteUI = PNLightRemoteUiView(frame: host.view.bounds)
        host.view.addSubview(remoteUI)
        let coordinator = RemoteUiView.Coordinator()
        let state = PNLightHomeGestureDeferralState()
        coordinator.observeHomeGestureDeferral(of: remoteUI, state: state)

        remoteUI.deferHomeGesture = true
        drainMainQueue()
        XCTAssertTrue(state.isDeferring)

        remoteUI.deferHomeGesture = false
        drainMainQueue()
        XCTAssertFalse(state.isDeferring)

        remoteUI.deferHomeGesture = true
        drainMainQueue()
        XCTAssertTrue(state.isDeferring)

        RemoteUiView.dismantleUIView(remoteUI, coordinator: coordinator)
        drainMainQueue()
        XCTAssertFalse(state.isDeferring, "a dismantled view stops deferring")
    }

    @available(iOS 16, *)
    func testModifierDefersHostingControllerBottomEdge() {
        let deferring = DeferralSwitch()
        let host = UIHostingController(
            rootView: DeferralReporter(deferring: deferring).pnlightHomeGestureDeferral()
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        drainMainQueue()
        XCTAssertEqual(host.preferredScreenEdgesDeferringSystemGestures, [])

        deferring.isOn = true
        drainMainQueue()
        XCTAssertEqual(host.preferredScreenEdgesDeferringSystemGestures, .bottom)

        deferring.isOn = false
        drainMainQueue()
        XCTAssertEqual(host.preferredScreenEdgesDeferringSystemGestures, [])
    }

    private func waitForVisibilityPoll() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
    }

    private func drainMainQueue() {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

private final class DeferralSwitch: ObservableObject {
    @Published var isOn = false
}

/// Stands in for `RemoteUiView`, reporting to the modifier's environment state.
private struct DeferralReporter: View {
    @ObservedObject var deferring: DeferralSwitch
    @Environment(\.pnlightHomeGestureDeferral) private var state

    var body: some View {
        Color.clear.onChange(of: deferring.isOn) { isOn in
            state?.setDeferring(isOn, for: ObjectIdentifier(deferring))
        }
    }
}

