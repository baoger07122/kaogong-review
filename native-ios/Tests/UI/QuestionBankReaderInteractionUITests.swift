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
    func testReaderOptionsMenuTogglesAndClosesOnOutsideTap() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        let tip = app.staticTexts["设置会立即应用到当前题目。"].firstMatch

        readerOptions.tap()
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        readerOptions.tap()
        let toggledClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: tip
        )
        XCTAssertEqual(XCTWaiter.wait(for: [toggledClosed], timeout: 3), .completed)

        readerOptions.tap()
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        element(app, identifier: "question-bank-question-stem-\(reader.questionID)").tap()
        let outsideTapClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: tip
        )
        XCTAssertEqual(XCTWaiter.wait(for: [outsideTapClosed], timeout: 3), .completed)
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

        let continuousDoodle = app.buttons["question-bank-doodle-question-\(reader.questionID)"].firstMatch
        XCTAssertTrue(continuousDoodle.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, identifier: "question-bank-doodle-current-question").exists)
        let continuousScroll = app.scrollViews["question-bank-continuous-scroll"].firstMatch
        XCTAssertTrue(continuousScroll.waitForExistence(timeout: 5))
        let continuousStem = element(app, identifier: "question-bank-question-stem-\(reader.questionID)")
        let continuousOption = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(continuousStem.waitForExistence(timeout: 5))
        XCTAssertTrue(continuousOption.waitForExistence(timeout: 5))
        let continuousStemY = continuousStem.frame.minY
        continuousDoodle.tap()
        XCTAssertTrue(app.buttons["library-doodle-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, identifier: "question-bank-doodle-current-question").exists)
        let continuousCanvas = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library-doodle-content-layer-")
        ).firstMatch
        XCTAssertTrue(continuousCanvas.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(continuousCanvas.frame.minY, continuousStem.frame.minY)
        XCTAssertGreaterThanOrEqual(continuousCanvas.frame.maxY, continuousOption.frame.maxY)
        continuousScroll.swipeUp()
        XCTAssertLessThanOrEqual(
            abs(continuousStem.frame.minY - continuousStemY),
            2,
            "The full-page doodle layer must keep the continuous reader from scrolling"
        )
        app.buttons["library-doodle-close"].tap()

        let presentationMenu = element(app, identifier: "question-bank-reader-options")
        presentationMenu.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(optionA.waitForExistence(timeout: 5))
        let optionFrame = optionA.frame
        let singleScroll = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        let position = element(app, identifier: "question-bank-single-position")
        XCTAssertTrue(position.label.contains("1/2"))
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
        let wholePageCanvas = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library-doodle-content-layer-")
        ).firstMatch
        XCTAssertTrue(wholePageCanvas.waitForExistence(timeout: 5))
        let materialText = app.staticTexts["用于检验共享材料分屏下的涂鸦命中区域。"].firstMatch
        XCTAssertTrue(materialText.exists)
        XCTAssertLessThanOrEqual(wholePageCanvas.frame.minY, materialText.frame.minY)
        XCTAssertGreaterThanOrEqual(wholePageCanvas.frame.maxY, optionFrame.maxY)
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
        XCTAssertTrue(position.label.contains("1/2"), "Doodle mode must block page navigation")

        app.buttons["library-doodle-close"].tap()
        XCTAssertFalse(closeSplit.exists, "Doodle taps must not reopen or replace the closed split")
        XCTAssertTrue(position.label.contains("1/2"), "Doodle taps must not advance to the next question")
        XCTAssertFalse(app.images["你的选择"].exists, "Doodle taps must not select an option")
    }

    @MainActor
    func testSingleQuestionHorizontalSwipesRetainSelectionAndReturnToTop() throws {
        let reader = launchPracticeReader(longContent: true)
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["五、资料分析"].exists)
        XCTAssertFalse(app.staticTexts["1."].exists)

        XCTAssertFalse(app.buttons["question-bank-single-next"].exists)
        XCTAssertFalse(app.buttons["question-bank-single-previous"].exists)

        let scrollView = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        let longMaterial = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "长材料用于验证单题模式保留纵向阅读")
        ).firstMatch
        XCTAssertTrue(longMaterial.waitForExistence(timeout: 5))
        let materialAtTop = longMaterial.frame.minY
        scrollView.swipeUp()
        XCTAssertLessThan(longMaterial.frame.minY, materialAtTop, "Long material must remain vertically readable")
        let stem = element(app, identifier: "question-bank-question-stem-\(reader.questionID)")
        XCTAssertTrue(stem.waitForExistence(timeout: 5))
        let stemAtTop = stem.frame.minY
        scrollView.swipeUp()
        XCTAssertTrue(stem.isHittable, "Long question stem should remain vertically readable in single mode")
        XCTAssertLessThan(stem.frame.minY, stemAtTop)

        let stemBeforeDiagonalDrag = stem.frame.minY
        let diagonalStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.50))
        let diagonalEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.51))
        diagonalStart.press(forDuration: 0.05, thenDragTo: diagonalEnd)
        let position = element(app, identifier: "question-bank-single-position")
        XCTAssertTrue(position.label.contains("1/2"), "A short diagonal drag should rebound on the same page")
        XCTAssertLessThanOrEqual(
            abs(stem.frame.minY - stemBeforeDiagonalDrag),
            2,
            "A horizontal drag must not move page content vertically"
        )

        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        if !optionA.isHittable { scrollView.swipeUp() }
        XCTAssertTrue(optionA.isHittable)
        optionA.tap()
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))

        scrollView.swipeLeft()
        let secondQuestion = "\(reader.paperID)-question-2"
        let secondQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "2/2"),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [secondQuestionVisible], timeout: 5), .completed)
        let secondOption = app.buttons["question-bank-option-\(secondQuestion)-A"].firstMatch
        XCTAssertTrue(secondOption.waitForExistence(timeout: 5))
        let secondStem = element(app, identifier: "question-bank-question-stem-\(secondQuestion)")
        XCTAssertTrue(secondStem.waitForExistence(timeout: 5))
        XCTAssertEqual(secondStem.label, "用于检查涂鸦状态下不能跳到下一题。")
        XCTAssertFalse(stem.exists, "The outgoing question must leave the accessible page after a left swipe")
        XCTAssertFalse(app.staticTexts["单项选择题"].exists, "Question type labels are hidden in the reader")
        if !secondOption.isHittable { scrollView.swipeUp() }
        XCTAssertTrue(secondOption.isHittable, "A long single-mode page must still scroll to its options")

        position.tap()
        XCTAssertTrue(app.navigationBars["第2题详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["单项选择题"].exists, "Question type data remains visible in question details")
        app.buttons["完成"].firstMatch.tap()

        scrollView.swipeRight()
        let firstQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "1/2"),
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstQuestionVisible], timeout: 5), .completed)
        XCTAssertTrue(stem.exists, "The previous question must be restored after a right swipe")
        XCTAssertFalse(secondStem.exists, "The outgoing question must leave the accessible page after a right swipe")
        XCTAssertTrue(answerFeedback.exists, "Returning to the prior question must restore its selected answer")
        XCTAssertTrue(answerFeedback.label.contains("你的选择：A"))
    }

    @MainActor
    func testLeftEdgeSwipeRemainsAvailableForNavigationBack() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        XCTAssertTrue(element(app, identifier: "question-bank-single-position").waitForExistence(timeout: 5))

        let edgeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let swipeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        edgeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)

        XCTAssertTrue(
            app.buttons["question-bank-module-\(reader.paperID.replacingOccurrences(of: "-paper", with: "-module"))"]
                .waitForExistence(timeout: 6),
            "The system back gesture should keep priority at the left edge"
        )
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
        let confirmationMessage = app.alerts["答案更新"].staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "答案已补录为 C"))
            .firstMatch
        XCTAssertTrue(confirmationMessage.waitForExistence(timeout: 5))
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
        let longTitlePaper = element(app, identifier: "question-bank-paper-\(paperID)")
        let compactPaper = element(app, identifier: "question-bank-paper-ui-test-\(sessionID)-compact-paper")
        XCTAssertTrue(compactPaper.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            longTitlePaper.frame.height,
            compactPaper.frame.height + 5,
            "A two-line paper title should make its capsule taller than a one-line title"
        )
        XCTAssertFalse(element(app, identifier: "question-bank-import").exists)
        let managementMenu = element(app, identifier: "question-bank-management-menu")
        managementMenu.tap()
        let importAction = element(app, identifier: "question-bank-import")
        XCTAssertTrue(importAction.waitForExistence(timeout: 5), "Import should remain available from the top-right menu")
        XCTAssertEqual(importAction.label, "导入真题包")
        app.buttons["清除筛选"].tap()
        XCTAssertFalse(element(app, identifier: "question-bank-search-field").exists)
        XCTAssertFalse(element(app, identifier: "question-bank-module-filter-all").exists)

        app.buttons["question-bank-search"].tap()
        XCTAssertTrue(element(app, identifier: "question-bank-search-field").waitForExistence(timeout: 5))
        app.buttons["question-bank-search"].tap()
        app.buttons["question-bank-filter-toggle"].tap()

        let dataAnalysisFilter = app.buttons["question-bank-module-filter-资料分析"].firstMatch
        XCTAssertTrue(dataAnalysisFilter.waitForExistence(timeout: 5))
        dataAnalysisFilter.tap()
        let paperRow = app.buttons["question-bank-paper-\(paperID)"].firstMatch
        XCTAssertTrue(paperRow.waitForExistence(timeout: 5))
        managementMenu.tap()
        app.buttons["清除筛选"].tap()
        let unfilteredPaperRow = app.buttons["question-bank-paper-\(paperID)"].firstMatch
        XCTAssertTrue(unfilteredPaperRow.waitForExistence(timeout: 5))
        unfilteredPaperRow.tap()
        let localFilterToggle = element(app, identifier: "question-bank-paper-filter-toggle")
        XCTAssertTrue(localFilterToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, identifier: "question-bank-paper-filter-panel").exists)
        XCTAssertFalse(app.textFields["题号"].exists, "Paper management must not add a local question-number field")
        localFilterToggle.tap()
        XCTAssertTrue(element(app, identifier: "question-bank-paper-filter-panel").waitForExistence(timeout: 5))
        let localModuleFilter = app.buttons["本卷模块筛选：全部模块"].firstMatch
        XCTAssertTrue(localModuleFilter.waitForExistence(timeout: 5))
        localModuleFilter.tap()
        let dataAnalysisModule = app.buttons["五、资料分析"].firstMatch
        XCTAssertTrue(dataAnalysisModule.waitForExistence(timeout: 5))
        dataAnalysisModule.tap()
        XCTAssertTrue(app.buttons["本卷模块筛选：五、资料分析"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
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
    func testQuestionDetailOpensFromContinuousNumberAndSingleProgress() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let continuousScroll = app.scrollViews["question-bank-continuous-scroll"].firstMatch
        XCTAssertTrue(continuousScroll.waitForExistence(timeout: 5))
        let question2ID = "\(reader.paperID)-question-2"
        if !app.buttons["question-bank-doodle-question-\(question2ID)"].isHittable {
            continuousScroll.swipeUp()
        }
        XCTAssertTrue(app.buttons["question-bank-doodle-question-\(question2ID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["单项选择题"].exists, "Continuous reading hides the stored question type label")
        continuousScroll.swipeDown()
        app.buttons["question-bank-option-\(reader.questionID)-A"].tap()
        let answerFeedback = app.descendants(matching: .any)
            .matching(identifier: "question-bank-answer-feedback-\(reader.questionID)").firstMatch
        XCTAssertTrue(answerFeedback.waitForExistence(timeout: 5))

        let continuousDetail = app.buttons["question-bank-question-detail-\(reader.questionID)"].firstMatch
        XCTAssertTrue(continuousDetail.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, identifier: "question-bank-provenance-disclosure-题目来源").exists)
        continuousDetail.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用于检验共享材料分屏下的涂鸦命中区域。"].exists)
        XCTAssertTrue(element(app, identifier: "question-bank-provenance-disclosure-题目来源").exists)
        assertExactStemAndHiddenInternalType(in: app, questionID: reader.questionID)
        XCTAssertTrue(answerFeedback.exists)
        app.buttons["完成"].firstMatch.tap()

        app.buttons["question-bank-number-overview"].tap()
        app.buttons["卡片"].tap()
        XCTAssertFalse(app.buttons["question-bank-overview-detail-\(reader.questionID)"].exists)
        let overviewItem = app.buttons["question-bank-overview-item-\(reader.questionID)"].firstMatch
        XCTAssertTrue(overviewItem.waitForExistence(timeout: 5))
        overviewItem.tap()

        let singlePosition = app.buttons["question-bank-single-position"].firstMatch
        XCTAssertTrue(singlePosition.waitForExistence(timeout: 5))
        XCTAssertTrue(singlePosition.label.contains("1/2"))
        singlePosition.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用于检验共享材料分屏下的涂鸦命中区域。"].exists)
        assertExactStemAndHiddenInternalType(in: app, questionID: reader.questionID)
        XCTAssertTrue(answerFeedback.exists, "Switching presentation must retain the selected answer")
    }

    @MainActor
    func testQuestionDetailTextEditorKeepsNewlinesAndUpdatesSearchIndex() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        app.buttons["question-bank-question-detail-\(reader.questionID)"].tap()
        XCTAssertTrue(app.buttons["question-bank-edit-question"].waitForExistence(timeout: 5))
        app.buttons["question-bank-edit-question"].tap()

        let stemEditor = element(app, identifier: "question-bank-edit-stem")
        XCTAssertTrue(stemEditor.waitForExistence(timeout: 5))
        stemEditor.tap()
        stemEditor.typeText("\nEDITLINEONE\n\nEDITLINETHREE")
        let optionEditor = element(app, identifier: "question-bank-edit-option-A")
        XCTAssertTrue(optionEditor.waitForExistence(timeout: 5))
        optionEditor.tap()
        optionEditor.typeText("\nOPTIONLINEONE\n\nOPTIONLINETHREE")
        app.buttons["question-bank-save-question-text"].tap()

        let renderedStem = element(app, identifier: "question-bank-question-stem-\(reader.questionID)")
        XCTAssertTrue(renderedStem.waitForExistence(timeout: 5))
        XCTAssertTrue(renderedStem.label.contains("EDITLINEONE"))
        XCTAssertTrue(renderedStem.label.contains("EDITLINETHREE"))
        let renderedOption = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        XCTAssertTrue(renderedOption.waitForExistence(timeout: 5))
        XCTAssertTrue(renderedOption.label.contains("OPTIONLINETHREE"))

        app.buttons["完成"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let searchButton = element(app, identifier: "question-bank-search")
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()
        let searchField = element(app, identifier: "question-bank-search-field")
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("EDITLINETHREE")
        XCTAssertTrue(
            app.buttons["question-bank-paper-\(reader.paperID)"].waitForExistence(timeout: 5),
            "The saved multiline text should be present in the question search index"
        )
    }

    @MainActor
    func testCrossPaperRedoUsesSharedStableAnswerStateAndClearsCurrentGroup() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let optionA = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        optionA.tap()
        let moduleFeedback = element(app, identifier: "question-bank-answer-feedback-\(reader.questionID)")
        XCTAssertTrue(moduleFeedback.waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["question-bank-filter-toggle"].tap()
        let dataAnalysis = app.buttons["question-bank-module-filter-资料分析"].firstMatch
        XCTAssertTrue(dataAnalysis.waitForExistence(timeout: 5))
        dataAnalysis.tap()
        app.buttons["question-bank-scope-all-questions"].tap()

        let crossQuestionRecordID = "\(reader.paperID)::question::\(reader.questionID)"
        let crossFeedback = element(app, identifier: "question-bank-answer-feedback-\(crossQuestionRecordID)")
        XCTAssertTrue(crossFeedback.waitForExistence(timeout: 5), "The answer must follow the stable question ID into the cross-paper reader")
        let question2ID = "\(reader.paperID)-question-2"
        let question2Option = app.buttons["question-bank-option-\(question2ID)-A"].firstMatch
        XCTAssertTrue(question2Option.waitForExistence(timeout: 5))
        if !question2Option.isHittable { app.swipeUp() }
        question2Option.tap()
        let question2RecordID = "\(reader.paperID)::question::\(question2ID)"
        XCTAssertTrue(element(app, identifier: "question-bank-answer-feedback-\(question2RecordID)").waitForExistence(timeout: 5))

        element(app, identifier: "question-bank-redo-filtered-group").tap()
        app.buttons["清除当前题组作答记录"].tap()
        XCTAssertFalse(element(app, identifier: "question-bank-answer-feedback-\(question2RecordID)").exists)
        XCTAssertTrue(question2Option.isEnabled, "Redo should unlock the current question for another attempt")
        app.swipeDown()
        XCTAssertFalse(crossFeedback.exists, "Redo should clear earlier questions in the same filtered group")
        XCTAssertTrue(optionA.isEnabled, "Redo should clear the earlier question shared with the paper reader")
    }

    @MainActor
    func testQuestionAndPaperAnswerClearingStaySyncedAcrossReaders() throws {
        let reader = launchPracticeReader()
        let app = reader.app
        let question2ID = "\(reader.paperID)-question-2"
        let question1Option = app.buttons["question-bank-option-\(reader.questionID)-A"].firstMatch
        let question2Option = app.buttons["question-bank-option-\(question2ID)-A"].firstMatch
        question1Option.tap()
        XCTAssertTrue(
            element(app, identifier: "question-bank-answer-feedback-\(reader.questionID)")
                .waitForExistence(timeout: 5)
        )

        let moduleOptions = element(app, identifier: "question-bank-reader-options")
        moduleOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        XCTAssertTrue(app.buttons["question-bank-single-position"].waitForExistence(timeout: 5))
        XCTAssertFalse(question1Option.isEnabled)

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["question-bank-filter-toggle"].tap()
        app.buttons["question-bank-module-filter-资料分析"].firstMatch.tap()
        app.buttons["question-bank-scope-all-questions"].tap()

        let crossQuestionRecordID = "\(reader.paperID)::question::\(reader.questionID)"
        let crossFeedback = element(app, identifier: "question-bank-answer-feedback-\(crossQuestionRecordID)")
        XCTAssertTrue(crossFeedback.waitForExistence(timeout: 5), "Single mode should read the module's saved answer")
        let crossPosition = app.buttons["question-bank-single-position"].firstMatch
        let crossScroll = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(crossScroll.waitForExistence(timeout: 5))
        crossScroll.swipeLeft()
        XCTAssertTrue(question2Option.waitForExistence(timeout: 5))
        if !question2Option.isHittable { crossScroll.swipeUp() }
        question2Option.tap()
        XCTAssertFalse(question2Option.isEnabled, "The second question should retain its independent selected answer")
        crossScroll.swipeRight()
        let crossFirstQuestionVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "1/3"),
            object: crossPosition
        )
        XCTAssertEqual(XCTWaiter.wait(for: [crossFirstQuestionVisible], timeout: 5), .completed)
        crossPosition.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))

        let questionActions = element(app, identifier: "question-bank-question-actions")
        XCTAssertTrue(questionActions.waitForExistence(timeout: 5))
        questionActions.tap()
        let clearQuestion = element(app, identifier: "question-bank-clear-question-answer")
        XCTAssertTrue(clearQuestion.waitForExistence(timeout: 5))
        clearQuestion.tap()
        let confirmQuestionClear = app.buttons["清除本题作答记录"].firstMatch
        XCTAssertTrue(confirmQuestionClear.waitForExistence(timeout: 5))
        confirmQuestionClear.tap()
        app.buttons["完成"].firstMatch.tap()

        XCTAssertFalse(crossFeedback.exists)
        XCTAssertTrue(question1Option.isEnabled, "Clearing one question in cross view must unlock it across readers")
        crossScroll.swipeLeft()
        XCTAssertFalse(question2Option.isEnabled, "Clearing question one must preserve question two's answer")

        app.navigationBars.buttons.firstMatch.tap()
        element(app, identifier: "question-bank-management-menu").tap()
        app.buttons["清除筛选"].tap()
        let paperRow = app.buttons["question-bank-paper-\(reader.paperID)"].firstMatch
        XCTAssertTrue(paperRow.waitForExistence(timeout: 5))
        paperRow.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let paperManagement = element(app, identifier: "question-bank-paper-management-menu")
        XCTAssertTrue(paperManagement.waitForExistence(timeout: 5))
        paperManagement.tap()
        let clearPaper = element(app, identifier: "question-bank-clear-paper-answers")
        XCTAssertTrue(clearPaper.waitForExistence(timeout: 5))
        clearPaper.tap()
        let confirmPaperClear = app.buttons["清除本卷作答记录"].firstMatch
        XCTAssertTrue(confirmPaperClear.waitForExistence(timeout: 5))
        confirmPaperClear.tap()
        XCTAssertTrue(app.alerts["作答记录已清除"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["question-bank-filter-toggle"].tap()
        let dataAnalysis = app.buttons["question-bank-module-filter-资料分析"].firstMatch
        XCTAssertTrue(dataAnalysis.waitForExistence(timeout: 5))
        dataAnalysis.tap()
        app.buttons["question-bank-scope-all-questions"].tap()
        let clearedCrossScroll = app.scrollViews["question-bank-single-page-scroll"].firstMatch
        XCTAssertTrue(clearedCrossScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(question1Option.waitForExistence(timeout: 5))
        XCTAssertTrue(question1Option.isEnabled, "Paper-level clearing must clear question one")
        clearedCrossScroll.swipeLeft()
        XCTAssertTrue(question2Option.waitForExistence(timeout: 5))
        XCTAssertTrue(question2Option.isEnabled, "Paper-level clearing must clear question two across readers")
    }

    @MainActor
    func testPresentationModePreferenceSurvivesRestartAndOtherReaders() throws {
        let sessionID = UUID().uuidString
        let reader = launchPracticeReader(sessionID: sessionID)
        let app = reader.app
        let readerOptions = element(app, identifier: "question-bank-reader-options")
        readerOptions.tap()
        app.buttons["question-bank-presentation-单题"].firstMatch.tap()
        XCTAssertTrue(app.buttons["question-bank-single-position"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        let tab = app.buttons["root-tab-questionBank"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        app.buttons["question-bank-paper-\(reader.paperID)"].tap()
        let firstModuleID = "ui-test-\(sessionID)-module"
        app.buttons["question-bank-module-\(firstModuleID)"].tap()
        let reopenedOptions = element(app, identifier: "question-bank-reader-options")
        XCTAssertTrue(reopenedOptions.waitForExistence(timeout: 10))
        XCTAssertTrue((reopenedOptions.value as? String)?.contains("浏览方式：单题") == true)
        XCTAssertTrue(app.buttons["question-bank-single-position"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let compactPaperID = "ui-test-\(sessionID)-compact-paper"
        app.buttons["question-bank-paper-\(compactPaperID)"].tap()
        let compactModuleID = "ui-test-\(sessionID)-compact-module"
        app.buttons["question-bank-module-\(compactModuleID)"].tap()
        let otherPaperOptions = element(app, identifier: "question-bank-reader-options")
        XCTAssertTrue(otherPaperOptions.waitForExistence(timeout: 10))
        XCTAssertTrue((otherPaperOptions.value as? String)?.contains("浏览方式：单题") == true)

        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["question-bank-filter-toggle"].tap()
        let dataAnalysis = app.buttons["question-bank-module-filter-资料分析"].firstMatch
        XCTAssertTrue(dataAnalysis.waitForExistence(timeout: 5))
        dataAnalysis.tap()
        app.buttons["question-bank-scope-all-questions"].tap()
        let crossPaperOptions = element(app, identifier: "question-bank-reader-options")
        XCTAssertTrue(crossPaperOptions.waitForExistence(timeout: 10))
        XCTAssertTrue((crossPaperOptions.value as? String)?.contains("浏览方式：单题") == true)
        let crossPaperPosition = app.buttons["question-bank-single-position"].firstMatch
        XCTAssertTrue(crossPaperPosition.waitForExistence(timeout: 5))
        XCTAssertTrue(crossPaperPosition.label.contains("/3"))
        crossPaperPosition.tap()
        XCTAssertTrue(app.navigationBars["第1题详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchPracticeReader(
        expectAutomaticMaterialSplit: Bool = false,
        longContent: Bool = false,
        sessionID requestedSessionID: String? = nil
    ) -> ReaderUITestContext {
        let sessionID = requestedSessionID ?? UUID().uuidString
        let paperID = "ui-test-\(sessionID)-paper"
        let moduleID = "ui-test-\(sessionID)-module"
        let materialID = "ui-test-\(sessionID)-material"
        let questionID = "ui-test-\(sessionID)-question-1"
        let app = XCUIApplication()
        app.launchArguments = [
            "--question-bank-reader-ui-test",
            "--question-bank-reader-ui-test-session=\(sessionID)"
        ]
        if longContent { app.launchArguments.append("--question-bank-reader-ui-test-long-content") }
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
        if (readerOptions.value as? String)?.contains("浏览方式：连续") != true {
            readerOptions.tap()
            app.buttons["question-bank-presentation-连续"].firstMatch.tap()
        }

        let automaticSplit = app.buttons["question-bank-close-material-split"].firstMatch
        XCTAssertTrue(automaticSplit.waitForExistence(timeout: 10), "The data-analysis module should reveal its shared-material group on iPad")
        if expectAutomaticMaterialSplit {
            XCTAssertTrue(element(app, identifier: "question-bank-split-material-pane-\(materialID)").exists)
        } else {
            automaticSplit.tap()
        }

        XCTAssertTrue(readerOptions.waitForExistence(timeout: 10))
        XCTAssertEqual(readerOptions.label, "阅读设置")
        XCTAssertFalse(app.staticTexts["连续 · 看题"].exists)
        XCTAssertTrue((readerOptions.value as? String)?.contains("答题方式：刷题") == true)
        XCTAssertTrue(app.buttons["question-bank-option-\(questionID)-A"].waitForExistence(timeout: 10))
        XCTAssertTrue((readerOptions.value as? String)?.contains("答题方式：刷题") == true)
        if (readerOptions.value as? String)?.contains("浏览方式：连续") != true {
            readerOptions.tap()
            app.buttons["question-bank-presentation-连续"].firstMatch.tap()
        }
        if longContent {
            let longStem = element(app, identifier: "question-bank-question-stem-\(questionID)")
            XCTAssertTrue(longStem.waitForExistence(timeout: 5))
            XCTAssertTrue(longStem.label.hasPrefix("长题干内容用于验证单题模式纵向阅读"))
            XCTAssertFalse(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "纯文字")).firstMatch.exists
            )
        } else {
            assertExactStemAndHiddenInternalType(in: app, questionID: questionID)
        }
        return ReaderUITestContext(
            app: app,
            paperID: paperID,
            materialID: materialID,
            questionID: questionID
        )
    }

    @MainActor
    private func element(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
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
