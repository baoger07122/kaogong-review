import XCTest

final class SpeedInteractionUITests: XCTestCase {
    @MainActor
    func testBlankStartAreaAndSingleDispatchForKeys() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let shortcut = app.buttons["速算练习"].firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        shortcut.tap()
        let start = app.buttons["speed-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        app.buttons["speed-type-addsub2"].tap()
        if !start.isHittable { app.swipeUp() }
        // Far from centered text, but inside the intended full-width button.
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let two = app.buttons["speed-key-2"]
        XCTAssertTrue(two.waitForExistence(timeout: 10))
        let doodle = app.buttons["speed-doodle-open"]
        XCTAssertTrue(doodle.waitForExistence(timeout: 5))
        doodle.tap()
        let closeDoodle = app.buttons["speed-doodle-close"]
        XCTAssertTrue(closeDoodle.waitForExistence(timeout: 5))
        XCTAssertTrue(closeDoodle.isHittable)
        closeDoodle.tap()
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        XCTAssertTrue(two.isHittable)
        let answer = app.descendants(matching: .any)["speed-answer"].firstMatch
        func expect(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
            let predicate = NSPredicate(format: "value == %@", value)
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: answer)], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
        two.tap()
        expect("2")
        two.tap(withNumberOfTaps: 2, numberOfTouches: 1)
        expect("222")
        app.buttons["speed-key-delete.backward"].tap()
        expect("")
        two.tap()
        expect("2")
        two.tap()
        expect("22")
        app.buttons["speed-key-3"].tap()
        expect("223")
        app.buttons["speed-key-C"].tap()
        expect("22")
        app.buttons["speed-key-delete.backward"].tap()
        expect("")
        app.buttons["speed-key-5"].tap()
        expect("5")
        app.buttons["speed-key-checkmark"].tap()
        expect("")
        two.tap()
        expect("2")
    }

    @MainActor
    func testExitBaselineAndInlineConfirmation() throws {
        continueAfterFailure = false
        for systemAlert in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-speed-exit-diagnostics"] + (systemAlert ? ["-speed-exit-system-alert"] : [])
            app.launch()
            let shortcut = app.buttons["速算练习"].firstMatch
            XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
            shortcut.tap()
            let start = app.buttons["speed-start"]
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            app.buttons["speed-type-addsub2"].tap()
            for attempt in 0..<2 {
                start.tap()
                let key = app.buttons["speed-key-2"]
                XCTAssertTrue(key.waitForExistence(timeout: 5))
                key.tap()
                let back = app.buttons["speed-back"]
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                back.tap()
                if attempt == 0 {
                    let cancel = systemAlert ? app.alerts.buttons["继续"] : app.buttons["speed-exit-continue"]
                    XCTAssertTrue(cancel.waitForExistence(timeout: 1))
                    cancel.tap()
                    XCTAssertEqual(app.descendants(matching: .any)["speed-answer"].firstMatch.value as? String, "2")
                    back.tap()
                }
                let exit = systemAlert ? app.alerts.buttons["退出"] : app.buttons["speed-exit-confirm"]
                XCTAssertTrue(exit.waitForExistence(timeout: 1))
                exit.tap()
                XCTAssertTrue(start.waitForExistence(timeout: 3))
                let metrics = app.staticTexts["speed-exit-metrics"]
                XCTAssertTrue(metrics.waitForExistence(timeout: 3))
                print("MEASURED \(metrics.label)")
            }
            app.terminate()
        }
    }

    @MainActor
    func testEstimateTwoRowsAndTableEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let shortcut = app.buttons["速算练习"].firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        shortcut.tap()
        let type = app.buttons["speed-type-est05"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.tap()
        app.buttons["speed-start"].tap()
        let exercise = app.descendants(matching: .any)["speed-estimate-exercise"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        app.buttons["speed-key-2"].tap()
        let inputUpdated = NSPredicate(format: "value == %@", "2")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: inputUpdated, object: exercise)], timeout: 3), .completed)
        app.buttons["speed-back"].tap()
        app.buttons["speed-exit-confirm"].tap()
        app.buttons["估算表"].tap()
        let add = app.buttons["estimate-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        for identifier in ["estimate-minimum", "estimate-maximum", "estimate-value"] {
            XCTAssertTrue(app.textFields[identifier].waitForExistence(timeout: 3))
        }
    }
}
