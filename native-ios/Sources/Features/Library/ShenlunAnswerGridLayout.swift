import Foundation

struct ShenlunAnswerGridCell: Equatable, Sendable {
    var index: Int
    var character: String
    var sharesCellWithFullStop = false

    var pageIndex: Int { max(0, index - 1) / 600 }
    var row: Int { (max(0, index - 1) % 600) / 25 }
    var column: Int { max(0, index - 1) % 25 }
}

struct ShenlunAnswerGridProjection: Equatable, Sendable {
    var cells: [ShenlunAnswerGridCell]
    var occupiedCount: Int
    var maximumCount: Int?
    var isReview = false

    static let reserveCount = 100
    var isGridEnabled: Bool { maximumCount != nil || isReview }
    var visibleCellCount: Int {
        if let maximumCount {
            return isReview ? max(maximumCount, occupiedCount)
                : min(maximumCount, Int.max - Self.reserveCount) + Self.reserveCount
        }
        return isReview ? (max(1, occupiedCount) - 1) / 25 * 25 + 25 : 0
    }
    var sheetCount: Int { visibleCellCount > 0 ? (visibleCellCount - 1) / 600 + 1 : 1 }
    var overflowCount: Int { isGridEnabled ? max(0, occupiedCount - visibleCellCount) : 0 }

    func visibleCells(on sheet: Int) -> [ShenlunAnswerGridCell] {
        guard let range = cellRange(on: sheet) else { return [] }
        return cells.filter { range.contains($0.index) }
    }

    func gridCellCount(on sheet: Int) -> Int {
        cellRange(on: sheet)?.count ?? 0
    }

    func rowCount(on sheet: Int) -> Int {
        Int(ceil(Double(gridCellCount(on: sheet)) / 25))
    }

    func markers(on sheet: Int, minimumWordCount: Int?) -> [Int] {
        guard let range = cellRange(on: sheet) else { return [] }
        return range.filter {
            $0.isMultiple(of: 100) || $0 == minimumWordCount || $0 == maximumCount || $0 == visibleCellCount
        }
    }

    private func cellRange(on sheet: Int) -> ClosedRange<Int>? {
        guard isGridEnabled, sheet >= 0, sheet < sheetCount else { return nil }
        let preceding = sheet * 600
        return (preceding + 1)...(preceding + min(600, visibleCellCount - preceding))
    }
}

enum ShenlunAnswerGridLayout {
    private static let numberingBoundaries = "。！？；：，、.!?;:,"

    static func project(answerText: String, maximumWordCount: Int?, isReview: Bool = false) -> ShenlunAnswerGridProjection {
        let maximum = maximumWordCount.flatMap { $0 > 0 ? $0 : nil }
        var row = 0
        var column = 0
        var occupiedCount = 0
        var fullRowBreakPending = false
        var atParagraphStart = true
        var canStartNumberedItem = true
        let characters = Array(answerText)
        var offset = 0
        var cells: [ShenlunAnswerGridCell] = []
        cells.reserveCapacity(characters.count)

        while offset < characters.count {
            let character = characters[offset]
            offset += 1
            if character.isNewline {
                atParagraphStart = true
                canStartNumberedItem = true
                if column > 0 {
                    row += 1
                    column = 0
                    fullRowBreakPending = false
                } else if fullRowBreakPending {
                    fullRowBreakPending = false
                } else {
                    row += 1
                }
                continue
            }

            if character == "。", !atParagraphStart,
               (fullRowBreakPending || characters.dropFirst(offset).prefix(while: { !$0.isNewline }).allSatisfy(\.isWhitespace)),
               let last = cells.indices.last,
               !cells[last].character.allSatisfy(\.isWhitespace), !cells[last].sharesCellWithFullStop {
                cells[last].sharesCellWithFullStop = true
                canStartNumberedItem = true
                continue
            }

            var value = String(character)
            let followsSpace = offset >= 2 && characters[offset - 2].isWhitespace
            if canStartNumberedItem || followsSpace,
               let end = numberingEnd(in: characters, after: offset, startingWith: character) {
                value += String(characters[offset...end])
                offset = end + 1
            }
            if !character.isWhitespace {
                atParagraphStart = false
                let dotFollowsDigit = (character == "." || character == "．") &&
                    offset >= 2 && isNumberingDigit(characters[offset - 2])
                canStartNumberedItem = numberingBoundaries.contains(character) && !dotFollowsDigit
            }
            let index = row * 25 + column + 1
            cells.append(ShenlunAnswerGridCell(index: index, character: value))
            occupiedCount = index
            column += 1
            if column == 25 {
                row += 1
                column = 0
                fullRowBreakPending = true
            } else {
                fullRowBreakPending = false
            }
        }

        return ShenlunAnswerGridProjection(
            cells: cells, occupiedCount: occupiedCount, maximumCount: maximum, isReview: isReview
        )
    }

    private static func isNumberingDigit(_ character: Character) -> Bool {
        "0123456789０１２３４５６７８９".contains(character)
    }

    private static func isChineseNumber(_ character: Character) -> Bool {
        "〇零一二三四五六七八九十百千".contains(character)
    }

    private static func numberingEnd(in characters: [Character], after offset: Int, startingWith first: Character) -> Int? {
        if isChineseNumber(first) {
            let end = characters[offset...].prefix(while: isChineseNumber).endIndex
            return end < characters.count && characters[end] == "、" ? end : nil
        }
        guard isNumberingDigit(first) else { return nil }
        let end = characters[offset...].prefix(while: isNumberingDigit).endIndex
        guard end < characters.count, [".", "．"].contains(characters[end]),
              end + 1 == characters.count || !isNumberingDigit(characters[end + 1]) else { return nil }
        return end
    }
}

enum ShenlunPDFPageSelectionPolicy {
    static func parse(_ text: String, pageCount: Int) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, pageCount > 0 else { return nil }
        var selected = Set<Int>()
        for component in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            let token = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            if bounds.count == 1 {
                guard let page = Int(bounds[0]), (1...pageCount).contains(page) else { return nil }
                selected.insert(page - 1)
            } else if bounds.count == 2,
                      let first = Int(bounds[0]), let last = Int(bounds[1]),
                      first > 0, first <= last, last <= pageCount {
                selected.formUnion((first...last).map { $0 - 1 })
            } else {
                return nil
            }
        }
        return selected.sorted()
    }
}
