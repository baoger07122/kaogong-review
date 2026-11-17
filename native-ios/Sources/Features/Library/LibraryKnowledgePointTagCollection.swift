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
    var allowsManagementActions = true
    var onToggle: (LibraryKnowledgePointReference) -> Void
    var onReorder: ([LibraryKnowledgePointReference]) -> Bool
    var onRename: (LibraryKnowledgePointReference) -> Void = { _ in }
    var onDelete: (LibraryKnowledgePointReference) -> Void = { _ in }
    var onAdjustOrder: (LibraryKnowledgePointReference) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> KnowledgePointCollectionView {
        let layout = KnowledgePointTagCollectionLayout(items: items)
        let view = KnowledgePointCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.allowsSelection = false
        view.delaysContentTouches = false
        view.canCancelContentTouches = true
        view.contentInset = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.register(KnowledgePointTagCell.self, forCellWithReuseIdentifier: KnowledgePointTagCell.reuseID)
        context.coordinator.collectionView = view
        view.reloadData()
        return view
    }

    func updateUIView(_ view: KnowledgePointCollectionView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.items != items {
            context.coordinator.items = items
            (view.collectionViewLayout as? KnowledgePointTagCollectionLayout)?.update(items: items)
            view.reloadData()
            view.collectionViewLayout.invalidateLayout()
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KnowledgePointCollectionView, context: Context) -> CGSize? {
        guard let width = proposal.width ?? (uiView.bounds.width > 0 ? uiView.bounds.width : nil), width > 0 else {
            return nil
        }
        return Self.layoutSnapshot(for: items, width: width).contentSize
    }

    fileprivate static let spacing: CGFloat = 6
    fileprivate static let font = UIFont.systemFont(ofSize: 12, weight: .regular)

    fileprivate static func displayedTitle(_ item: LibraryKnowledgePointTagItem) -> String { item.title }

    fileprivate static func itemSize(title: String, width: CGFloat) -> CGSize {
        guard width > 0 else { return .zero }
        let accessoryWidth: CGFloat = 14
        let accessoryGap: CGFloat = 4
        let horizontalInsets: CGFloat = 20
        let availableTextWidth = max(1, width - horizontalInsets - accessoryWidth - accessoryGap)
        let naturalTextWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let itemWidth = min(width, max(20, naturalTextWidth + horizontalInsets + accessoryWidth + accessoryGap))
        let textWidth = max(1, itemWidth - horizontalInsets - accessoryWidth - accessoryGap)
        let textBounds = (title as NSString).boundingRect(
            with: CGSize(width: min(availableTextWidth, textWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: itemWidth, height: max(font.lineHeight, ceil(textBounds.height)) + 16)
    }

    fileprivate static func layoutSnapshot(for items: [LibraryKnowledgePointTagItem], width: CGFloat) -> LibraryKnowledgePointTagLayoutSnapshot {
        let sizes = items.map { itemSize(title: displayedTitle($0), width: width) }
        return LibraryKnowledgePointTagLayoutPolicy.layout(itemSizes: sizes, width: width, spacing: spacing)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: LibraryKnowledgePointTagCollection
        var items: [LibraryKnowledgePointTagItem]
        weak var collectionView: UICollectionView?

        init(_ parent: LibraryKnowledgePointTagCollection) {
            self.parent = parent
            items = parent.items
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: KnowledgePointTagCell.reuseID, for: indexPath)
            guard items.indices.contains(indexPath.item), let tagCell = cell as? KnowledgePointTagCell else { return cell }
            let item = items[indexPath.item]
            tagCell.configure(item) { [weak self] reference in
                guard let self,
                      let current = self.items.first(where: { $0.reference == reference }) else { return }
                self.parent.onToggle(current.reference)
            }
            return tagCell
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            false
        }

        func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            return
        }

        func collectionView(
            _ collectionView: UICollectionView,
            contextMenuConfigurationForItemAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard parent.allowsManagementActions, items.indices.contains(indexPath.item) else { return nil }
            let item = items[indexPath.item]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return UIMenu(children: []) }
                var actions = [
                    UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
                        self?.parent.onRename(item.reference)
                    }
                ]
                if self.parent.allowsReordering {
                    actions.append(UIAction(title: "调整顺序", image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
                        self?.parent.onAdjustOrder(item.reference)
                    })
                }
                actions.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.parent.onDelete(item.reference)
                })
                return UIMenu(children: actions)
            }
        }

    }
}

