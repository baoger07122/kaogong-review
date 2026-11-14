import SwiftUI
import UIKit

struct HomeTodoCollection: UIViewRepresentable {
    let items: [HomeTodo]
    let onToggleCompleted: (HomeTodo) -> Void
    let onEdit: (HomeTodo) -> Void
    let onDelete: (HomeTodo) -> Void
    let onSkipToday: (HomeTodo) -> Void
    let onDeleteToday: (HomeTodo) -> Void
    let onDeleteRule: (HomeTodo) -> Void
    let onToggleTimer: (HomeTodo) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> HomeTodoCollectionView {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
        configuration.trailingSwipeActionsConfigurationProvider = { [weak coordinator = context.coordinator] indexPath in
            coordinator?.swipeActions(at: indexPath)
        }
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let view = HomeTodoCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.contentInset = .zero
        view.dataSource = context.coordinator
        view.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: Coordinator.reuseID)
        context.coordinator.collectionView = view
        return view
    }

    func updateUIView(_ view: HomeTodoCollectionView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.items != items else { return }
        context.coordinator.items = items
        view.reloadData()
        view.collectionViewLayout.invalidateLayout()
        view.layoutIfNeeded()
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HomeTodoCollectionView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        uiView.bounds.size.width = width
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        return CGSize(width: width, height: uiView.collectionViewLayout.collectionViewContentSize.height)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource {
        static let reuseID = "home-todo-list-cell"
        var parent: HomeTodoCollection
        var items: [HomeTodo]
        weak var collectionView: UICollectionView?

        init(_ parent: HomeTodoCollection) {
            self.parent = parent
            items = parent.items
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
            guard items.indices.contains(indexPath.item), let listCell = cell as? UICollectionViewListCell else {
                return cell
            }
            let todo = items[indexPath.item]
            listCell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            listCell.contentConfiguration = UIHostingConfiguration {
                HomeTodoRow(
                    todo: todo,
                    onToggleCompleted: { self.parent.onToggleCompleted(todo) },
                    onEdit: { self.parent.onEdit(todo) },
                    onDelete: { self.parent.onDelete(todo) },
                    onSkipToday: { self.parent.onSkipToday(todo) },
                    onDeleteToday: { self.parent.onDeleteToday(todo) },
                    onDeleteRule: { self.parent.onDeleteRule(todo) },
                    onToggleTimer: { self.parent.onToggleTimer(todo) },
                    showsDivider: indexPath.item < self.items.count - 1
                )
            }
            .margins(.all, 0)
            return listCell
        }

        func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard items.indices.contains(indexPath.item) else { return nil }
            let todo = items[indexPath.item]
            let actions: [UIContextualAction]
            if todo.dailyRuleID == nil {
                actions = [makeAction(title: "删除", image: "trash", style: .destructive) { self.parent.onDelete(todo) }]
            } else {
                var recurringActions: [UIContextualAction] = []
                if !todo.isCompleted {
                    recurringActions.append(makeAction(
                        title: todo.isSkipped ? "恢复今天" : "跳过今天",
                        image: todo.isSkipped ? "arrow.uturn.backward" : "forward.fill",
                        style: .normal
                    ) { self.parent.onSkipToday(todo) })
                    recurringActions.append(makeAction(
                        title: "仅删除今天",
                        image: "trash",
                        style: .destructive
                    ) { self.parent.onDeleteToday(todo) })
                }
                recurringActions.append(makeAction(
                    title: "删除规则",
                    image: "trash.slash",
                    style: .destructive
                ) { self.parent.onDeleteRule(todo) })
                actions = recurringActions
            }
            let configuration = UISwipeActionsConfiguration(actions: actions)
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }

        private func makeAction(
            title: String,
            image: String,
            style: UIContextualAction.Style,
            perform: @escaping () -> Void
        ) -> UIContextualAction {
            let action = UIContextualAction(style: style, title: title) { _, _, completion in
                perform()
                completion(true)
            }
            action.image = UIImage(systemName: image)
            if style == .normal { action.backgroundColor = UIColor.systemBlue }
            return action
        }
    }
}

final class HomeTodoCollectionView: UICollectionView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: collectionViewLayout.collectionViewContentSize.height)
    }
}
