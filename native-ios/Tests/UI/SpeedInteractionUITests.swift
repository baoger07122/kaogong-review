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
        if !start.isHittable { app.swipeUp() }
        // Far from centered text, but inside the intended full-width button.
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let two = app.buttons["speed-key-2"]
        XCTAssertTrue(two.waitForExistence(timeout: 10))
        let answer = app.descendants(matching: .any)["speed-answer"].firstMatch
        func expect(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
            let predicate = NSPredicate(format: "value == %@", value)
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: answer)], timeout: 3)
            XCTAssertEqual(result, .completed, file: file, line: line)
        }
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
}
