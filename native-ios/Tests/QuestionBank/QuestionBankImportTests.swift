import Foundation
import CryptoKit
import SwiftData
import UIKit
import XCTest
@testable import KaogongReviewNative

@MainActor
final class QuestionBankImportTests: XCTestCase {
    func testPickerDidPickThenDismissKeepsSelectionAndStartsOnce() throws {
        let coordinator = QuestionBankImportSelectionCoordinator()
        let pickerID = coordinator.beginPicker()
        let url = URL(fileURLWithPath: "/tmp/question-bank-v1.json")

        guard case .selected(let selection) = coordinator.receivePickedURLs(requestID: pickerID, urls: [url]) else {
            return XCTFail("The first file callback should be accepted")
        }
        XCTAssertEqual(selection.id, pickerID)
        XCTAssertEqual(selection.url, url)
        XCTAssertEqual(coordinator.pickerWasDismissed(requestID: pickerID), .selectionAlreadyReceived)
        XCTAssertEqual(coordinator.takePendingSelection(requestID: pickerID), selection)
        XCTAssertNil(coordinator.takePendingSelection(requestID: pickerID))
        XCTAssertEqual(coordinator.receivePickedURLs(requestID: pickerID, urls: [url]), .duplicate)
        XCTAssertTrue(coordinator.hasActivePickerRequest, "The request remains current until import preview finishes")
    }

    func testPickerDismissThenDidPickAcceptsLateCallback() throws {
        let coordinator = QuestionBankImportSelectionCoordinator()
        let pickerID = coordinator.beginPicker()
        let url = URL(fileURLWithPath: "/tmp/late-question-bank-v1.json")

        XCTAssertEqual(coordinator.pickerWasDismissed(requestID: pickerID), .awaitingCallback)
        XCTAssertTrue(coordinator.noteDismissalWithoutCallback(requestID: pickerID))
        guard case .selected(let selection) = coordinator.receivePickedURLs(requestID: pickerID, urls: [url]) else {
            return XCTFail("A dismissal must not invalidate a late valid file callback")
        }
        XCTAssertEqual(selection.id, pickerID)
        XCTAssertEqual(coordinator.takePendingSelection(requestID: pickerID), selection)
    }

    func testPickerDuplicateCallbackIsIgnoredWithoutResettingPreparation() throws {
        let coordinator = QuestionBankImportSelectionCoordinator()
        let pickerID = coordinator.beginPicker()
        let url = URL(fileURLWithPath: "/tmp/question-bank-v1.json")
        guard case .selected = coordinator.receivePickedURLs(requestID: pickerID, urls: [url]) else {
            return XCTFail("The initial selection should be accepted")
        }
        _ = try XCTUnwrap(coordinator.takePendingSelection(requestID: pickerID))

        XCTAssertEqual(coordinator.receivePickedURLs(requestID: pickerID, urls: [url]), .duplicate)
        XCTAssertTrue(coordinator.markPreviewReady(requestID: pickerID))
        XCTAssertEqual(coordinator.receivePickedURLs(requestID: pickerID, urls: [url]), .duplicate)
        XCTAssertEqual(coordinator.pickerWasDismissed(requestID: pickerID), .previewAlreadyPresented)
    }

    func testPickerExplicitCancellationRejectsLateSelection() throws {
        let coordinator = QuestionBankImportSelectionCoordinator()
        let pickerID = coordinator.beginPicker()
        var cancelledRequestID: UUID?
        let pickerDelegate = QuestionBankDocumentPicker.Coordinator(
            requestID: pickerID,
            onPick: { _, _ in },
            onCancel: { requestID in
                cancelledRequestID = requestID
                _ = coordinator.cancelPickerRequest(requestID: requestID)
            }
        )
        let pickerController = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        pickerDelegate.documentPickerWasCancelled(pickerController)
        XCTAssertEqual(cancelledRequestID, pickerID)
        XCTAssertFalse(coordinator.hasActivePickerRequest)
        XCTAssertFalse(coordinator.cancelPickerRequest(requestID: pickerID))
        XCTAssertEqual(
            coordinator.receivePickedURLs(requestID: pickerID, urls: [URL(fileURLWithPath: "/tmp/stale.json")]),
            .staleRequest
        )
    }

    func testPickerInvalidResultsAreDistinctAndAllowReselection() throws {
        let coordinator = QuestionBankImportSelectionCoordinator()
        let emptySelectionID = coordinator.beginPicker()
        XCTAssertEqual(coordinator.receivePickedURLs(requestID: emptySelectionID, urls: []), .emptySelection)

        let emptyURLID = coordinator.beginPicker()
        let emptyURL = try XCTUnwrap(URL(string: "file:"))
        XCTAssertTrue(emptyURL.isFileURL)
        XCTAssertTrue(emptyURL.path.isEmpty)
        XCTAssertEqual(coordinator.receivePickedURLs(requestID: emptyURLID, urls: [emptyURL]), .emptyURL)

        let nonFileID = coordinator.beginPicker()
        let nonFileURL = try XCTUnwrap(URL(string: "https://example.com/questions.json"))
        XCTAssertEqual(coordinator.receivePickedURLs(requestID: nonFileID, urls: [nonFileURL]), .nonFileURL)

        let retryID = coordinator.beginPicker()
        guard case .selected = coordinator.receivePickedURLs(
            requestID: retryID, urls: [URL(fileURLWithPath: "/tmp/retry.json")]
        ) else {
            return XCTFail("A new request should accept a valid file after earlier invalid results")
        }
    }

    func testAssetPathResolverRejectsTraversalAndSymlinkEscape() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankAssetPathTest-\(UUID().uuidString)", isDirectory: true)
        let root = temporaryRoot.appendingPathComponent("root", isDirectory: true)
        let assetsDirectory = root.appendingPathComponent("assets", isDirectory: true)
        let outsideDirectory = temporaryRoot.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let validPath = "assets/q071-combined-figure.png"
        XCTAssertNotNil(QuestionBankAssetStore.url(for: validPath, under: root))
        for invalidPath in [
            "../escaped.png", "/private/escaped.png", "assets/../escaped.png",
            "assets//escaped.png", "assets/./escaped.png", "assets\\..\\escaped.png",
            "C:/escaped.png"
        ] {
            XCTAssertNil(QuestionBankAssetStore.url(for: invalidPath, under: root), invalidPath)
        }

