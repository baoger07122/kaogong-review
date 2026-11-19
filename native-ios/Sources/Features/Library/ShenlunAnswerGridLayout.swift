import Foundation

struct ShenlunAnswerGridCell: Equatable, Sendable {
    var index: Int
    var character: String

    var pageIndex: Int { max(0, index - 1) / 600 }
    var row: Int { (max(0, index - 1) % 600) / 25 }
    var column: Int { max(0, index - 1) % 25 }
}

struct ShenlunAnswerGridProjection: Equatable, Sendable {
    var cells: [ShenlunAnswerGridCell]
    var occupiedCount: Int
    var maximumCount: Int?

    var isGridEnabled: Bool { maximumCount != nil }
    var visibleCellCount: Int { maximumCount ?? 0 }
    var sheetCount: Int { max(1, Int(ceil(Double(maximumCount ?? 0) / 600))) }
    var overflowCount: Int { max(0, occupiedCount - (maximumCount ?? occupiedCount)) }

    func visibleCells(on sheet: Int) -> [ShenlunAnswerGridCell] {
        let lowerBound = sheet * 600 + 1
        let upperBound = min((sheet + 1) * 600, maximumCount ?? 0)
        guard lowerBound <= upperBound else { return [] }
        return cells.filter { (lowerBound...upperBound).contains($0.index) }
    }

    func gridCellCount(on sheet: Int) -> Int {
        let lowerBound = sheet * 600 + 1
        return max(0, min(600, (maximumCount ?? 0) - lowerBound + 1))
    }

    func rowCount(on sheet: Int) -> Int {
        Int(ceil(Double(gridCellCount(on: sheet)) / 25))
    }

    func markers(on sheet: Int, minimumWordCount: Int?) -> [Int] {
        let lowerBound = sheet * 600 + 1
        let upperBound = min((sheet + 1) * 600, maximumCount ?? 0)
        guard lowerBound <= upperBound else { return [] }
        let rulers = stride(from: 100, through: upperBound, by: 100).filter { $0 >= lowerBound }
        return Array(Set(rulers + [minimumWordCount, maximumCount].compactMap { $0 }.filter { (lowerBound...upperBound).contains($0) })).sorted()
    }
}

enum ShenlunAnswerGridLayout {
    static func project(answerText: String, maximumWordCount: Int?) -> ShenlunAnswerGridProjection {
        let maximum = maximumWordCount.flatMap { $0 > 0 ? $0 : nil }
        var row = 0
        var column = 0
        var occupiedCount = 0
        var fullRowBreakPending = false
        var cells: [ShenlunAnswerGridCell] = []
        cells.reserveCapacity(answerText.count)

        for character in answerText {
            let value = String(character)
            if value == "\n" || value == "\r" || value == "\r\n" {
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

        return ShenlunAnswerGridProjection(cells: cells, occupiedCount: occupiedCount, maximumCount: maximum)
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
