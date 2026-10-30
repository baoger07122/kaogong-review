import Foundation
import XCTest
@testable import KaogongReviewNative

final class QuestionBankReaderWindowTests: XCTestCase {
    func testWindowBoundsUseNearQuestionRadiusAndStayInsideDirectoryEdges() {
        let ids = (0..<40).map { "q\($0)" }

        XCTAssertEqual(
            QuestionBankReaderWindowBounds.IDs(in: ids, around: "q0", radius: 5),
            Array(ids[0..<11])
        )
        XCTAssertEqual(
            QuestionBankReaderWindowBounds.IDs(in: ids, around: "q20", radius: 2),
            Array(ids[18..<23])
        )
        XCTAssertEqual(
            QuestionBankReaderWindowBounds.IDs(in: ids, around: "q39", radius: 5),
            Array(ids[29..<40])
        )
        XCTAssertLessThanOrEqual(
            QuestionBankReaderWindowBounds.IDs(
                in: ids,
                around: "q20",
                radius: 100
            ).count,
            QuestionBankReaderWindowBounds.maximumQuestionBodies
        )
    }

    func testCrossPaperDirectoryKeepsPaperAndQuestionOrderWithoutBodyPayloads() throws {
        let version = QuestionBankCatalogDataVersion(generationID: "g1", revision: 7)
        let papers = [
            paper("p-old", title: "乙卷", year: 2024, questionCount: 2),
            paper("p-new", title: "甲卷", year: 2025, questionCount: 3)
        ]
        let modules = [
            module("p-old", id: "m1", title: "言语理解", sequence: 1),
            module("p-new", id: "m2", title: "资料分析", sequence: 2),
            module("p-new", id: "m1", title: "言语理解", sequence: 1)
        ]
        let questions = [
            question("p-old", id: "q1", module: "m1", number: 1, moduleSequence: 1, material: "shared"),
            question("p-old", id: "q2", module: "m1", number: 2, moduleSequence: 1, material: "shared"),
            question("p-new", id: "q3", module: "m2", number: 2, moduleSequence: 2),
            question("p-new", id: "q1", module: "m1", number: 1, moduleSequence: 1),
            question("p-new", id: "q2", module: "m1", number: 2, moduleSequence: 1)
        ]
        let directory = QuestionBankCatalogReaderDirectory(
            catalogVersion: version,
            papers: papers,
            modules: modules,
            questions: questions
        )
        let options = try QuestionBankCatalogHomeFilterOptions.prepare(papers: papers, questions: questions)
        let home = QuestionBankCatalogHomeSnapshot(
            status: status(questionCount: questions.count),
            catalogVersion: version,
            papers: papers,
            filterOptions: options
        )

        let result = try QuestionBankReaderDirectoryBuilder.crossPaper(
            directory: directory,
            home: home,
            filter: QuestionBankHomeFilter(),
            paperID: nil,
            scopedPaperIDs: nil,
            searchMatches: nil
        )

        XCTAssertEqual(
            result.questions.map(\.sourceCompoundID),
            ["p-new::question::q1", "p-new::question::q2", "p-new::question::q3",
             "p-old::question::q1", "p-old::question::q2"]
        )
        XCTAssertEqual(Array(result.paperSummariesByID.keys).sorted(), ["p-new", "p-old"])
        XCTAssertFalse(result.questions.contains { $0.sourceCompoundID.isEmpty })
    }

    func testMaterialDependenciesAreDeduplicatedAndLimitedToWindowQuestions() {
        let entries = [
            readerQuestion(paper: "p1", id: "q1", material: "m1"),
            readerQuestion(paper: "p1", id: "q2", material: "m1"),
            readerQuestion(paper: "p2", id: "q3", material: "m2"),
            readerQuestion(paper: "p2", id: "q4", material: "")
        ]

        XCTAssertEqual(
            QuestionBankReaderWindowBounds.materialCompoundIDs(for: entries),
            ["p1::material::m1", "p2::material::m2"]
        )
    }

    func testCacheEvictionRetainsCurrentRowsWithinCapacity() {
        let orderedIDs = (0..<8).map { "q\($0)" }
        let loadedIDs = Set(orderedIDs)
        let retained = QuestionBankReaderWindowBounds.retainedIDs(
            from: orderedIDs,
            loadedIDs: loadedIDs,
            pinnedIDs: ["q6"],
            capacity: 3
        )

        XCTAssertEqual(retained, ["q6", "q0", "q1"])
        XCTAssertEqual(
            QuestionBankReaderWindowBounds.evictedIDs(
                loadedIDs: loadedIDs,
                retainedIDs: retained,
                capacity: 3
            ),
            loadedIDs.subtracting(retained)
        )
    }

    func testSingleQuestionRefreshDoesNotExpandToTheLoadedRange() {
        let loaded = Set((0..<11).map { "q\($0)" })

        XCTAssertEqual(
            QuestionBankReaderWindowBounds.refreshIDs(changedIDs: ["q4"], loadedIDs: loaded),
            ["q4"]
        )
        XCTAssertTrue(
            QuestionBankReaderWindowBounds.refreshIDs(changedIDs: ["q28"], loadedIDs: loaded).isEmpty
        )
    }

