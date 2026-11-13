import SwiftUI
import UIKit

struct LibraryKnowledgePointTagItem: Identifiable, Hashable {
    let reference: LibraryKnowledgePointReference
    let title: String
    var isSelected: Bool
    var id: String { reference.id }
}

struct LibraryKnowledgePointGroupBar: View {
    let groups: [LibraryKnowledgePointGroup]
    let selectedID: String?
    let action: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(groups) { group in
                    Button { action(group.id) } label: {
                        Text(group.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedID == group.id ? AppTheme.accent : Color.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                selectedID == group.id ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 28)
    }
}

struct LibraryKnowledgePointTagCollection: UIViewRepresentable {
    let items: [LibraryKnowledgePointTagItem]
    var allowsReordering = false
    var onToggle: (LibraryKnowledgePointReference) -> Void
    var onReorder: ([LibraryKnowledgePointReference]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> KnowledgePointCollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Self.spacing
        layout.minimumLineSpacing = Self.spacing
        layout.estimatedItemSize = .zero
        let view = KnowledgePointCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.contentInset = .zero
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.register(KnowledgePointTagCell.self, forCellWithReuseIdentifier: KnowledgePointTagCell.reuseID)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = true
        longPress.isEnabled = allowsReordering
        view.addGestureRecognizer(longPress)
        context.coordinator.collectionView = view
        context.coordinator.longPress = longPress
        return view
    }

    func updateUIView(_ view: KnowledgePointCollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.longPress?.isEnabled = allowsReordering
        guard !context.coordinator.isMoving else { return }
        if context.coordinator.items != items {
            context.coordinator.items = items
            view.reloadData()
            view.collectionViewLayout.invalidateLayout()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KnowledgePointCollectionView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? uiView.bounds.width)
        return CGSize(width: width, height: Self.height(for: items, width: width))
    }

    static func height(for items: [LibraryKnowledgePointTagItem], width: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for item in items {
            let size = itemSize(title: displayedTitle(item), width: width)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return y + rowHeight
    }

    private static let spacing: CGFloat = 6
    private static let font = UIFont.systemFont(ofSize: 12, weight: .regular)

    fileprivate static func displayedTitle(_ item: LibraryKnowledgePointTagItem) -> String {
        item.isSelected ? "\(item.title)  ✓" : item.title
    }

    fileprivate static func itemSize(title: String, width: CGFloat) -> CGSize {
        let maximumTextWidth = max(1, width - 20)
        let measured = (title as NSString).boundingRect(
            with: CGSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let naturalWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 20
        let itemWidth = min(width, max(20, naturalWidth))
        let textWidth = max(1, itemWidth - 20)
        let textBounds = (title as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: itemWidth, height: max(font.lineHeight, ceil(textBounds.height)) + 16)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
        var parent: LibraryKnowledgePointTagCollection
        var items: [LibraryKnowledgePointTagItem]
        weak var collectionView: UICollectionView?
        weak var longPress: UILongPressGestureRecognizer?
        var isMoving = false
        private var startingOrder: [LibraryKnowledgePointReference] = []

        init(_ parent: LibraryKnowledgePointTagCollection) {
            self.parent = parent
            items = parent.items
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: KnowledgePointTagCell.reuseID, for: indexPath)
            (cell as? KnowledgePointTagCell)?.configure(items[indexPath.item])
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard items.indices.contains(indexPath.item) else { return }
            parent.onToggle(items[indexPath.item].reference)
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            parent.allowsReordering
        }

        func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            guard items.indices.contains(sourceIndexPath.item), items.indices.contains(destinationIndexPath.item) else { return }
            let item = items.remove(at: sourceIndexPath.item)
            items.insert(item, at: destinationIndexPath.item)
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            guard items.indices.contains(indexPath.item) else { return .zero }
            return LibraryKnowledgePointTagCollection.itemSize(
                title: LibraryKnowledgePointTagCollection.displayedTitle(items[indexPath.item]),
                width: max(1, collectionView.bounds.width)
            )
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            let point = gesture.location(in: collectionView)
            switch gesture.state {
            case .began:
                guard parent.allowsReordering, let indexPath = collectionView.indexPathForItem(at: point) else { return }
                isMoving = true
                startingOrder = items.map(\.reference)
                if !collectionView.beginInteractiveMovementForItem(at: indexPath) { isMoving = false }
            case .changed:
                if isMoving { collectionView.updateInteractiveMovementTargetPosition(point) }
            case .ended:
                guard isMoving else { return }
                collectionView.endInteractiveMovement()
                let order = items.map(\.reference)
                if order != startingOrder, !parent.onReorder(order) {
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

final class KnowledgePointCollectionView: UICollectionView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: collectionViewLayout.collectionViewContentSize.height)
    }
}

private final class KnowledgePointTagCell: UICollectionViewCell {
    static let reuseID = "knowledge-point-tag"
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
        contentView.layer.cornerRadius = 6
        contentView.clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: LibraryKnowledgePointTagItem) {
        titleLabel.text = LibraryKnowledgePointTagCollection.displayedTitle(item)
        contentView.backgroundColor = item.isSelected
            ? UIColor(AppTheme.accent.opacity(0.10))
            : UIColor(Color.primary.opacity(0.04))
        titleLabel.textColor = item.isSelected ? UIColor(AppTheme.accent) : UIColor.label
        accessibilityLabel = item.title
        accessibilityTraits = item.isSelected ? [.button, .selected] : [.button]
    }
}
