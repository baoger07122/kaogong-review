import XCTest

private struct ReaderUITestContext {
    let app: XCUIApplication
    let paperID: String
    let materialID: String
    let questionID: String
}

final class QuestionBankReaderInteractionUITests: XCTestCase {
    @MainActor
    func testPracticeAnswerWaitsForConfirmationAndSurvivesReaderModeChanges() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertFalse(answerFeedback.exists)

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        optionA.tap()
        XCTAssertFalse(answerFeedback.exists, "Selecting an option must not reveal the answer")

        let confirm = app.buttons["question-bank-confirm-answer-\(reader.questionID)"].firstMatch
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
        XCTAssertTrue(answerFeedback.label.contains("正确答案：B"))

        let presentationMenu = element(app, identifier: "question-bank-presentation-mode")
        presentationMenu.tap()
        app.buttons["单题模式"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["question-bank-single-position"].waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.exists, "Revealed state must follow the stable question ID")

        let readingMenu = element(app, identifier: "question-bank-reading-mode")
        readingMenu.tap()
        app.buttons["看题"].firstMatch.tap()
        readingMenu.tap()
        app.buttons["刷题"].firstMatch.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
    }

    @MainActor
    func testDoodleBlocksOptionSelectionAndQuestionNavigationInMaterialSplit() throws {
        let reader = launchPracticeReader()
        let app = reader.app

        let presentationMenu = element(app, identifier: "question-bank-presentation-mode")
        presentationMenu.tap()
        app.buttons["单题模式"].firstMatch.tap()
        let materialEntry = app.buttons["question-bank-single-material-\(reader.materialID)"].firstMatch
        XCTAssertTrue(materialEntry.waitForExistence(timeout: 5))
        materialEntry.tap()

        let closeSplit = app.buttons["question-bank-close-material-split"].firstMatch
        XCTAssertTrue(closeSplit.waitForExistence(timeout: 5), "The iPad fixture should open the shared-material split")
        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        let nextQuestion = app.buttons["question-bank-single-next"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        XCTAssertTrue(nextQuestion.waitForExistence(timeout: 5))
        let optionFrame = optionA.frame
        let nextFrame = nextQuestion.frame

        let doodle = app.buttons["question-bank-doodle-current-question"].firstMatch
        XCTAssertTrue(doodle.waitForExistence(timeout: 5))
        doodle.tap()
        XCTAssertTrue(app.buttons["library-doodle-close"].waitForExistence(timeout: 5))

        let shield = element(app, identifier: "library-doodle-interaction-shield")
        XCTAssertTrue(shield.waitForExistence(timeout: 5))
        coordinate(in: app, at: optionFrame).tap()
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "canvas-ready"),
            object: shield
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        coordinate(in: app, at: optionFrame).tap()
        coordinate(in: app, at: nextFrame).tap()

        app.buttons["library-doodle-close"].tap()
        XCTAssertTrue(closeSplit.waitForExistence(timeout: 5), "Doodle taps must not close or replace the split")
        XCTAssertTrue(app.buttons["question-bank-single-next"].exists)
        let position = element(app, identifier: "question-bank-single-position")
        XCTAssertTrue(position.label.contains("第1题"), "Doodle taps must not advance to the next question")
        let confirm = app.buttons["question-bank-confirm-answer-\(reader.questionID)"].firstMatch
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled, "Doodle taps must not select an option")
    }

    @MainActor
    private func launchPracticeReader() -> ReaderUITestContext {
        let sessionID = UUID().uuidString
        let paperID = "ui-test-\(sessionID)-paper"
        let moduleID = "ui-test-\(sessionID)-module"
        let materialID = "ui-test-\(sessionID)-material"
        let questionID = "ui-test-\(sessionID)-question-1"
        let app = XCUIApplication()
        app.launchArguments = [
            "--question-bank-reader-ui-test",
            "--question-bank-reader-ui-test-session=\(sessionID)"
        ]
        app.launch()
        let tab = app.buttons["root-tab-questionBank"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()

        let paper = app.buttons["question-bank-paper-\(paperID)"].firstMatch
        XCTAssertTrue(paper.waitForExistence(timeout: 10))
        paper.tap()

        let module = app.buttons["question-bank-module-\(moduleID)"].firstMatch
        XCTAssertTrue(module.waitForExistence(timeout: 10))
        module.tap()

        let readingMode = element(app, identifier: "question-bank-reading-mode")
        XCTAssertTrue(readingMode.waitForExistence(timeout: 10))
        readingMode.tap()
        app.buttons["刷题"].firstMatch.tap()
        XCTAssertTrue(app.buttons["question-bank-option-\(questionID)-A"].waitForExistence(timeout: 10))
        return ReaderUITestContext(
            app: app,
            paperID: paperID,
            materialID: materialID,
            questionID: questionID
        )
    }

    @MainActor
    private func element(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func coordinate(in app: XCUIApplication, at frame: CGRect) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(
            dx: frame.midX / app.frame.width,
            dy: frame.midY / app.frame.height
        ))
    }
}
