import Foundation
import XCTest
@testable import KaogongReviewNative

@MainActor
final class LibraryDoodleExitSessionTests: XCTestCase {
    func testExitRestoresPageBeforePendingDrawingFinishesEncoding() async throws {
        let session = LibraryDoodleSession()
        let saved = expectation(description: "save receives the final snapshot")
        var finishEncoding: (() -> Void)?
        session.present(
            targetRecordID: "errors:original",
            drawingData: "previous drawing",
            legacyPreviewDataURL: "",
            source: "test",
            exitsBeforeEncoding: true
        ) { drawing, _, _, _ in
            XCTAssertEqual(drawing, "final drawing")
            XCTAssertEqual(session.targetRecordID, "errors:original")
            XCTAssertFalse(session.isPresented)
            saved.fulfill()
            return nil
        }
        session.canvas.controller.installCloseCapture(owner: UUID()) { completion in
            finishEncoding = completion
            return true
        }
        session.canvas.controller.undo()
        session.dismiss()

        XCTAssertFalse(session.isPresented)
        XCTAssertTrue(session.isDismissing)
        let publishSnapshot = try XCTUnwrap(finishEncoding)
        finishEncoding = nil
        session.canvas.drawingData = "final drawing"
        session.canvas.controller.noteUserDrawingPublished()
        publishSnapshot()

        await fulfillment(of: [saved], timeout: 1)
        XCTAssertFalse(session.isDismissing)
    }

    func testFailedCloseRetriesOriginalDrawingWithoutReopeningPage() async {
        let session = LibraryDoodleSession()
        let failed = expectation(description: "first write fails")
        let retried = expectation(description: "retry writes the same original drawing")
        var writeCount = 0
        session.present(
            targetRecordID: "errors:original",
            drawingData: "",
            legacyPreviewDataURL: "",
            source: "test",
            exitsBeforeEncoding: true
        ) { drawing, _, _, _ in
            XCTAssertEqual(drawing, "unsaved drawing")
            XCTAssertEqual(session.targetRecordID, "errors:original")
            XCTAssertFalse(session.isPresented)
            writeCount += 1
            if writeCount == 1 {
                failed.fulfill()
                return "temporary write error"
            }
            retried.fulfill()
            return nil
        }
        session.canvas.drawingData = "unsaved drawing"
        session.canvas.controller.noteUserDrawingPublished()
        session.dismiss()

        await fulfillment(of: [failed], timeout: 1)
        XCTAssertTrue(session.canRetryCloseSave)
        XCTAssertFalse(session.isPresented)
        session.retryCloseSave()

        await fulfillment(of: [retried], timeout: 1)
        XCTAssertEqual(writeCount, 2)
        XCTAssertFalse(session.canRetryCloseSave)
        XCTAssertFalse(session.isDismissing)
        XCTAssertFalse(session.isPresented)
    }
}
