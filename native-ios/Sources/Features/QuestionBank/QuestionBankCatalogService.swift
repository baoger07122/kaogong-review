import Foundation
import SwiftData

enum QuestionBankCatalogIndexState: String, Equatable, Sendable {
    case notStarted
    case building
    case paused
    case ready
    case needsRepair
}

struct QuestionBankCatalogStatus: Sendable {
    let state: QuestionBankCatalogIndexState
    let metadataReadyVersion: Int
    let indexedSourceRowCount: Int
    let totalSourceRowCount: Int?
    let lastCompoundID: String?
    let invalidatedPaperID: String?
    let invalidatedModuleID: String?
    let invalidatedQuestionID: String?
    /// Nil until the full generation has been validated and published.
    let questionCount: Int?
}

struct QuestionBankCatalogBuildResult: Sendable {
    let status: QuestionBankCatalogStatus
    let resumed: Bool
}

struct QuestionBankCatalogPaperSummary: Sendable, Identifiable {
    let paperID: String
    let sourceCompoundID: String
    let title: String
    let year: Int
    let examType: String
    let volume: String
    let provinceCode: String?
    let provinceName: String?
    let provinceLabels: [String]
    let questionCount: Int
    let metadataReadyVersion: Int

    var id: String { paperID }
}

struct QuestionBankCatalogModuleSummary: Sendable, Identifiable {
    let paperID: String
    let moduleID: String
    let sourceCompoundID: String
    let title: String
    let sequence: Int
    let questionCount: Int
    let metadataReadyVersion: Int

    var id: String { sourceCompoundID }
}

/// Ordered identifiers and filter metadata only. It deliberately has no question
/// body, options, analysis, note, image, doodle, or source-payload field.
struct QuestionBankCatalogQuestionSummary: Sendable, Identifiable {
    let paperID: String
    let questionID: String
    let sourceCompoundID: String
    let moduleID: String
    let originalNumber: Int
    let moduleSequence: Int
    let questionTypeSequence: Int
    let coarseModule: String
    let coarseQuestionType: String
    let materialID: String
    let isDifficult: Bool
    let needsReview: Bool
    let knowledgePoints: [String]
    let weaknessTags: [String]
    let sourceRevision: Int

    var id: String { sourceCompoundID }
}

struct QuestionBankCatalogDataVersion: Hashable, Sendable {
    let generationID: String
    let revision: Int
}

struct QuestionBankCatalogQuestionRouteKey: Hashable, Sendable {
    let paperID: String
    let questionNumber: Int
}

struct QuestionBankCatalogQuestionRoute: Sendable {
    let moduleID: String
    let questionNumber: Int
    let moduleSequence: Int
    let questionTypeSequence: Int
    let sourceCompoundID: String
}

struct QuestionBankCatalogHomeFilterOptions: Sendable {
    let years: [String]
    let knownYears: Set<Int>
    let examTypes: [String]
    let provinces: [String]
    let knowledgePoints: [String]
    let weaknessTags: [String]
    let questionTypeOptionsByModule: [String: [String]]
    let questionRoutes: [QuestionBankCatalogQuestionRouteKey: QuestionBankCatalogQuestionRoute]

    static func prepare(
        papers: [QuestionBankCatalogPaperSummary],
        questions: [QuestionBankCatalogQuestionSummary]
    ) throws -> QuestionBankCatalogHomeFilterOptions {
        var knownYears = Set<Int>()
        var examTypes = Set<String>()
        var provinces = Set<String>()
        for paper in papers {
            try Task.checkCancellation()
            knownYears.insert(paper.year)
            if !paper.examType.isEmpty { examTypes.insert(paper.examType) }
            provinces.formUnion(paper.provinceLabels)
        }

        var knowledgePoints = Set<String>()
        var weaknessTags = Set<String>()
        var hasUnclassifiedByModule = Set<String>()
        var questionRoutes: [QuestionBankCatalogQuestionRouteKey: QuestionBankCatalogQuestionRoute] = [:]
        for question in questions {
            try Task.checkCancellation()
            knowledgePoints.formUnion(question.knowledgePoints)
            weaknessTags.formUnion(question.weaknessTags)
            if question.coarseQuestionType == "未分类" {
                hasUnclassifiedByModule.insert(question.coarseModule)
            }
            let key = QuestionBankCatalogQuestionRouteKey(
                paperID: question.paperID,
                questionNumber: question.originalNumber
            )
            let currentRoute = questionRoutes[key]
            let hasEarlierRoute = currentRoute.map { current in
                question.moduleSequence < current.moduleSequence
                    || (question.moduleSequence == current.moduleSequence
                        && question.questionTypeSequence < current.questionTypeSequence)
                    || (question.moduleSequence == current.moduleSequence
                        && question.questionTypeSequence == current.questionTypeSequence
                        && question.sourceCompoundID < current.sourceCompoundID)
            } ?? true
            if hasEarlierRoute {
                questionRoutes[key] = QuestionBankCatalogQuestionRoute(
                    moduleID: question.moduleID,
                    questionNumber: question.originalNumber,
                    moduleSequence: question.moduleSequence,
                    questionTypeSequence: question.questionTypeSequence,
                    sourceCompoundID: question.sourceCompoundID
                )
            }
        }

        var questionTypeOptionsByModule: [String: [String]] = [:]
        for module in QuestionBankCoarseModule.homeOrder where !module.allowedQuestionTypes.isEmpty {
            questionTypeOptionsByModule[module.rawValue] = module.allowedQuestionTypes
                + (hasUnclassifiedByModule.contains(module.rawValue) ? ["未分类"] : [])
        }
        return QuestionBankCatalogHomeFilterOptions(
            years: knownYears.map { String($0) }.sorted(by: >),
            knownYears: knownYears,
            examTypes: examTypes.sorted(),
            provinces: provinces.sorted(),
            knowledgePoints: knowledgePoints.sorted(),
            weaknessTags: weaknessTags.sorted(),
            questionTypeOptionsByModule: questionTypeOptionsByModule,
            questionRoutes: questionRoutes
        )
    }
}

struct QuestionBankCatalogHomeSnapshot: Sendable {
    let status: QuestionBankCatalogStatus
    let catalogVersion: QuestionBankCatalogDataVersion
    let papers: [QuestionBankCatalogPaperSummary]
    let filterOptions: QuestionBankCatalogHomeFilterOptions
}

struct QuestionBankCatalogSearchMatches: Sendable {
    let catalogVersion: QuestionBankCatalogDataVersion?
    let paperIDs: Set<String>
    let questionCompoundIDs: Set<String>
}

struct QuestionBankCatalogQuestionSummaryBatch: Sendable {
    let catalogVersion: QuestionBankCatalogDataVersion
    let questions: [QuestionBankCatalogQuestionSummary]
}

struct QuestionBankCatalogReaderDirectory: Sendable {
    let catalogVersion: QuestionBankCatalogDataVersion
    let papers: [QuestionBankCatalogPaperSummary]
    let modules: [QuestionBankCatalogModuleSummary]
    let questions: [QuestionBankCatalogQuestionSummary]
}

enum QuestionBankCatalogQuestionUpdateResult: Equatable, Sendable {
    case updated
    case requiresRebuild
}

enum QuestionBankCatalogServiceFailure: LocalizedError, Sendable {
    case invalidChunkSize
    case buildAlreadyRunning
    case notReady(QuestionBankCatalogIndexState)
    case sourceChanged
    case malformedSourceRecord(String)
    case inconsistentSourceRecord(String)
    case corruptProgress
    case corruptCatalogMetadata

    var errorDescription: String? {
        switch self {
        case .invalidChunkSize:
            "目录回填分块大小无效。"
        case .buildAlreadyRunning:
            "题库目录正在回填，请稍后重试。"
        case .notReady(let state):
            switch state {
            case .notStarted: "题库目录尚未建立。"
            case .building: "题库目录仍在回填。"
            case .paused: "题库目录回填已暂停，可从上次保存位置继续。"
            case .ready: "题库目录版本不匹配，请重新回填。"
            case .needsRepair: "题库目录需要修复，请重新回填。"
            }
        case .sourceChanged:
            "回填期间题库源记录发生变化，目录已标记为待修复。"
        case .malformedSourceRecord(let compoundID):
            "题库源记录无法解析：\(compoundID)"
        case .inconsistentSourceRecord(let compoundID):
            "题库源记录身份不一致：\(compoundID)"
        case .corruptProgress:
            "题库目录进度数据损坏，已要求重新回填。"
        case .corruptCatalogMetadata:
            "题库目录筛选元数据损坏。"
        }
    }
}

enum QuestionBankCatalogService {
    static let currentMetadataVersion = 3
    fileprivate static let indexID = "question-bank-catalog"
    private static let coordinator = QuestionBankCatalogBuildCoordinator()

    /// Starts a background build, or resumes after the last fully saved page.
    /// Each page and its cursor/counts are committed in the same ModelContext save.
    static func buildOrResume(
        in container: ModelContainer,
        chunkSize: Int = 128,
        onProgress: (@Sendable (QuestionBankCatalogStatus) -> Void)? = nil
    ) async throws -> QuestionBankCatalogBuildResult {
        guard (1...128).contains(chunkSize) else {
            throw QuestionBankCatalogServiceFailure.invalidChunkSize
        }
        let writePermit = try QuestionBankWriteCoordinator.acquire()
        defer { writePermit.release() }
        let containerID = ObjectIdentifier(container)
        guard await coordinator.acquire(containerID) else {
            throw QuestionBankCatalogServiceFailure.buildAlreadyRunning
        }

        let worker = Task.detached(priority: .utility) {
            try QuestionBankCatalogBuilder.build(
                container: container,
                chunkSize: chunkSize,
                onProgress: onProgress
            )
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            await coordinator.release(containerID)
            return result
        } catch {
            if error is CancellationError {
                await markPaused(in: container)
                if let pausedStatus = try? await status(in: container) {
                    onProgress?(pausedStatus)
                }
            }
            await coordinator.release(containerID)
            throw error
        }
    }

