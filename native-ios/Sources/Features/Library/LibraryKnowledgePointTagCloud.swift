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
    let points: [String]
    var label: String? = nil
    var showsBulb = false

    static func leadingAccessoryWidth(label: String? = nil, showsBulb: Bool = false) -> CGFloat {
        if let label {
            let font = UIFont.systemFont(ofSize: 11, weight: .medium)
            return ceil(("\(label)：" as NSString).size(withAttributes: [.font: font]).width) + 6
        }
        return showsBulb ? 17 : 0
    }

    private var visiblePoints: [String] {
        points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let label {
                Text("\(label)：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.top, 3)
            }
            if showsBulb {
                Image(systemName: "lightbulb.min")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.black)
                    .frame(width: 11)
                    .padding(.top, 4)
            }
            LibraryKnowledgePointTagLayout(points: visiblePoints) {
                ForEach(Array(visiblePoints.enumerated()), id: \.offset) { _, point in
                    Text(point)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 34 / 255.0, green: 34 / 255.0, blue: 34 / 255.0))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, LibraryKnowledgePointTagLayout.horizontalPadding)
                        .padding(.vertical, LibraryKnowledgePointTagLayout.verticalPadding)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.75)
                        }
                }
            }
            .accessibilityElement(children: .contain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(visiblePoints.joined(separator: "、"))
    }
}