        let outsideImage = outsideDirectory.appendingPathComponent("escaped.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outsideImage)
        let symlink = assetsDirectory.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideDirectory)
        XCTAssertNil(QuestionBankAssetStore.url(for: "assets/external/escaped.png", under: root))
        XCTAssertEqual(try Data(contentsOf: outsideImage), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testReadingSequenceGroupsSharedMaterialsOnceAndKeepsQuestionOrder() {
        let questions = [
            readingQuestion(id: "q-115", number: 115, materialID: "material-a"),
            readingQuestion(id: "q-112", number: 112),
            readingQuestion(id: "q-114", number: 114, materialID: "material-b"),
            readingQuestion(id: "q-111", number: 111, materialID: "material-a"),
            readingQuestion(id: "q-113", number: 113, materialID: "material-b")
        ]

        let steps = QuestionBankReadingSequence.steps(for: questions)
        let sequence = steps.map { step -> String in
            switch step.kind {
            case .material(let materialID): "material:\(materialID)"
            case .question(let questionID): "question:\(questionID)"
            }
        }

        XCTAssertEqual(sequence, [
            "material:material-a", "question:q-111", "question:q-112",
            "material:material-b", "question:q-113", "question:q-114", "question:q-115"
        ])
        XCTAssertEqual(steps.filter {
            if case .material(_) = $0.kind { return true }
            return false
        }.count, 2)

        let dataQuestions = (111...115).reversed().map {
            readingQuestion(id: "q-\($0)", number: $0, materialID: "data-set")
        }
        let dataSequence = QuestionBankReadingSequence.steps(for: dataQuestions)
        XCTAssertEqual(dataSequence.first?.kind, .material("data-set"))
        XCTAssertEqual(dataSequence.filter {
            if case .material(_) = $0.kind { return true }
            return false
        }.count, 1)
        XCTAssertEqual(dataSequence.compactMap { step -> String? in
            guard case .question(let id) = step.kind else { return nil }
            return id
        }, (111...115).map { "q-\($0)" })
    }

    func testQuestionBankReaderLayoutModesAndOptionDisplay() {
        XCTAssertEqual(
            QuestionBankSplitLayout.orientation(width: 1194, height: 834),
            .landscape
        )
        XCTAssertEqual(
            QuestionBankSplitLayout.orientation(width: 834, height: 1194),
            .portrait
        )
        XCTAssertEqual(QuestionBankSplitLayout.materialWidth(totalWidth: 1024), 568.32, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(
            960 - QuestionBankSplitLayout.materialWidth(totalWidth: 960) - 1,
            QuestionBankSplitLayout.minimumQuestionPaneWidth
        )

        XCTAssertTrue(QuestionBankReadingMode.reading.revealsAnswer(afterSelecting: nil))
        XCTAssertFalse(QuestionBankReadingMode.practice.revealsAnswer(afterSelecting: nil))
        XCTAssertTrue(QuestionBankReadingMode.practice.revealsAnswer(afterSelecting: "B"))

        XCTAssertNil(QuestionBankOptionDisplay.text(for: QuestionBankOption(id: "A", text: "A", imageAssetID: "")))
        XCTAssertNil(QuestionBankOptionDisplay.text(for: QuestionBankOption(id: "A", text: " A\n", imageAssetID: "")))
        XCTAssertEqual(QuestionBankOptionDisplay.text(for: QuestionBankOption(id: "A", text: "选项内容", imageAssetID: "")), "选项内容")
    }

    func testQuestionBankPresentationSwitchPreservesCurrentQuestionAndReadingMode() {
        let continuous = QuestionBankReaderPosition(
            presentationMode: .continuous,
            currentQuestionID: "q-114",
            splitMaterialID: "material-a"
        )
        let single = QuestionBankReaderTransition.switchingPresentation(to: .single, from: continuous)
        XCTAssertEqual(single.presentationMode, .single)
        XCTAssertEqual(single.currentQuestionID, "q-114")
        XCTAssertEqual(single.splitMaterialID, "material-a")

        let returnedToContinuous = QuestionBankReaderTransition.switchingPresentation(
            to: .continuous, from: single
        )
        XCTAssertEqual(returnedToContinuous.currentQuestionID, "q-114")
        XCTAssertTrue(QuestionBankReadingMode.reading.revealsAnswer(afterSelecting: nil))
        XCTAssertFalse(QuestionBankReadingMode.practice.revealsAnswer(afterSelecting: nil))
    }

    func testQuestionBankSingleQuestionNavigationStopsAtModuleBoundaries() {
        let questionIDs = ["q-111", "q-112", "q-113"]
        XCTAssertNil(QuestionBankReaderTransition.adjacentQuestionID(
            currentID: "q-111", orderedIDs: questionIDs, direction: -1
        ))
        XCTAssertEqual(QuestionBankReaderTransition.adjacentQuestionID(
            currentID: "q-111", orderedIDs: questionIDs, direction: 1
        ), "q-112")
        XCTAssertEqual(QuestionBankReaderTransition.adjacentQuestionID(
            currentID: "q-112", orderedIDs: questionIDs, direction: -1
        ), "q-111")
        XCTAssertNil(QuestionBankReaderTransition.adjacentQuestionID(
            currentID: "q-113", orderedIDs: questionIDs, direction: 1
        ))
        XCTAssertNil(QuestionBankReaderTransition.adjacentQuestionID(
            currentID: "missing", orderedIDs: questionIDs, direction: 1
        ))
        XCTAssertEqual(QuestionBankReaderTransition.ordinal(of: "q-112", in: questionIDs), 2)
    }

    func testQuestionBankPresentationModeSelectsOnlyTheCurrentVisibleQuestion() {
        let questionIDs = ["q-111", "q-112", "q-113"]
        XCTAssertEqual(QuestionBankReaderTransition.displayedQuestionIDs(
            for: .single, currentID: "q-112", orderedIDs: questionIDs
        ), ["q-112"])
        XCTAssertEqual(QuestionBankReaderTransition.displayedQuestionIDs(
            for: .continuous, currentID: "q-112", orderedIDs: questionIDs
        ), questionIDs)
        XCTAssertEqual(QuestionBankReaderTransition.displayedQuestionIDs(
            for: .single, currentID: "missing", orderedIDs: questionIDs
        ), ["q-111"])
    }

    func testQuestionBankOverviewSelectionUsesSingleModeAndKeepsSplitMaterialSafe() {
        let continuous = QuestionBankReaderPosition(
            presentationMode: .continuous,
            currentQuestionID: "q-111",
            splitMaterialID: nil
        )
        let fromOverview = QuestionBankReaderTransition.selectingOverviewQuestion(
            "q-114", materialID: "material-b", availableMaterialIDs: ["material-b"], from: continuous
        )
        XCTAssertEqual(fromOverview.presentationMode, .single)
        XCTAssertEqual(fromOverview.currentQuestionID, "q-114")
        XCTAssertNil(fromOverview.splitMaterialID)

        let split = QuestionBankReaderPosition(
            presentationMode: .single,
            currentQuestionID: "q-112",
            splitMaterialID: "material-a"
        )
        let sameGroup = QuestionBankReaderTransition.movingToQuestion(
            "q-113", materialID: "material-a", availableMaterialIDs: ["material-a", "material-b"], from: split
        )
        XCTAssertEqual(sameGroup.splitMaterialID, "material-a")

        let otherGroup = QuestionBankReaderTransition.movingToQuestion(
            "q-114", materialID: "material-b", availableMaterialIDs: ["material-a", "material-b"], from: sameGroup
        )
        XCTAssertEqual(otherGroup.splitMaterialID, "material-b")

        let overviewInOtherGroup = QuestionBankReaderTransition.selectingOverviewQuestion(
            "q-114", materialID: "material-b", availableMaterialIDs: ["material-a", "material-b"], from: split
        )
        XCTAssertEqual(overviewInOtherGroup.presentationMode, .single)
        XCTAssertEqual(overviewInOtherGroup.currentQuestionID, "q-114")
        XCTAssertEqual(overviewInOtherGroup.splitMaterialID, "material-b")

        let overviewWithoutMaterial = QuestionBankReaderTransition.selectingOverviewQuestion(
            "q-115", materialID: nil, availableMaterialIDs: ["material-a", "material-b"], from: split
        )
        XCTAssertNil(overviewWithoutMaterial.splitMaterialID)

        let withoutMaterial = QuestionBankReaderTransition.movingToQuestion(
            "q-115", materialID: nil, availableMaterialIDs: ["material-a", "material-b"], from: otherGroup
        )
        XCTAssertNil(withoutMaterial.splitMaterialID)
    }

    func testQuestionBankSelectedOptionsPersistByStableQuestionID() {
        let selected = ["q-114": "C", "q-115": "A"]
        XCTAssertEqual(QuestionBankSelectedOptionsStorage.decode(
            QuestionBankSelectedOptionsStorage.encode(selected)
        ), selected)
        XCTAssertEqual(QuestionBankSelectedOptionsStorage.decode("invalid"), [:])
    }

    func testQuestionBankDoodleToolbarTargetFollowsVisibleQuestionAndMaterial() {
        let questions = [
            readingQuestion(id: "q-one", number: 1, materialID: "material-one"),
            readingQuestion(id: "q-two", number: 2, materialID: "material-two"),
            readingQuestion(id: "q-three", number: 3)
        ]

        let firstTarget = QuestionBankDoodleToolbarTarget.resolve(
            visibleQuestionID: "q-one", questions: questions,
            materialIDs: ["material-one", "material-two"]
        )
        XCTAssertEqual(firstTarget, QuestionBankDoodleToolbarTarget(
            questionID: "q-one", questionNumber: 1, materialID: "material-one"
        ))

        let switchedTarget = QuestionBankDoodleToolbarTarget.resolve(
            visibleQuestionID: "q-two", questions: questions,
            materialIDs: ["material-one", "material-two"]
        )
        XCTAssertEqual(switchedTarget?.questionID, "q-two")
        XCTAssertEqual(switchedTarget?.materialID, "material-two")

        let questionWithoutMaterial = QuestionBankDoodleToolbarTarget.resolve(
            visibleQuestionID: "q-three", questions: questions, materialIDs: []
        )
        XCTAssertEqual(questionWithoutMaterial?.questionNumber, 3)
        XCTAssertNil(questionWithoutMaterial?.materialID)
        XCTAssertNil(QuestionBankDoodleToolbarTarget.resolve(
            visibleQuestionID: "stale", questions: questions, materialIDs: []
        ))
    }

    func testQuestionBankDoodlesRoundTripThroughGenericKeyValueBackup() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankDoodleBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let paperID = "sample-paper"
        let questionScope = QuestionBankDoodleScope.question("q-114")
        let questionDoodleID = QuestionBankDoodleRepository.recordID(paperID: paperID, scope: questionScope)
        XCTAssertEqual(
            QuestionBankDoodleRepository.recordID(paperID: paperID, scope: questionScope),
            questionDoodleID
        )
        XCTAssertNotEqual(
            questionDoodleID,
            QuestionBankDoodleRepository.recordID(paperID: paperID, scope: .question("q-115"))
        )
        XCTAssertNotEqual(
            questionDoodleID,
            QuestionBankDoodleRepository.recordID(paperID: paperID, scope: .material("q-114"))
        )

        let questionPayload = Data("{\"id\":\"q-114\",\"answer\":\"C\"}".utf8)
        let container = try makeContainer(storeURL: temporaryRoot.appendingPathComponent("source.store"))
        let context = container.mainContext
        let question = QuestionBankRecord(
            compoundID: "sample-paper::question::q-114",
            paperID: paperID,
            kind: QuestionBankRepository.questionKind,
            stableID: "q-114",
            moduleID: "data-analysis",
            questionNumber: 114,
            payload: questionPayload
        )
        context.insert(question)
        try context.save()

        XCTAssertNil(QuestionBankDoodleRepository.save(
            recordID: questionDoodleID,
            drawingData: "encoded-pencil-kit-drawing",
            context: context
        ))
        XCTAssertEqual(question.payload, questionPayload, "A doodle save must leave imported question JSON untouched")

        let storedRecords = try context.fetch(FetchDescriptor<StoredRecord>())
        let doodle = try XCTUnwrap(storedRecords.first {
            $0.collection == QuestionBankDoodleRepository.collection && $0.recordID == questionDoodleID
        })
        XCTAssertEqual(doodle.jsonObject?["key"] as? String, questionDoodleID)
        XCTAssertEqual(
            try QuestionBankDoodleRepository.drawingData(recordID: questionDoodleID, context: context),
            "encoded-pencil-kit-drawing"
        )
        XCTAssertNil(QuestionBankDoodleRepository.save(
            recordID: questionDoodleID,
            drawingData: "updated-pencil-kit-drawing",
            context: context
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).filter {
            $0.collection == QuestionBankDoodleRepository.collection && $0.recordID == questionDoodleID
        }.count, 1, "Updating a doodle must replace its stable record instead of duplicating it")

        let updatedStoredRecords = try context.fetch(FetchDescriptor<StoredRecord>())
        let backupData = try LegacyBackupExporter.makeData(records: updatedStoredRecords)
        let package = try LegacyBackupImporter.parse(data: backupData)
        let backupDoodle = try XCTUnwrap(package.records.first {
            $0.collection == QuestionBankDoodleRepository.collection && $0.recordID == questionDoodleID
        })
        let backupPayloadObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: backupDoodle.payload) as? [String: Any]
        )
        XCTAssertEqual(backupPayloadObject["pencilKitData"] as? String, "updated-pencil-kit-drawing")