    func testWindowAcceptanceRejectsStaleGenerationVersionAndCancellation() {
        let version = QuestionBankCatalogDataVersion(generationID: "g1", revision: 3)

        XCTAssertTrue(QuestionBankReaderWindowAcceptance.accepts(
            requestGeneration: 4,
            currentGeneration: 4,
            requestVersion: version,
            currentVersion: version,
            isCancelled: false
        ))
        XCTAssertFalse(QuestionBankReaderWindowAcceptance.accepts(
            requestGeneration: 3,
            currentGeneration: 4,
            requestVersion: version,
            currentVersion: version,
            isCancelled: false
        ))
        XCTAssertFalse(QuestionBankReaderWindowAcceptance.accepts(
            requestGeneration: 4,
            currentGeneration: 4,
            requestVersion: version,
            currentVersion: .init(generationID: "g1", revision: 4),
            isCancelled: false
        ))
        XCTAssertFalse(QuestionBankReaderWindowAcceptance.accepts(
            requestGeneration: 4,
            currentGeneration: 4,
            requestVersion: version,
            currentVersion: version,
            isCancelled: true
        ))
    }

    func testCrossPaperQuestionNumberFilterCanProduceAnEmptyWindow() throws {
        let version = QuestionBankCatalogDataVersion(generationID: "g1", revision: 1)
        let papers = [paper("p1", title: "测试卷", year: 2025, questionCount: 1)]
        let questions = [question("p1", id: "q1", module: "m1", number: 1, moduleSequence: 1)]
        let directory = QuestionBankCatalogReaderDirectory(
            catalogVersion: version,
            papers: papers,
            modules: [module("p1", id: "m1", title: "言语理解", sequence: 1)],
            questions: questions
        )
        let home = QuestionBankCatalogHomeSnapshot(
            status: status(questionCount: 1),
            catalogVersion: version,
            papers: papers,
            filterOptions: try QuestionBankCatalogHomeFilterOptions.prepare(papers: papers, questions: questions)
        )
        var filter = QuestionBankHomeFilter()
        filter.questionNumber = "999"

        let result = try QuestionBankReaderDirectoryBuilder.crossPaper(
            directory: directory,
            home: home,
            filter: filter,
            paperID: nil,
            scopedPaperIDs: nil,
            searchMatches: nil
        )

        XCTAssertTrue(result.questions.isEmpty)
    }

    private func readerQuestion(paper: String, id: String, material: String) -> QuestionBankReaderDirectoryQuestion {
        QuestionBankReaderDirectoryQuestion(
            summary: question(paper, id: id, module: "m1", number: 1, moduleSequence: 1, material: material),
            paperTitle: "试卷",
            moduleTitle: "言语理解",
            localOrdinal: 1
        )
    }

    private func paper(
        _ id: String,
        title: String,
        year: Int,
        questionCount: Int
    ) -> QuestionBankCatalogPaperSummary {
        QuestionBankCatalogPaperSummary(
            paperID: id,
            sourceCompoundID: "\(id)::paper::\(id)",
            title: title,
            year: year,
            examType: "国考",
            volume: "",
            provinceCode: nil,
            provinceName: nil,
            provinceLabels: [],
            questionCount: questionCount,
            metadataReadyVersion: 1
        )
    }

    private func module(
        _ paperID: String,
        id: String,
        title: String,
        sequence: Int
    ) -> QuestionBankCatalogModuleSummary {
        QuestionBankCatalogModuleSummary(
            paperID: paperID,
            moduleID: id,
            sourceCompoundID: "\(paperID)::module::\(id)",
            title: title,
            sequence: sequence,
            questionCount: 1,
            metadataReadyVersion: 1
        )
    }

    private func question(
        _ paperID: String,
        id: String,
        module moduleID: String,
        number: Int,
        moduleSequence: Int,
        material: String = ""
    ) -> QuestionBankCatalogQuestionSummary {
        let moduleTitle = moduleID == "m2" ? "资料分析" : "言语理解"
        let coarseModule = QuestionBankCoarseModule.classify(explicitModuleTitle: moduleTitle)
        let type = coarseModule.questionTypeFilter(for: "逻辑填空")
        return QuestionBankCatalogQuestionSummary(
            paperID: paperID,
            questionID: id,
            sourceCompoundID: "\(paperID)::question::\(id)",
            moduleID: moduleID,
            originalNumber: number,
            moduleSequence: moduleSequence,
            questionTypeSequence: QuestionBankCoarseModule.questionTypeSequence(module: coarseModule, typeFilter: type),
            coarseModule: coarseModule.rawValue,
            coarseQuestionType: type,
            materialID: material,
            isDifficult: false,
            needsReview: false,
            knowledgePoints: [],
            weaknessTags: [],
            sourceRevision: 1
        )
    }

    private func status(questionCount: Int) -> QuestionBankCatalogStatus {
        QuestionBankCatalogStatus(
            state: .ready,
            metadataReadyVersion: 1,
            indexedSourceRowCount: questionCount,
            totalSourceRowCount: questionCount,
            lastCompoundID: nil,
            invalidatedPaperID: nil,
            invalidatedModuleID: nil,
            invalidatedQuestionID: nil,
            questionCount: questionCount
        )
    }
}
