import SwiftUI
import UIKit

@MainActor
struct LibraryHorizontalRecordPager: UIViewControllerRepresentable {
    let recordIDs: [String]
    @Binding var currentRecordID: String
    let isPagingEnabled: Bool
    let contentForRecord: (String) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        controller.view.backgroundColor = .white
        controller.delegate = context.coordinator
        controller.dataSource = context.coordinator
        context.coordinator.attach(to: controller)
        context.coordinator.configureVisibleController()
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: controller)
        context.coordinator.updatePagingAvailability()
        context.coordinator.refreshCachedContent()

        guard !context.coordinator.isTransitioning,
              let visibleID = context.coordinator.visibleRecordID else { return }
        if visibleID == currentRecordID, recordIDs.contains(currentRecordID) {
            context.coordinator.pruneCache(around: currentRecordID)
        }
        guard visibleID != currentRecordID,
              recordIDs.contains(currentRecordID) else { return }

        let direction: UIPageViewController.NavigationDirection =
            (recordIDs.firstIndex(of: currentRecordID) ?? 0) >= (recordIDs.firstIndex(of: visibleID) ?? 0)
                ? .forward
                : .reverse
        guard let target = context.coordinator.hostingController(for: currentRecordID) else { return }
        controller.setViewControllers([target], direction: direction, animated: false)
        context.coordinator.pruneCache(around: currentRecordID)
    }

    static func dismantleUIViewController(_ controller: UIPageViewController, coordinator: Coordinator) {
        controller.delegate = nil
        controller.dataSource = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: LibraryHorizontalRecordPager
        private weak var pageController: UIPageViewController?
        private var cache: [String: UIHostingController<AnyView>] = [:]
        private var lastTransitionDirection: UIPageViewController.NavigationDirection = .forward
        private(set) var isTransitioning = false

        var visibleRecordID: String? {
            guard let visible = pageController?.viewControllers?.first else { return nil }
            return cache.first(where: { $0.value === visible })?.key
        }

        init(parent: LibraryHorizontalRecordPager) {
            self.parent = parent
            super.init()
        }

        func attach(to controller: UIPageViewController) {
            pageController = controller
        }

        func detach() {
            pageController = nil
            cache.removeAll()
        }

        func configureVisibleController() {
            guard let pageController,
                  parent.recordIDs.contains(parent.currentRecordID),
                  let initial = hostingController(for: parent.currentRecordID) else { return }
            updatePagingAvailability()
            pageController.setViewControllers([initial], direction: .forward, animated: false)
            pruneCache(around: parent.currentRecordID)
        }

        func updatePagingAvailability() {
            guard let pageController else { return }
            for scrollView in pageController.view.subviews.compactMap({ $0 as? UIScrollView }) {
                scrollView.isScrollEnabled = parent.isPagingEnabled
                scrollView.panGestureRecognizer.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.direct.rawValue),
                    NSNumber(value: UITouch.TouchType.pencil.rawValue)
                ]
            }
        }

        func refreshCachedContent() {
            for (recordID, controller) in cache {
                controller.rootView = parent.contentForRecord(recordID)
                controller.view.backgroundColor = .white
            }
        }

        func pruneCache(around recordID: String) {
            guard let index = parent.recordIDs.firstIndex(of: recordID) else {
                cache.removeAll()
                return
            }
            let retainedIDs = Set(parent.recordIDs[max(0, index - 1)...min(parent.recordIDs.count - 1, index + 1)])
            cache = cache.filter { retainedIDs.contains($0.key) }
        }

        func hostingController(for recordID: String) -> UIHostingController<AnyView>? {
            guard parent.recordIDs.contains(recordID) else { return nil }
            if let cached = cache[recordID] {
                cached.rootView = parent.contentForRecord(recordID)
                cached.view.backgroundColor = .white
                return cached
            }
            let controller = UIHostingController(rootView: parent.contentForRecord(recordID))
            controller.view.backgroundColor = .white
            controller.view.clipsToBounds = true
            cache[recordID] = controller
            return controller
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            adjacentController(from: viewController, offset: -1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            adjacentController(from: viewController, offset: 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isTransitioning = true
            guard let currentID = visibleRecordID,
                  let pendingID = pendingViewControllers.first.flatMap({ pending in
                      cache.first(where: { $0.value === pending })?.key
                  }),
                  let currentIndex = parent.recordIDs.firstIndex(of: currentID),
                  let pendingIndex = parent.recordIDs.firstIndex(of: pendingID) else { return }
            lastTransitionDirection = pendingIndex >= currentIndex ? .forward : .reverse
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            guard completed, let newID = visibleRecordID else {
                updatePagingAvailability()
                return
            }
            _ = lastTransitionDirection
            parent.currentRecordID = newID
            pruneCache(around: newID)
            updatePagingAvailability()
        }

        private func adjacentController(from viewController: UIViewController, offset: Int) -> UIViewController? {
            guard let currentID = cache.first(where: { $0.value === viewController })?.key,
                  currentID == parent.currentRecordID,
                  let currentIndex = parent.recordIDs.firstIndex(of: currentID) else { return nil }
            let nextIndex = currentIndex + offset
            guard parent.recordIDs.indices.contains(nextIndex) else { return nil }
            return hostingController(for: parent.recordIDs[nextIndex])
        }
    }
}

struct LibraryRecordSwipePreview: View {
    let record: StoredRecord

    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var title: String {
        [object["question"] as? String, object["title"] as? String, object["content"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "未命名题目"
    }
    private var options: [String] { object["options"] as? [String] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                    Text(record.module?.isEmpty == false ? record.module ?? "" : record.subject ?? "")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !options.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            if !option.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(alignment: .top, spacing: 9) {
                                    Text(optionLabel(at: index))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 24, height: 24)
                                        .background(AppTheme.accent.opacity(0.08), in: Circle())
                                    Text(option)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }

    private func optionLabel(at index: Int) -> String {
        guard let scalar = UnicodeScalar(65 + index) else { return "\(index + 1)" }
        return String(scalar)
    }
}
