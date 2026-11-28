import Foundation
import XCTest
@testable import KaogongReviewNative

@MainActor
final class JudgmentReasoningModuleTests: XCTestCase {
    func testModuleOrderAndLegacyRecordScope() throws {
        let subject = try XCTUnwrap(SubjectDefinition.all.first { $0.name == "判断推理" })
        XCTAssertEqual(subject.modules.map { SubjectDefinition.moduleTitle($0, subject: subject.name) },
                       ["图形推理", "定义判断", "类比推理", "论证推理", "形式逻辑"])
        let legacy = StoredRecord(
            collection: "errors", recordID: "legacy", payload: Data("{}".utf8),
            subject: subject.name, module: "逻辑判断"
        )
        let formal = StoredRecord(
            collection: "errors", recordID: "formal", payload: Data("{}".utf8),
            subject: subject.name, module: "形式逻辑"
        )
        let argumentScope = LibraryScope(subject: subject.name, module: SubjectDefinition.argumentReasoningModule)
        let formalScope = LibraryScope(subject: subject.name, module: SubjectDefinition.formalLogicModule)

        XCTAssertEqual(argumentScope.title, "论证推理")
        XCTAssertEqual(legacy.moduleDisplayTitle, "论证推理")
        XCTAssertEqual(legacy.module, "逻辑判断")
        XCTAssertTrue(argumentScope.contains(legacy))
        XCTAssertFalse(argumentScope.contains(formal))
        XCTAssertTrue(formalScope.contains(formal))
        XCTAssertFalse(formalScope.contains(legacy))
        XCTAssertEqual(SubjectDefinition.moduleTitle("逻辑判断", subject: "数量关系"), "逻辑判断")
    }

    func testExistingQuestionTypeStaysInArgumentReasoning() throws {
        let subject = LibraryErrorTypeSubject.judgmentReasoning
        let payload = try JSONSerialization.data(withJSONObject: [
            "value": [["id": "old-type", "name": "削弱加强", "module": "逻辑判断"]]
        ])
        let catalog = StoredRecord(collection: "keyvalue", recordID: subject.recordID, payload: payload)
        let type = try XCTUnwrap(LibraryErrorTypeRepository.types(for: subject, records: [catalog]).first)
        XCTAssertTrue(type.isAvailable(in: SubjectDefinition.argumentReasoningModule))
        XCTAssertFalse(type.isAvailable(in: SubjectDefinition.formalLogicModule))
    }
}
