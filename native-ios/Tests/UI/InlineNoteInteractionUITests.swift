import XCTest

final class InlineNoteInteractionUITests: XCTestCase {
    @MainActor
    func testOneCharacterDoneAndTopAlignedEditor() throws {
        continueAfterFailure = false
        let app = openQuestionWithEmptyNote()
        let placeholder = app.staticTexts["点击添加错题笔记"]
        let firstLineY = placeholder.frame.minY
        placeholder.tap()

        let note = app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertLessThan(abs(note.frame.minY - firstLineY), 70,
                          "Empty note editor must start near the first line, not in the middle of its canvas")
        note.tap()
        note.typeText("我")
        let done = app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let status = app.staticTexts["library-inline-note-save-status"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "已保存"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed,
                       "Done must write the note to the record, rather than only retaining a draft")
        XCTAssertTrue(app.staticTexts["错题详情"].waitForExistence(timeout: 5),
                      "Detail must survive saving a nonempty inline note")
    }

    @MainActor
    func testTableArrowsKeepInputAndPlaceCaretAtEnd() {
        continueAfterFailure = false
        let app = openQuestionWithEmptyNote()
        app.staticTexts["点击添加错题笔记"].tap()

        let insert = app.buttons["插入"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        insert.tap()
        app.buttons["表格"].tap()

        let first = app.textViews["第 1 行第 1 列"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.typeText("c")
        XCTAssertEqual((first.value as? String)?.lowercased(), "c")

        let down = app.buttons["下一行单元格"]
        XCTAssertTrue(down.waitForExistence(timeout: 5))
        XCTAssertTrue(down.isEnabled)
        down.tap()
        let second = app.textViews["第 2 行第 1 列"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.typeText("乙")

        app.buttons["上一行单元格"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.typeText("x")
        XCTAssertEqual((first.value as? String)?.lowercased(), "cx")
        app.buttons["下一行单元格"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertEqual(second.value as? String, "乙")
    }

    @MainActor
    func testBackspaceExitsEmptyListWithoutRemovingPreviousParagraph() {
        continueAfterFailure = false
        let app = openQuestionWithEmptyNote()
        app.staticTexts["点击添加错题笔记"].tap()
        let note = app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.typeText("甲\n")

        let bullets = app.buttons["无序列表"].firstMatch
        XCTAssertTrue(bullets.waitForExistence(timeout: 5))
        bullets.tap()
        XCTAssertTrue((note.value as? String)?.contains("•") == true)
        note.typeText(XCUIKeyboardKey.delete.rawValue)
        note.typeText("乙")
        XCTAssertEqual(note.value as? String, "甲\n乙")
    }

    @MainActor
    func testSingleTapMovesNoteCaret() {
        continueAfterFailure = false
        let app = openQuestionWithEmptyNote()
        app.staticTexts["点击添加错题笔记"].tap()
        let note = app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.typeText("乙")
        note.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 2, dy: 10)).tap()
        note.typeText("甲")
        XCTAssertEqual(note.value as? String, "甲乙")
    }

    @MainActor
    private func openQuestionWithEmptyNote() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let library = app.buttons["root-tab-library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        library.tap()

        let add = app.buttons["新增错题"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let question = app.textViews.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        question.tap()
        question.typeText("模拟排查题干")
        let save = app.buttons["保存"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["点击添加错题笔记"].waitForExistence(timeout: 10))
        return app
    }
}
