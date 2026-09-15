import XCTest

final class InlineNoteCrashUITests: XCTestCase {
    @MainActor
    func testOneCharacterThenDoneKeepsAppAlive() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let library = app.buttons["root-tab-library"]
        XCTAssertTrue(library.waitForExistence(timeout: 15), "Library tab did not appear")
        library.tap()

        let add = app.buttons["新增错题"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Add-error button did not appear")
        add.tap()

        let question = app.textViews.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 10), "Question editor did not appear")
        question.tap()
        question.typeText("模拟排查题干")

        let save = app.buttons["保存"]
        XCTAssertTrue(save.isEnabled, "Minimal question should be saveable")
        save.tap()

        let placeholder = app.staticTexts["点击添加错题笔记"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10), "Saved error detail did not appear")
        placeholder.tap()

        let note = app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "Inline rich-text editor did not appear")
        note.tap()
        note.typeText("我")

        let done = app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Inline note Done button did not appear")
        done.tap()

        XCTAssertTrue(app.staticTexts["错题详情"].waitForExistence(timeout: 5),
                      "App terminated or detail vanished immediately after saving one character")
    }
}
