import SwiftUI
import UIKit

struct LibraryKnowledgePointTagLayout: Layout {
    static let font = UIFont.systemFont(ofSize: 11, weight: .medium)
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 3
    static let minimumTagHeight: CGFloat = 19
    static let rowSpacing: CGFloat = 4

    let points: [String]

    private var visiblePoints: [String] {
        points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widestNaturalTag = visiblePoints.map { metrics(for: $0, availableWidth: .greatestFiniteMagnitude).width }.max() ?? 0
        let availableWidth = max(1, proposal.width ?? max(240, widestNaturalTag))
        let sizes = visiblePoints.map { metrics(for: $0, availableWidth: availableWidth) }
        let contentWidth = sizes.map(\.width).max() ?? 0
        let contentHeight = sizes.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(0, sizes.count - 1)) * Self.rowSpacing
        return CGSize(width: min(availableWidth, contentWidth), height: contentHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let values = visiblePoints
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() where values.indices.contains(index) {
            let size = metrics(for: values[index], availableWidth: max(1, bounds.width))
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            y += size.height + Self.rowSpacing
        }
    }

    static func estimatedHeight(for points: [String], width: CGFloat) -> CGFloat {
        let visible = points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !visible.isEmpty else { return 0 }
        let layout = LibraryKnowledgePointTagLayout(points: visible)
        let sizes = visible.map { layout.metrics(for: $0, availableWidth: max(1, width)) }
        return sizes.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(0, sizes.count - 1)) * rowSpacing
    }

    private func metrics(for text: String, availableWidth: CGFloat) -> CGSize {
        let fullTextWidth = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width)
        let width = min(availableWidth, fullTextWidth + Self.horizontalPadding * 2)
        let textWidth = max(1, width - Self.horizontalPadding * 2)
        let textBounds = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.font],
            context: nil
        )
        let textHeight = max(Self.font.lineHeight, ceil(textBounds.height))
        return CGSize(width: width, height: max(Self.minimumTagHeight, textHeight + Self.verticalPadding * 2))
    }
}

struct LibraryKnowledgePointTagCloud: View {
    private struct TagGroup {
        let points: [String]
        let kind: LibraryCardTopTag.Kind?

        func accessibilityText(for point: String) -> String {
            switch kind {
            case .knowledgePoint: "考点，\(point)"
            case .mistakeTag: "错因标签，\(point)"
            case nil: point
            }
        }
    }

    private static let accessorySpacing: CGFloat = 6
    private static let iconWidth: CGFloat = 11

    static var cardLeadingAccessoryWidth: CGFloat { iconWidth + accessorySpacing }

    private let groups: [TagGroup]
    private let label: String?

    init(points: [String], label: String? = nil) {
        let visiblePoints = points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        groups = [TagGroup(points: visiblePoints, kind: nil)]
        self.label = label
    }

    init(cardTags: [LibraryCardTopTag]) {
        let kinds: [LibraryCardTopTag.Kind] = [.knowledgePoint, .mistakeTag]
        groups = kinds.compactMap { kind in
            let points = cardTags.filter { $0.kind == kind }.map(\.text)
            return points.isEmpty ? nil : TagGroup(points: points, kind: kind)
        }
        label = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryKnowledgePointTagLayout.rowSpacing) {
            ForEach(groups.indices, id: \.self) { index in
                tagGroup(groups[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(groups.flatMap { group in
            group.points.map { group.accessibilityText(for: $0) }
        }.joined(separator: "、"))
    }

    private func tagGroup(_ group: TagGroup) -> some View {
        let isKnowledgePoint = group.kind == .knowledgePoint
        return HStack(alignment: .top, spacing: Self.accessorySpacing) {
            if let label {
                Text("\(label)：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.top, 3)
            }
            if let kind = group.kind {
                cardIcon(for: kind)
                    .frame(width: Self.iconWidth, height: Self.iconWidth)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            LibraryKnowledgePointTagLayout(points: group.points) {
                ForEach(Array(group.points.enumerated()), id: \.offset) { _, point in
                    Text(point)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isKnowledgePoint
                            ? AppTheme.accent
                            : Color(red: 34 / 255.0, green: 34 / 255.0, blue: 34 / 255.0))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, LibraryKnowledgePointTagLayout.horizontalPadding)
                        .padding(.vertical, LibraryKnowledgePointTagLayout.verticalPadding)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isKnowledgePoint ? AppTheme.accent.opacity(0.72) : Color.primary.opacity(0.15), lineWidth: 0.75)
                        }
                        .accessibilityLabel(group.accessibilityText(for: point))
                }
            }
            .accessibilityElement(children: .contain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cardIcon(for kind: LibraryCardTopTag.Kind) -> some View {
        switch kind {
        case .knowledgePoint:
            Image(systemName: "lightbulb.min")
                .font(.system(size: Self.iconWidth, weight: .regular))
                .foregroundStyle(AppTheme.accent)
        case .mistakeTag:
            MistakeAnnotationIcon()
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct MistakeAnnotationIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: 9.8, y: 21))
        path.addLine(to: CGPoint(x: 5.2, y: 21))
        path.addQuadCurve(to: CGPoint(x: 3.7, y: 19.5), control: CGPoint(x: 3.7, y: 21))
        path.addLine(to: CGPoint(x: 3.7, y: 4.2))
        path.addQuadCurve(to: CGPoint(x: 5.2, y: 2.7), control: CGPoint(x: 3.7, y: 2.7))
        path.addLine(to: CGPoint(x: 13.6, y: 2.7))
        path.addLine(to: CGPoint(x: 18.2, y: 7.3))
        path.addLine(to: CGPoint(x: 18.2, y: 10))

        path.move(to: CGPoint(x: 13.6, y: 2.7))
        path.addLine(to: CGPoint(x: 13.6, y: 7.3))
        path.addLine(to: CGPoint(x: 18.2, y: 7.3))

        path.move(to: CGPoint(x: 7, y: 8.9))
        path.addLine(to: CGPoint(x: 10.1, y: 8.9))
        path.move(to: CGPoint(x: 7, y: 12.2))
        path.addLine(to: CGPoint(x: 10.3, y: 12.2))

        path.addEllipse(in: CGRect(x: 11.3, y: 12.1, width: 10.2, height: 10.2))
        path.move(to: CGPoint(x: 14.8, y: 15.6))
        path.addLine(to: CGPoint(x: 18, y: 18.8))
        path.move(to: CGPoint(x: 18, y: 15.6))
        path.addLine(to: CGPoint(x: 14.8, y: 18.8))

        return path.applying(CGAffineTransform(
            a: rect.width / 24, b: 0,
            c: 0, d: rect.height / 24,
            tx: rect.minX, ty: rect.minY
        ))
    }
}
