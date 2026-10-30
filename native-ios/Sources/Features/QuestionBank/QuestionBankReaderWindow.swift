import Foundation
import SwiftData
import SwiftUI

struct QuestionBankReaderDirectoryQuestion: Equatable, Hashable, Sendable, Identifiable {
    let sourceCompoundID: String
    let paperID: String
    let paperTitle: String
    let questionID: String
    let moduleID: String
    let moduleTitle: String
    let moduleSequence: Int
    let questionTypeSequence: Int
    let originalNumber: Int
    let localOrdinal: Int
    let materialID: String
    let coarseModule: String
    let coarseQuestionType: String
    let isDifficult: Bool
    let needsReview: Bool
    let knowledgePoints: [String]
    let weaknessTags: [String]
    let sourceRevision: Int

    var id: String { sourceCompoundID }
    var materialCompoundID: String? {
        materialID.isEmpty ? nil : "\(paperID)::\(QuestionBankRepository.materialKind)::\(materialID)"
    }

    init(
        summary: QuestionBankCatalogQuestionSummary,
        paperTitle: String,
        moduleTitle: String,
        localOrdinal: Int
    ) {
        sourceCompoundID = summary.sourceCompoundID
        paperID = summary.paperID
        self.paperTitle = paperTitle
        questionID = summary.questionID
        moduleID = summary.moduleID
        self.moduleTitle = moduleTitle
        moduleSequence = summary.moduleSequence
        questionTypeSequence = summary.questionTypeSequence
        originalNumber = summary.originalNumber
        self.localOrdinal = localOrdinal
        materialID = summary.materialID
        coarseModule = summary.coarseModule
        coarseQuestionType = summary.coarseQuestionType
        isDifficult = summary.isDifficult
        needsReview = summary.needsReview
        knowledgePoints = summary.knowledgePoints
        weaknessTags = summary.weaknessTags
        sourceRevision = summary.sourceRevision
    }
}

struct QuestionBankReaderDirectorySnapshot: Sendable {
    let catalogVersion: QuestionBankCatalogDataVersion
    let questions: [QuestionBankReaderDirectoryQuestion]
    let orderedIDs: [String]
    let indexByID: [String: Int]
    let questionsByCompoundID: [String: QuestionBankReaderDirectoryQuestion]
    let questionIDsByPaper: [String: [String]]
    let paperSummariesByID: [String: QuestionBankCatalogPaperSummary]
    let moduleSummariesByPaperAndID: [String: QuestionBankCatalogModuleSummary]

