import Foundation

enum LibraryDataAnalysisCauseLayout {
    static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func estimatedTagLineHeight(label: String, values: [String], width: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }

        let labelWidth = CGFloat(label.count + 1) * 12
        let flowWidth = max(1, width - labelWidth - 5)
        let fontSize: CGFloat = 11
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 10
        let lineHeight = fontSize * 1.35
        let spacing: CGFloat = 5
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowWidth: CGFloat = 0

        for value in values {
            let naturalWidth = CGFloat(value.count) * fontSize + horizontalPadding
            let itemWidth = min(flowWidth, naturalWidth)
            let textWidth = max(1, flowWidth - horizontalPadding)
            let lineCount = max(1, Int(ceil(CGFloat(value.count) * fontSize / textWidth)))
            let itemHeight = CGFloat(lineCount) * lineHeight + verticalPadding

            if rowWidth > 0, rowWidth + spacing + itemWidth > flowWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }

            rowWidth += (rowWidth > 0 ? spacing : 0) + itemWidth
            rowHeight = max(rowHeight, itemHeight)
        }

        return max(14, totalHeight + rowHeight)
    }
}