    static func status(in container: ModelContainer) async throws -> QuestionBankCatalogStatus {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            return try status(in: context)
        }.value
    }

    static func paperSummaries(
        in container: ModelContainer
    ) async throws -> [QuestionBankCatalogPaperSummary] {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let predicate = #Predicate<QuestionBankCatalogPaperRecord> {
                $0.generationID == generation
            }
            var descriptor = FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: predicate)
            descriptor.sortBy = [
                SortDescriptor(\QuestionBankCatalogPaperRecord.year, order: .reverse),
                SortDescriptor(\QuestionBankCatalogPaperRecord.title, order: .forward),
                SortDescriptor(\QuestionBankCatalogPaperRecord.paperID, order: .forward)
            ]
            return try context.fetch(descriptor).map(makePaperSummary)
        }.value
    }

    /// Returns only directory rows for a reader route. Question bodies and source
    /// asset rows remain in `QuestionBankRecord` and are loaded by bounded windows.
    static func readerDirectory(
        in container: ModelContainer,
        paperIDs: Set<String>? = nil
    ) async throws -> QuestionBankCatalogReaderDirectory {
        let worker = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let version = QuestionBankCatalogDataVersion(
                generationID: generation,
                revision: progress.catalogRevision
            )
            if let paperIDs, paperIDs.isEmpty {
                return QuestionBankCatalogReaderDirectory(
                    catalogVersion: version,
                    papers: [],
                    modules: [],
                    questions: []
                )
            }

            let paperPredicate: Predicate<QuestionBankCatalogPaperRecord>
            let modulePredicate: Predicate<QuestionBankCatalogModuleRecord>
            let questionPredicate: Predicate<QuestionBankCatalogQuestionRecord>
            if let paperIDs {
                let selectedPaperIDs = Array(paperIDs)
                paperPredicate = #Predicate {
                    $0.generationID == generation && selectedPaperIDs.contains($0.paperID)
                }
                modulePredicate = #Predicate {
                    $0.generationID == generation && selectedPaperIDs.contains($0.paperID)
                }
                questionPredicate = #Predicate {
                    $0.generationID == generation && selectedPaperIDs.contains($0.paperID)
                }
            } else {
                paperPredicate = #Predicate { $0.generationID == generation }
                modulePredicate = #Predicate { $0.generationID == generation }
                questionPredicate = #Predicate { $0.generationID == generation }
            }

            var paperDescriptor = FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: paperPredicate)
            paperDescriptor.sortBy = [
                SortDescriptor(\QuestionBankCatalogPaperRecord.year, order: .reverse),
                SortDescriptor(\QuestionBankCatalogPaperRecord.title, order: .forward),
                SortDescriptor(\QuestionBankCatalogPaperRecord.paperID, order: .forward)
            ]
            let papers = try context.fetch(paperDescriptor).map(makePaperSummary)

            var moduleDescriptor = FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: modulePredicate)
            moduleDescriptor.sortBy = [
                SortDescriptor(\QuestionBankCatalogModuleRecord.paperID, order: .forward),
                SortDescriptor(\QuestionBankCatalogModuleRecord.sequence, order: .forward),
                SortDescriptor(\QuestionBankCatalogModuleRecord.moduleID, order: .forward)
            ]
            let modules = try context.fetch(moduleDescriptor).map { record in
                QuestionBankCatalogModuleSummary(
                    paperID: record.paperID,
                    moduleID: record.moduleID,
                    sourceCompoundID: record.sourceCompoundID,
                    title: record.title,
                    sequence: record.sequence,
                    questionCount: record.questionCount,
                    metadataReadyVersion: record.metadataReadyVersion
                )
            }
            let questions = try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(
                predicate: questionPredicate,
                sortBy: questionSortDescriptors
            )).map(makeQuestionSummary)
            try Task.checkCancellation()
            return QuestionBankCatalogReaderDirectory(
                catalogVersion: version,
                papers: papers,
                modules: modules,
                questions: questions
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func currentDataVersion(in context: ModelContext) throws -> QuestionBankCatalogDataVersion {
        let progress = try requireReadyProgress(in: context)
        guard let generation = progress.readyGeneration else {
            throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
        }
        return QuestionBankCatalogDataVersion(generationID: generation, revision: progress.catalogRevision)
    }

    static func paperSummary(
        for paperID: String,
        in container: ModelContainer
    ) async throws -> QuestionBankCatalogPaperSummary? {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let predicate = #Predicate<QuestionBankCatalogPaperRecord> {
                $0.generationID == generation && $0.paperID == paperID
            }
            var descriptor = FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else { return nil }
            return try makePaperSummary(record)
        }.value
    }

    /// Loads directory metadata only. The default home path never fetches source
    /// question payloads to build its visible list or apply ordinary filters.
    static func homeSnapshot(in container: ModelContainer) async throws -> QuestionBankCatalogHomeSnapshot {
        let worker = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let catalogVersion = QuestionBankCatalogDataVersion(
                generationID: generation,
                revision: progress.catalogRevision
            )
            let paperPredicate = #Predicate<QuestionBankCatalogPaperRecord> {
                $0.generationID == generation
            }
            var paperDescriptor = FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: paperPredicate)
            paperDescriptor.sortBy = [
                SortDescriptor(\.year, order: .reverse),
                SortDescriptor(\.title, order: .forward),
                SortDescriptor(\.paperID, order: .forward)
            ]
            let papers = try context.fetch(paperDescriptor).map(makePaperSummary)
            let questionPredicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                $0.generationID == generation
            }
            let questionDescriptor = FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: questionPredicate)
            let questions = try context.fetch(questionDescriptor).map(makeQuestionSummary)
            let filterOptions = try QuestionBankCatalogHomeFilterOptions.prepare(
                papers: papers,
                questions: questions
            )
            return QuestionBankCatalogHomeSnapshot(
                status: try status(in: context),
                catalogVersion: catalogVersion,
                papers: papers,
                filterOptions: filterOptions
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Search uses a text projection stored with catalog rows, not source payload
    /// records, so even matching rows never materialize their JSON payloads.
    static func searchMatches(
        query: String,
        in container: ModelContainer
    ) async throws -> QuestionBankCatalogSearchMatches {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return QuestionBankCatalogSearchMatches(
                catalogVersion: nil,
                paperIDs: [],
                questionCompoundIDs: []
            )
        }
        let worker = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let catalogVersion = QuestionBankCatalogDataVersion(
                generationID: generation,
                revision: progress.catalogRevision
            )
            let paperPredicate = #Predicate<QuestionBankCatalogPaperRecord> {
                $0.generationID == generation && $0.searchText.localizedStandardContains(normalizedQuery)
            }
            let questionPredicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                $0.generationID == generation && $0.searchText.localizedStandardContains(normalizedQuery)
            }
            var paperIDs = Set<String>()
            var questionIDs = Set<String>()
            for record in try context.fetch(FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: paperPredicate)) {
                try Task.checkCancellation()
                paperIDs.insert(record.paperID)
            }
            for record in try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: questionPredicate)) {
                try Task.checkCancellation()
                questionIDs.insert(record.sourceCompoundID)
            }
            return QuestionBankCatalogSearchMatches(
                catalogVersion: catalogVersion,
                paperIDs: paperIDs,
                questionCompoundIDs: questionIDs
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func questionSummaries(
        for changes: [QuestionBankRecordChangeSignal.RecordChange],
        in container: ModelContainer
    ) async throws -> QuestionBankCatalogQuestionSummaryBatch {
        let questionChanges = changes.filter { $0.kind == .questionContent }
        let worker = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let version = QuestionBankCatalogDataVersion(
                generationID: generation,
                revision: progress.catalogRevision
            )
            let paperIDs = Set(questionChanges.map(\.paperID))
            let questionIDs = Set(questionChanges.map(\.recordID))
            guard !paperIDs.isEmpty, !questionIDs.isEmpty else {
                return QuestionBankCatalogQuestionSummaryBatch(catalogVersion: version, questions: [])
            }
            let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                $0.generationID == generation
                    && paperIDs.contains($0.paperID)
                    && questionIDs.contains($0.stableID)
            }
            let questions = try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(
                predicate: predicate,
                sortBy: questionSortDescriptors
            )).map(makeQuestionSummary)
            let requestedKeys = Set(questionChanges.map { "\($0.paperID)|\($0.recordID)" })
            let returnedKeys = Set(questions.map { "\($0.paperID)|\($0.questionID)" })
            guard requestedKeys.isSubset(of: returnedKeys) else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            return QuestionBankCatalogQuestionSummaryBatch(catalogVersion: version, questions: questions)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func questionSummaries(
        forSourceCompoundIDs sourceCompoundIDs: Set<String>?,
        in container: ModelContainer
    ) async throws -> QuestionBankCatalogQuestionSummaryBatch {
        let worker = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let version = QuestionBankCatalogDataVersion(
                generationID: generation,
                revision: progress.catalogRevision
            )
            let descriptor: FetchDescriptor<QuestionBankCatalogQuestionRecord>
            if let sourceCompoundIDs {
                guard !sourceCompoundIDs.isEmpty else {
                    return QuestionBankCatalogQuestionSummaryBatch(catalogVersion: version, questions: [])
                }
                let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                    $0.generationID == generation && sourceCompoundIDs.contains($0.sourceCompoundID)
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: questionSortDescriptors)
            } else {
                let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                    $0.generationID == generation
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: questionSortDescriptors)
            }
            let questions = try context.fetch(descriptor).map(makeQuestionSummary)
            return QuestionBankCatalogQuestionSummaryBatch(catalogVersion: version, questions: questions)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func questionOwners(
        forQuestionIDs questionIDs: Set<String>,
        in container: ModelContainer
    ) async throws -> [String: Set<String>] {
        let worker = Task.detached(priority: .userInitiated) {
            try questionOwners(forQuestionIDs: questionIDs, in: ModelContext(container))
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func questionOwners(
        forQuestionIDs questionIDs: Set<String>,
        in context: ModelContext
    ) throws -> [String: Set<String>] {
        guard !questionIDs.isEmpty else { return [:] }
        let progress = try requireReadyProgress(in: context)
        guard let generation = progress.readyGeneration else {
            throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
        }
        let ids = Array(questionIDs)
        let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
            $0.generationID == generation && ids.contains($0.stableID)
        }
        var owners: [String: Set<String>] = [:]
        for record in try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: predicate)) {
            owners[record.stableID, default: []].insert(record.paperID)
        }
        return owners
    }

    static func moduleSummaries(
        for paperID: String,
        in container: ModelContainer
    ) async throws -> [QuestionBankCatalogModuleSummary] {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let predicate = #Predicate<QuestionBankCatalogModuleRecord> {
                $0.generationID == generation && $0.paperID == paperID
            }
            var descriptor = FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: predicate)
            descriptor.sortBy = [
                SortDescriptor(\QuestionBankCatalogModuleRecord.sequence, order: .forward),
                SortDescriptor(\QuestionBankCatalogModuleRecord.moduleID, order: .forward)
            ]
            return try context.fetch(descriptor).map { record in
                QuestionBankCatalogModuleSummary(
                    paperID: record.paperID,
                    moduleID: record.moduleID,
                    sourceCompoundID: record.sourceCompoundID,
                    title: record.title,
                    sequence: record.sequence,
                    questionCount: record.questionCount,
                    metadataReadyVersion: record.metadataReadyVersion
                )
            }
        }.value
    }

    static func questionIDs(
        for paperID: String,
        moduleID: String? = nil,
        in container: ModelContainer
    ) async throws -> [QuestionBankCatalogQuestionSummary] {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let progress = try requireReadyProgress(in: context)
            guard let generation = progress.readyGeneration else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let descriptor: FetchDescriptor<QuestionBankCatalogQuestionRecord>
            if let moduleID {
                let selectedModuleID = moduleID
                let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                    $0.generationID == generation && $0.paperID == paperID
                        && $0.moduleID == selectedModuleID
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: questionSortDescriptors)
            } else {
                let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                    $0.generationID == generation && $0.paperID == paperID
                }
                descriptor = FetchDescriptor(predicate: predicate, sortBy: questionSortDescriptors)
            }
            return try context.fetch(descriptor).map(makeQuestionSummary)
        }.value
    }

    /// Marking any source change hides the old generation until a complete rebuild.
    /// These entry points are intended to be called in the same writer context as
    /// the corresponding QuestionBankRecord mutation.
    @MainActor
    static func invalidatePaper(_ paperID: String, context: ModelContext) throws {
        try markNeedsRepair(paperID: paperID, moduleID: nil, questionID: nil, context: context)
    }

    @MainActor
    static func invalidateModule(
        paperID: String,
        moduleID: String,
        context: ModelContext
    ) throws {
        try markNeedsRepair(paperID: paperID, moduleID: moduleID, questionID: nil, context: context)
    }

    @MainActor
    static func invalidateQuestion(
        paperID: String,
        questionID: String,
        context: ModelContext
    ) throws {
        try markNeedsRepair(paperID: paperID, moduleID: nil, questionID: questionID, context: context)
    }

    /// Refreshes filter fields for an existing question when its identity/order did
    /// not change. Structural edits must use the corresponding invalidation API.
    @MainActor
    static func updateQuestion(
        paperID: String,
        questionID: String,
        context: ModelContext
    ) throws -> QuestionBankCatalogQuestionUpdateResult {
        let questionKind = QuestionBankRepository.questionKind
        let questionPredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID && $0.kind == questionKind && $0.stableID == questionID
        }
        var questionDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: questionPredicate)
        questionDescriptor.fetchLimit = 1
        guard let source = try context.fetch(questionDescriptor).first,
              let question = source.decoded(QuestionBankQuestion.self),
              question.paperID == paperID,
              question.id == questionID,
              source.moduleID == question.moduleID else {
            try invalidateQuestion(paperID: paperID, questionID: questionID, context: context)
            return .requiresRebuild
        }

        guard let progress = try fetchProgress(in: context),
              QuestionBankCatalogIndexState(rawValue: progress.stateRawValue) == .ready,
              progress.metadataReadyVersion == currentMetadataVersion,
              let generation = progress.readyGeneration else {
            try invalidateQuestion(paperID: paperID, questionID: questionID, context: context)
            return .requiresRebuild
        }
        let sourceCompoundID = source.compoundID
        let catalogPredicate = #Predicate<QuestionBankCatalogQuestionRecord> {
            $0.sourceCompoundID == sourceCompoundID
        }
        var catalogDescriptor = FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: catalogPredicate)
        catalogDescriptor.fetchLimit = 1
        guard let catalog = try context.fetch(catalogDescriptor).first,
              catalog.generationID == generation else {
            try invalidateQuestion(paperID: paperID, questionID: questionID, context: context)
            return .requiresRebuild
        }
        guard catalog.moduleID == question.moduleID,
              catalog.originalNumber == question.number else {
            try invalidateModule(paperID: paperID, moduleID: catalog.moduleID, context: context)
            return .requiresRebuild
        }

        let selectedModuleID = question.moduleID
        let modulePredicate = #Predicate<QuestionBankCatalogModuleRecord> {
            $0.paperID == paperID && $0.moduleID == selectedModuleID && $0.generationID == generation
        }
        var moduleDescriptor = FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: modulePredicate)
        moduleDescriptor.fetchLimit = 1
        let module = try context.fetch(moduleDescriptor).first
        let coarseModule = QuestionBankCoarseModule.classify(
            explicitModuleTitle: module?.title ?? question.subject
        )
        let questionFilterMetadata = try makeQuestionFilterMetadata(question, coarseModule: coarseModule)
        let catalogMetadataChanged = catalog.isDifficult != questionFilterMetadata.isDifficult
            || catalog.needsReview != questionFilterMetadata.needsReview
            || catalog.knowledgePointsData != questionFilterMetadata.knowledgePointsData
            || catalog.weaknessTagsData != questionFilterMetadata.weaknessTagsData
            || catalog.coarseModule != questionFilterMetadata.coarseModule
            || catalog.coarseQuestionType != questionFilterMetadata.coarseQuestionType
            || catalog.questionTypeSequence != questionFilterMetadata.questionTypeSequence
            || catalog.materialID != question.materialID
            || catalog.searchText != source.searchText
        catalog.isDifficult = questionFilterMetadata.isDifficult
        catalog.needsReview = questionFilterMetadata.needsReview
        catalog.knowledgePointsData = questionFilterMetadata.knowledgePointsData
        catalog.weaknessTagsData = questionFilterMetadata.weaknessTagsData
        catalog.coarseModule = questionFilterMetadata.coarseModule
        catalog.coarseQuestionType = questionFilterMetadata.coarseQuestionType
        catalog.questionTypeSequence = questionFilterMetadata.questionTypeSequence
        catalog.materialID = question.materialID
        catalog.searchText = source.searchText
        catalog.sourceRevision = source.contentRevision
        catalog.metadataReadyVersion = currentMetadataVersion
        if catalogMetadataChanged { progress.catalogRevision &+= 1 }
        return .updated
    }

    /// Rebuilds only one paper's derived rows in the caller's transaction. This is
    /// for imports, replacements, metadata changes, and deletions; single-question
    /// edits should use updateQuestion instead.
    @MainActor
    static func refreshPaper(_ paperID: String, context: ModelContext) throws {
        try QuestionBankCatalogBuilder.refreshPaper(paperID: paperID, context: context)
    }

    fileprivate static let questionSortDescriptors: [SortDescriptor<QuestionBankCatalogQuestionRecord>] = [
        SortDescriptor(\QuestionBankCatalogQuestionRecord.moduleSequence, order: .forward),
        SortDescriptor(\QuestionBankCatalogQuestionRecord.questionTypeSequence, order: .forward),
        SortDescriptor(\QuestionBankCatalogQuestionRecord.originalNumber, order: .forward),
        SortDescriptor(\QuestionBankCatalogQuestionRecord.sourceCompoundID, order: .forward)
    ]

    fileprivate static func status(in context: ModelContext) throws -> QuestionBankCatalogStatus {
        guard let progress = try fetchProgress(in: context) else {
            return QuestionBankCatalogStatus(
                state: .notStarted,
                metadataReadyVersion: currentMetadataVersion,
                indexedSourceRowCount: 0,
                totalSourceRowCount: nil,
                lastCompoundID: nil,
                invalidatedPaperID: nil,
                invalidatedModuleID: nil,
                invalidatedQuestionID: nil,
                questionCount: nil
            )
        }
        let decodedState = QuestionBankCatalogIndexState(rawValue: progress.stateRawValue) ?? .needsRepair
        let isCurrentReady = decodedState == .ready
            && progress.metadataReadyVersion == currentMetadataVersion
            && progress.readyGeneration != nil
        let visibleState = isCurrentReady
            ? QuestionBankCatalogIndexState.ready
            : (decodedState == .ready ? .needsRepair : decodedState)
        let questionCount = isCurrentReady
            ? try decodeCounts(progress.paperQuestionCountsData).values.reduce(0, +)
            : nil
        return QuestionBankCatalogStatus(
            state: visibleState,
            metadataReadyVersion: progress.metadataReadyVersion,
            indexedSourceRowCount: progress.indexedSourceRowCount,
            totalSourceRowCount: progress.totalSourceRowCount,
            lastCompoundID: progress.lastCompoundID,
            invalidatedPaperID: progress.invalidatedPaperID,
            invalidatedModuleID: progress.invalidatedModuleID,
            invalidatedQuestionID: progress.invalidatedQuestionID,
            questionCount: questionCount
        )
    }

    private static func requireReadyProgress(in context: ModelContext) throws -> QuestionBankCatalogProgressRecord {
        guard let progress = try fetchProgress(in: context) else {
            throw QuestionBankCatalogServiceFailure.notReady(.notStarted)
        }
        guard QuestionBankCatalogIndexState(rawValue: progress.stateRawValue) == .ready,
              progress.metadataReadyVersion == currentMetadataVersion,
              progress.readyGeneration != nil else {
            throw QuestionBankCatalogServiceFailure.notReady(
                QuestionBankCatalogIndexState(rawValue: progress.stateRawValue) ?? .needsRepair
            )
        }
        return progress
    }

    fileprivate static func fetchProgress(in context: ModelContext) throws -> QuestionBankCatalogProgressRecord? {
        let selectedIndexID = indexID
        let predicate = #Predicate<QuestionBankCatalogProgressRecord> {
            $0.indexID == selectedIndexID
        }
        var descriptor = FetchDescriptor<QuestionBankCatalogProgressRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func markPaused(in container: ModelContainer) async {
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            guard let progress = try? fetchProgress(in: context),
                  progress.stateRawValue == QuestionBankCatalogIndexState.building.rawValue else { return }
            progress.stateRawValue = QuestionBankCatalogIndexState.paused.rawValue
            progress.updatedAt = .now
            try? context.save()
        }.value
    }

    @MainActor
    private static func markNeedsRepair(
        paperID: String?,
        moduleID: String?,
        questionID: String?,
        context: ModelContext
    ) throws {
        let progress: QuestionBankCatalogProgressRecord
        if let existing = try fetchProgress(in: context) {
            progress = existing
        } else {
            let created = QuestionBankCatalogProgressRecord(
                indexID: indexID,
                metadataReadyVersion: currentMetadataVersion
            )
            context.insert(created)
            progress = created
        }
        progress.stateRawValue = QuestionBankCatalogIndexState.needsRepair.rawValue
        progress.readyGeneration = nil
        progress.buildGeneration = nil
        progress.lastCompoundID = nil
        progress.indexedSourceRowCount = 0
        progress.totalSourceRowCount = nil
        progress.paperQuestionCountsData = Data("{}".utf8)
        progress.moduleQuestionCountsData = Data("{}".utf8)
        progress.catalogRevision &+= 1
        progress.invalidatedPaperID = paperID
        progress.invalidatedModuleID = moduleID
        progress.invalidatedQuestionID = questionID
        progress.updatedAt = .now
    }

    private static func makeQuestionSummary(
        _ record: QuestionBankCatalogQuestionRecord
    ) throws -> QuestionBankCatalogQuestionSummary {
        guard let knowledgePoints = try? JSONDecoder().decode([String].self, from: record.knowledgePointsData),
              let weaknessTags = try? JSONDecoder().decode([String].self, from: record.weaknessTagsData) else {
            throw QuestionBankCatalogServiceFailure.corruptCatalogMetadata
        }
        return QuestionBankCatalogQuestionSummary(
            paperID: record.paperID,
            questionID: record.stableID,
            sourceCompoundID: record.sourceCompoundID,
            moduleID: record.moduleID,
            originalNumber: record.originalNumber,
            moduleSequence: record.moduleSequence,
            questionTypeSequence: record.questionTypeSequence,
            coarseModule: record.coarseModule,
            coarseQuestionType: record.coarseQuestionType,
            materialID: record.materialID,
            isDifficult: record.isDifficult,
            needsReview: record.needsReview,
            knowledgePoints: knowledgePoints,
            weaknessTags: weaknessTags,
            sourceRevision: record.sourceRevision
        )
    }

    private static func makePaperSummary(
        _ record: QuestionBankCatalogPaperRecord
    ) throws -> QuestionBankCatalogPaperSummary {
        guard let provinceLabels = try? JSONDecoder().decode([String].self, from: record.provinceLabelsData) else {
            throw QuestionBankCatalogServiceFailure.corruptCatalogMetadata
        }
        return QuestionBankCatalogPaperSummary(
            paperID: record.paperID,
            sourceCompoundID: record.sourceCompoundID,
            title: record.title,
            year: record.year,
            examType: record.examType,
            volume: record.volume,
            provinceCode: record.provinceCode,
            provinceName: record.provinceName,
            provinceLabels: provinceLabels,
            questionCount: record.questionCount,
            metadataReadyVersion: record.metadataReadyVersion
        )
    }

    fileprivate static func makeQuestionFilterMetadata(
        _ question: QuestionBankQuestion
    ) throws -> QuestionBankCatalogQuestionFilterMetadata {
        let coarseModule = QuestionBankCoarseModule.classify(explicitModuleTitle: question.subject)
        return try makeQuestionFilterMetadata(question, coarseModule: coarseModule)
    }

    fileprivate static func makeQuestionFilterMetadata(
        _ question: QuestionBankQuestion,
        coarseModule: QuestionBankCoarseModule
    ) throws -> QuestionBankCatalogQuestionFilterMetadata {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return QuestionBankCatalogQuestionFilterMetadata(
            isDifficult: question.isDifficult ?? false,
            needsReview: question.needsReview ?? false,
            knowledgePointsData: try encoder.encode(question.knowledgePoints ?? []),
            weaknessTagsData: try encoder.encode(question.weaknessTags ?? []),
            coarseModule: coarseModule.rawValue,
            coarseQuestionType: coarseModule.questionTypeFilter(for: question.type),
            questionTypeSequence: QuestionBankCoarseModule.questionTypeSequence(
                module: coarseModule,
                typeFilter: coarseModule.questionTypeFilter(for: question.type)
            )
        )
    }

    private static func decodeCounts(_ data: Data) throws -> [String: Int] {
        try JSONDecoder().decode([String: Int].self, from: data)
    }
}

