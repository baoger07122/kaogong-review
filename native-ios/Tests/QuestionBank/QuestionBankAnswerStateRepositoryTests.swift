import Foundation
import SwiftData
import XCTest
@testable import KaogongReviewNative

@MainActor
final class QuestionBankAnswerStateRepositoryTests: XCTestCase {
    func testPerQuestionWritesAndClearsDoNotChangeOtherQuestionState() async throws {
        let container = try makeContainer()
        let firstID = compoundID("paper-a", "question-a")
        let secondID = compoundID("paper-a", "question-b")

        try await QuestionBankAnswerStateRepository.upsert(
            value(firstID, selected: "B", revealed: true),
            in: container
        )
        try await QuestionBankAnswerStateRepository.upsert(
            value(secondID, selected: "D", revealed: false),
            in: container
        )

        try await QuestionBankAnswerStateRepository.clear(compoundIDs: [firstID], in: container)
        let result = try await QuestionBankAnswerStateRepository.read(
            compoundIDs: [firstID, secondID],
            from: container
        )

        XCTAssertTrue(result[firstID]?.isCleared == true)
        XCTAssertNil(result[firstID]?.selectedOptionID)
        XCTAssertEqual(result[secondID]?.selectedOptionID, "D")
        XCTAssertFalse(result[secondID]?.isRevealed ?? true)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<QuestionBankAnswerStateRecord>()), 2)
    }

    func testPaperClearMarkerSuppressesOldWritesAndIsRefreshedOnEveryClear() async throws {
        let container = try makeContainer()
        let questionID = compoundID("paper-clear-marker", "question-a")
        var oldValue = value(questionID, selected: "A", revealed: false)
        oldValue.updatedAt = Date.now.addingTimeInterval(-60)
        try await QuestionBankAnswerStateRepository.upsert(oldValue, in: container)

        try await QuestionBankAnswerStateRepository.clear(
            compoundIDs: [questionID], paperScope: "paper-clear-marker", in: container
        )
        var betweenClears = value(questionID, selected: "B", revealed: false)
        betweenClears.updatedAt = Date.now.addingTimeInterval(0.01)
        try await QuestionBankAnswerStateRepository.upsert(betweenClears, in: container)
        try await Task.sleep(for: .milliseconds(20))
        try await QuestionBankAnswerStateRepository.clear(
            compoundIDs: [questionID], paperScope: "paper-clear-marker", in: container
        )
        try await QuestionBankAnswerStateRepository.upsert(betweenClears, in: container)

        let afterStaleWrite = try await QuestionBankAnswerStateRepository.read(
            compoundIDs: [questionID], from: container
        )
        XCTAssertTrue(afterStaleWrite[questionID]?.isCleared == true)
        XCTAssertNil(afterStaleWrite[questionID]?.selectedOptionID)

        var currentValue = value(questionID, selected: "D", revealed: false)
        currentValue.updatedAt = Date.now.addingTimeInterval(1)
        try await QuestionBankAnswerStateRepository.upsert(currentValue, in: container)
        let afterCurrentWrite = try await QuestionBankAnswerStateRepository.read(
            compoundIDs: [questionID], from: container
        )
        XCTAssertEqual(afterCurrentWrite[questionID]?.selectedOptionID, "D")
        XCTAssertFalse(afterCurrentWrite[questionID]?.isCleared ?? true)
    }

    func testLegacyMigrationRacingDataClearCannotResurrectAnswerState() async throws {
        let container = try makeContainer()
        let migratedID = compoundID("paper-migration-clear", "question-a")
        let store = QuestionBankAnswerStateStore.shared

        async let migration: Void = store.migrateSceneStorageIfNeeded(
            sourceKey: "test-scene-answer-state",
            selectedOptionsJSON: "{\"question-a\":\"C\"}",
            revealedAnswersJSON: "[]",
            paperID: "paper-migration-clear",
            in: container
        )
        async let clear: Void = QuestionBankAnswerStateRepository.clearAllForDataReset(in: container)
        _ = try await (migration, clear)

        let result = try await QuestionBankAnswerStateRepository.read(compoundIDs: [migratedID], from: container)
        XCTAssertNil(result[migratedID], "The answer-state mutation coordinator and clear barrier must prevent migration resurrection.")
    }

    func testSharedStoreKeepsReaderAndPaperViewsOnOneQuestionState() async throws {
        let container = try makeContainer()
        let questionID = compoundID("paper-shared", "question-a")
        let readerStore = QuestionBankAnswerStateStore.shared
        let paperStore = QuestionBankAnswerStateStore.shared

        try await readerStore.load([questionID], from: container)
        try await readerStore.setSelection(
            "C",
            for: questionID,
            paperID: "paper-shared",
            questionID: "question-a",
            revealed: false,
            in: container
        )
        XCTAssertEqual(paperStore.value(for: questionID)?.selectedOptionID, "C")
        XCTAssertFalse(paperStore.value(for: questionID)?.isRevealed ?? true)

        try await paperStore.setRevealed(
            true,
            for: questionID,
            paperID: "paper-shared",
            questionID: "question-a",
            in: container
        )
        let persisted = try await QuestionBankAnswerStateRepository.read(compoundIDs: [questionID], from: container)
        XCTAssertEqual(persisted[questionID]?.selectedOptionID, "C")
        XCTAssertTrue(persisted[questionID]?.isRevealed == true)
    }

    func testLegacyMigrationResumesFromPersistedCursorAndKeepsExistingWrites() async throws {
        let container = try makeContainer()
        let defaults = UserDefaults.standard
        let key = QuestionBankAnswerStateStorage.appStorageKey
        defer { defaults.removeObject(forKey: key) }

        let firstID = compoundID("paper-b", "question-a")
        let secondID = compoundID("paper-b", "question-b")
        let legacy = QuestionBankAnswerState(selectedOptions: [firstID: "A", secondID: "C"])
        let rawData = try JSONEncoder().encode(legacy)
        let raw = String(decoding: rawData, as: UTF8.self)
        let migrationID = "legacy-global-v1-\(QuestionBankAnswerStateRepository.digest(Data(raw.utf8)))"
        defaults.set(raw, forKey: key)

        container.mainContext.insert(QuestionBankAnswerStateMigrationRecord(
            migrationID: migrationID,
            sourceKind: "global-v1",
            sourceBackupPayload: Data(raw.utf8),
            sourceDigest: QuestionBankAnswerStateRepository.digest(Data(raw.utf8)),
            phaseRawValue: "migrating",
            cursor: 1,
            sourceItemCount: 2,
            processedItemCount: 1
        ))
        container.mainContext.insert(QuestionBankAnswerStateRecord(
            compoundID: firstID,
            paperID: "paper-b",
            questionID: "question-a",
            selectedOptionID: "D",
            mutationRevision: 4
        ))
        try container.mainContext.save()

        try await QuestionBankAnswerStateStore.shared.migrateGlobalIfNeeded(in: container)
        try await QuestionBankAnswerStateStore.shared.migrateGlobalIfNeeded(in: container)

        let result = try await QuestionBankAnswerStateRepository.read(
            compoundIDs: [firstID, secondID],
            from: container
        )
        XCTAssertEqual(result[firstID]?.selectedOptionID, "D", "A newer per-question row wins over legacy data")
        XCTAssertEqual(result[secondID]?.selectedOptionID, "C", "The saved cursor resumes the remaining legacy item")
        let progress = try XCTUnwrap(container.mainContext.fetch(
            FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                predicate: #Predicate { $0.migrationID == migrationID }
            )
        ).first)
        XCTAssertEqual(progress.phaseRawValue, "complete")
        XCTAssertEqual(progress.processedItemCount, 2)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<QuestionBankAnswerStateRecord>()), 2)
    }

    func testSceneStorageMigrationUsesPaperAndRetainsRawSnapshotAfterCompletion() async throws {
        let container = try makeContainer()
        let store = QuestionBankAnswerStateStore.shared

        try await store.migrateSceneStorageIfNeeded(
            sourceKey: "question-bank.selected-options.paper-c.module-c|question-bank.revealed-answers.paper-c.module-c",
            selectedOptionsJSON: "{\"stable-q\":\"B\"}",
            revealedAnswersJSON: "[\"stable-q\"]",
            paperID: "paper-c",
            in: container
        )

        let id = compoundID("paper-c", "stable-q")
        let state = try await QuestionBankAnswerStateRepository.read(compoundIDs: [id], from: container)[id]
        XCTAssertEqual(state?.selectedOptionID, "B")
        XCTAssertTrue(state?.isRevealed == true)

        let progress = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<QuestionBankAnswerStateMigrationRecord>()).first)
        XCTAssertEqual(progress.phaseRawValue, "complete")
        XCTAssertTrue(String(decoding: progress.sourceBackupPayload, as: UTF8.self).contains("stable-q"))
    }

    func testBackupRoundTripsAnswerStateAndOldBackupRestoresWithoutAnswerTable() throws {
        let container = try makeContainer()
        let state = QuestionBankAnswerStateBackup(
            compoundID: compoundID("paper-d", "question-a"),
            paperID: "paper-d",
            questionID: "question-a",
            selectedOptionID: "A",
            isRevealed: true,
            isCleared: false,
            mutationRevision: 3,
            updatedAt: Date(timeIntervalSince1970: 1_792_000_123.456)
        )
        let data = try LegacyBackupExporter.makeData(records: [], answerStates: [state])
        let package = try LegacyBackupImporter.parse(data: data)
        XCTAssertEqual(package.questionBankAnswerStates, [state])

        container.mainContext.insert(QuestionBankAnswerStateRecord(
            compoundID: compoundID("paper-d", "stale-question"),
            paperID: "paper-d",
            questionID: "stale-question",
            selectedOptionID: "D"
        ))
        try container.mainContext.save()
        try LegacyBackupRestorer.replace(with: package, in: container.mainContext)
        let restored = try container.mainContext.fetch(FetchDescriptor<QuestionBankAnswerStateRecord>())
        XCTAssertEqual(restored.map(QuestionBankAnswerStateBackup.init(record:)), [state])

        let oldPackage = try LegacyBackupImporter.parse(data: Data("{\"version\":1}".utf8))
        XCTAssertTrue(oldPackage.questionBankAnswerStates.isEmpty)
        try LegacyBackupRestorer.replace(with: oldPackage, in: container.mainContext)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<QuestionBankAnswerStateRecord>()).isEmpty)
    }

    func testBackupRejectsContradictoryClearedAnswerState() throws {
        let invalid = QuestionBankAnswerStateBackup(
            compoundID: compoundID("paper-invalid", "question-a"),
            paperID: "paper-invalid",
            questionID: "question-a",
            selectedOptionID: "B",
            isRevealed: false,
            isCleared: true,
            mutationRevision: 2,
            updatedAt: .now
        )
        let data = try LegacyBackupExporter.makeData(records: [], answerStates: [invalid])

        XCTAssertThrowsError(try LegacyBackupImporter.parse(data: data))
    }

    func testDamagedLegacyPayloadKeepsOriginalForRecovery() async throws {
        let container = try makeContainer()
        let defaults = UserDefaults.standard
        let key = QuestionBankAnswerStateStorage.appStorageKey
        let damaged = "{not-valid-json"
        defaults.set(damaged, forKey: key)
        defer { defaults.removeObject(forKey: key) }

        do {
            try await QuestionBankAnswerStateStore.shared.migrateGlobalIfNeeded(in: container)
            XCTFail("Invalid legacy data must not be silently discarded")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertEqual(defaults.string(forKey: key), damaged)
        let progress = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<QuestionBankAnswerStateMigrationRecord>()).first)
        XCTAssertEqual(String(decoding: progress.sourceBackupPayload, as: UTF8.self), damaged)
        XCTAssertEqual(progress.phaseRawValue, "failed")
        XCTAssertFalse(progress.lastError?.isEmpty ?? true)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<QuestionBankAnswerStateRecord>()).isEmpty)
    }

    func testClearAllBarrierBlocksLegacyRevivalAndAllowsLaterUserAnswer() async throws {
        let container = try makeContainer()
        let defaults = UserDefaults.standard
        let key = QuestionBankAnswerStateStorage.appStorageKey
        defer { defaults.removeObject(forKey: key) }
        let id = compoundID("paper-e", "question-a")
        defaults.set(
            QuestionBankAnswerStateStorage.encode(QuestionBankAnswerState(selectedOptions: [id: "A"])),
            forKey: key
        )

        try container.mainContext.transaction {
            try QuestionBankAnswerStateRepository.clearAllForDataReset(in: container.mainContext)
        }
        QuestionBankAnswerStateRepository.postReset()
        try await QuestionBankAnswerStateStore.shared.migrateGlobalIfNeeded(in: container)

        let afterClear = try await QuestionBankAnswerStateRepository.read(compoundIDs: [id], from: container)
        XCTAssertTrue(afterClear.isEmpty)
        try await QuestionBankAnswerStateStore.shared.setSelection(
            "C",
            for: id,
            paperID: "paper-e",
            questionID: "question-a",
            revealed: false,
            in: container
        )
        let afterNewAnswer = try await QuestionBankAnswerStateRepository.read(compoundIDs: [id], from: container)
        XCTAssertEqual(afterNewAnswer[id]?.selectedOptionID, "C")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            QuestionBankAnswerStateRecord.self,
            QuestionBankAnswerStateMigrationRecord.self,
            QuestionBankAnswerStateScopeClearRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func compoundID(_ paperID: String, _ questionID: String) -> String {
        "\(paperID)::\(QuestionBankRepository.questionKind)::\(questionID)"
    }

    private func value(_ compoundID: String, selected: String, revealed: Bool) -> QuestionBankAnswerStateValue {
        let pieces = compoundID.components(separatedBy: "::\(QuestionBankRepository.questionKind)::")
        return QuestionBankAnswerStateValue(
            compoundID: compoundID,
            paperID: pieces[0],
            questionID: pieces[1],
            selectedOptionID: selected,
            isRevealed: revealed,
            isCleared: false,
            mutationRevision: 1,
            updatedAt: .now
        )
    }
}
