import Foundation

@main
enum ShenlunWorkspaceBehavior {
    static func main() {
        for (limit, expectedRows) in [(250, 10), (300, 12), (450, 18)] {
            let projection = ShenlunAnswerGridLayout.project(answerText: "", maximumWordCount: limit)
            precondition(projection.sheetCount == 1, "(limit) cells should fit on one sheet")
            precondition(projection.rowCount(on: 0) == expectedRows, "(limit) cells should produce (expectedRows) rows")
        }

        let partial = ShenlunAnswerGridLayout.project(answerText: "", maximumWordCount: 257)
        precondition(partial.gridCellCount(on: 0) == 257 && partial.rowCount(on: 0) == 11,
                     "a 257-cell limit should leave only seven cells on its last row")

        let wrapped = ShenlunAnswerGridLayout.project(answerText: "甲，乙。\n两个字符", maximumWordCount: 300)
        precondition(wrapped.occupiedCount == 29, "newline should skip the unused tail of the first row when later text exists")
        precondition(wrapped.cells.map(\.index) == [1, 2, 3, 4, 26, 27, 28, 29], "characters after a line break should begin at the next 25-column row")

        let exactRow = ShenlunAnswerGridLayout.project(answerText: String(repeating: "字", count: 25) + "\n后", maximumWordCount: 100)
        precondition(exactRow.cells.last?.index == 26, "a return after a full row must not insert an extra blank row")
        let blankLine = ShenlunAnswerGridLayout.project(answerText: "甲\n\n乙", maximumWordCount: 100)
        precondition(blankLine.cells.last?.index == 51, "an explicit blank paragraph should skip one additional row")
        let trailingReturn = ShenlunAnswerGridLayout.project(answerText: "甲\n", maximumWordCount: 100)
        precondition(trailingReturn.occupiedCount == 1, "a trailing newline must not inflate the occupied count")
        let spaces = ShenlunAnswerGridLayout.project(answerText: "a b", maximumWordCount: 100)
        precondition(spaces.occupiedCount == 3 && spaces.cells[1].character == " ", "an explicit space should occupy a cell even though drawing may leave it blank")

        let overflow = ShenlunAnswerGridLayout.project(answerText: String(repeating: "字", count: 260), maximumWordCount: 257)
        precondition(overflow.occupiedCount == 260 && overflow.overflowCount == 3,
                     "input beyond the upper bound must stay intact and expose the overflow count")
        let twoSheets = ShenlunAnswerGridLayout.project(answerText: "", maximumWordCount: 1_200)
        precondition(twoSheets.sheetCount == 2 && twoSheets.gridCellCount(on: 0) == 600 && twoSheets.gridCellCount(on: 1) == 600,
                     "a 1,200-cell upper limit should use two full 600-cell sheets")
        let secondSheetMarkers = twoSheets.markers(on: 1, minimumWordCount: 1_000)
        precondition(secondSheetMarkers == [700, 800, 900, 1_000, 1_100, 1_200],
                     "the second sheet should mark each 100-cell ruler plus the 1,000 lower and 1,200 upper bounds")

        precondition(ShenlunPDFPageSelectionPolicy.parse("1-3,5,3", pageCount: 7) == [0, 1, 2, 4],
                     "PDF range selection should preserve selected page order and remove repeated pages")
        for invalid in ["", "0", "1-0", "4-2", "1,", "1-8"] {
            precondition(ShenlunPDFPageSelectionPolicy.parse(invalid, pageCount: 7) == nil,
                         "invalid PDF page range (invalid) must be rejected")
        }
        print("PASS Shenlun answer grid indexing, limits, line breaks, overflow, and explicit PDF page selection")
    }
}