private actor QuestionBankCatalogBuildCoordinator {
    private var activeContainers = Set<ObjectIdentifier>()

    func acquire(_ containerID: ObjectIdentifier) -> Bool {
        activeContainers.insert(containerID).inserted
    }

    func release(_ containerID: ObjectIdentifier) {
        activeContainers.remove(containerID)
    }
}

private struct QuestionBankCatalogQuestionFilterMetadata {
    let isDifficult: Bool
    let needsReview: Bool
    let knowledgePointsData: Data
    let weaknessTagsData: Data
    let coarseModule: String
    let coarseQuestionType: String
    let questionTypeSequence: Int
}

private struct QuestionBankCatalogModuleReference: Sendable {
    let title: String
    let sequence: Int
}

private struct QuestionBankCatalogSourceRow: Sendable {
    let compoundID: String
    let paperID: String
    let kind: String
    let stableID: String
    let moduleID: String?
    let questionNumber: Int?
    let contentRevision: Int
    let searchText: String
    let payload: Data

    init(_ record: QuestionBankRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        kind = record.kind
        stableID = record.stableID
        moduleID = record.moduleID
        questionNumber = record.questionNumber
        contentRevision = record.contentRevision
        searchText = record.searchText
        payload = record.payload
    }
}

private struct QuestionBankCatalogSourceRevision: Sendable {
    let compoundID: String
    let paperID: String
    let kind: String
    let moduleID: String?
    let contentRevision: Int

