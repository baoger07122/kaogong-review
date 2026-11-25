import SwiftUI
import UIKit

struct ShenlunReaderZoomRequest {
    let id = UUID()
    let fraction: CGFloat
}

struct ShenlunMaterialZoomReader<Paper: View>: UIViewControllerRepresentable {
    let paper: Paper
    let paperSize: CGSize
    let pageID: String
    let isDrawing: Bool
    let initialFraction: CGFloat
    let request: ShenlunReaderZoomRequest?
    let onInteraction: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(paper: paper)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(with: self)
    }

    final class Controller: UIViewController, UIScrollViewDelegate {
        private let scroll = UIScrollView()
        private let host: UIHostingController<Paper>
        private var paperSize: CGSize = .zero
        private var displayedPaperSize: CGSize = .zero
        private var pageID: String?
        private var displayedPageID: String?
        private var availableWidth: CGFloat = 0
        private var fitScale: CGFloat = 1
        private var initialFraction: CGFloat = 1
        private var request: ShenlunReaderZoomRequest?
        private var appliedRequestID: UUID?
        private var isAdjusting = false
        private var lastInteraction: TimeInterval = 0
        private var onInteraction: ((CGFloat) -> Void)?

        init(paper: Paper) {
            host = UIHostingController(rootView: paper)
            super.init(nibName: nil, bundle: nil)
            host.safeAreaRegions = []
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func loadView() {
            view = scroll
            scroll.delegate = self
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.alwaysBounceVertical = true
            scroll.scrollsToTop = false
            scroll.delaysContentTouches = false
            scroll.panGestureRecognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
            ]
            scroll.accessibilityIdentifier = "shenlun-material-reader"
            addChild(host)
            host.view.backgroundColor = .clear
            scroll.addSubview(host.view)
            host.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            layoutPaper()
        }

        func update(with reader: ShenlunMaterialZoomReader<Paper>) {
            host.rootView = reader.paper
            paperSize = reader.paperSize
            pageID = reader.pageID
            request = reader.request
            initialFraction = reader.initialFraction
            onInteraction = reader.onInteraction
            guard isViewLoaded else { return }
            scroll.panGestureRecognizer.minimumNumberOfTouches = reader.isDrawing ? 2 : 1
            layoutPaper()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.viewIfLoaded }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.isDragging || scrollView.isDecelerating || scrollView.isZooming {
                reportInteraction()
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerPaperHorizontally()
            if scrollView.isZooming { reportInteraction() }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            reportInteraction(force: true)
        }

        private func reportInteraction(force: Bool = false) {
            guard !isAdjusting, availableWidth > 0 else { return }
            let now = Date.timeIntervalSinceReferenceDate
            guard force || now - lastInteraction >= 0.12 else { return }
            lastInteraction = now
            let fraction = scroll.zoomScale / fitScale
            DispatchQueue.main.async { [weak self] in self?.onInteraction?(fraction) }
        }

        private func layoutPaper() {
            let width = scroll.bounds.width
            guard width > 0, paperSize.width > 0, paperSize.height > 0 else { return }
            let paperChanged = displayedPaperSize != paperSize
            let pageChanged = displayedPageID != pageID
            if paperChanged || availableWidth != width || pageChanged {
                isAdjusting = true
                let fraction = availableWidth > 0 ? scroll.zoomScale / fitScale : initialFraction
                if paperChanged {
                    scroll.minimumZoomScale = 0.01
                    scroll.maximumZoomScale = 20
                    scroll.setZoomScale(1, animated: false)
                    host.view.frame = CGRect(origin: .zero, size: paperSize)
                    scroll.contentSize = paperSize
                    displayedPaperSize = paperSize
                }
                availableWidth = width
                displayedPageID = pageID
                fitScale = width / paperSize.width
                scroll.maximumZoomScale = max(scroll.maximumZoomScale, fitScale * 3)
                scroll.minimumZoomScale = fitScale * 0.5
                scroll.maximumZoomScale = fitScale * 3
                scroll.setZoomScale(fitScale * fraction, animated: false)
                centerPaperHorizontally()
                if pageChanged || paperChanged {
                    scroll.setContentOffset(CGPoint(x: -scroll.contentInset.left, y: 0), animated: false)
                }
                isAdjusting = false
            }
            if let request, request.id != appliedRequestID {
                appliedRequestID = request.id
                scroll.setZoomScale(fitScale * request.fraction, animated: true)
            }
        }

        private func centerPaperHorizontally() {
            let inset = max(0, (scroll.bounds.width - scroll.contentSize.width) / 2)
            if abs(scroll.contentInset.left - inset) > 0.5 {
                scroll.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            }
        }
    }
}