private final class KnowledgePointTagCollectionLayout: UICollectionViewLayout {
    private var items: [LibraryKnowledgePointTagItem]
    private var frames: [CGRect] = []
    private var contentSize: CGSize = .zero
    private var measuredWidth: CGFloat = -1

    init(items: [LibraryKnowledgePointTagItem]) {
        self.items = items
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(items: [LibraryKnowledgePointTagItem]) {
        self.items = items
        measuredWidth = -1
        invalidateLayout()
        collectionView?.invalidateIntrinsicContentSize()
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let width = max(0, collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right)
        guard width > 0 else {
            frames = []
            contentSize = .zero
            measuredWidth = width
            return
        }
        if abs(width - measuredWidth) < 0.5, frames.count == items.count { return }
        let snapshot = LibraryKnowledgePointTagCollection.layoutSnapshot(for: items, width: width)
        frames = snapshot.frames
        contentSize = snapshot.contentSize
        measuredWidth = width
    }

    override var collectionViewContentSize: CGSize { contentSize }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        frames.enumerated().compactMap { index, frame in
            guard frame.intersects(rect) else { return nil }
            return attributes(for: index, frame: frame)
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.item) else { return nil }
        return attributes(for: indexPath.item, frame: frames[indexPath.item])
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        abs(newBounds.width - measuredWidth) >= 0.5
    }

    private func attributes(for index: Int, frame: CGRect) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
        attributes.frame = frame
        return attributes
    }
}

final class KnowledgePointCollectionView: UICollectionView {
    private var lastMeasuredWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, abs(width - lastMeasuredWidth) > 0.5 else { return }
        lastMeasuredWidth = width
        collectionViewLayout.invalidateLayout()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: collectionViewLayout.collectionViewContentSize.height)
    }
}

private final class KnowledgePointTagCell: UICollectionViewCell {
    static let reuseID = "knowledge-point-tag"
    private let button = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark"))
    private var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.adjustsImageWhenHighlighted = false
        button.clipsToBounds = true
        button.layer.cornerRadius = 6
        button.addTarget(self, action: #selector(activate), for: .touchUpInside)
        contentView.addSubview(button)

        titleLabel.font = LibraryKnowledgePointTagCollection.font
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.addSubview(titleLabel)

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.isAccessibilityElement = false
        button.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -4),
            checkmarkView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
            checkmarkView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onActivate = nil
    }

    func configure(_ item: LibraryKnowledgePointTagItem, onActivate: @escaping (LibraryKnowledgePointReference) -> Void) {
        titleLabel.text = item.title
        button.backgroundColor = item.isSelected
            ? UIColor(AppTheme.accent.opacity(0.10))
            : UIColor(Color.primary.opacity(0.04))
        titleLabel.textColor = item.isSelected ? UIColor(AppTheme.accent) : UIColor.label
        checkmarkView.tintColor = UIColor(AppTheme.accent)
        checkmarkView.alpha = item.isSelected ? 1 : 0
        button.isSelected = item.isSelected
        button.accessibilityLabel = item.title
        button.accessibilityValue = item.isSelected ? "已选" : "未选"
        button.accessibilityIdentifier = "knowledge-point-tag-\(item.reference.id)"
        button.accessibilityTraits = item.isSelected ? [.button, .selected] : [.button]
        self.onActivate = { onActivate(item.reference) }
    }

    @objc private func activate() { onActivate?() }
}
