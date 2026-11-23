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
        checkMaterialFormatting()
        print("PASS Shenlun answer grid, explicit PDF page selection, and copied material formatting")
    }

    private static func checkMaterialFormatting() {
        let copiedFromPDF = """
        “今年父母双双退休，父亲有高压电工证，母亲有执业药师证，退休后想
        找份相对轻松的
        工作。
        ”几个月前，小丁开始在社交平台上给退休的父母找工作。信息发布后引
        起了反响，有
        不少网友表示支持。
        33岁的小丁是一名律师，经常加班，她很羡慕退休后时间更加自由的父
        母，但父母都出
        现了不同程度的焦虑。
        """
        let expected = """
        “今年父母双双退休，父亲有高压电工证，母亲有执业药师证，退休后想找份相对轻松的工作。”几个月前，小丁开始在社交平台上给退休的父母找工作。信息发布后引起了反响，有不少网友表示支持。

        33岁的小丁是一名律师，经常加班，她很羡慕退休后时间更加自由的父母，但父母都出现了不同程度的焦虑。
        """
        let formatted = ShenlunMaterialTextFormatter.format(copiedFromPDF)
        precondition(formatted == expected, "word wraps and orphan closing quotes must join without merging the inferred paragraphs")
        precondition(ShenlunMaterialTextFormatter.format(formatted) == formatted, "formatted material should stay stable")

        let structured = "材料4\r\n　　第一段内容，\r\n跨行继续。\r\n\r\n第二段内容。\r\n（一）第一项\r\n接着说明。\r\n（二）第二项"
        let expectedStructure = "材料4\n\n第一段内容，跨行继续。\n\n第二段内容。\n\n（一）第一项接着说明。\n\n（二）第二项"
        precondition(ShenlunMaterialTextFormatter.format(structured) == expectedStructure,
                     "keep the heading, existing paragraph gaps and list starts")
        precondition(ShenlunMaterialTextFormatter.format("public\nservice\u{2029}下一段") == "public service\n\n下一段",
                     "retain word spacing and Unicode paragraph separators")
        precondition(ShenlunMaterialTextFormatter.format("无须整理的单段。") == "无须整理的单段。",
                     "preserve text with no line breaks")
    }
}