        let restored = try makeContainer(storeURL: temporaryRoot.appendingPathComponent("restored.store"))
        try LegacyBackupRestorer.replace(with: package, in: restored.mainContext)
        let restoredDoodle = try XCTUnwrap(try restored.mainContext.fetch(FetchDescriptor<StoredRecord>()).first {
            $0.collection == QuestionBankDoodleRepository.collection && $0.recordID == questionDoodleID
        })
        XCTAssertEqual(
            try QuestionBankDoodleRepository.drawingData(recordID: questionDoodleID, context: restored.mainContext),
            "updated-pencil-kit-drawing"
        )

        XCTAssertNil(QuestionBankDoodleRepository.save(recordID: questionDoodleID, drawingData: "", context: context))
        XCTAssertFalse(try context.fetch(FetchDescriptor<StoredRecord>()).contains {
            $0.collection == QuestionBankDoodleRepository.collection && $0.recordID == questionDoodleID
        }, "Clearing a doodle must remove its separate saved record")
        XCTAssertEqual(question.payload, questionPayload, "Saving or clearing a doodle must not mutate question JSON")
    }

    func testQuestionNumberFilterTargetsOwningModuleAndQuestion() {
        let module = QuestionBankRecord(
            compoundID: "sample-paper::module::data",
            paperID: "sample-paper",
            kind: QuestionBankRepository.moduleKind,
            stableID: "data-analysis",
            title: "资料分析",
            payload: Data()
        )
        let question = QuestionBankRecord(
            compoundID: "sample-paper::question::q-113",
            paperID: "sample-paper",
            kind: QuestionBankRepository.questionKind,
            stableID: "q-113",
            moduleID: "data-analysis",
            questionNumber: 113,
            payload: Data()
        )

        XCTAssertEqual(
            QuestionBankQuestionRoute.target(
                questionNumber: 113,
                paperID: "sample-paper",
                selectedModuleTitle: "",
                records: [module, question]
            ),
            QuestionBankQuestionRouteTarget(moduleID: "data-analysis", questionNumber: 113)
        )
        XCTAssertNil(QuestionBankQuestionRoute.target(
            questionNumber: 113,
            paperID: "sample-paper",
            selectedModuleTitle: "常识判断",
            records: [module, question]
        ))
        XCTAssertNil(QuestionBankQuestionRoute.target(
            questionNumber: nil,
            paperID: "sample-paper",
            selectedModuleTitle: "",
            records: [module, question]
        ))
    }

    func testSingleJSONPickerCallbackReachesPreviewAndConfirmedCommit() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankPickerJSONFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let sourcePlan = try QuestionBankPackageImporter.prepare(from: validationPackageURL())
        defer { QuestionBankPackageImporter.cleanup(sourcePlan) }
        let jsonURL = try writeJSON(makeJSONDocument(from: sourcePlan), to: temporaryRoot, name: "picker-one-file.json")

        let coordinator = QuestionBankImportSelectionCoordinator()
        let requestID = coordinator.beginPicker()
        var callbackResult: QuestionBankPickerSelectionResult?
        let pickerDelegate = QuestionBankDocumentPicker.Coordinator(
            requestID: requestID,
            onPick: { callbackRequestID, urls in
                XCTAssertEqual(callbackRequestID, requestID)
                callbackResult = coordinator.receivePickedURLs(requestID: callbackRequestID, urls: urls)
            },
            onCancel: { cancelledRequestID in
                XCTAssertEqual(cancelledRequestID, requestID)
            }
        )
        let pickerController = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        pickerDelegate.documentPicker(pickerController, didPickDocumentsAt: [jsonURL])

        guard case .selected(let selection) = try XCTUnwrap(callbackResult) else {
            return XCTFail("The UIDocumentPicker delegate callback should select the JSON fixture")
        }
        XCTAssertEqual(selection.url, jsonURL)
        XCTAssertEqual(coordinator.pickerWasDismissed(requestID: requestID), .selectionAlreadyReceived)
        let preparingSelection = try XCTUnwrap(coordinator.takePendingSelection(requestID: requestID))
        let previewPlan = try QuestionBankPackageImporter.prepare(
            from: preparingSelection.url, source: .pickerCopy, onProgress: { _ in }
        )
        defer { QuestionBankPackageImporter.cleanup(previewPlan) }
        XCTAssertTrue(previewPlan.errors.isEmpty, previewPlan.errors.joined(separator: "\n"))
        XCTAssertTrue(previewPlan.canImport)
        XCTAssertEqual(previewPlan.questions.count, 7)
        XCTAssertTrue(coordinator.markPreviewReady(requestID: requestID), "A valid JSON plan should reach the import preview")

        let storeURL = temporaryRoot.appendingPathComponent("QuestionBank.store")
        let assetRoot = temporaryRoot.appendingPathComponent("assets", isDirectory: true)
        let container = try makeContainer(storeURL: storeURL)
        try QuestionBankRepository.commit(
            previewPlan, decision: .add, records: [], context: container.mainContext, assetRoot: assetRoot
        )
        let committed = try container.mainContext.fetch(FetchDescriptor<QuestionBankRecord>())
        XCTAssertEqual(committed.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
        XCTAssertEqual(committed.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
        XCTAssertEqual(committed.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
        XCTAssertEqual(coordinator.pickerWasDismissed(requestID: requestID), .previewAlreadyPresented)
    }

    func testShenlunAdaptationBacksUpExactPayloadAndWritesOnce() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShenlunAdaptationTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let recordID = "legacy-shenlun-1"
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let originalObject: [String: Any] = [
            "id": recordID,
            "subject": "申论",
            "module": "旧题型",
            "isShenlun": true,
            "status": "待吸收",
            "myFramework": "原始框架",
            "bias": [["wrong": "原思路", "right": "修正思路"]],
            "legacySentinel": ["keep", "exactly"]
        ]
        let originalPayload = try JSONSerialization.data(withJSONObject: originalObject, options: [.sortedKeys])
        var values = ShenlunAdaptationValues()
        values.questionType = "归纳概括"
        values.questionSource = "2022 国考"
        values.questionNumber = "1"
        values.score = "18"
        values.totalScore = "25"
        values.question = "根据给定资料，概括主要问题。"
        values.currentAffairsSupplement = "补充背景"
        values.myAnswer = "我的答案"
        values.referenceAnswer = "参考答案"
        values.myAnswerIssues = "遗漏依据"
        values.materialsAnalysis = "材料分析"
        values.reviewNote = "复盘笔记"
        values.materials = ["第一则材料", "第二则材料"]

        let storeURL = temporaryRoot.appendingPathComponent("shenlun.store")
        do {
            let container = try makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let record = StoredRecord(
                collection: "errors", recordID: recordID, payload: originalPayload,
                subject: "申论", module: "旧题型", createdAt: createdAt, updatedAt: createdAt
            )
            context.insert(record)
            try context.save()
            XCTAssertFalse(context.hasChanges)

            try LibraryRecordRepository.adaptShenlunRecord(record: record, values: values, context: context)
            XCTAssertFalse(context.hasChanges, "The adaptation transaction should finish its one persistent write")
            XCTAssertFalse(record.requiresShenlunAdaptation)
            XCTAssertEqual(record.subject, "申论")
            XCTAssertEqual(record.module, "归纳概括")

            let backupID = "\(ShenlunRecordFormat.backupCollection):\(recordID)"
            let backupDescriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.compoundID == backupID })
            let backup = try XCTUnwrap(context.fetch(backupDescriptor).first)
            XCTAssertEqual(backup.payload, originalPayload, "Backup payload bytes must be preserved exactly")
            XCTAssertEqual(backup.createdAt, createdAt)
            XCTAssertEqual(backup.updatedAt, createdAt)

            let adapted = try XCTUnwrap(record.jsonObject)
            XCTAssertEqual(adapted["shenlunFormatVersion"] as? Int, ShenlunRecordFormat.currentVersion)
            XCTAssertEqual(adapted["question"] as? String, values.question)
            XCTAssertEqual(adapted["questionSource"] as? String, values.questionSource)
            XCTAssertEqual(adapted["score"] as? Int, 18)
            XCTAssertEqual(adapted["totalScore"] as? Int, 25)
            XCTAssertEqual(adapted["materials"] as? [String], values.materials)
            XCTAssertEqual(adapted["status"] as? String, "待吸收")
            XCTAssertEqual(adapted["myFramework"] as? String, "原始框架")
            XCTAssertEqual(adapted["legacySentinel"] as? [String], ["keep", "exactly"])

            let adaptedPayload = record.payload
            XCTAssertThrowsError(try LibraryRecordRepository.adaptShenlunRecord(
                record: record, values: values, context: context
            )) { error in
                XCTAssertEqual(error as? ShenlunAdaptationError, .alreadyAdapted)
            }
            XCTAssertEqual(record.payload, adaptedPayload, "A second confirmation must not write again")
            let backupCount = try context.fetch(backupDescriptor).count
            XCTAssertEqual(backupCount, 1, "The first backup must never be overwritten or duplicated")
        }

        let reopened = try makeContainer(storeURL: storeURL)
        let persisted = try reopened.mainContext.fetch(FetchDescriptor<StoredRecord>())
        let adapted = try XCTUnwrap(persisted.first { $0.collection == "errors" && $0.recordID == recordID })
        let persistedBackup = try XCTUnwrap(persisted.first {
            $0.collection == ShenlunRecordFormat.backupCollection && $0.recordID == recordID
        })
        XCTAssertFalse(adapted.requiresShenlunAdaptation)
        XCTAssertEqual(adapted.jsonObject?["question"] as? String, values.question)
        XCTAssertEqual(persistedBackup.payload, originalPayload)
    }

    func testInvalidShenlunAdaptationLeavesPayloadAndBackupUntouched() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShenlunAdaptationRejectedTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let storeURL = temporaryRoot.appendingPathComponent("shenlun.store")
        let container = try makeContainer(storeURL: storeURL)
        let context = container.mainContext
        let recordID = "legacy-shenlun-invalid-score"
        let originalPayload = try JSONSerialization.data(withJSONObject: [
            "id": recordID, "subject": "申论", "isShenlun": true, "status": "待吸收"
        ], options: [.sortedKeys])
        let record = StoredRecord(collection: "errors", recordID: recordID, payload: originalPayload, subject: "申论")
        context.insert(record)
        try context.save()

        var values = ShenlunAdaptationValues()
        values.score = "18.5"
        XCTAssertThrowsError(try LibraryRecordRepository.adaptShenlunRecord(
            record: record, values: values, context: context
        )) { error in
            XCTAssertEqual(error as? ShenlunAdaptationError, .invalidNumber(field: "score"))
        }
        XCTAssertEqual(record.payload, originalPayload)
        XCTAssertFalse(context.hasChanges)
        let backupID = "\(ShenlunRecordFormat.backupCollection):\(recordID)"
        let backupDescriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.compoundID == backupID })
        let backups = try context.fetch(backupDescriptor)
        XCTAssertTrue(backups.isEmpty, "Validation failure must not leave a partial backup")
    }

    func testLibraryLegacyIndexMigrationIsVersionedAndRepairsOnlyOnce() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryIndexMigrationTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let container = try makeContainer(storeURL: temporaryRoot.appendingPathComponent("library.store"))
        let context = container.mainContext
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": "legacy-error",
            "pitfall": "旧索引缺字段",
            "options": [["text": "A"]],
            "status": "未掌握"
        ], options: [.sortedKeys])
        let record = StoredRecord(collection: "errors", recordID: "legacy-error", payload: payload)
        record.indexPayload = try JSONSerialization.data(withJSONObject: ["id": "legacy-error", "status": "未掌握"])
        context.insert(record)
        try context.save()

        let changed = try await LibraryLegacyIndexMigration.runIfNeeded(in: container, storedVersion: 0)
        XCTAssertEqual(changed, 1)
        let verificationContext = ModelContext(container)
        let verified = try verificationContext.fetch(FetchDescriptor<StoredRecord>()).first
        XCTAssertNotNil(verified?.indexObject?["pitfall"])
        XCTAssertNotNil(verified?.indexObject?["options"])

        let skipped = try await LibraryLegacyIndexMigration.runIfNeeded(
            in: container,
            storedVersion: LibraryLegacyIndexMigration.currentVersion
        )
        XCTAssertEqual(skipped, 0)
    }

    func testValidationPackageImportsAtomicallyAndPersistsAcrossContainerReopen() throws {
        try assertInvalidPackagesAreRejectedWithoutLeavingTemporaryFiles()
        let packageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/QuestionBank/2019-national-exam-city-7q.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path), "Validation ZIP fixture should be checked in alongside the app sources.")

        let plan = try QuestionBankPackageImporter.prepare(from: packageURL)
        defer { QuestionBankPackageImporter.cleanup(plan) }
        XCTAssertTrue(plan.errors.isEmpty, plan.errors.joined(separator: "\n"))
        XCTAssertTrue(plan.canImport)
        XCTAssertEqual(plan.modules.count, 5)
        XCTAssertEqual(plan.questions.count, 7)
        XCTAssertEqual(plan.assets.count, 6)

        let q71 = try XCTUnwrap(plan.questions.first { $0.number == 71 })
        XCTAssertEqual(q71.stemImageAssetID, "q-2019-071-full-figure")
        XCTAssertEqual(q71.options.map(\.text), ["A", "B", "C", "D"])
        XCTAssertTrue(q71.options.allSatisfy { $0.imageAssetID.isEmpty })
        let q71Figure = try XCTUnwrap(plan.assets.first { $0.id == q71.stemImageAssetID })
        XCTAssertEqual(q71Figure.role, "题干整图")
        let q71FigureURL = try XCTUnwrap(QuestionBankAssetStore.url(
            for: q71Figure.path, under: try XCTUnwrap(plan.stagingDirectory)
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: q71FigureURL.path))

        let dataQuestions = plan.questions.filter { (111...115).contains($0.number) }
        XCTAssertEqual(dataQuestions.count, 5)
        XCTAssertEqual(Set(dataQuestions.map(\.materialID)), ["m-2019-drugs-111-115"])
        XCTAssertTrue(dataQuestions.allSatisfy { !$0.stem.isEmpty })
        let dataReadingSteps = QuestionBankReadingSequence.steps(for: dataQuestions)
        XCTAssertEqual(dataReadingSteps.first?.kind, .material("m-2019-drugs-111-115"))
        XCTAssertEqual(dataReadingSteps.filter {
            if case .material = $0.kind { return true }
            return false
        }.count, 1)
        XCTAssertEqual(dataReadingSteps.compactMap { step -> String? in
            guard case .question(let id) = step.kind else { return nil }
            return id
        }, dataQuestions.sorted { $0.number < $1.number }.map(\.id))
        let q114 = try XCTUnwrap(dataQuestions.first { $0.number == 114 })
        XCTAssertEqual(q114.options.map(\.text), ["A", "B", "C", "D"])
        XCTAssertEqual(q114.options.map(\.imageAssetID).filter { !$0.isEmpty }.count, 4)
        XCTAssertEqual(plan.assets.filter { $0.ownerID == q114.id }.count, 4)
        XCTAssertFalse(plan.materials.contains { $0.text.contains("五、资料分析") })
        XCTAssertFalse(q114.stem.contains("五、资料分析"))

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let storeURL = temporaryRoot.appendingPathComponent("QuestionBank.store")
        let assetRoot = temporaryRoot.appendingPathComponent("assets", isDirectory: true)

        do {
            // Create the database with the exact old production schema first.
            let legacyContainer = try makeLegacyContainer(storeURL: storeURL)
            let legacyPayload = try JSONSerialization.data(withJSONObject: ["id": "existing-exam", "name": "旧套卷成绩"])
            legacyContainer.mainContext.insert(
                StoredRecord(collection: "exams", recordID: "existing-exam", payload: legacyPayload)
            )
            try legacyContainer.mainContext.save()
        }

        do {
            // Opening the expanded schema must migrate additively and retain the old exam row.
            let container = try makeContainer(storeURL: storeURL)
            let context = container.mainContext
            XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).first?.recordID, "existing-exam")

            try QuestionBankRepository.commit(plan, decision: .add, records: [], context: context, assetRoot: assetRoot)
            var imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            let importedAssets = imported.filter { $0.kind == QuestionBankRepository.assetKind }
            XCTAssertEqual(importedAssets.count, 6)
            XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).first?.recordID, "existing-exam")
            for importedAsset in importedAssets {
                let relativePath = try XCTUnwrap(importedAsset.assetRelativePath)
                let localURL = try XCTUnwrap(QuestionBankAssetStore.url(for: relativePath, under: assetRoot))
                let storedBytes = try Data(contentsOf: localURL)
                let sourceAsset = try XCTUnwrap(plan.assets.first { $0.id == importedAsset.stableID })
                let stage = try XCTUnwrap(plan.stagingDirectory)
                let sourceURL = try XCTUnwrap(QuestionBankAssetStore.url(for: sourceAsset.path, under: stage))
                XCTAssertEqual(storedBytes, try Data(contentsOf: sourceURL))
            }

            let duplicate = try XCTUnwrap(QuestionBankRepository.duplicatePaper(for: XCTUnwrap(plan.paper), in: imported))
            XCTAssertEqual(duplicate.stableID, plan.paper?.id)
            XCTAssertThrowsError(try QuestionBankRepository.commit(
                plan, decision: .add, records: imported, context: context, assetRoot: assetRoot
            ))
            XCTAssertEqual(try context.fetch(FetchDescriptor<QuestionBankRecord>())
                .filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)

            var invalidPlan = plan
            invalidPlan.errors.append("测试缺图：必须拒绝提交")
            XCTAssertThrowsError(try QuestionBankRepository.commit(
                invalidPlan, decision: .replaceExisting, records: imported, context: context, assetRoot: assetRoot
            ))
            imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)

            try QuestionBankRepository.commit(plan, decision: .replaceExisting, records: imported, context: context, assetRoot: assetRoot)
            imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
            let q114Assets = imported.filter { $0.kind == QuestionBankRepository.assetKind && $0.stableID.hasPrefix("q-2019-114-option-") }
            XCTAssertEqual(q114Assets.count, 4)
            for asset in q114Assets {
                let relativePath = try XCTUnwrap(asset.assetRelativePath)
                let localURL = try XCTUnwrap(QuestionBankAssetStore.url(for: relativePath, under: assetRoot))
                XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path), "Missing imported image: \(asset.title ?? asset.stableID)")
            }
            try context.save()
        }

        // A fresh container models closing and reopening the app against the same store.
        let reopened = try makeContainer(storeURL: storeURL)
        let persisted = try reopened.mainContext.fetch(FetchDescriptor<QuestionBankRecord>())
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
        let persistedAssets = persisted.filter { $0.kind == QuestionBankRepository.assetKind }
        XCTAssertEqual(persistedAssets.count, 6)
        for asset in persistedAssets {
            let relativePath = try XCTUnwrap(asset.assetRelativePath)
            let localURL = try XCTUnwrap(QuestionBankAssetStore.url(for: relativePath, under: assetRoot))
            XCTAssertFalse(try Data(contentsOf: localURL).isEmpty)
        }
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<StoredRecord>()).first?.recordID, "existing-exam")
    }

    func testJSONV1PreservesVerifiedQuestionsAndPersistsWithoutBase64Payloads() throws {
        let zipURL = validationPackageURL()
        let sourcePlan = try QuestionBankPackageImporter.prepare(from: zipURL)
        defer { QuestionBankPackageImporter.cleanup(sourcePlan) }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankJSONImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let realInputAssetPaths = [
            "assets/q071-combined-figure.png",
            "assets/shared-material-111-115.png",
            "assets/q114-option-a-graph.png",
            "assets/q114-option-b-graph.png",
            "assets/q114-option-c-graph.png",
            "assets/q114-option-d-graph.png"
        ]
        var document = try makeJSONDocument(from: sourcePlan)
        XCTAssertEqual(document.assets.count, realInputAssetPaths.count)
        for index in document.assets.indices {
            document.assets[index].path = realInputAssetPaths[index]
            document.assets[index].fileName = String(try XCTUnwrap(
                realInputAssetPaths[index].split(separator: "/").last
            ))
        }
        let jsonURL = try writeJSON(document, to: temporaryRoot, name: "validation.json")
        let plan = try QuestionBankPackageImporter.prepare(from: jsonURL, source: .pickerCopy, onProgress: { _ in })
        defer { QuestionBankPackageImporter.cleanup(plan) }

        XCTAssertTrue(plan.errors.isEmpty, plan.errors.joined(separator: "\n"))
        XCTAssertTrue(plan.canImport)
        XCTAssertEqual(plan.paper?.id, sourcePlan.paper?.id)
        XCTAssertEqual(plan.modules.map(\.id), sourcePlan.modules.map(\.id))
        XCTAssertEqual(plan.materials.map(\.id), sourcePlan.materials.map(\.id))
        XCTAssertEqual(plan.questions.map(\.id), sourcePlan.questions.map(\.id))
        XCTAssertEqual(plan.assets.map(\.id), sourcePlan.assets.map(\.id))
        XCTAssertEqual(plan.assets.count, 6)
        let jsonStagingDirectory = try XCTUnwrap(plan.stagingDirectory)
        for inputPath in realInputAssetPaths {
            let legacyTarget = jsonStagingDirectory.appendingPathComponent(inputPath).standardizedFileURL
            let diagnostic = QuestionBankAssetStore.redactedContainmentDiagnostic(
                root: jsonStagingDirectory, candidate: legacyTarget
            )
            print("QUESTION_BANK_PATH_COMPARE \(diagnostic)")
            XCTAssertNotNil(QuestionBankAssetStore.url(for: inputPath, under: jsonStagingDirectory))
        }
        for asset in plan.assets {
            let sourceAsset = try XCTUnwrap(sourcePlan.assets.first { $0.id == asset.id })
            let importedURL = try XCTUnwrap(QuestionBankAssetStore.url(for: asset.path, under: jsonStagingDirectory))
            let sourceURL = try XCTUnwrap(QuestionBankAssetStore.url(
                for: sourceAsset.path, under: try XCTUnwrap(sourcePlan.stagingDirectory)
            ))
            let importedBytes = try Data(contentsOf: importedURL)
            let originalBytes = try Data(contentsOf: sourceURL)
            XCTAssertEqual(importedBytes, originalBytes, "JSON import must preserve source image bytes for \(asset.fileName).")
        }

        var maliciousDocument = document
        maliciousDocument.assets[0].path = "../escaped.png"
        maliciousDocument.assets[0].fileName = "escaped.png"
        let maliciousURL = try writeJSON(maliciousDocument, to: temporaryRoot, name: "malicious-path.json")
        let maliciousPlan = try QuestionBankPackageImporter.prepare(
            from: maliciousURL, source: .pickerCopy, onProgress: { _ in }
        )
        defer { QuestionBankPackageImporter.cleanup(maliciousPlan) }
        XCTAssertFalse(maliciousPlan.canImport)
        XCTAssertTrue(maliciousPlan.errors.contains { $0.contains("安全的 assets/文件名路径") })
        let maliciousStage = try XCTUnwrap(maliciousPlan.stagingDirectory)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: maliciousStage.deletingLastPathComponent().appendingPathComponent("escaped.png").path
        ))

        let filesOpenInPlan = try QuestionBankPackageImporter.prepare(
            from: jsonURL, source: .filesOpenIn, onProgress: { _ in }
        )
        defer { QuestionBankPackageImporter.cleanup(filesOpenInPlan) }
        XCTAssertTrue(filesOpenInPlan.errors.isEmpty, filesOpenInPlan.errors.joined(separator: "\n"))
        XCTAssertEqual(filesOpenInPlan.questions.map(\.id), plan.questions.map(\.id))

        let q71 = try XCTUnwrap(plan.questions.first { $0.number == 71 })
        XCTAssertEqual(q71.stemImageAssetID, "q-2019-071-full-figure")
        let q71Asset = try XCTUnwrap(plan.assets.first { $0.id == q71.stemImageAssetID })
        let q71AssetURL = try XCTUnwrap(QuestionBankAssetStore.url(for: q71Asset.path, under: jsonStagingDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: q71AssetURL.path))

        let sharedMaterialQuestions = plan.questions.filter { (111...115).contains($0.number) }
        XCTAssertEqual(Set(sharedMaterialQuestions.map(\.materialID)), ["m-2019-drugs-111-115"])
        let q114 = try XCTUnwrap(plan.questions.first { $0.number == 114 })
        XCTAssertEqual(q114.options.map(\.imageAssetID).filter { !$0.isEmpty }.count, 4)
        XCTAssertEqual(plan.assets.filter { $0.ownerID == q114.id }.count, 4)

        let storeURL = temporaryRoot.appendingPathComponent("QuestionBank.store")
        let assetRoot = temporaryRoot.appendingPathComponent("assets", isDirectory: true)
        do {
            let container = try makeContainer(storeURL: storeURL)
            let context = container.mainContext
            try QuestionBankRepository.commit(plan, decision: .add, records: [], context: context, assetRoot: assetRoot)
            var imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            let importedAssets = imported.filter { $0.kind == QuestionBankRepository.assetKind }
            XCTAssertEqual(importedAssets.count, 6)
            for importedAsset in importedAssets {
                let relativePath = try XCTUnwrap(importedAsset.assetRelativePath)
                let storedURL = try XCTUnwrap(QuestionBankAssetStore.url(for: relativePath, under: assetRoot))
                let sourceAsset = try XCTUnwrap(sourcePlan.assets.first { $0.id == importedAsset.stableID })
                let sourceURL = try XCTUnwrap(QuestionBankAssetStore.url(
                    for: sourceAsset.path, under: try XCTUnwrap(sourcePlan.stagingDirectory)
                ))
                XCTAssertEqual(try Data(contentsOf: storedURL), try Data(contentsOf: sourceURL))
            }
            let imageRecord = try XCTUnwrap(imported.first { $0.kind == QuestionBankRepository.assetKind })
            let imagePayload = String(decoding: imageRecord.payload, as: UTF8.self)
            XCTAssertFalse(imagePayload.contains("dataBase64"))
            XCTAssertFalse(imagePayload.contains("AABAA"), "Asset records must store metadata, never encoded image bytes.")

            XCTAssertThrowsError(try QuestionBankRepository.commit(
                plan, decision: .add, records: imported, context: context, assetRoot: assetRoot
            ))
            imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            try context.save()
        }

        let reopened = try makeContainer(storeURL: storeURL)
        let persisted = try reopened.mainContext.fetch(FetchDescriptor<QuestionBankRecord>())
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
        let persistedAssets = persisted.filter { $0.kind == QuestionBankRepository.assetKind }
        XCTAssertEqual(persistedAssets.count, 6)
        for asset in persistedAssets {
            let relativePath = try XCTUnwrap(asset.assetRelativePath)
            let storedURL = try XCTUnwrap(QuestionBankAssetStore.url(for: relativePath, under: assetRoot))
            let sourceAsset = try XCTUnwrap(sourcePlan.assets.first { $0.id == asset.stableID })
            let sourceURL = try XCTUnwrap(QuestionBankAssetStore.url(
                for: sourceAsset.path, under: try XCTUnwrap(sourcePlan.stagingDirectory)
            ))
            XCTAssertEqual(try Data(contentsOf: storedURL), try Data(contentsOf: sourceURL))
        }
        let persistedQ114Assets = persisted.filter {
            $0.kind == QuestionBankRepository.assetKind && $0.stableID.hasPrefix("q-2019-114-option-")
        }
        XCTAssertEqual(persistedQ114Assets.count, 4)
        for asset in persistedQ114Assets {
            let path = try XCTUnwrap(asset.assetRelativePath)
            let storedURL = try XCTUnwrap(QuestionBankAssetStore.url(for: path, under: assetRoot))
            XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        }
    }

    func testJSONV1RejectsWrongFormatSchemaAndInvalidImageData() throws {
        let sourcePlan = try QuestionBankPackageImporter.prepare(from: validationPackageURL())
        defer { QuestionBankPackageImporter.cleanup(sourcePlan) }
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankJSONRejectedTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let original = try makeJSONDocument(from: sourcePlan)
        let q71AssetIndex = try XCTUnwrap(original.assets.firstIndex { $0.id == "q-2019-071-full-figure" })
        let q71FileName = original.assets[q71AssetIndex].fileName

        var unsupportedSchema = original
        unsupportedSchema.schemaVersion = 2
        let schemaURL = try writeJSON(unsupportedSchema, to: temporaryRoot, name: "schema-v2.json")
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: schemaURL)) {
            XCTAssertTrue($0.localizedDescription.contains("schemaVersion=2"), $0.localizedDescription)
        }

        let backupURL = temporaryRoot.appendingPathComponent("backup.json")
        try JSONSerialization.data(withJSONObject: ["dataVersion": 1, "records": []]).write(to: backupURL)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: backupURL)) {
            XCTAssertTrue($0.localizedDescription.contains("备份 JSON"), $0.localizedDescription)
        }

        var invalidBase64 = original
        invalidBase64.assets[q71AssetIndex].dataBase64 = "%%%"
        try assertJSONPlanContainsError(invalidBase64, directory: temporaryRoot, name: "bad-base64.json",
                                        matching: "不是有效的纯 Base64", context: q71FileName)

        var invalidHash = original
        invalidHash.assets[q71AssetIndex].sha256 = String(repeating: "0", count: 64)
        try assertJSONPlanContainsError(invalidHash, directory: temporaryRoot, name: "bad-hash.json",
                                        matching: "sha256 与图片原始字节不匹配", context: q71FileName)

        var oversizedImage = original
        let maxEncodedLength = ((QuestionBankPackageImporter.maxJSONImageBytes + 2) / 3) * 4
        oversizedImage.assets[q71AssetIndex].dataBase64 = String(repeating: "A", count: maxEncodedLength + 4)
        try assertJSONPlanContainsError(oversizedImage, directory: temporaryRoot, name: "oversized-image.json",
                                        matching: "超过 16 MiB 单图上限", context: "第71题")

        var missingID = original
        missingID.assets[q71AssetIndex].id = ""
        try assertJSONPlanContainsError(missingID, directory: temporaryRoot, name: "missing-id.json",
                                        matching: "图片资源ID不能为空", context: "第71题")

        let missingIDFieldURL = try writeJSONRemovingField(original, directory: temporaryRoot,
            name: "missing-id-field.json", collection: "assets", index: q71AssetIndex, field: "id")
        try assertJSONFileContainsError(missingIDFieldURL, matching: "图片资源ID不能为空", context: q71FileName)

        let q71QuestionIndex = try XCTUnwrap(original.questions.firstIndex { $0.number == 71 })
        let missingQuestionIDFieldURL = try writeJSONRemovingField(original, directory: temporaryRoot,
            name: "missing-question-id-field.json", collection: "questions", index: q71QuestionIndex, field: "id")
        try assertJSONFileContainsError(missingQuestionIDFieldURL, matching: "题目ID不能为空", context: "第71题")

        var brokenAssociation = original
        brokenAssociation.assets[q71AssetIndex].ownerID = "question-does-not-exist"
        try assertJSONPlanContainsError(brokenAssociation, directory: temporaryRoot, name: "broken-link.json",
                                        matching: "所属记录或用途关联不匹配", context: "第71题")
    }

    private func assertInvalidPackagesAreRejectedWithoutLeavingTemporaryFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankRejectedPackageTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let stagingRoot = FileManager.default.temporaryDirectory
        let previousStaging = Set(try FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("QuestionBankImport-") })

        let spreadsheetURL = temporaryRoot.appendingPathComponent("not-a-package.xlsx")
        try Data("not a ZIP".utf8).write(to: spreadsheetURL)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: spreadsheetURL)) {
            XCTAssertTrue($0.localizedDescription.contains(".zip"), $0.localizedDescription)
        }

        let folderURL = temporaryRoot.appendingPathComponent("folder.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: folderURL)) {
            XCTAssertTrue($0.localizedDescription.contains("文件夹"), $0.localizedDescription)
        }

        let brokenArchiveURL = temporaryRoot.appendingPathComponent("broken.zip")
        try Data("not a ZIP".utf8).write(to: brokenArchiveURL)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: brokenArchiveURL)) {
            XCTAssertTrue($0.localizedDescription.contains("有效 ZIP"), $0.localizedDescription)
        }
        let remainingStaging = Set(try FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("QuestionBankImport-") })
        XCTAssertEqual(remainingStaging, previousStaging, "Rejected packages must not leave temporary staging directories.")
    }

    private func validationPackageURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/QuestionBank/2019-national-exam-city-7q.zip")
    }

    private func makeJSONDocument(from plan: QuestionBankImportPlan) throws -> QuestionBankImportJSONV1 {
        let staging = try XCTUnwrap(plan.stagingDirectory)
        let assets = try plan.assets.map { asset -> QuestionBankJSONAssetV1 in
            let assetURL = try XCTUnwrap(QuestionBankAssetStore.url(for: asset.path, under: staging))
            let data = try Data(contentsOf: assetURL)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return QuestionBankJSONAssetV1(id: asset.id, paperID: asset.paperID,
                ownerType: asset.ownerType, ownerID: asset.ownerID, role: asset.role,
                path: asset.path, mimeType: asset.mimeType, fileName: asset.fileName,
                originalPage: asset.originalPage, dataBase64: data.base64EncodedString(), sha256: digest)
        }
        return QuestionBankImportJSONV1(paper: try XCTUnwrap(plan.paper), modules: plan.modules,
            materials: plan.materials, questions: plan.questions, assets: assets)
    }

    private func writeJSON(_ document: QuestionBankImportJSONV1, to directory: URL, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        return url
    }

    private func assertJSONPlanContainsError(_ document: QuestionBankImportJSONV1, directory: URL,
        name: String, matching phrase: String, context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try writeJSON(document, to: directory, name: name)
        try assertJSONFileContainsError(url, matching: phrase, context: context, file: file, line: line)
    }

    private func writeJSONRemovingField(_ document: QuestionBankImportJSONV1, directory: URL,
        name: String, collection: String, index: Int, field: String) throws -> URL {
        let encoded = try JSONEncoder().encode(document)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var rows = try XCTUnwrap(root[collection] as? [[String: Any]])
        var row = try XCTUnwrap(index < rows.count ? rows[index] : nil)
        row.removeValue(forKey: field)
        rows[index] = row
        root[collection] = rows
        let url = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: root).write(to: url, options: .atomic)
        return url
    }

    private func assertJSONFileContainsError(_ url: URL, matching phrase: String, context: String,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let plan = try QuestionBankPackageImporter.prepare(from: url)
        defer { QuestionBankPackageImporter.cleanup(plan) }
        XCTAssertFalse(plan.canImport)
        XCTAssertTrue(plan.errors.contains { $0.contains(phrase) && $0.contains(context) },
            "Expected error containing ‘\(phrase)’ and ‘\(context)’; got: \(plan.errors)", file: file, line: line)
    }

    private func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema([StoredRecord.self, QuestionBankRecord.self])
        let configuration = ModelConfiguration(
            "QuestionBankImportTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func readingQuestion(id: String, number: Int, materialID: String = "") -> QuestionBankQuestion {
        QuestionBankQuestion(
            id: id,
            paperID: "sample-paper",
            moduleID: "sample-module",
            number: number,
            subject: "",
            type: "",
            materialID: materialID,
            stem: "",
            stemImageAssetID: "",
            options: [],
            answer: "",
            explanation: "",
            originalPage: ""
        )
    }

    private func makeLegacyContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema([StoredRecord.self])
        let configuration = ModelConfiguration(
            "QuestionBankImportTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
