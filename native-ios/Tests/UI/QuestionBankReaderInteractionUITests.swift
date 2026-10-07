import XCTest

private struct ReaderUITestContext {
    let app: XCUIApplication
    let paperID: String
    let materialID: String
    let questionID: String
}

final class QuestionBankReaderInteractionUITests: XCTestCase {
    @MainActor
    func testPracticeAnswerRevealsOnSelectionByDefaultAndFollowsSelection() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertFalse(answerFeedback.exists)

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        optionA.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
        XCTAssertTrue(answerFeedback.label.contains("正确答案：B"))
        XCTAssertFalse(app.buttons["question-bank-confirm-answer-\(reader.questionID)"].exists)

        app.buttons["question-bank-option-\(reader.questionID)-B"].tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：B"))
    }

    @MainActor
    func testPracticeAnswerConfirmationTogglePersistsAcrossReaderModeChanges() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        let confirmationToggle = element(app, identifier: "question-bank-confirm-answer-toggle")
        XCTAssertTrue(confirmationToggle.waitForExistence(timeout: 5))
        confirmationToggle.tap()
        let practiceChoice = app.buttons["刷题"].firstMatch
        if practiceChoice.waitForExistence(timeout: 1) { practiceChoice.tap() }

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        let optionB = app.buttons["question-bank-option-\(reader.questionID)-B"].firstMatch
        optionA.tap()
        XCTAssertFalse(answerFeedback.exists, "Confirmation mode must wait for the confirm action")
        let confirm = app.buttons["question-bank-confirm-answer-\(reader.questionID)"].firstMatch
        XCTAssertTrue(confirm.isEnabled)
        optionB.tap()
        XCTAssertFalse(answerFeedback.exists, "Changing the selection before confirmation must keep the answer hidden")
        confirm.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：B"))

        readerOptions.tap()
        app.buttons["单题模式"].firstMatch.tap()
        XCTAssertTrue(answerFeedback.exists, "Confirmed state must follow the stable question ID")

        readerOptions.tap()
        app.buttons["看题"].firstMatch.tap()
        readerOptions.tap()
        app.buttons["刷题"].firstMatch.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：B"))

        readerOptions.tap()
        XCTAssertTrue(element(app, identifier: "question-bank-confirm-answer-toggle").waitForExistence(timeout: 5))
    }

    @MainActor
    func testDoodleBlocksOptionSelectionAndQuestionNavigationInMaterialSplit() throws {
        let reader = launchPracticeReader()
        let app = reader.app

        let presentationMenu = element(app, identifier: "question-bank-reader-options")
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
        XCTAssertTrue(optionA.isEnabled, "The interaction shield must not dim or disable option content")
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
        XCTAssertFalse(app.images["你的选择"].exists, "Doodle taps must not select an option")
    }

    @MainActor
    func testSingleQuestionHorizontalSwipesRetainSelectionAndReturnToTop() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        app.buttons["单题模式"].firstMatch.tap()

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        optionA.tap()
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.swipeLeft()
        let position = element(app, identifier: "question-bank-single-position")
        let secondQuestion = "\(reader.paperID)-question-2"
        let secondQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "第2题"),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [secondQuestionVisible], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["question-bank-option-\(secondQuestion)-A"].waitForExistence(timeout: 5))

        scrollView.swipeRight()
        let firstQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "第1题"),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstQuestionVisible], timeout: 5), .completed)
        XCTAssertTrue(answerFeedback.exists, "Returning to the prior question must restore its selected answer")
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
    }

    @MainActor
    func testQuestionDetailOpensFromContinuousCardAndOverviewCard() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        app.buttons["question-bank-option-\(reader.questionID)-A"].tap()
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))

        let continuousDetail = app.buttons["question-bank-question-detail-\(reader.questionID)"].firstMatch
        XCTAssertTrue(continuousDetail.waitForExistence(timeout: 5))
        continuousDetail.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用于检验共享材料分屏下的涂鸦命中区域。"].exists)
        XCTAssertTrue(answerFeedback.exists)
        app.buttons["完成"].firstMatch.tap()

        app.buttons["question-bank-number-overview"].tap()
        app.buttons["卡片"].tap()
        let overviewDetail = app.buttons["question-bank-overview-detail-\(reader.questionID)"].firstMatch
        XCTAssertTrue(overviewDetail.waitForExistence(timeout: 5))
        overviewDetail.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用于检验共享材料分屏下的涂鸦命中区域。"].exists)
        XCTAssertTrue(answerFeedback.exists, "The overview detail must retain the selected option state")
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

        let readerOptions = element(app, identifier: "question-bank-reader-options")
        XCTAssertTrue(readerOptions.waitForExistence(timeout: 10))
        readerOptions.tap()
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