    init(
        catalogVersion: QuestionBankCatalogDataVersion,
        questions: [QuestionBankReaderDirectoryQuestion],
        paperSummariesByID: [String: QuestionBankCatalogPaperSummary],
        moduleSummariesByPaperAndID: [String: QuestionBankCatalogModuleSummary]
    ) {
        self.catalogVersion = catalogVersion
        self.questions = questions
        orderedIDs = questions.map(\.sourceCompoundID)
        indexByID = Dictionary(
            questions.enumerated().map { ($1.sourceCompoundID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        questionsByCompoundID = Dictionary(
            questions.map { ($0.sourceCompoundID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        questionIDsByPaper = Dictionary(grouping: questions, by: \.paperID)
            .mapValues { $0.map(\.sourceCompoundID) }
        self.paperSummariesByID = paperSummariesByID
        self.moduleSummariesByPaperAndID = moduleSummariesByPaperAndID
    }

    func question(for compoundID: String) -> QuestionBankReaderDirectoryQuestion? {
        questionsByCompoundID[compoundID]
    }
}

enum QuestionBankReaderDirectoryBuilder {
    static func module(
        from directory: QuestionBankCatalogReaderDirectory,
        paperID: String,
        moduleID: String
    ) -> QuestionBankReaderDirectorySnapshot {
        let papersByID = Dictionary(directory.papers.map { ($0.paperID, $0) }, uniquingKeysWith: { first, _ in first })
        let modules = directory.modules.filter { $0.paperID == paperID && $0.moduleID == moduleID }
        let module = modules.first
        let questions = directory.questions
            .filter { $0.paperID == paperID && $0.moduleID == moduleID }
            .sorted(by: questionOrder)
            .enumerated()
            .map { index, summary in
                QuestionBankReaderDirectoryQuestion(
                    summary: summary,
                    paperTitle: papersByID[paperID]?.title ?? "未命名试卷",
                    moduleTitle: module?.title ?? "",
                    localOrdinal: index + 1
                )
            }
        let modulesByKey = Dictionary(
            modules.map { ("\($0.paperID)::\($0.moduleID)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return QuestionBankReaderDirectorySnapshot(
            catalogVersion: directory.catalogVersion,
            questions: questions,
            paperSummariesByID: Dictionary(
                directory.papers.filter { $0.paperID == paperID }.map { ($0.paperID, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            moduleSummariesByPaperAndID: modulesByKey
        )
    }

    static func crossPaper(
        directory: QuestionBankCatalogReaderDirectory,
        home: QuestionBankCatalogHomeSnapshot,
        filter: QuestionBankHomeFilter,
        paperID: String?,
        scopedPaperIDs: [String]?,
        searchMatches: QuestionBankCatalogSearchMatches?
    ) throws -> QuestionBankReaderDirectorySnapshot {
        guard directory.catalogVersion == home.catalogVersion else {
            throw QuestionBankReaderDirectoryFailure.catalogChanged
        }
        let allowedPaperIDs: Set<String>
        if let paperID {
            allowedPaperIDs = [paperID]
        } else if let scopedPaperIDs {
            allowedPaperIDs = Set(scopedPaperIDs)
        } else {
            allowedPaperIDs = Set(directory.papers.map(\.paperID))
        }
        let scopedPapers = directory.papers.filter { allowedPaperIDs.contains($0.paperID) }
        let scopedQuestionSummaries = directory.questions.filter { allowedPaperIDs.contains($0.paperID) }
        let scopedHome = QuestionBankCatalogHomeSnapshot(
            status: home.status,
            catalogVersion: home.catalogVersion,
            papers: scopedPapers,
            filterOptions: home.filterOptions
        )
        let result = try scopedHome.filtered(
            matching: filter,
            questions: scopedQuestionSummaries,
            searchMatches: searchMatches
        )
        let query = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuestionNumberSearch = Int(filter.questionNumber.trimmingCharacters(in: .whitespacesAndNewlines))
            .map { $0 > 0 } == true
        let hasTextSearch = !query.isEmpty && !hasQuestionNumberSearch
        let visiblePaperIDs = Set(result.visiblePapers.map(\.paperID))
        let searchPaperIDs = searchMatches?.catalogVersion == directory.catalogVersion
            ? (searchMatches?.paperIDs ?? [])
            : []
        let filteredByPaper = Dictionary(
            result.matchingQuestionsByPaperID.map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        var selected: [QuestionBankCatalogQuestionSummary] = []
        for paper in result.visiblePapers {
            if filter.hasQuestionRestriction {
                selected.append(contentsOf: filteredByPaper[paper.paperID] ?? [])
            } else if hasTextSearch, !searchPaperIDs.contains(paper.paperID) {
                selected.append(contentsOf: filteredByPaper[paper.paperID] ?? [])
            } else {
                selected.append(contentsOf: scopedQuestionSummaries.filter { $0.paperID == paper.paperID })
            }
        }
        selected = selected.filter { visiblePaperIDs.contains($0.paperID) }

        let paperTitles = Dictionary(scopedPapers.map { ($0.paperID, $0.title) }, uniquingKeysWith: { first, _ in first })
        let moduleTitles = Dictionary(
            directory.modules.map { ("\($0.paperID)::\($0.moduleID)", $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        selected = orderForReading(selected, papers: scopedPapers)

        var ordinalsByPaper: [String: Int] = [:]
        let questions = selected.map { summary -> QuestionBankReaderDirectoryQuestion in
            let ordinal = ordinalsByPaper[summary.paperID, default: 0] + 1
            ordinalsByPaper[summary.paperID] = ordinal
            return QuestionBankReaderDirectoryQuestion(
                summary: summary,
                paperTitle: paperTitles[summary.paperID] ?? "未命名试卷",
                moduleTitle: moduleTitles["\(summary.paperID)::\(summary.moduleID)"] ?? "",
                localOrdinal: ordinal
            )
        }
        let relevantModuleKeys = Set(questions.map { "\($0.paperID)::\($0.moduleID)" })
        let modules = Dictionary(
            directory.modules.filter { relevantModuleKeys.contains("\($0.paperID)::\($0.moduleID)") }
                .map { ("\($0.paperID)::\($0.moduleID)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return QuestionBankReaderDirectorySnapshot(
            catalogVersion: directory.catalogVersion,
            questions: questions,
            paperSummariesByID: Dictionary(
                result.visiblePapers.map { ($0.paperID, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            moduleSummariesByPaperAndID: modules
        )
    }

    static func questionOrder(
        _ left: QuestionBankCatalogQuestionSummary,
        _ right: QuestionBankCatalogQuestionSummary
    ) -> Bool {
        if left.moduleSequence != right.moduleSequence { return left.moduleSequence < right.moduleSequence }
        if left.questionTypeSequence != right.questionTypeSequence {
            return left.questionTypeSequence < right.questionTypeSequence
        }
        if left.originalNumber != right.originalNumber { return left.originalNumber < right.originalNumber }
        return left.sourceCompoundID < right.sourceCompoundID
    }

    static func orderForReading(
        _ summaries: [QuestionBankCatalogQuestionSummary],
        papers: [QuestionBankCatalogPaperSummary]
    ) -> [QuestionBankCatalogQuestionSummary] {
        let papersByID = Dictionary(papers.map { ($0.paperID, $0) }, uniquingKeysWith: { first, _ in first })
        return summaries.sorted { left, right in
            let leftPaper = papersByID[left.paperID]
            let rightPaper = papersByID[right.paperID]
            if leftPaper?.year != rightPaper?.year { return (leftPaper?.year ?? 0) > (rightPaper?.year ?? 0) }
            let titleOrder = (leftPaper?.title ?? "").localizedStandardCompare(rightPaper?.title ?? "")
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if left.paperID != right.paperID { return left.paperID < right.paperID }
            return questionOrder(left, right)
        }
    }
}

enum QuestionBankReaderDirectoryFailure: LocalizedError, Equatable {
    case catalogChanged

    var errorDescription: String? {
        "题目目录刚刚更新，请重新加载当前题目范围。"
    }
}

enum QuestionBankReaderWindowFailure: LocalizedError, Equatable {
    case payloadLimitExceeded
    case sourceChangedDuringLoad

    var errorDescription: String? {
        switch self {
        case .payloadLimitExceeded:
            return "当前题目窗口的数据超过内存上限，请缩小题目内容或检查图片数据。"
        case .sourceChangedDuringLoad:
            return "题目在加载过程中已更新，请重新加载当前窗口。"
        }
    }
}

struct QuestionBankReaderWindowBounds: Equatable, Sendable {
    static let maximumQuestionBodies = 18
    static let continuousPrefetchRadius = 5
    static let singlePagePrefetchRadius = 2

    let range: Range<Int>

    static func around(
        anchorIndex: Int,
        count: Int,
        radius: Int,
        maximumCount: Int = maximumQuestionBodies
    ) -> Self {
        guard count > 0, maximumCount > 0 else { return Self(range: 0..<0) }
        let anchor = min(max(anchorIndex, 0), count - 1)
        let safeRadius = max(radius, 0)
        let limit = min(count, maximumCount, safeRadius * 2 + 1)
        let preferredStart = max(0, anchor - safeRadius)
        let start = min(preferredStart, max(0, count - limit))
        return Self(range: start..<(start + limit))
    }

    static func IDs(
        in orderedIDs: [String],
        around anchorID: String,
        radius: Int,
        maximumCount: Int = maximumQuestionBodies
    ) -> [String] {
        let index = orderedIDs.firstIndex(of: anchorID) ?? 0
        let bounds = around(anchorIndex: index, count: orderedIDs.count, radius: radius, maximumCount: maximumCount)
        return bounds.range.isEmpty ? [] : Array(orderedIDs[bounds.range])
    }

    static func IDs(
        in orderedIDs: [String],
        aroundVisibleIDs visibleIDs: Set<String>,
        fallbackAnchorID: String?,
        radius: Int = continuousPrefetchRadius,
        maximumCount: Int = maximumQuestionBodies
    ) -> [String] {
        let indices = visibleIDs.compactMap { orderedIDs.firstIndex(of: $0) }.sorted()
        guard let first = indices.first, let last = indices.last else {
            guard let fallbackAnchorID else { return [] }
            return IDs(in: orderedIDs, around: fallbackAnchorID, radius: radius, maximumCount: maximumCount)
        }
        let limit = min(orderedIDs.count, max(1, maximumCount))
        if last - first + 1 >= limit {
            let anchor = fallbackAnchorID.flatMap { orderedIDs.firstIndex(of: $0) } ?? first
            return IDs(in: orderedIDs, around: orderedIDs[anchor], radius: 0, maximumCount: limit)
        }
        let before = max(0, first - radius)
        let after = min(orderedIDs.count, last + radius + 1)
        var start = before
        var end = after
        if end - start > limit {
            let anchor = fallbackAnchorID.flatMap { orderedIDs.firstIndex(of: $0) } ?? first
            start = min(max(0, anchor - limit / 2), orderedIDs.count - limit)
            end = start + limit
        }
        return Array(orderedIDs[start..<end])
    }

    static func IDs(
        in orderedIDs: [String],
        indexByID: [String: Int],
        aroundVisibleIDs visibleIDs: Set<String>,
        fallbackAnchorID: String?,
        radius: Int = continuousPrefetchRadius,
        maximumCount: Int = maximumQuestionBodies
    ) -> [String] {
        let indices = visibleIDs.compactMap { indexByID[$0] }.sorted()
        guard let first = indices.first, let last = indices.last else {
            guard let fallbackAnchorID else { return [] }
            let anchor = indexByID[fallbackAnchorID] ?? 0
            let bounds = around(anchorIndex: anchor, count: orderedIDs.count, radius: radius, maximumCount: maximumCount)
            return bounds.range.isEmpty ? [] : Array(orderedIDs[bounds.range])
        }
        let limit = min(orderedIDs.count, max(1, maximumCount))
        if last - first + 1 >= limit {
            let anchor = fallbackAnchorID.flatMap { indexByID[$0] } ?? first
            let bounds = around(anchorIndex: anchor, count: orderedIDs.count, radius: 0, maximumCount: limit)
            return Array(orderedIDs[bounds.range])
        }
        var start = max(0, first - radius)
        var end = min(orderedIDs.count, last + radius + 1)
        if end - start > limit {
            let anchor = fallbackAnchorID.flatMap { indexByID[$0] } ?? first
            start = min(max(0, anchor - limit / 2), orderedIDs.count - limit)
            end = start + limit
        }
        return Array(orderedIDs[start..<end])
    }

    static func evictedIDs(loadedIDs: Set<String>, retainedIDs: Set<String>, capacity: Int) -> Set<String> {
        let capacity = max(0, capacity)
        guard loadedIDs.count > capacity else { return [] }
        let keptPinned = loadedIDs.intersection(retainedIDs).sorted().prefix(capacity)
        let remainingCapacity = max(0, capacity - keptPinned.count)
        let keptOther = loadedIDs.subtracting(retainedIDs).sorted().prefix(remainingCapacity)
        return loadedIDs.subtracting(Set(keptPinned).union(keptOther))
    }

    static func retainedIDs(
        from orderedIDs: [String],
        loadedIDs: Set<String>,
        pinnedIDs: Set<String>,
        capacity: Int
    ) -> Set<String> {
        let limit = max(0, capacity)
        let pinned = orderedIDs.filter { loadedIDs.contains($0) && pinnedIDs.contains($0) }
        let other = orderedIDs.filter { loadedIDs.contains($0) && !pinnedIDs.contains($0) }
        return Set((Array(pinned.prefix(limit)) + Array(other.prefix(max(0, limit - pinned.count)))))
    }

    static func materialCompoundIDs(for questions: [QuestionBankReaderDirectoryQuestion]) -> Set<String> {
        Set(questions.compactMap(\.materialCompoundID))
    }

    static func refreshIDs(changedIDs: Set<String>, loadedIDs: Set<String>) -> Set<String> {
        changedIDs.intersection(loadedIDs)
    }
}

enum QuestionBankReaderWindowAcceptance {
    static func accepts(
        requestGeneration: Int,
        currentGeneration: Int,
        requestVersion: QuestionBankCatalogDataVersion,
        currentVersion: QuestionBankCatalogDataVersion?,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requestGeneration == currentGeneration && requestVersion == currentVersion
    }
}

struct QuestionBankReaderWindowQuestion: Sendable {
    let directory: QuestionBankReaderDirectoryQuestion
    let question: QuestionBankQuestion
    let revisionToken: QuestionBankReaderRecordRevisionToken
    let payloadByteCount: Int
}

struct QuestionBankReaderWindowSnapshot: Sendable {
    let catalogVersion: QuestionBankCatalogDataVersion
    let questionsByCompoundID: [String: QuestionBankReaderWindowQuestion]
    let materialsByCompoundID: [String: QuestionBankMaterial]
    let assetsByCompoundID: [String: QuestionBankAssetReference]
    let sourcePapersByID: [String: [QuestionBankSourcePaper]]
    let payloadByteCount: Int
}

enum QuestionBankReaderWindowDataService {
    static let maximumWindowPayloadBytes = 12 * 1_024 * 1_024

    static func load(
        container: ModelContainer,
        expectedVersion: QuestionBankCatalogDataVersion,
        questions: [QuestionBankReaderDirectoryQuestion]
    ) throws -> QuestionBankReaderWindowSnapshot {
        guard !Task.isCancelled else { throw CancellationError() }
        guard questions.count <= QuestionBankReaderWindowBounds.maximumQuestionBodies else {
            throw QuestionBankReaderWindowFailure.payloadLimitExceeded
        }
        let context = ModelContext(container)
        guard try QuestionBankCatalogService.currentDataVersion(in: context) == expectedVersion else {
            throw QuestionBankReaderDirectoryFailure.catalogChanged
        }
        guard !questions.isEmpty else {
            return QuestionBankReaderWindowSnapshot(
                catalogVersion: expectedVersion,
                questionsByCompoundID: [:],
                materialsByCompoundID: [:],
                assetsByCompoundID: [:],
                sourcePapersByID: [:],
                payloadByteCount: 0
            )
        }

        let questionKind = QuestionBankRepository.questionKind
        let requestedQuestionIDs = Array(Set(questions.map(\.sourceCompoundID)))
        let questionPredicate = #Predicate<QuestionBankRecord> {
            $0.kind == questionKind && requestedQuestionIDs.contains($0.compoundID)
        }
        var questionDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: questionPredicate)
        questionDescriptor.fetchLimit = requestedQuestionIDs.count
        let records = try context.fetch(questionDescriptor)
        let recordsByCompoundID = Dictionary(records.map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
        guard recordsByCompoundID.count == requestedQuestionIDs.count else {
            throw QuestionBankModuleReaderFailure.questionRowsNotReady
        }

        let materialIDs = QuestionBankReaderWindowBounds.materialCompoundIDs(for: questions)
        let materialKind = QuestionBankRepository.materialKind
        let materialRecords: [QuestionBankRecord]
        if materialIDs.isEmpty {
            materialRecords = []
        } else {
            let requestedMaterialIDs = Array(materialIDs)
            let materialPredicate = #Predicate<QuestionBankRecord> {
                $0.kind == materialKind && requestedMaterialIDs.contains($0.compoundID)
            }
            var materialDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: materialPredicate)
            materialDescriptor.fetchLimit = requestedMaterialIDs.count
            materialRecords = try context.fetch(materialDescriptor)
        }
        let decoder = JSONDecoder()
        var materialByCompoundID: [String: QuestionBankMaterial] = [:]
        var payloadBytes = records.reduce(0) { $0 + $1.payload.count }
            + materialRecords.reduce(0) { $0 + $1.payload.count }
        guard payloadBytes <= maximumWindowPayloadBytes else {
            throw QuestionBankReaderWindowFailure.payloadLimitExceeded
        }
        for record in materialRecords {
            try Task.checkCancellation()
            guard let value = try? decoder.decode(QuestionBankMaterial.self, from: record.payload),
                  value.id == record.stableID,
                  value.paperID == record.paperID else { continue }
            materialByCompoundID[record.compoundID] = value
        }

        var questionValues: [String: QuestionBankReaderWindowQuestion] = [:]
        let entriesByID = Dictionary(questions.map { ($0.sourceCompoundID, $0) }, uniquingKeysWith: { first, _ in first })
        for (compoundID, record) in recordsByCompoundID {
            try Task.checkCancellation()
            guard let entry = entriesByID[compoundID],
                  record.paperID == entry.paperID,
                  record.stableID == entry.questionID,
                  let value = try? decoder.decode(QuestionBankQuestion.self, from: record.payload),
                  value.id == entry.questionID,
                  value.paperID == entry.paperID else {
                throw QuestionBankReaderDirectoryFailure.catalogChanged
            }
            let token = QuestionBankReaderRecordRevisionToken(
                compoundID: record.compoundID,
                paperID: record.paperID,
                kind: record.kind,
                moduleID: record.moduleID,
                title: record.title,
                contentRevision: record.contentRevision,
                assetRelativePath: record.assetRelativePath
            )
            questionValues[compoundID] = QuestionBankReaderWindowQuestion(
                directory: entry,
                question: value,
                revisionToken: token,
                payloadByteCount: record.payload.count
            )
        }

        let paperKind = QuestionBankRepository.paperKind
        let paperIDs = Set(questions.map(\.paperID))
        let paperRecordIDs = paperIDs.map { "\($0)::\(paperKind)::\($0)" }
        let paperPredicate = #Predicate<QuestionBankRecord> {
            $0.kind == paperKind && paperRecordIDs.contains($0.compoundID)
        }
        var paperDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: paperPredicate)
        paperDescriptor.fetchLimit = paperRecordIDs.count
        let paperRecords = try context.fetch(paperDescriptor)
        payloadBytes += paperRecords.reduce(0) { $0 + $1.payload.count }
        guard payloadBytes <= maximumWindowPayloadBytes else {
            throw QuestionBankReaderWindowFailure.payloadLimitExceeded
        }
        var sourcePapersByID: [String: [QuestionBankSourcePaper]] = [:]
        for record in paperRecords {
            try Task.checkCancellation()
            guard let paper = try? decoder.decode(QuestionBankPaper.self, from: record.payload) else { continue }
            sourcePapersByID[record.paperID] = paper.sourcePapers ?? []
        }

        var referencedAssetCompoundIDs = Set<String>()
        for value in questionValues.values {
            if !value.question.stemImageAssetID.isEmpty {
                referencedAssetCompoundIDs.insert("\(value.question.paperID)::\(QuestionBankRepository.assetKind)::\(value.question.stemImageAssetID)")
            }
            for option in value.question.options where !option.imageAssetID.isEmpty {
                referencedAssetCompoundIDs.insert("\(value.question.paperID)::\(QuestionBankRepository.assetKind)::\(option.imageAssetID)")
            }
        }
        for material in materialByCompoundID.values where !material.imageAssetID.isEmpty {
            referencedAssetCompoundIDs.insert("\(material.paperID)::\(QuestionBankRepository.assetKind)::\(material.imageAssetID)")
        }
        let assetsByCompoundID: [String: QuestionBankAssetReference]
        if referencedAssetCompoundIDs.isEmpty {
            assetsByCompoundID = [:]
        } else {
            let assetKind = QuestionBankRepository.assetKind
            let requestedAssetIDs = Array(referencedAssetCompoundIDs)
            let assetPredicate = #Predicate<QuestionBankRecord> {
                $0.kind == assetKind && requestedAssetIDs.contains($0.compoundID)
            }
            var assetDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: assetPredicate)
            assetDescriptor.fetchLimit = requestedAssetIDs.count
            let assetRecords = try context.fetch(assetDescriptor)
            payloadBytes += assetRecords.reduce(0) { $0 + $1.payload.count }
            guard payloadBytes <= maximumWindowPayloadBytes else {
                throw QuestionBankReaderWindowFailure.payloadLimitExceeded
            }
            assetsByCompoundID = Dictionary(
                assetRecords.map { ($0.compoundID, QuestionBankAssetReference(record: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        guard try QuestionBankCatalogService.currentDataVersion(in: context) == expectedVersion else {
            throw QuestionBankReaderDirectoryFailure.catalogChanged
        }
        try Task.checkCancellation()
        let verificationContext = ModelContext(container)
        let verificationPredicate = #Predicate<QuestionBankRecord> {
            $0.kind == questionKind && requestedQuestionIDs.contains($0.compoundID)
        }
        var verificationDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: verificationPredicate)
        verificationDescriptor.fetchLimit = requestedQuestionIDs.count
        let verifiedRecords = try verificationContext.fetch(verificationDescriptor)
        let verifiedRevisions = Dictionary(
            verifiedRecords.map { ($0.compoundID, $0.contentRevision) },
            uniquingKeysWith: { first, _ in first }
        )
        guard requestedQuestionIDs.allSatisfy({ compoundID in
            guard let originalRevision = recordsByCompoundID[compoundID]?.contentRevision,
                  let verifiedRevision = verifiedRevisions[compoundID] else { return false }
            return originalRevision == verifiedRevision
        }) else {
            throw QuestionBankReaderWindowFailure.sourceChangedDuringLoad
        }
        return QuestionBankReaderWindowSnapshot(
            catalogVersion: expectedVersion,
            questionsByCompoundID: questionValues,
            materialsByCompoundID: materialByCompoundID,
            assetsByCompoundID: assetsByCompoundID,
            sourcePapersByID: sourcePapersByID,
            payloadByteCount: payloadBytes
        )
    }
}

@MainActor
final class QuestionBankReaderDirectoryStore: ObservableObject {
    @Published private(set) var directory: QuestionBankReaderDirectorySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var generation = 0

    private var activeLoadID: UUID?

    func loadModule(
        container: ModelContainer,
        paperID: String,
        moduleID: String
    ) async {
        let requestID = beginLoad()
        do {
            let source = try await QuestionBankCatalogService.readerDirectory(
                in: container,
                paperIDs: [paperID]
            )
            guard accepts(requestID), !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                QuestionBankReaderDirectoryBuilder.module(
                    from: source,
                    paperID: paperID,
                    moduleID: moduleID
                )
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard accepts(requestID), !Task.isCancelled else { return }
            publish(result, requestID: requestID)
        } catch is CancellationError {
            finishCancelled(requestID)
        } catch {
            fail(error, requestID: requestID)
        }
    }

    func loadCrossPaper(
        container: ModelContainer,
        filter: QuestionBankHomeFilter,
        paperID: String?,
        scopedPaperIDs: [String]?
    ) async {
        let requestID = beginLoad()
        do {
            let scope: Set<String>? = if let paperID {
                [paperID]
            } else {
                scopedPaperIDs.map { Set($0) }
            }
            async let homeTask = QuestionBankCatalogService.homeSnapshot(in: container)
            async let directoryTask = QuestionBankCatalogService.readerDirectory(in: container, paperIDs: scope)
            let (home, source) = try await (homeTask, directoryTask)
            guard accepts(requestID), !Task.isCancelled else { return }
            let normalizedQuery = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
            let isQuestionNumberSearch = Int(filter.questionNumber.trimmingCharacters(in: .whitespacesAndNewlines))
                .map { $0 > 0 } == true
            let matches: QuestionBankCatalogSearchMatches?
            if !normalizedQuery.isEmpty && !isQuestionNumberSearch {
                matches = try await QuestionBankCatalogService.searchMatches(query: normalizedQuery, in: container)
            } else {
                matches = nil
            }
            guard accepts(requestID), !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                try QuestionBankReaderDirectoryBuilder.crossPaper(
                    directory: source,
                    home: home,
                    filter: filter,
                    paperID: paperID,
                    scopedPaperIDs: scopedPaperIDs,
                    searchMatches: matches
                )
            }
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard accepts(requestID), !Task.isCancelled else { return }
            publish(result, requestID: requestID)
        } catch is CancellationError {
            finishCancelled(requestID)
        } catch {
            fail(error, requestID: requestID)
        }
    }

    func cancel(clear: Bool = false) {
        activeLoadID = nil
        generation &+= 1
        isLoading = false
        if clear { directory = nil }
    }

    private func beginLoad() -> UUID {
        generation &+= 1
        let requestID = UUID()
        activeLoadID = requestID
        isLoading = true
        errorMessage = nil
        return requestID
    }

    private func accepts(_ requestID: UUID) -> Bool { activeLoadID == requestID }

    private func publish(_ value: QuestionBankReaderDirectorySnapshot, requestID: UUID) {
        guard accepts(requestID) else { return }
        directory = value
        activeLoadID = nil
        isLoading = false
        errorMessage = nil
    }

    private func fail(_ error: Error, requestID: UUID) {
        guard accepts(requestID) else { return }
        activeLoadID = nil
        isLoading = false
        errorMessage = error.localizedDescription
    }

    private func finishCancelled(_ requestID: UUID) {
        guard accepts(requestID) else { return }
        activeLoadID = nil
        isLoading = false
    }
}

@MainActor
final class QuestionBankReaderWindowStore: ObservableObject {
    @Published private(set) var questionsByCompoundID: [String: QuestionBankReaderWindowQuestion] = [:]
    @Published private(set) var materialsByCompoundID: [String: QuestionBankMaterial] = [:]
    @Published private(set) var assetsByCompoundID: [String: QuestionBankAssetReference] = [:]
    @Published private(set) var sourcePapersByID: [String: [QuestionBankSourcePaper]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var requestGeneration = 0

    private var activeTask: Task<QuestionBankReaderWindowSnapshot, Error>?
    private var directoryVersion: QuestionBankCatalogDataVersion?
    private var currentWindowIDs: Set<String> = []

    func install(directory: QuestionBankReaderDirectorySnapshot?) {
        cancel(clear: true)
        directoryVersion = directory?.catalogVersion
    }

    func question(for compoundID: String) -> QuestionBankReaderWindowQuestion? {
        questionsByCompoundID[compoundID]
    }

    func material(paperID: String, materialID: String) -> QuestionBankMaterial? {
        materialsByCompoundID["\(paperID)::\(QuestionBankRepository.materialKind)::\(materialID)"]
    }

    func asset(paperID: String, assetID: String) -> QuestionBankAssetReference? {
        assetsByCompoundID["\(paperID)::\(QuestionBankRepository.assetKind)::\(assetID)"]
    }

    func loadWindow(
        container: ModelContainer,
        directory: QuestionBankReaderDirectorySnapshot,
        anchorID: String,
        visibleIDs: Set<String> = [],
        radius: Int,
        specificIDs: Set<String>? = nil
    ) async {
        guard directory.catalogVersion == directoryVersion else { return }
        let directoryIDs = directory.orderedIDs
        let requestedIDs: [String]
        if let specificIDs {
            requestedIDs = QuestionBankReaderWindowBounds.refreshIDs(
                changedIDs: specificIDs,
                loadedIDs: currentWindowIDs
            ).sorted()
        } else {
            requestedIDs = QuestionBankReaderWindowBounds.IDs(
                in: directoryIDs,
                indexByID: directory.indexByID,
                aroundVisibleIDs: visibleIDs,
                fallbackAnchorID: anchorID,
                radius: radius
            )
        }
        guard !requestedIDs.isEmpty else { return }
        if specificIDs == nil,
           Set(requestedIDs).isSubset(of: currentWindowIDs),
           requestedIDs.allSatisfy({ questionsByCompoundID[$0] != nil }) {
            return
        }
        activeTask?.cancel()
        requestGeneration &+= 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil
        let entries = requestedIDs.compactMap { directory.questionsByCompoundID[$0] }
        let expectedVersion = directory.catalogVersion
        let worker = Task.detached(priority: .userInitiated) {
            try QuestionBankReaderWindowDataService.load(
                container: container,
                expectedVersion: expectedVersion,
                questions: entries
            )
        }
        activeTask = worker
        do {
            let snapshot = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard QuestionBankReaderWindowAcceptance.accepts(
                requestGeneration: generation,
                currentGeneration: requestGeneration,
                requestVersion: expectedVersion,
                currentVersion: directoryVersion,
                isCancelled: Task.isCancelled
            ) else { return }
            if let specificIDs {
                questionsByCompoundID.merge(snapshot.questionsByCompoundID) { _, newest in newest }
                materialsByCompoundID.merge(snapshot.materialsByCompoundID) { _, newest in newest }
                assetsByCompoundID.merge(snapshot.assetsByCompoundID) { _, newest in newest }
                sourcePapersByID.merge(snapshot.sourcePapersByID) { _, newest in newest }
                pruneDependenciesOutsideWindow()
            } else {
                questionsByCompoundID = snapshot.questionsByCompoundID
                materialsByCompoundID = snapshot.materialsByCompoundID
                assetsByCompoundID = snapshot.assetsByCompoundID
                sourcePapersByID = snapshot.sourcePapersByID
                currentWindowIDs = Set(snapshot.questionsByCompoundID.keys)
            }
            isLoading = false
            activeTask = nil
            NativePerformanceLog.event(
                "question bank reader window questions=\(snapshot.questionsByCompoundID.count) materials=\(snapshot.materialsByCompoundID.count) assets=\(snapshot.assetsByCompoundID.count) payloadBytes=\(snapshot.payloadByteCount)"
            )
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            activeTask = nil
            isLoading = false
        } catch {
            guard requestGeneration == generation else { return }
            activeTask = nil
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func cancel(clear: Bool) {
        requestGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        if clear {
            questionsByCompoundID.removeAll(keepingCapacity: true)
            materialsByCompoundID.removeAll(keepingCapacity: true)
            assetsByCompoundID.removeAll(keepingCapacity: true)
            sourcePapersByID.removeAll(keepingCapacity: true)
            currentWindowIDs.removeAll(keepingCapacity: true)
        }
    }

    private func pruneDependenciesOutsideWindow() {
        let loadedQuestions = currentWindowIDs.compactMap { questionsByCompoundID[$0]?.question }
        let materialCompoundIDs = Set(loadedQuestions.compactMap { question in
            question.materialID.isEmpty
                ? nil
                : "\(question.paperID)::\(QuestionBankRepository.materialKind)::\(question.materialID)"
        })
        materialsByCompoundID = materialsByCompoundID.filter { materialCompoundIDs.contains($0.key) }

        var assetCompoundIDs = Set<String>()
        for question in loadedQuestions {
            if !question.stemImageAssetID.isEmpty {
                assetCompoundIDs.insert("\(question.paperID)::\(QuestionBankRepository.assetKind)::\(question.stemImageAssetID)")
            }
            for option in question.options where !option.imageAssetID.isEmpty {
                assetCompoundIDs.insert("\(question.paperID)::\(QuestionBankRepository.assetKind)::\(option.imageAssetID)")
            }
        }
        for material in materialsByCompoundID.values where !material.imageAssetID.isEmpty {
            assetCompoundIDs.insert("\(material.paperID)::\(QuestionBankRepository.assetKind)::\(material.imageAssetID)")
        }
        assetsByCompoundID = assetsByCompoundID.filter { assetCompoundIDs.contains($0.key) }
        let paperIDs = Set(loadedQuestions.map(\.paperID))
        sourcePapersByID = sourcePapersByID.filter { paperIDs.contains($0.key) }
    }
}
