import SwiftUI
import UIKit

/// Ordinary pushed pages deliberately use UIKit's own interactive-pop gesture.
/// This bridge only intervenes for an in-place subpage or a blocking overlay.
struct NativeNavigationInteraction: UIViewControllerRepresentable {
    var rootPage = false
    var blocked = false
    var localBack: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.blocked = blocked
        probe.localBack = localBack
        probe.synchronize()
    }

    final class Probe: UIViewController {
        var blocked = false
        var localBack: (() -> Void)?
        private weak var installedNavigation: UINavigationController?
        private var edgeGesture: UIScreenEdgePanGestureRecognizer?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            synchronize()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreSystemGesture()
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil { restoreSystemGesture() }
        }

        func synchronize() {
            guard isViewLoaded, view.window != nil, let nav = navigationController else { return }
            installedNavigation = nav
            let needsLocalHandling = blocked || localBack != nil
            if nav.interactivePopGestureRecognizer?.isEnabled == needsLocalHandling {
                nav.interactivePopGestureRecognizer?.isEnabled = !needsLocalHandling
            }
            if localBack != nil, edgeGesture == nil {
                let recognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(localEdge(_:)))
                recognizer.edges = .left
                nav.view.addGestureRecognizer(recognizer)
                edgeGesture = recognizer
            } else if localBack == nil, let edgeGesture {
                nav.view.removeGestureRecognizer(edgeGesture)
                self.edgeGesture = nil
            }
            edgeGesture?.isEnabled = !blocked
        }

        private func restoreSystemGesture() {
            guard let nav = installedNavigation else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            if let edgeGesture { nav.view.removeGestureRecognizer(edgeGesture) }
            edgeGesture = nil
            installedNavigation = nil
        }

        @objc private func localEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended, !blocked else { return }
            let distance = gesture.translation(in: gesture.view).x
            let velocity = gesture.velocity(in: gesture.view).x
            if distance > 60 || (distance > 15 && velocity > 350) {
                localBack?()
            }
        }
    }
}
