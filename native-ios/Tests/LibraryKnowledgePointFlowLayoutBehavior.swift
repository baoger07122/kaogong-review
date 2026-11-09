import Foundation

@main
enum LibraryKnowledgePointFlowLayoutBehavior {
    static func main() {
        let tags = ["中心主旨与作者态度判断", "结构识别", "长标签用于验证不同宽度下拆行与轮廓连续"]
        let narrowWidth: CGFloat = 88
        let regularWidth: CGFloat = 156
        let wideWidth: CGFloat = 320

        let narrow = LibraryKnowledgePointFlowLayout.layout(tags: tags, width: narrowWidth)
        let regular = LibraryKnowledgePointFlowLayout.layout(tags: tags, width: regularWidth)
        let wide = LibraryKnowledgePointFlowLayout.layout(tags: tags, width: wideWidth)

        precondition(narrow.rows.count >= regular.rows.count, "narrow cards use at least as many rows as regular cards")
        precondition(regular.rows.count >= wide.rows.count, "regular cards use at least as many rows as wide cards")
        precondition(narrow.height == CGFloat(narrow.rows.count) * narrow.rowHeight
            + CGFloat(max(0, narrow.rows.count - 1)) * narrow.rowSpacing,
            "estimated height matches the emitted row count")

        for (width, layout) in [(narrowWidth, narrow), (regularWidth, regular), (wideWidth, wide)] {
            for row in layout.rows {
                let rowWidth = row.reduce(CGFloat.zero) { $0 + $1.leadingSpacing + $1.width }
                precondition(rowWidth <= width + 0.01, "every row fits its available width")
                precondition(row.allSatisfy { $0.width <= width + 0.01 }, "no capsule fragment exceeds its row")
            }
        }

        let reconstructed = Dictionary(grouping: narrow.rows.flatMap { $0 }, by: \.tagIndex)
            .mapValues { $0.map(\.text).joined() }
        for (index, tag) in tags.enumerated() {
            precondition(reconstructed[index] == tag, "wrapped capsule fragments reconstruct their original tag")
        }
        let fragmentsForLongTag = narrow.rows.flatMap { $0 }.filter { $0.tagIndex == 2 }
        precondition(fragmentsForLongTag.count > 1, "a long tag continues as separate outlined row fragments")
    }
}