    init(_ record: QuestionBankRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        kind = record.kind
        moduleID = record.moduleID
        contentRevision = record.contentRevision
    }
}

private enum QuestionBankCatalogDecodedRow: Sendable {
    case paper(QuestionBankCatalogPaperValue)
    case module(QuestionBankCatalogModuleValue)
    case question(QuestionBankCatalogQuestionValue)
}

private struct QuestionBankCatalogPaperValue: Sendable {
    let source: QuestionBankCatalogSourceRevision
    let title: String
    let year: Int
    let examType: String
    let volume: String
    let searchText: String
    let provinceCode: String?
    let provinceName: String?
    let provinceLabelsData: Data
}

private struct QuestionBankCatalogModuleValue: Sendable {
    let source: QuestionBankCatalogSourceRevision
    let moduleID: String
    let title: String
    let sequence: Int
}

private struct QuestionBankCatalogQuestionValue: Sendable {
    let source: QuestionBankCatalogSourceRevision
    let questionID: String
    let moduleID: String
    let originalNumber: Int
    let moduleSequence: Int
    let questionTypeSequence: Int
    let searchText: String
    let coarseModule: String
    let coarseQuestionType: String
    let materialID: String
    let isDifficult: Bool
    let needsReview: Bool
    let knowledgePointsData: Data
    let weaknessTagsData: Data
}

private final class QuestionBankCatalogChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var didChange = false
    private var firstPaperID: String?

    func record(_ notification: Notification) {
        lock.lock()
        defer { lock.unlock() }
        didChange = true
        if firstPaperID == nil {
            firstPaperID = (notification.userInfo?[QuestionBankRecordChangeSignal.paperIDsKey] as? [String])?.first
        }
    }

    func snapshot() -> (didChange: Bool, paperID: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (didChange, firstPaperID)
    }
}

private enum QuestionBankCatalogBuilder {
    private static let indexID = QuestionBankCatalogService.indexID
    private static let metadataVersion = QuestionBankCatalogService.currentMetadataVersion

