import XCTest

private struct ReaderUITestContext {
    let app: XCUIApplication
    let paperID: String
    let materialID: String
    let questionID: String
}

final class QuestionBankReaderInteractionUITests: XCTestCase {
    @MainActor
    func testPracticeAnswerRevealsOnSelectionByDefaultAndLocksSelection() throws {
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

        let optionB = app.buttons["question-bank-option-\(reader.questionID)-B"].firstMatch
        XCTAssertFalse(optionB.isEnabled, "A revealed answer must lock the submitted selection")
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
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
        let confirmationOn = app.buttons["question-bank-confirm-answer-on"].firstMatch
        XCTAssertTrue(confirmationOn.waitForExistence(timeout: 5))
        confirmationOn.tap()
        let practiceChoice = app.buttons["question-bank-reading-mode-刷题"].firstMatch
        if practiceChoice.waitForExistence(timeout: 1) { practiceChoice.tap() }

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        let optionB = app.buttons["question-bank-option-\(reader.questionID)-B"].firstMatch
        optionA.tap()
        XCTAssertFalse(answerFeedback.exists, "Confirmation mode must wait for the confirm action")
        let confirm = app.buttons["question-bank-confirm-answer-\(reader.questionID)"].firstMatch
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertFalse(optionB.isEnabled, "The first choice must lock before answer confirmation")
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
        XCTAssertTrue(answerFeedback.label.contains("正确答案：B"))
        XCTAssertFalse(optionA.isEnabled, "A confirmed answer must lock the submitted selection")
        XCTAssertFalse(optionB.isEnabled, "A confirmed answer must lock the submitted selection")

        readerOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        XCTAssertTrue(answerFeedback.exists, "Confirmed state must follow the stable question ID")

        readerOptions.tap()
        app.buttons["question-bank-reading-mode-看题"].firstMatch.tap()
        readerOptions.tap()
        app.buttons["question-bank-reading-mode-刷题"].firstMatch.tap()
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))

        readerOptions.tap()
        XCTAssertTrue(element(app, identifier: "question-bank-confirm-answer-toggle").waitForExistence(timeout: 5))
    }

    @MainActor
    func testDoodleBlocksOptionSelectionAndQuestionNavigationInMaterialSplit() throws {
        let reader = launchPracticeReader(expectAutomaticMaterialSplit: true)
        let app = reader.app
        let closeSplit = app.buttons["question-bank-close-material-split"].firstMatch
        XCTAssertTrue(closeSplit.waitForExistence(timeout: 5), "Data-analysis entry should open its shared material on iPad")
        XCTAssertTrue(element(app, identifier: "question-bank-split-material-pane-\(reader.materialID)").exists)
        XCTAssertTrue(app.buttons["question-bank-option-\(reader.questionID)-A"].waitForExistence(timeout: 5))
        let splitScreenshot = XCTAttachment(screenshot: app.screenshot())
        splitScreenshot.name = "question-bank-data-analysis-shared-material"
        splitScreenshot.lifetime = .keepAlways
        add(splitScreenshot)
        closeSplit.tap()

        let presentationMenu = element(app, identifier: "question-bank-reader-options")
        presentationMenu.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        let optionFrame = optionA.frame
        let singleScroll = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        let position = element(app, identifier: "question-bank-single-position")
        XCTAssertEqual(position.label, "1/2")
        XCTAssertFalse(app.buttons["question-bank-single-next"].exists)
        XCTAssertFalse(app.buttons["question-bank-single-previous"].exists)

        let doodle = app.buttons["question-bank-doodle-current-question"].firstMatch
        XCTAssertTrue(doodle.waitForExistence(timeout: 5))
        doodle.tap()
        XCTAssertTrue(app.buttons["library-doodle-close"].waitForExistence(timeout: 5))

        let shield = element(app, identifier: "library-doodle-interaction-shield")
        XCTAssertTrue(shield.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, identifier: "question-bank-reader-options").exists)
        XCTAssertFalse(element(app, identifier: "question-bank-doodle-current-question").exists)
        XCTAssertFalse(element(app, identifier: "question-bank-number-overview").exists)
        XCTAssertTrue(optionA.isEnabled, "The interaction shield must not dim or disable option content")
        coordinate(in: app, at: optionFrame).tap()
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "canvas-ready"),
            object: shield
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let loadingIndicator = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "正在载入涂鸦")).firstMatch
        let loadingIndicatorDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: loadingIndicator
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadingIndicatorDismissed], timeout: 2), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "question-bank-doodle-overlay"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        coordinate(in: app, at: optionFrame).tap()
        let deckStart = singleScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let deckEnd = singleScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        deckStart.press(
            forDuration: 0.05,
            thenDragTo: deckEnd
        )
        XCTAssertEqual(position.label, "1/2", "Doodle mode must block page navigation")

        app.buttons["library-doodle-close"].tap()
        XCTAssertFalse(closeSplit.exists, "Doodle taps must not reopen or replace the closed split")
        XCTAssertEqual(position.label, "1/2", "Doodle taps must not advance to the next question")
        XCTAssertFalse(app.images["你的选择"].exists, "Doodle taps must not select an option")
    }

    @MainActor
    func testSingleQuestionHorizontalSwipesRetainSelectionAndReturnToTop() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["五、资料分析"].exists)
        XCTAssertFalse(app.staticTexts["1."].exists)

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        optionA.tap()
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))

        let scrollView = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["question-bank-single-next"].exists)
        XCTAssertFalse(app.buttons["question-bank-single-previous"].exists)
        scrollView.swipeLeft()
        let position = element(app, identifier: "question-bank-single-position")
        let secondQuestion = "\(reader.paperID)-question-2"
        let secondQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "2/2"),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [secondQuestionVisible], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["question-bank-option-\(secondQuestion)-A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["单项选择题"].exists)

        scrollView.swipeRight()
        let firstQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "1/2"),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstQuestionVisible], timeout: 5), .completed)
        XCTAssertTrue(answerFeedback.exists, "Returning to the prior question must restore its selected answer")
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
    }

    @MainActor
    func testMissingAnswerCanBeAddedOnlyFromItsQuestionOptions() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()

        let scrollView = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.swipeLeft()

        let secondQuestion = "\(reader.paperID)-question-2"
        let missingAnswerMenu = app.buttons["question-bank-missing-answer-\(secondQuestion)"].firstMatch
        XCTAssertTrue(missingAnswerMenu.waitForExistence(timeout: 5))
        if !missingAnswerMenu.isHittable { scrollView.swipeUp() }
        missingAnswerMenu.tap()
        let setAnswer = app.buttons["设为 C"].firstMatch
        XCTAssertTrue(setAnswer.waitForExistence(timeout: 5))
        setAnswer.tap()
        XCTAssertTrue(app.alerts["答案更新"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["答案更新"].label.contains("答案已补录为 C"))
        app.alerts.buttons["好"].tap()
        let missingAnswerActionDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: missingAnswerMenu
        )
        XCTAssertEqual(XCTWaiter.wait(for: [missingAnswerActionDismissed], timeout: 5), .completed)
    }

    @MainActor
    func testHomeSearchAndModuleFiltersStartCollapsedAndMatchNumberedModules() throws {
        let sessionID = UUID().uuidString
        let paperID = "ui-test-\(sessionID)-paper"
        let app = XCUIApplication()
        app.launchArguments = [
            "--question-bank-reader-ui-test",
            "--question-bank-reader-ui-test-session=\(sessionID)"
        ]
        app.launch()
        let tab = app.buttons["root-tab-questionBank"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()

        XCTAssertTrue(app.buttons["question-bank-paper-\(paperID)"].waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, identifier: "question-bank-search-field").exists)
        XCTAssertFalse(element(app, identifier: "question-bank-module-filter-all").exists)

        app.buttons["question-bank-search"].tap()
        XCTAssertTrue(element(app, identifier: "question-bank-search-field").waitForExistence(timeout: 5))
        app.buttons["question-bank-search"].tap()
        app.buttons["question-bank-filter-toggle"].tap()

        let dataAnalysisFilter = app.buttons["question-bank-module-filter-資料分析"].firstMatch
        XCTAssertTrue(dataAnalysisFilter.waitForExistence(timeout: 5))
        dataAnalysisFilter.tap()
        XCTAssertTrue(app.buttons["question-bank-paper-\(paperID)"].waitForExistence(timeout: 5))
        app.buttons["question-bank-module-filter-常识判断"].tap()
        XCTAssertFalse(app.buttons["question-bank-paper-\(paperID)"].exists)
    }

    @MainActor
    func testHomePaperRowSwipeRevealsDeleteActionWithoutOpeningPaper() throws {
        let sessionID = UUID().uuidString
        let paperID = "ui-test-\(sessionID)-paper"
        let app = XCUIApplication()
        app.launchArguments = [
            "--question-bank-reader-ui-test",
            "--question-bank-reader-ui-test-session=\(sessionID)"
        ]
        app.launch()
        let tab = app.buttons["root-tab-questionBank"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()

        let row = element(app, identifier: "question-bank-paper-\(paperID)")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let deleteAction = element(app, identifier: "question-bank-paper-delete-action")
        XCTAssertFalse(deleteAction.isHittable)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteAction.isHittable, "A completed right swipe should reveal the row action")
        XCTAssertTrue(app.navigationBars["真题库"].exists, "A horizontal row swipe must not activate the paper link")
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
        assertExactStemAndHiddenInternalType(in: app, questionID: reader.questionID)
        XCTAssertTrue(answerFeedback.exists)
        app.buttons["完成"].firstMatch.tap()

        app.buttons["question-bank-number-overview"].tap()
        app.buttons["卡片"].tap()
        let overviewDetail = app.buttons["question-bank-overview-detail-\(reader.questionID)"].firstMatch
        XCTAssertTrue(overviewDetail.waitForExistence(timeout: 5))
        overviewDetail.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用于检验共享材料分屏下的涂鸦命中区域。"].exists)
        assertExactStemAndHiddenInternalType(in: app, questionID: reader.questionID)
        XCTAssertTrue(answerFeedback.exists, "The overview detail must retain the selected option state")
    }

    @MainActor
    private func launchPracticeReader(expectAutomaticMaterialSplit: Bool = false) -> ReaderUITestContext {
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

        let automaticSplit = app.buttons["question-bank-close-material-split"].firstMatch
        XCTAssertTrue(automaticSplit.waitForExistence(timeout: 10), "The data-analysis module should reveal its shared-material group on iPad")
        if expectAutomaticMaterialSplit {
            XCTAssertTrue(element(app, identifier: "question-bank-split-material-pane-\(materialID)").exists)
        } else {
            automaticSplit.tap()
        }

        let readerOptions = element(app, identifier: "question-bank-reader-options")
        XCTAssertTrue(readerOptions.waitForExistence(timeout: 10))
        XCTAssertEqual(readerOptions.label, "阅读设置")
        XCTAssertFalse(app.staticTexts["连续 · 看题"].exists)
        XCTAssertTrue((readerOptions.value as? String)?.contains("答题方式：刷题") == true)
        XCTAssertTrue(app.buttons["question-bank-option-\(questionID)-A"].waitForExistence(timeout: 10))
        XCTAssertTrue((readerOptions.value as? String)?.contains("答题方式：刷题") == true)
        assertExactStemAndHiddenInternalType(in: app, questionID: questionID)
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
    private func assertExactStemAndHiddenInternalType(in app: XCUIApplication, questionID: String) {
        let stem = element(app, identifier: "question-bank-question-stem-\(questionID)")
        XCTAssertTrue(stem.waitForExistence(timeout: 5))
        XCTAssertEqual(stem.label, "下列哪项是本题正确答案？____并保留连续空位__。")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "纯文字")).firstMatch.exists
        )
    }

    @MainActor
    private func coordinate(in app: XCUIApplication, at frame: CGRect) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(
            dx: frame.midX / app.frame.width,
            dy: frame.midY / app.frame.height
        ))
    }
}
