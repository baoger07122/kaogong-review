import SwiftUI
import UIKit

struct KnowledgePointTagFragment {
    let text: String
    let width: CGFloat
}

enum LibraryKnowledgePointTagLayout {
    static let font = UIFont.systemFont(ofSize: 11, weight: .medium)
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 3
    static let rowHeight: CGFloat = 19
    static let itemSpacing: CGFloat = 5
    static let rowSpacing: CGFloat = 4

    static func rows(_ values: [String], width: CGFloat) -> [[KnowledgePointTagFragment]] {
        let availableWidth = max(1, width)
        var result: [[KnowledgePointTagFragment]] = [[]]
        var usedWidth: CGFloat = 0

        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let characters = Array(value)
            var index = 0

            while index < characters.count {
                let hasItems = !result[result.count - 1].isEmpty
                let remainingWidth = availableWidth - usedWidth - (hasItems ? itemSpacing : 0)
                let textWidth = max(0, remainingWidth - horizontalPadding * 2)
                let count = fittingCharacterCount(characters, from: index, width: textWidth)

                if hasItems && count < 2 {
                    result.append([])
                    usedWidth = 0
                    continue
                }

                let fragmentCount = max(1, count)
                let text = String(characters[index..<min(characters.count, index + fragmentCount)])
                let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
                let fragmentWidth = min(remainingWidth, measuredWidth + horizontalPadding * 2)
                result[result.count - 1].append(KnowledgePointTagFragment(text: text, width: fragmentWidth))
                usedWidth += (hasItems ? itemSpacing : 0) + fragmentWidth
                index += fragmentCount

                if index < characters.count {
                    result.append([])
                    usedWidth = 0
                }
            }
        }

        return result.filter { !$0.isEmpty }
    }

    static func height(_ values: [String], width: CGFloat) -> CGFloat {
        let count = rows(values, width: width).count
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
    }

    private static func fittingCharacterCount(_ characters: [Character], from start: Int, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        var candidate = ""
        var fitting = 0
        for character in characters[start...] {
            candidate.append(character)
            let measured = (candidate as NSString).size(withAttributes: [.font: font]).width
            guard measured <= width else { break }
            fitting += 1
        }
        return fitting
    }
}

private struct KnowledgePointTagCloudLayout: Layout {
    let points: [String]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 240)
        return CGSize(width: width, height: LibraryKnowledgePointTagLayout.height(points, width: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let canvas = subviews.first else { return }
        canvas.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

struct LibraryKnowledgePointTagCloud: View {
    let points: [String]
    var label: String? = nil
    var showsBulb = false

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
            AnyLayout(KnowledgePointTagCloudLayout(points: points)) {
                Canvas { context, size in
                    let rows = LibraryKnowledgePointTagLayout.rows(points, width: size.width)
                    for (rowIndex, row) in rows.enumerated() {
                        var x: CGFloat = 0
                        let y = CGFloat(rowIndex) * (LibraryKnowledgePointTagLayout.rowHeight + LibraryKnowledgePointTagLayout.rowSpacing)
                        for (itemIndex, fragment) in row.enumerated() {
                            if itemIndex > 0 { x += LibraryKnowledgePointTagLayout.itemSpacing }
                            let rect = CGRect(
                                x: x,
                                y: y,
                                width: fragment.width,
                                height: LibraryKnowledgePointTagLayout.rowHeight
                            )
                            context.stroke(
                                RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: rect),
                                with: .color(Color.primary.opacity(0.15)),
                                lineWidth: 0.75
                            )
                            let resolved = context.resolve(
                                Text(fragment.text)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(red: 34 / 255.0, green: 34 / 255.0, blue: 34 / 255.0))
                            )
                            context.draw(
                                resolved,
                                at: CGPoint(x: x + LibraryKnowledgePointTagLayout.horizontalPadding, y: y + LibraryKnowledgePointTagLayout.verticalPadding),
                                anchor: .topLeading
                            )
                            x += fragment.width
                        }
                    }
                }
                .accessibilityLabel(points.joined(separator: "、"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