    static func build(
        container: ModelContainer,
        chunkSize: Int,
        onProgress: (@Sendable (QuestionBankCatalogStatus) -> Void)?
    ) throws -> QuestionBankCatalogBuildResult {
        let changeFlag = QuestionBankCatalogChangeFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: QuestionBankRecordChangeSignal.notification,
            object: nil,
            queue: nil
        ) { notification in
            changeFlag.record(notification)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try Task.checkCancellation()
        let startContext = ModelContext(container)
        let progress = try fetchOrCreateProgress(in: startContext)
        if QuestionBankCatalogIndexState(rawValue: progress.stateRawValue) == .ready,
           progress.metadataReadyVersion == metadataVersion,
           progress.readyGeneration != nil {
            let readyStatus = try QuestionBankCatalogService.status(in: startContext)
            onProgress?(readyStatus)
            return QuestionBankCatalogBuildResult(
                status: readyStatus,
                resumed: false
            )
        }

        let priorState = QuestionBankCatalogIndexState(rawValue: progress.stateRawValue)
        let canResume = (priorState == .building || priorState == .paused)
            && progress.metadataReadyVersion == metadataVersion
            && progress.buildGeneration != nil
            && progress.indexedSourceRowCount >= 0
            && ((progress.lastCompoundID == nil && progress.indexedSourceRowCount == 0)
                || (progress.lastCompoundID != nil && progress.indexedSourceRowCount > 0))
            && (try? decodeCounts(progress.paperQuestionCountsData)) != nil
            && (try? decodeCounts(progress.moduleQuestionCountsData)) != nil
        let generation = canResume ? progress.buildGeneration! : UUID().uuidString
        let startCursor = canResume ? progress.lastCompoundID : nil
        var paperCounts = canResume ? try decodeCounts(progress.paperQuestionCountsData) : [:]
        var moduleCounts = canResume ? try decodeCounts(progress.moduleQuestionCountsData) : [:]
        var processedRows = canResume ? progress.indexedSourceRowCount : 0
        progress.totalSourceRowCount = try startContext.fetchCount(sourceDescriptor())
        if !canResume {
            progress.stateRawValue = QuestionBankCatalogIndexState.building.rawValue
            progress.metadataReadyVersion = metadataVersion
            progress.buildGeneration = generation
            progress.readyGeneration = nil
            progress.lastCompoundID = nil
            progress.paperQuestionCountsData = try encodeCounts([String: Int]())
            progress.moduleQuestionCountsData = try encodeCounts([String: Int]())
            progress.indexedSourceRowCount = 0
            progress.invalidatedPaperID = nil
            progress.invalidatedModuleID = nil
            progress.invalidatedQuestionID = nil
            progress.updatedAt = .now
        } else {
            progress.stateRawValue = QuestionBankCatalogIndexState.building.rawValue
            progress.readyGeneration = nil
            progress.updatedAt = .now
        }
        try startContext.save()
        onProgress?(try QuestionBankCatalogService.status(in: startContext))

        if canResume, let startCursor {
            try verifyCompletedPrefix(
                container: container,
                generation: generation,
                through: startCursor,
                expectedCount: processedRows,
                expectedPaperCounts: paperCounts,
                expectedModuleCounts: moduleCounts,
                changeFlag: changeFlag
            )
        }

        var moduleReferences = try loadModuleReferences(container: container, generation: generation)
        var cursor = startCursor
        while true {
            try Task.checkCancellation()
            try failIfSourceChanged(changeFlag, container: container, generation: generation)

            var sourcePage = try readSourcePage(
                from: container,
                after: cursor,
                limit: chunkSize
            )
            guard !sourcePage.isEmpty else { break }

            var decodedPage: [QuestionBankCatalogDecodedRow] = []
            decodedPage.reserveCapacity(sourcePage.count)
            for source in sourcePage {
                try Task.checkCancellation()
                decodedPage.append(try decode(source, moduleReferences: &moduleReferences))
            }
            let revisionPage = decodedPage.map(sourceRevision)
            sourcePage.removeAll(keepingCapacity: false)

            try Task.checkCancellation()
            try failIfSourceChanged(changeFlag, container: container, generation: generation)
            try verifyCurrentSourceRows(
                revisionPage,
                in: ModelContext(container),
                generation: generation
            )
            let writeContext = ModelContext(container)
            guard let currentProgress = try fetchProgress(in: writeContext),
                  currentProgress.stateRawValue == QuestionBankCatalogIndexState.building.rawValue,
                  currentProgress.buildGeneration == generation,
                  currentProgress.lastCompoundID == cursor else {
                throw QuestionBankCatalogServiceFailure.sourceChanged
            }
            var existingPageRecords = try fetchExistingCatalogRows(for: decodedPage, in: writeContext)

            for entry in decodedPage {
                try Task.checkCancellation()
                upsert(
                    entry,
                    generation: generation,
                    existing: &existingPageRecords,
                    in: writeContext
                )
                switch entry {
                case .paper:
                    break
                case .module:
                    break
                case .question(let question):
                    paperCounts[question.source.paperID, default: 0] += 1
                    moduleCounts[moduleCountKey(paperID: question.source.paperID, moduleID: question.moduleID), default: 0] += 1
                }
            }

            let lastID = revisionPage[revisionPage.count - 1].compoundID
            guard cursor.map({ lastID > $0 }) ?? true else {
                throw QuestionBankCatalogServiceFailure.inconsistentSourceRecord(lastID)
            }
            currentProgress.lastCompoundID = lastID
            processedRows += revisionPage.count
            currentProgress.indexedSourceRowCount = processedRows
            currentProgress.paperQuestionCountsData = try encodeCounts(paperCounts)
            currentProgress.moduleQuestionCountsData = try encodeCounts(moduleCounts)
            currentProgress.updatedAt = .now
            try Task.checkCancellation()
            try writeContext.save()
            onProgress?(try QuestionBankCatalogService.status(in: writeContext))
            cursor = lastID
        }

        try Task.checkCancellation()
        try failIfSourceChanged(changeFlag, container: container, generation: generation)
        try finish(
            container: container,
            generation: generation,
            paperCounts: paperCounts,
            moduleCounts: moduleCounts,
            processedRows: processedRows
        )
        try failIfSourceChanged(changeFlag, container: container, generation: generation)
        let statusContext = ModelContext(container)
        let readyStatus = try QuestionBankCatalogService.status(in: statusContext)
        onProgress?(readyStatus)
        return QuestionBankCatalogBuildResult(
            status: readyStatus,
            resumed: canResume
        )
    }

    private static func fetchOrCreateProgress(in context: ModelContext) throws -> QuestionBankCatalogProgressRecord {
        let selectedIndexID = indexID
        let predicate = #Predicate<QuestionBankCatalogProgressRecord> { $0.indexID == selectedIndexID }
        var descriptor = FetchDescriptor<QuestionBankCatalogProgressRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let progress = try context.fetch(descriptor).first { return progress }
        let progress = QuestionBankCatalogProgressRecord(indexID: indexID, metadataReadyVersion: metadataVersion)
        context.insert(progress)
        try context.save()
        return progress
    }

