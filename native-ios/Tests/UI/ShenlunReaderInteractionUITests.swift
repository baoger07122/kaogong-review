import XCTest

final class ShenlunReaderInteractionUITests: XCTestCase {
    @MainActor
    func testPinchZoomKeepsAnnotationCanvasAlignedWithPaper() throws {
        let sessionID = UUID().uuidString
        let app = launchShenlunFixture(sessionID: sessionID)

        let reader = element(app, identifier: "shenlun-material-reader")
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        let zoom = app.buttons["shenlun-reader-zoom"].firstMatch
        reader.pinch(withScale: 1.5, velocity: 1)

        XCTAssertTrue(zoom.waitForExistence(timeout: 5), "Pinching should reveal the zoom control")
        let zoomChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "100%"),
            object: zoom
        )
        XCTAssertEqual(XCTWaiter.wait(for: [zoomChanged], timeout: 5), .completed)
        let pinchedZoom = Int((zoom.value as? String ?? "100%").replacingOccurrences(of: "%", with: "")) ?? 100
        XCTAssertNotEqual(pinchedZoom, 100, "Pinching should update the displayed zoom percentage")
        zoom.tap()
        let twoHundredPercent = app.buttons["200%"].firstMatch
        XCTAssertTrue(twoHundredPercent.waitForExistence(timeout: 5))
        twoHundredPercent.tap()
        XCTAssertEqual(zoom.value as? String, "200%")

        let openDoodle = app.buttons["shenlun-doodle-open"].firstMatch
        XCTAssertTrue(openDoodle.waitForExistence(timeout: 5))
        openDoodle.tap()

        let paper = element(app, identifier: "shenlun-material-paper")
        let canvasID = "shenlun-page-drawing-ui-test-\(sessionID)-material-ui-test-\(sessionID)-layer"
        let canvas = element(app, identifier: canvasID)
        XCTAssertTrue(paper.waitForExistence(timeout: 5))
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let fingerDrawing = app.buttons["开启手指涂鸦"].firstMatch
        XCTAssertTrue(fingerDrawing.waitForExistence(timeout: 5))
        let canvasReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == YES"),
            object: fingerDrawing
        )
        XCTAssertEqual(XCTWaiter.wait(for: [canvasReady], timeout: 5), .completed)
        fingerDrawing.tap()

        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.38))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.38))
        start.press(forDuration: 0.1, thenDragTo: end)

        let paperFrame = paper.frame
        let canvasFrame = canvas.frame
        XCTAssertGreaterThan(paperFrame.width, 0)
        XCTAssertEqual(canvasFrame.minX, paperFrame.minX, accuracy: 3, "The annotation must track the zoomed page origin")
        XCTAssertEqual(canvasFrame.minY, paperFrame.minY, accuracy: 3, "The annotation must track the zoomed page origin")
        XCTAssertEqual(canvasFrame.width, paperFrame.width, accuracy: 3, "The annotation and paper must use the same zoom scale")
        XCTAssertEqual(canvasFrame.height, paperFrame.height, accuracy: 3, "The annotation and paper must use the same zoom scale")
    }

    @MainActor
    func testAnswerAndReviewTabsSaveTheirOwnFields() throws {
        let sessionID = UUID().uuidString
        let app = launchShenlunFixture(sessionID: sessionID)
        let practice = element(app, identifier: "shenlun-practice-ui-test-\(sessionID)-practice")
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        practice.tap()

        let grid = element(app, identifier: "shenlun-answer-grid")
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        grid.tap()
        let answer = app.textViews["shenlun-answer-text"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        answer.typeText("Answer after zoom")
        app.buttons["shenlun-complete-answer"].tap()

        let answerTab = app.buttons["shenlun-review-section-answer"].firstMatch
        let reviewTab = app.buttons["shenlun-review-section-review"].firstMatch
        XCTAssertTrue(answerTab.waitForExistence(timeout: 10))
        XCTAssertTrue(reviewTab.exists)
        XCTAssertTrue(element(app, identifier: "shenlun-review-score").exists, "The score should be on the default answer tab")
        XCTAssertLessThan(
            element(app, identifier: "shenlun-review-score").frame.minY,
            app.staticTexts["我的作答"].firstMatch.frame.minY,
            "The score card should precede the answer content"
        )
        app.buttons["普通"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Answer after zoom"].waitForExistence(timeout: 5))

        reviewTab.tap()
        let note = element(app, identifier: "shenlun-review-note")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("Independent review note")
        app.buttons["保存本次复盘"].tap()

        answerTab.tap()
        let score = element(app, identifier: "shenlun-review-score")
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        score.tap()
        score.typeText("18")
        app.buttons["保存成绩"].tap()

        reviewTab.tap()
        XCTAssertEqual(note.value as? String, "Independent review note")
        app.buttons["保存本次复盘"].tap()
        answerTab.tap()
        XCTAssertEqual(element(app, identifier: "shenlun-review-score").value as? String, "18")
    }

    @MainActor
    private func launchShenlunFixture(sessionID: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            ShenlunReaderUITestLaunchArgument.enabled,
            "--shenlun-reader-ui-test-session=\(sessionID)"
        ]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let tab = app.buttons["root-tab-shenlun"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }
}

private enum ShenlunReaderUITestLaunchArgument {
    static let enabled = "--shenlun-reader-ui-test"
}
