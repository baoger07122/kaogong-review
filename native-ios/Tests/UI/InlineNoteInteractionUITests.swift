import XCTest

final class InlineNoteInteractionUITests: XCTestCase {
    @MainActor
    func testOneCharacterDoneAndTopAlignedEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let library = app.buttons["root-tab-library"]
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

        let placeholder = app.staticTexts["点击添加错题笔记"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
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

        XCTAssertTrue(app.staticTexts["错题详情"].waitForExistence(timeout: 5),
                      "Detail must survive saving a nonempty inline note")
    }
}
