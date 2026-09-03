import XCTest
import UIKit

@MainActor
final class SpeedTextAnimationTests: XCTestCase {
    private func mount(_ view: SpeedTextSurface) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        window.makeKeyAndVisible()
        return window
    }

    private func update(_ view: SpeedTextSurface, _ text: String, _ revision: Int, reduceMotion: Bool = false) {
        view.update(text: text, fontSize: 42, nightMode: false,
                    motion: .answer(revision), kerning: 0, reduceMotion: reduceMotion)
    }

    func testFirstDigitActuallyScalesAndCompletesIn150ms() async throws {
        let view = SpeedTextSurface()
        view.frame = CGRect(x: 60, y: 60, width: 40, height: 56)
        let window = mount(view)
        defer { window.isHidden = true }
        update(view, "", 0)
        CATransaction.flush()
        // Let the test-only window present its initial frame before simulating a tap.
        try await Task.sleep(for: .milliseconds(150))
        update(view, "2", 1)
        let layer = view.subviews[0].layer
        let group = try XCTUnwrap(layer.animation(forKey: "web-text-motion") as? CAAnimationGroup)
        XCTAssertEqual(group.duration, 0.15)
        XCTAssertEqual(group.animations?.map(\.duration), [0.15, 0.15])
        XCTAssertTrue(group.isRemovedOnCompletion)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(35))
        let presentation = try XCTUnwrap(layer.presentation())
        XCTAssertGreaterThan(presentation.transform.m11, 0.79)
        XCTAssertLessThan(presentation.transform.m11, 0.999)
        XCTAssertLessThan(presentation.opacity, 1)
        try await Task.sleep(for: .milliseconds(180))
        // Test visible completion, not render-server animation-object cleanup timing.
        CATransaction.flush()
        XCTAssertEqual(layer.presentation()?.transform.m11 ?? layer.transform.m11, 1, accuracy: 0.01)
        XCTAssertEqual(layer.presentation()?.opacity ?? layer.opacity, 1, accuracy: 0.01)
        XCTAssertEqual(layer.transform.m11, 1)
        XCTAssertEqual(layer.opacity, 1)
    }

    func testPendingFirstDigitWaitsForBoundsAndEachQuestionCanAnimate() throws {
        let view = SpeedTextSurface()
        let window = mount(view)
        defer { window.isHidden = true }
        update(view, "5", 1)
        let layer = view.subviews[0].layer
        XCTAssertNil(layer.animation(forKey: "web-text-motion"))
        view.frame = CGRect(x: 60, y: 60, width: 40, height: 56)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertNotNil(layer.animation(forKey: "web-text-motion"))
        update(view, "", 1) // Confirm clears text without replaying the previous input.
        XCTAssertNil(layer.animation(forKey: "web-text-motion"))
        update(view, "2", 2)
        XCTAssertNotNil(layer.animation(forKey: "web-text-motion"))
        update(view, "22", 3)
        XCTAssertEqual(layer.animationKeys(), ["web-text-motion"])
        update(view, "22", 3) // Unrelated rendering must not cancel the active pulse.
        XCTAssertEqual(layer.animationKeys(), ["web-text-motion"])
        update(view, "222", 4, reduceMotion: true)
        XCTAssertNil(layer.animation(forKey: "web-text-motion"))
    }
}
