import SwiftUI
import UIKit

struct HomeDailyTodoRuleReorderList: UIViewRepresentable {
    let items: [HomeDailyTodoRule]
    let onReorder: ([String]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.contentInset = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.alwaysBounceVertical = true
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseID)
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = true
        view.addGestureRecognizer(longPress)
        context.coordinator.collectionView = view
        context.coordinator.longPress = longPress
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isMoving, context.coordinator.items != items else { return }
        context.coordinator.items = items
        view.reloadData()
        view.collectionViewLayout.invalidateLayout()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
        static let reuseID = "home-daily-rule-reorder-cell"
        var parent: HomeDailyTodoRuleReorderList
        var items: [HomeDailyTodoRule]
        weak var collectionView: UICollectionView?
        weak var longPress: UILongPressGestureRecognizer?
        var isMoving = false
        private var startingOrder: [String] = []

        init(_ parent: HomeDailyTodoRuleReorderList) {
            self.parent = parent
            items = parent.items
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            guard items.indices.contains(indexPath.item) else { return cell }
            let rule = items[indexPath.item]
            cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                HomeDailyTodoRuleRow(
                    rule: rule,
                    onEdit: {},
                    onTogglePause: {},
                    onDelete: {},
                    isReordering: true
                )
            }
            .margins(.all, 0)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            items.indices.contains(indexPath.item)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            moveItemAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath
        ) {
            guard items.indices.contains(sourceIndexPath.item), items.indices.contains(destinationIndexPath.item) else { return }
            let moved = items.remove(at: sourceIndexPath.item)
            items.insert(moved, at: destinationIndexPath.item)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            let point = gesture.location(in: collectionView)
            switch gesture.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
                isMoving = true
                startingOrder = items.map(\.id)
                if !collectionView.beginInteractiveMovementForItem(at: indexPath) { isMoving = false }
            case .changed:
                if isMoving { collectionView.updateInteractiveMovementTargetPosition(point) }
            case .ended:
                guard isMoving else { return }
                collectionView.endInteractiveMovement()
                let newOrder = items.map(\.id)
                if newOrder != startingOrder, !parent.onReorder(newOrder) {
                    items = parent.items
                    collectionView.reloadData()
                }
                isMoving = false
            case .cancelled, .failed:
                guard isMoving else { return }
                collectionView.cancelInteractiveMovement()
                items = parent.items
                isMoving = false
            default:
                break
            }
        }
    }
}
