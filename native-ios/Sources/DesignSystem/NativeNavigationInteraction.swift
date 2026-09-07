import SwiftUI
import UIKit

/// Leaves UIKit's interactive pop untouched for ordinary destinations. Local
/// practice states and unsaved forms must resolve their own exit first.
struct NativeNavigationInteraction: UIViewControllerRepresentable {
    var rootPage = false
    var blocked = false
    var localBack: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.configuration = self
        probe.installIfVisible()
    }

    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        var configuration = NativeNavigationInteraction()
        private weak var installedNavigation: UINavigationController?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var edge: UIScreenEdgePanGestureRecognizer?
        private var active = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            active = true
            installIfVisible()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            active = true
            installIfVisible()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            active = false
            uninstall()
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil { uninstall() }
        }

        func installIfVisible() {
            guard active, let nav = navigationController else { return }
            var owner: UIViewController = self
            while let parent = owner.parent, parent !== nav { owner = parent }
            guard nav.topViewController === owner else { return }
            if installedNavigation !== nav {
                uninstall()
                installedNavigation = nav
                previousDelegate = nav.interactivePopGestureRecognizer?.delegate
                nav.interactivePopGestureRecognizer?.delegate = self
                let recognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(localEdge(_:)))
                recognizer.edges = .left
                recognizer.delegate = self
                nav.view.addGestureRecognizer(recognizer)
                edge = recognizer
            }
            // Empty root chrome remains laid out, but cannot swallow taps on
            // content occupying that region. Restore before pushing a child.
            nav.navigationBar.isUserInteractionEnabled = !configuration.rootPage
            edge?.isEnabled = configuration.localBack != nil && !configuration.blocked
        }

        private func uninstall() {
            guard let nav = installedNavigation else { return }
            if nav.interactivePopGestureRecognizer?.delegate === self {
                nav.interactivePopGestureRecognizer?.delegate = previousDelegate
            }
            nav.navigationBar.isUserInteractionEnabled = true
            if let edge { nav.view.removeGestureRecognizer(edge) }
            edge = nil
            installedNavigation = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard active, !configuration.blocked, let nav = installedNavigation,
                  nav.transitionCoordinator == nil else { return false }
            if gestureRecognizer === edge { return configuration.localBack != nil }
            guard configuration.localBack == nil, nav.viewControllers.count > 1 else { return false }
            return previousDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
        }

        @objc private func localEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended, !configuration.blocked else { return }
            let distance = gesture.translation(in: gesture.view).x
            let velocity = gesture.velocity(in: gesture.view).x
            if distance > 60 || (distance > 15 && velocity > 350) {
                configuration.localBack?()
            }
        }
    }
}
