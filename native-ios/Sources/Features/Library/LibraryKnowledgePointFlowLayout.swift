import Foundation

struct LibraryKnowledgePointFlowFragment: Equatable {
    let tagIndex: Int
    let text: String
    let textWidth: CGFloat
    let width: CGFloat
    let leadingSpacing: CGFloat
}

struct LibraryKnowledgePointFlowResult: Equatable {
    let rows: [[LibraryKnowledgePointFlowFragment]]
    let rowHeight: CGFloat
    let rowSpacing: CGFloat

    var height: CGFloat {
        guard !rows.isEmpty else { return 0 }
        return CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowSpacing
    }
}

enum LibraryKnowledgePointFlowLayout {
    static let fontSize: CGFloat = 11
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 3
    static let tagSpacing: CGFloat = 4
    static let rowSpacing: CGFloat = 2
    static let rowHeight: CGFloat = 20

    static func layout(tags: [String], width: CGFloat) -> LibraryKnowledgePointFlowResult {
        let availableWidth = width.isFinite ? max(0, width) : 0
        guard availableWidth > 0 else {
            return LibraryKnowledgePointFlowResult(rows: [], rowHeight: rowHeight, rowSpacing: rowSpacing)
        }

        var rows: [[LibraryKnowledgePointFlowFragment]] = [[]]
        var rowWidth: CGFloat = 0
        var currentTagIndex: Int?
        var currentText = ""
        var currentLeadingSpacing: CGFloat = 0

        func beginNextRow() {
            if !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
        }

        func emitCurrentFragment() {
            guard let tagIndex = currentTagIndex, !currentText.isEmpty else { return }
            let measuredTextWidth = ceil(textWidth(currentText))
            let chipWidth = min(
                availableWidth,
                max(1, measuredTextWidth + horizontalPadding * 2)
            )
            let gap = rows[rows.count - 1].isEmpty ? 0 : currentLeadingSpacing
            let fragment = LibraryKnowledgePointFlowFragment(
                tagIndex: tagIndex,
                text: currentText,
                textWidth: measuredTextWidth,
                width: chipWidth,
                leadingSpacing: gap
            )
            rows[rows.count - 1].append(fragment)
            rowWidth += gap + chipWidth
            currentTagIndex = nil
            currentText = ""
            currentLeadingSpacing = 0
        }

        for (tagIndex, tag) in tags.enumerated() {
            let characters = Array(tag)
            guard !characters.isEmpty else { continue }

            for character in characters {
                let value = String(character)
                if let activeTag = currentTagIndex, activeTag == tagIndex {
                    let candidate = currentText + value
                    let candidateWidth = ceil(textWidth(candidate)) + horizontalPadding * 2
                    if rowWidth + currentLeadingSpacing + candidateWidth <= availableWidth {
                        currentText = candidate
                    } else {
                        emitCurrentFragment()
                        beginNextRow()
                        currentTagIndex = tagIndex
                        currentText = value
                    }
                    continue
                }

                let leading = rows[rows.count - 1].isEmpty ? 0 : tagSpacing
                let firstWidth = ceil(textWidth(value)) + horizontalPadding * 2
                if rowWidth + leading + firstWidth > availableWidth,
                   !rows[rows.count - 1].isEmpty {
                    beginNextRow()
                }
                currentTagIndex = tagIndex
                currentText = value
                currentLeadingSpacing = rows[rows.count - 1].isEmpty ? 0 : tagSpacing
            }
            emitCurrentFragment()
        }

        if rows.last?.isEmpty == true { rows.removeLast() }
        return LibraryKnowledgePointFlowResult(rows: rows, rowHeight: rowHeight, rowSpacing: rowSpacing)
    }

    private static func textWidth(_ text: String) -> CGFloat {
        text.reduce(CGFloat.zero) { total, character in
            let scalars = String(character).unicodeScalars
            guard scalars.allSatisfy({ $0.isASCII }) else { return total + fontSize * 1.06 }
            let value = String(character)
            if "ilI.,:;!'|`".contains(value) { return total + fontSize * 0.38 }
            if "MW@%".contains(value) { return total + fontSize * 0.9 }
            if value == " " { return total + fontSize * 0.36 }
            return total + fontSize * 0.64
        }
    }
}