    private static func fetchProgress(in context: ModelContext) throws -> QuestionBankCatalogProgressRecord? {
        let selectedIndexID = indexID
        let predicate = #Predicate<QuestionBankCatalogProgressRecord> { $0.indexID == selectedIndexID }
        var descriptor = FetchDescriptor<QuestionBankCatalogProgressRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchSourcePage(
        in context: ModelContext,
        after cursor: String?,
        limit: Int
    ) throws -> [QuestionBankRecord] {
        let paperKind = QuestionBankRepository.paperKind
        let moduleKind = QuestionBankRepository.moduleKind
        let questionKind = QuestionBankRepository.questionKind
        let lowerBound = cursor ?? ""
        let predicate = #Predicate<QuestionBankRecord> {
            $0.compoundID > lowerBound
                && ($0.kind == paperKind || $0.kind == moduleKind || $0.kind == questionKind)
        }
        let descriptor = FetchDescriptor<QuestionBankRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\QuestionBankRecord.compoundID, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    private static func readSourcePage(
        from container: ModelContainer,
        after cursor: String?,
        limit: Int
    ) throws -> [QuestionBankCatalogSourceRow] {
        let context = ModelContext(container)
        return try fetchSourcePage(in: context, after: cursor, limit: limit)
            .map(QuestionBankCatalogSourceRow.init)
    }

    @MainActor
    static func refreshPaper(paperID: String, context: ModelContext) throws {
        guard let progress = try QuestionBankCatalogService.fetchProgress(in: context) else { return }
        let state = QuestionBankCatalogIndexState(rawValue: progress.stateRawValue)
        guard state == .ready,
              progress.metadataReadyVersion == metadataVersion,
              let generation = progress.readyGeneration else {
            if state == .building || state == .ready || state == nil {
                if let generation = progress.buildGeneration ?? progress.readyGeneration {
                    try markNeedsRepair(in: context, generation: generation, paperID: paperID)
                } else {
                    progress.stateRawValue = QuestionBankCatalogIndexState.needsRepair.rawValue
                    progress.readyGeneration = nil
                    progress.buildGeneration = nil
                    progress.lastCompoundID = nil
                    progress.indexedSourceRowCount = 0
                    progress.totalSourceRowCount = nil
                    progress.catalogRevision &+= 1
                    progress.updatedAt = .now
                }
            }
            return
        }

        let paperKind = QuestionBankRepository.paperKind
        let moduleKind = QuestionBankRepository.moduleKind
        let questionKind = QuestionBankRepository.questionKind
        let sourcePredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID
                && ($0.kind == paperKind || $0.kind == moduleKind || $0.kind == questionKind)
        }
        let sourceDescriptor = FetchDescriptor<QuestionBankRecord>(
            predicate: sourcePredicate,
            sortBy: [SortDescriptor(\QuestionBankRecord.compoundID, order: .forward)]
        )
        let sourceRows = try context.fetch(sourceDescriptor).map(QuestionBankCatalogSourceRow.init)

        let oldPaperPredicate = #Predicate<QuestionBankCatalogPaperRecord> {
            $0.generationID == generation && $0.paperID == paperID
        }
        let oldModulePredicate = #Predicate<QuestionBankCatalogModuleRecord> {
            $0.generationID == generation && $0.paperID == paperID
        }
        let oldQuestionPredicate = #Predicate<QuestionBankCatalogQuestionRecord> {
            $0.generationID == generation && $0.paperID == paperID
        }
        let oldPapers = try context.fetch(FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: oldPaperPredicate))
        let oldModules = try context.fetch(FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: oldModulePredicate))
        let oldQuestions = try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: oldQuestionPredicate))
        let oldRowCount = oldPapers.count + oldModules.count + oldQuestions.count
        guard progress.indexedSourceRowCount >= oldRowCount else {
            try markNeedsRepair(in: context, generation: generation, paperID: paperID)
            return
        }

        var moduleReferences: [String: QuestionBankCatalogModuleReference] = [:]
        let entries = try sourceRows.map { try decode($0, moduleReferences: &moduleReferences) }
        let containsPaper = entries.contains { entry in
            if case .paper = entry { return true }
            return false
        }
        guard (entries.isEmpty || containsPaper) else {
            throw QuestionBankCatalogServiceFailure.inconsistentSourceRecord(paperID)
        }

        var existing = ExistingPageCatalogRows(
            papers: Dictionary(oldPapers.map { ($0.sourceCompoundID, $0) }, uniquingKeysWith: { first, _ in first }),
            modules: Dictionary(oldModules.map { ($0.sourceCompoundID, $0) }, uniquingKeysWith: { first, _ in first }),
            questions: Dictionary(oldQuestions.map { ($0.sourceCompoundID, $0) }, uniquingKeysWith: { first, _ in first })
        )
        for entry in entries {
            upsert(entry, generation: generation, existing: &existing, in: context)
        }
        let desiredIDs = Set(entries.map { sourceRevision($0).compoundID })
        for record in oldPapers where !desiredIDs.contains(record.sourceCompoundID) { context.delete(record) }
        for record in oldModules where !desiredIDs.contains(record.sourceCompoundID) { context.delete(record) }
        for record in oldQuestions where !desiredIDs.contains(record.sourceCompoundID) { context.delete(record) }

        let papers = try context.fetch(FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: oldPaperPredicate))
        let modules = try context.fetch(FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: oldModulePredicate))
        var moduleCounts: [String: Int] = [:]
        var questionCount = 0
        for entry in entries {
            guard case .question(let question) = entry else { continue }
            questionCount += 1
            moduleCounts[question.moduleID, default: 0] += 1
        }
        for paper in papers {
            paper.questionCount = questionCount
            paper.metadataReadyVersion = metadataVersion
        }
        for module in modules {
            module.questionCount = moduleCounts[module.moduleID] ?? 0
            module.metadataReadyVersion = metadataVersion
        }

        var paperQuestionCounts = try decodeCounts(progress.paperQuestionCountsData)
        var allModuleQuestionCounts = try decodeCounts(progress.moduleQuestionCountsData)
        let moduleKeyPrefix = "\(paperID.utf8.count):\(paperID)"
        allModuleQuestionCounts = allModuleQuestionCounts.filter { !$0.key.hasPrefix(moduleKeyPrefix) }
        if papers.isEmpty {
            paperQuestionCounts.removeValue(forKey: paperID)
        } else {
            paperQuestionCounts[paperID] = questionCount
        }
        for (moduleID, count) in moduleCounts where count > 0 {
            allModuleQuestionCounts[moduleCountKey(paperID: paperID, moduleID: moduleID)] = count
        }
        progress.paperQuestionCountsData = try encodeCounts(paperQuestionCounts)
        progress.moduleQuestionCountsData = try encodeCounts(allModuleQuestionCounts)
        progress.catalogRevision &+= 1
        progress.indexedSourceRowCount = progress.indexedSourceRowCount - oldRowCount + entries.count
        progress.totalSourceRowCount = progress.indexedSourceRowCount
        progress.updatedAt = .now
    }

    /// A resumed process has no in-memory notification history from the previous
    /// run. Recheck the committed prefix's IDs and revisions before trusting its
    /// saved cursor. This work is bounded by the same page size and does not decode
    /// question payloads.
    private static func verifyCompletedPrefix(
        container: ModelContainer,
        generation: String,
        through upperBound: String,
        expectedCount: Int,
        expectedPaperCounts: [String: Int],
        expectedModuleCounts: [String: Int],
        changeFlag: QuestionBankCatalogChangeFlag
    ) throws {
        var cursor: String?
        var scannedCount = 0
        var verifiedPaperCounts: [String: Int] = [:]
        var verifiedModuleCounts: [String: Int] = [:]
        while true {
            try Task.checkCancellation()
            try failIfSourceChanged(changeFlag, container: container, generation: generation)
            let context = ModelContext(container)
            let lowerBound = cursor ?? ""
            let paperKind = QuestionBankRepository.paperKind
            let moduleKind = QuestionBankRepository.moduleKind
            let questionKind = QuestionBankRepository.questionKind
            let sourcePredicate = #Predicate<QuestionBankRecord> {
                $0.compoundID > lowerBound && $0.compoundID <= upperBound
                    && ($0.kind == paperKind || $0.kind == moduleKind || $0.kind == questionKind)
            }
            let sourceDescriptor = FetchDescriptor<QuestionBankRecord>(
                predicate: sourcePredicate,
                sortBy: [SortDescriptor(\QuestionBankRecord.compoundID, order: .forward)]
            )
            var pageDescriptor = sourceDescriptor
            pageDescriptor.fetchLimit = 128
            let page = try context.fetch(pageDescriptor).map(QuestionBankCatalogSourceRevision.init)
            guard !page.isEmpty else { break }

            let paperIDs = page.filter { $0.kind == paperKind }.map(\.compoundID)
            let moduleIDs = page.filter { $0.kind == moduleKind }.map(\.compoundID)
            let questionIDs = page.filter { $0.kind == questionKind }.map(\.compoundID)
            let paperRows: [String: QuestionBankCatalogPaperRecord]
            if paperIDs.isEmpty {
                paperRows = [:]
            } else {
                let predicate = #Predicate<QuestionBankCatalogPaperRecord> {
                    $0.generationID == generation && paperIDs.contains($0.sourceCompoundID)
                }
                paperRows = Dictionary(
                    try context.fetch(FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: predicate))
                        .map { ($0.sourceCompoundID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            let moduleRows: [String: QuestionBankCatalogModuleRecord]
            if moduleIDs.isEmpty {
                moduleRows = [:]
            } else {
                let predicate = #Predicate<QuestionBankCatalogModuleRecord> {
                    $0.generationID == generation && moduleIDs.contains($0.sourceCompoundID)
                }
                moduleRows = Dictionary(
                    try context.fetch(FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: predicate))
                        .map { ($0.sourceCompoundID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            let questionRows: [String: QuestionBankCatalogQuestionRecord]
            if questionIDs.isEmpty {
                questionRows = [:]
            } else {
                let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                    $0.generationID == generation && questionIDs.contains($0.sourceCompoundID)
                }
                questionRows = Dictionary(
                    try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: predicate))
                        .map { ($0.sourceCompoundID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            let mismatch = page.first { source in
                let indexedRevision: Int?
                switch source.kind {
                case paperKind: indexedRevision = paperRows[source.compoundID]?.sourceRevision
                case moduleKind: indexedRevision = moduleRows[source.compoundID]?.sourceRevision
                case questionKind: indexedRevision = questionRows[source.compoundID]?.sourceRevision
                default: indexedRevision = nil
                }
                return indexedRevision != source.contentRevision
            }
            guard mismatch == nil else {
                try markNeedsRepair(
                    in: context,
                    generation: generation,
                    paperID: mismatch?.paperID ?? page.first?.paperID
                )
                try context.save()
                throw QuestionBankCatalogServiceFailure.sourceChanged
            }
            for source in page where source.kind == questionKind {
                verifiedPaperCounts[source.paperID, default: 0] += 1
                if let moduleID = source.moduleID {
                    verifiedModuleCounts[moduleCountKey(paperID: source.paperID, moduleID: moduleID), default: 0] += 1
                }
            }
            scannedCount += page.count
            cursor = page.last?.compoundID
        }

        let context = ModelContext(container)
        let upperBoundValue = upperBound
        let paperPredicate = #Predicate<QuestionBankCatalogPaperRecord> {
            $0.generationID == generation && $0.sourceCompoundID <= upperBoundValue
        }
        let modulePredicate = #Predicate<QuestionBankCatalogModuleRecord> {
            $0.generationID == generation && $0.sourceCompoundID <= upperBoundValue
        }
        let questionPredicate = #Predicate<QuestionBankCatalogQuestionRecord> {
            $0.generationID == generation && $0.sourceCompoundID <= upperBoundValue
        }
        let indexedPaperCount = try context.fetchCount(
            FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: paperPredicate)
        )
        let indexedModuleCount = try context.fetchCount(
            FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: modulePredicate)
        )
        let indexedQuestionCount = try context.fetchCount(
            FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: questionPredicate)
        )
        let indexedCount = indexedPaperCount + indexedModuleCount + indexedQuestionCount
        guard scannedCount == expectedCount,
              indexedCount == expectedCount,
              verifiedPaperCounts == expectedPaperCounts,
              verifiedModuleCounts == expectedModuleCounts else {
            try markNeedsRepair(in: context, generation: generation, paperID: nil)
            try context.save()
            throw QuestionBankCatalogServiceFailure.sourceChanged
        }
    }

    private static func loadModuleReferences(
        container: ModelContainer,
        generation: String
    ) throws -> [String: QuestionBankCatalogModuleReference] {
        let context = ModelContext(container)
        let predicate = #Predicate<QuestionBankCatalogModuleRecord> { $0.generationID == generation }
        let descriptor = FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: predicate)
        let rows = try context.fetch(descriptor)
        var references: [String: QuestionBankCatalogModuleReference] = [:]
        for row in rows {
            try Task.checkCancellation()
            references[moduleReferenceKey(paperID: row.paperID, moduleID: row.moduleID)] =
                QuestionBankCatalogModuleReference(
                    title: row.title,
                    sequence: row.sequence
                )
        }
        return references
    }

    private static func decode(
        _ source: QuestionBankCatalogSourceRow,
        moduleReferences: inout [String: QuestionBankCatalogModuleReference]
    ) throws -> QuestionBankCatalogDecodedRow {
        switch source.kind {
        case QuestionBankRepository.paperKind:
            guard let paper = try? JSONDecoder().decode(QuestionBankPaper.self, from: source.payload),
                  paper.id == source.stableID,
                  paper.id == source.paperID else {
                throw QuestionBankCatalogServiceFailure.malformedSourceRecord(source.compoundID)
            }
            let provinceLabels = Set(
                [paper.provinceName, paper.provinceCode]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    + (paper.sourcePapers ?? []).flatMap { sourcePaper in
                        [sourcePaper.provinceName, sourcePaper.provinceCode]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
            ).sorted()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return .paper(QuestionBankCatalogPaperValue(
                source: QuestionBankCatalogSourceRevision(source),
                title: paper.title,
                year: paper.year,
                examType: paper.examType,
                volume: paper.volume,
                searchText: source.searchText,
                provinceCode: paper.provinceCode,
                provinceName: paper.provinceName,
                provinceLabelsData: try encoder.encode(provinceLabels)
            ))
        case QuestionBankRepository.moduleKind:
            guard let module = try? JSONDecoder().decode(QuestionBankModule.self, from: source.payload),
                  module.id == source.stableID,
                  module.paperID == source.paperID else {
                throw QuestionBankCatalogServiceFailure.malformedSourceRecord(source.compoundID)
            }
            let value = QuestionBankCatalogModuleValue(
                source: QuestionBankCatalogSourceRevision(source),
                moduleID: module.id,
                title: module.title,
                sequence: module.sequence
            )
            moduleReferences[moduleReferenceKey(paperID: module.paperID, moduleID: module.id)] =
                QuestionBankCatalogModuleReference(
                    title: module.title,
                    sequence: module.sequence
                )
            return .module(value)
        case QuestionBankRepository.questionKind:
            guard let question = try? JSONDecoder().decode(QuestionBankQuestion.self, from: source.payload),
                  question.id == source.stableID,
                  question.paperID == source.paperID,
                  source.moduleID == question.moduleID else {
                throw QuestionBankCatalogServiceFailure.inconsistentSourceRecord(source.compoundID)
            }
            let moduleReference = moduleReferences[moduleReferenceKey(
                paperID: question.paperID,
                moduleID: question.moduleID
            )]
            let coarseModule = QuestionBankCoarseModule.classify(
                explicitModuleTitle: moduleReference?.title ?? question.subject
            )
            let filterMetadata = try QuestionBankCatalogService.makeQuestionFilterMetadata(
                question,
                coarseModule: coarseModule
            )
            return .question(QuestionBankCatalogQuestionValue(
                source: QuestionBankCatalogSourceRevision(source),
                questionID: question.id,
                moduleID: question.moduleID,
                originalNumber: source.questionNumber ?? question.number,
                moduleSequence: moduleReference?.sequence ?? Int.max,
                questionTypeSequence: QuestionBankCoarseModule.questionTypeSequence(
                    module: coarseModule,
                    typeFilter: filterMetadata.coarseQuestionType
                ),
                searchText: source.searchText,
                coarseModule: coarseModule.rawValue,
                coarseQuestionType: coarseModule.questionTypeFilter(for: question.type),
                materialID: question.materialID,
                isDifficult: filterMetadata.isDifficult,
                needsReview: filterMetadata.needsReview,
                knowledgePointsData: filterMetadata.knowledgePointsData,
                weaknessTagsData: filterMetadata.weaknessTagsData
            ))
        default:
            throw QuestionBankCatalogServiceFailure.inconsistentSourceRecord(source.compoundID)
        }
    }

    private static func sourceRevision(
        _ entry: QuestionBankCatalogDecodedRow
    ) -> QuestionBankCatalogSourceRevision {
        switch entry {
        case .paper(let value): return value.source
        case .module(let value): return value.source
        case .question(let value): return value.source
        }
    }

    private static func verifyCurrentSourceRows(
        _ page: [QuestionBankCatalogSourceRevision],
        in context: ModelContext,
        generation: String
    ) throws {
        let ids = page.map(\.compoundID)
        let predicate = #Predicate<QuestionBankRecord> { ids.contains($0.compoundID) }
        let currentRows = try context.fetch(FetchDescriptor<QuestionBankRecord>(predicate: predicate))
        let currentByID = Dictionary(currentRows.map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
        let changedRow = page.first {
            currentByID[$0.compoundID]?.contentRevision != $0.contentRevision
        }
        guard currentRows.count == page.count, changedRow == nil else {
            try markNeedsRepair(
                in: context,
                generation: generation,
                paperID: changedRow?.paperID ?? page.first?.paperID
            )
            try context.save()
            throw QuestionBankCatalogServiceFailure.sourceChanged
        }
    }

    private struct ExistingPageCatalogRows {
        var papers: [String: QuestionBankCatalogPaperRecord]
        var modules: [String: QuestionBankCatalogModuleRecord]
        var questions: [String: QuestionBankCatalogQuestionRecord]
    }

    private static func fetchExistingCatalogRows(
        for entries: [QuestionBankCatalogDecodedRow],
        in context: ModelContext
    ) throws -> ExistingPageCatalogRows {
        let paperIDs = entries.compactMap { entry -> String? in
            guard case .paper(let value) = entry else { return nil }
            return value.source.compoundID
        }
        let moduleIDs = entries.compactMap { entry -> String? in
            guard case .module(let value) = entry else { return nil }
            return value.source.compoundID
        }
        let questionIDs = entries.compactMap { entry -> String? in
            guard case .question(let value) = entry else { return nil }
            return value.source.compoundID
        }
        let papers: [String: QuestionBankCatalogPaperRecord]
        if paperIDs.isEmpty {
            papers = [:]
        } else {
            let predicate = #Predicate<QuestionBankCatalogPaperRecord> {
                paperIDs.contains($0.sourceCompoundID)
            }
            papers = Dictionary(
                try context.fetch(FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: predicate))
                    .map { ($0.sourceCompoundID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let modules: [String: QuestionBankCatalogModuleRecord]
        if moduleIDs.isEmpty {
            modules = [:]
        } else {
            let predicate = #Predicate<QuestionBankCatalogModuleRecord> {
                moduleIDs.contains($0.sourceCompoundID)
            }
            modules = Dictionary(
                try context.fetch(FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: predicate))
                    .map { ($0.sourceCompoundID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let questions: [String: QuestionBankCatalogQuestionRecord]
        if questionIDs.isEmpty {
            questions = [:]
        } else {
            let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                questionIDs.contains($0.sourceCompoundID)
            }
            questions = Dictionary(
                try context.fetch(FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: predicate))
                    .map { ($0.sourceCompoundID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        return ExistingPageCatalogRows(papers: papers, modules: modules, questions: questions)
    }

    private static func upsert(
        _ entry: QuestionBankCatalogDecodedRow,
        generation: String,
        existing: inout ExistingPageCatalogRows,
        in context: ModelContext
    ) {
        switch entry {
        case .paper(let value):
            let sourceID = value.source.compoundID
            if let record = existing.papers[sourceID] {
                record.paperID = value.source.paperID
                record.title = value.title
                record.year = value.year
                record.examType = value.examType
                record.volume = value.volume
                record.searchText = value.searchText
                record.provinceCode = value.provinceCode
                record.provinceName = value.provinceName
                record.provinceLabelsData = value.provinceLabelsData
                record.sourceRevision = value.source.contentRevision
                record.metadataReadyVersion = metadataVersion
                record.generationID = generation
            } else {
                context.insert(QuestionBankCatalogPaperRecord(
                    sourceCompoundID: sourceID,
                    paperID: value.source.paperID,
                    title: value.title,
                    year: value.year,
                    examType: value.examType,
                    volume: value.volume,
                    searchText: value.searchText,
                    provinceCode: value.provinceCode,
                    provinceName: value.provinceName,
                    provinceLabelsData: value.provinceLabelsData,
                    sourceRevision: value.source.contentRevision,
                    metadataReadyVersion: metadataVersion,
                    generationID: generation
                ))
            }
        case .module(let value):
            let sourceID = value.source.compoundID
            if let record = existing.modules[sourceID] {
                record.paperID = value.source.paperID
                record.moduleID = value.moduleID
                record.title = value.title
                record.sequence = value.sequence
                record.sourceRevision = value.source.contentRevision
                record.metadataReadyVersion = metadataVersion
                record.generationID = generation
            } else {
                context.insert(QuestionBankCatalogModuleRecord(
                    sourceCompoundID: sourceID,
                    paperID: value.source.paperID,
                    moduleID: value.moduleID,
                    title: value.title,
                    sequence: value.sequence,
                    sourceRevision: value.source.contentRevision,
                    metadataReadyVersion: metadataVersion,
                    generationID: generation
                ))
            }
        case .question(let value):
            let sourceID = value.source.compoundID
            if let record = existing.questions[sourceID] {
                record.paperID = value.source.paperID
                record.stableID = value.questionID
                record.moduleID = value.moduleID
                record.originalNumber = value.originalNumber
                record.moduleSequence = value.moduleSequence
                record.questionTypeSequence = value.questionTypeSequence
                record.searchText = value.searchText
                record.coarseModule = value.coarseModule
                record.coarseQuestionType = value.coarseQuestionType
                record.materialID = value.materialID
                record.isDifficult = value.isDifficult
                record.needsReview = value.needsReview
                record.knowledgePointsData = value.knowledgePointsData
                record.weaknessTagsData = value.weaknessTagsData
                record.sourceRevision = value.source.contentRevision
                record.metadataReadyVersion = metadataVersion
                record.generationID = generation
            } else {
                context.insert(QuestionBankCatalogQuestionRecord(
                    sourceCompoundID: sourceID,
                    paperID: value.source.paperID,
                    stableID: value.questionID,
                    moduleID: value.moduleID,
                    originalNumber: value.originalNumber,
                    moduleSequence: value.moduleSequence,
                    questionTypeSequence: value.questionTypeSequence,
                    searchText: value.searchText,
                    coarseModule: value.coarseModule,
                    coarseQuestionType: value.coarseQuestionType,
                    materialID: value.materialID,
                    isDifficult: value.isDifficult,
                    needsReview: value.needsReview,
                    knowledgePointsData: value.knowledgePointsData,
                    weaknessTagsData: value.weaknessTagsData,
                    sourceRevision: value.source.contentRevision,
                    metadataReadyVersion: metadataVersion,
                    generationID: generation
                ))
            }
        }
    }

    private static func finish(
        container: ModelContainer,
        generation: String,
        paperCounts: [String: Int],
        moduleCounts: [String: Int],
        processedRows: Int
    ) throws {
        let context = ModelContext(container)
        guard let progress = try fetchProgress(in: context),
              progress.stateRawValue == QuestionBankCatalogIndexState.building.rawValue,
              progress.buildGeneration == generation,
              progress.indexedSourceRowCount == processedRows else {
            throw QuestionBankCatalogServiceFailure.sourceChanged
        }
        let sourceCount = try context.fetchCount(sourceDescriptor())
        guard sourceCount == processedRows else {
            try markNeedsRepair(in: context, generation: generation, paperID: nil)
            try context.save()
            throw QuestionBankCatalogServiceFailure.sourceChanged
        }
        let indexedPaperCount = try context.fetchCount(FetchDescriptor<QuestionBankCatalogPaperRecord>(
            predicate: #Predicate<QuestionBankCatalogPaperRecord> { $0.generationID == generation }
        ))
        let indexedModuleCount = try context.fetchCount(FetchDescriptor<QuestionBankCatalogModuleRecord>(
            predicate: #Predicate<QuestionBankCatalogModuleRecord> { $0.generationID == generation }
        ))
        let indexedQuestionCount = try context.fetchCount(FetchDescriptor<QuestionBankCatalogQuestionRecord>(
            predicate: #Predicate<QuestionBankCatalogQuestionRecord> { $0.generationID == generation }
        ))
        guard indexedPaperCount + indexedModuleCount + indexedQuestionCount == processedRows,
              moduleCounts.values.reduce(0, +) == paperCounts.values.reduce(0, +) else {
            try markNeedsRepair(in: context, generation: generation, paperID: nil)
            try context.save()
            throw QuestionBankCatalogServiceFailure.corruptProgress
        }

        let paperPredicate = #Predicate<QuestionBankCatalogPaperRecord> { $0.generationID == generation }
        let papers = try context.fetch(FetchDescriptor<QuestionBankCatalogPaperRecord>(predicate: paperPredicate))
        for paper in papers {
            paper.questionCount = paperCounts[paper.paperID] ?? 0
            paper.metadataReadyVersion = metadataVersion
        }
        let modulePredicate = #Predicate<QuestionBankCatalogModuleRecord> { $0.generationID == generation }
        let modules = try context.fetch(FetchDescriptor<QuestionBankCatalogModuleRecord>(predicate: modulePredicate))
        let indexedPaperIDs = Set(papers.map(\.paperID))
        let indexedModuleKeys = Set(modules.map {
            moduleCountKey(paperID: $0.paperID, moduleID: $0.moduleID)
        })
        guard Set(paperCounts.keys).isSubset(of: indexedPaperIDs),
              Set(moduleCounts.keys).isSubset(of: indexedModuleKeys) else {
            try markNeedsRepair(in: context, generation: generation, paperID: nil)
            try context.save()
            throw QuestionBankCatalogServiceFailure.corruptProgress
        }
        for module in modules {
            module.questionCount = moduleCounts[moduleCountKey(paperID: module.paperID, moduleID: module.moduleID)] ?? 0
            module.metadataReadyVersion = metadataVersion
        }
        let questionPredicate = #Predicate<QuestionBankCatalogQuestionRecord> { $0.generationID == generation }
        let questionCount = try context.fetchCount(FetchDescriptor<QuestionBankCatalogQuestionRecord>(predicate: questionPredicate))
        guard questionCount == paperCounts.values.reduce(0, +) else {
            try markNeedsRepair(in: context, generation: generation, paperID: nil)
            try context.save()
            throw QuestionBankCatalogServiceFailure.corruptProgress
        }

        try deleteOldGenerations(in: context, except: generation)
        try Task.checkCancellation()
        progress.stateRawValue = QuestionBankCatalogIndexState.ready.rawValue
        progress.metadataReadyVersion = metadataVersion
        progress.readyGeneration = generation
        progress.buildGeneration = nil
        progress.paperQuestionCountsData = try encodeCounts(paperCounts)
        progress.moduleQuestionCountsData = try encodeCounts(moduleCounts)
        progress.catalogRevision &+= 1
        progress.updatedAt = .now
        try Task.checkCancellation()
        try context.save()
    }

    private static func deleteOldGenerations(in context: ModelContext, except generation: String) throws {
        var paperCursor: String?
        while true {
            try Task.checkCancellation()
            let lowerBound = paperCursor ?? ""
            let predicate = #Predicate<QuestionBankCatalogPaperRecord> {
                $0.generationID != generation && $0.sourceCompoundID > lowerBound
            }
            var descriptor = FetchDescriptor<QuestionBankCatalogPaperRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\QuestionBankCatalogPaperRecord.sourceCompoundID, order: .forward)]
            )
            descriptor.fetchLimit = 128
            let page = try context.fetch(descriptor)
            guard let last = page.last?.sourceCompoundID else { break }
            for record in page { context.delete(record) }
            try context.save()
            paperCursor = last
        }

        var moduleCursor: String?
        while true {
            try Task.checkCancellation()
            let lowerBound = moduleCursor ?? ""
            let predicate = #Predicate<QuestionBankCatalogModuleRecord> {
                $0.generationID != generation && $0.sourceCompoundID > lowerBound
            }
            var descriptor = FetchDescriptor<QuestionBankCatalogModuleRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\QuestionBankCatalogModuleRecord.sourceCompoundID, order: .forward)]
            )
            descriptor.fetchLimit = 128
            let page = try context.fetch(descriptor)
            guard let last = page.last?.sourceCompoundID else { break }
            for record in page { context.delete(record) }
            try context.save()
            moduleCursor = last
        }

        var questionCursor: String?
        while true {
            try Task.checkCancellation()
            let lowerBound = questionCursor ?? ""
            let predicate = #Predicate<QuestionBankCatalogQuestionRecord> {
                $0.generationID != generation && $0.sourceCompoundID > lowerBound
            }
            var descriptor = FetchDescriptor<QuestionBankCatalogQuestionRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\QuestionBankCatalogQuestionRecord.sourceCompoundID, order: .forward)]
            )
            descriptor.fetchLimit = 128
            let page = try context.fetch(descriptor)
            guard let last = page.last?.sourceCompoundID else { break }
            for record in page { context.delete(record) }
            try context.save()
            questionCursor = last
        }
    }

    private static func sourceDescriptor() -> FetchDescriptor<QuestionBankRecord> {
        let paperKind = QuestionBankRepository.paperKind
        let moduleKind = QuestionBankRepository.moduleKind
        let questionKind = QuestionBankRepository.questionKind
        let predicate = #Predicate<QuestionBankRecord> {
            $0.kind == paperKind || $0.kind == moduleKind || $0.kind == questionKind
        }
        return FetchDescriptor(predicate: predicate)
    }

    private static func failIfSourceChanged(
        _ flag: QuestionBankCatalogChangeFlag,
        container: ModelContainer,
        generation: String
    ) throws {
        let snapshot = flag.snapshot()
        guard snapshot.didChange else { return }
        let context = ModelContext(container)
        try markNeedsRepair(in: context, generation: generation, paperID: snapshot.paperID)
        try context.save()
        throw QuestionBankCatalogServiceFailure.sourceChanged
    }

    private static func markNeedsRepair(
        in context: ModelContext,
        generation: String,
        paperID: String?
    ) throws {
        guard let progress = try fetchProgress(in: context),
              progress.buildGeneration == generation || progress.readyGeneration == generation else { return }
        progress.stateRawValue = QuestionBankCatalogIndexState.needsRepair.rawValue
        progress.readyGeneration = nil
        progress.buildGeneration = nil
        progress.lastCompoundID = nil
        progress.indexedSourceRowCount = 0
        progress.totalSourceRowCount = nil
        progress.paperQuestionCountsData = Data("{}".utf8)
        progress.moduleQuestionCountsData = Data("{}".utf8)
        progress.catalogRevision &+= 1
        progress.invalidatedPaperID = paperID
        progress.invalidatedModuleID = nil
        progress.invalidatedQuestionID = nil
        progress.updatedAt = .now
    }

    private static func decodeCounts(_ data: Data) throws -> [String: Int] {
        try JSONDecoder().decode([String: Int].self, from: data)
    }

    private static func encodeCounts(_ value: [String: Int]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func moduleReferenceKey(paperID: String, moduleID: String) -> String {
        "\(paperID.utf8.count):\(paperID)\(moduleID)"
    }

    private static func moduleCountKey(paperID: String, moduleID: String) -> String {
        moduleReferenceKey(paperID: paperID, moduleID: moduleID)
    }
}
