import SwiftUI
import UIKit

/// Opt-in, DEBUG-only timings. No touch observer or metrics are installed in an IPA.
@MainActor
enum SpeedExitDiagnostics {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-speed-exit-diagnostics")
        #else
        false
        #endif
    }
    static var useSystemAlert: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-speed-exit-system-alert")
        #else
        false
        #endif
    }
    static var latestTouch: CFTimeInterval = 0
    private static var stamps: [String: CFTimeInterval] = [:]
    static func begin() {
        guard enabled else { return }
        stamps = ["back": CACurrentMediaTime(), "backTouch": latestTouch]
    }
    static func mark(_ name: String) {
        guard enabled, !stamps.isEmpty else { return }
        stamps[name] = CACurrentMediaTime()
        if name == "exit" { stamps["exitTouch"] = latestTouch }
    }
    static func finish() -> String {
        guard enabled, stamps["exit"] != nil else { return "" }
        stamps["frame"] = CACurrentMediaTime()
        func ms(_ start: String, _ end: String) -> String {
            guard let a = stamps[start], let b = stamps[end] else { return "n/a" }
            return String(format: "%.1f", (b - a) * 1000)
        }
        let result = "EXIT \(useSystemAlert ? "system" : "inline") backTouchToAction=\(ms("backTouch", "back"))ms touchToExit=\(ms("exitTouch", "exit"))ms exitToFrame=\(ms("exit", "frame"))ms audio=\(ms("audioStart", "audioEnd"))ms"
        print(result)
        stamps = [:]
        return result
    }
}

struct SpeedExitTouchProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchProbeView { TouchProbeView() }
    func updateUIView(_ uiView: TouchProbeView, context: Context) { }
    static func dismantleUIView(_ uiView: TouchProbeView, coordinator: ()) { uiView.detach() }

    final class TouchProbeView: UIView {
        private weak var observedWindow: UIWindow?
        private let observer = PassiveTouchObserver()
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard SpeedExitDiagnostics.enabled, let window else { return }
            observedWindow = window
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            window.addGestureRecognizer(observer)
        }
        func detach() { observedWindow?.removeGestureRecognizer(observer); observedWindow = nil }
    }
    private final class PassiveTouchObserver: UIGestureRecognizer {
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            SpeedExitDiagnostics.latestTouch = CACurrentMediaTime()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    }
}

/// Runs once on the first display tick after the home view joins the window.
struct SpeedExitFrameProbe: UIViewRepresentable {
    let onFrame: () -> Void
    func makeUIView(context: Context) -> FrameView { FrameView(onFrame: onFrame) }
    func updateUIView(_ uiView: FrameView, context: Context) { }
    static func dismantleUIView(_ uiView: FrameView, coordinator: ()) { uiView.stop() }
    final class FrameView: UIView {
        private var link: CADisplayLink?
        private let onFrame: () -> Void
        init(onFrame: @escaping () -> Void) { self.onFrame = onFrame; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            guard window != nil, SpeedExitDiagnostics.enabled else { return }
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        @objc private func tick() { stop(); onFrame() }
        func stop() { link?.invalidate(); link = nil }
    }
}
