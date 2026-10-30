import Foundation
import OSLog
import SwiftData

struct QuestionBankAssetReference: Equatable, Hashable, Sendable, Identifiable {
    let compoundID: String
    let paperID: String
    let stableID: String
    let contentRevision: Int
    let assetRelativePath: String?

    var id: String { compoundID }

    init(record: QuestionBankRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        stableID = record.stableID
        contentRevision = record.contentRevision
        assetRelativePath = record.assetRelativePath
    }
}

struct QuestionBankReaderRecordRevisionToken: Hashable, Sendable {
    let compoundID: String
    let paperID: String
    let kind: String
    let moduleID: String?
    let title: String?
    let contentRevision: Int
    let assetRelativePath: String?
}

struct QuestionBankModuleReaderQuestionSnapshot: Sendable {
    let compoundID: String
    let question: QuestionBankQuestion
    let localOrdinal: Int
}

struct QuestionBankReaderQuestionRefresh: Sendable {
    let compoundID: String
    let stableID: String
    let question: QuestionBankQuestion
    let revisionToken: QuestionBankReaderRecordRevisionToken
    let payloadByteCount: Int
}

struct QuestionBankModuleReaderSnapshot: Sendable {
    let module: QuestionBankModule?
    let paper: QuestionBankPaper?
    let questions: [QuestionBankModuleReaderQuestionSnapshot]
    let readingSteps: [QuestionBankReadingStep]
    let materialsByID: [String: QuestionBankMaterial]
    let assetsByID: [String: QuestionBankAssetReference]
    let revisionTokens: Set<QuestionBankReaderRecordRevisionToken>
    let questionRecordCount: Int
    let materialRecordCount: Int
    let referencedAssetCount: Int
    let payloadByteCount: Int
    let serviceStartedAt: TimeInterval
}

enum QuestionBankModuleReaderFailure: LocalizedError {
    case questionRowsNotReady

    var errorDescription: String? {
        switch self {
        case .questionRowsNotReady:
            "题目数据尚未就绪，请重试。"
        }
    }
}

private struct QuestionBankReaderRecordRow: Sendable {
    let compoundID: String
    let paperID: String
    let kind: String
    let stableID: String
    let moduleID: String?
    let title: String?
    let contentRevision: Int
    let payload: Data
    let assetRelativePath: String?

    init(_ record: QuestionBankRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        kind = record.kind
        stableID = record.stableID
        moduleID = record.moduleID
        title = record.title
        contentRevision = record.contentRevision
        payload = record.payload
        assetRelativePath = record.assetRelativePath
    }

    var revisionToken: QuestionBankReaderRecordRevisionToken {
        QuestionBankReaderRecordRevisionToken(
            compoundID: compoundID,
            paperID: paperID,
            kind: kind,
            moduleID: moduleID,
            title: title,
            contentRevision: contentRevision,
            assetRelativePath: assetRelativePath
        )
    }

}

private struct QuestionBankReaderAssetRow: Sendable {
    let reference: QuestionBankAssetReference
    let revisionToken: QuestionBankReaderRecordRevisionToken

    init(_ record: QuestionBankRecord) {
        reference = QuestionBankAssetReference(record: record)
        revisionToken = QuestionBankReaderRecordRevisionToken(
            compoundID: record.compoundID,
            paperID: record.paperID,
            kind: record.kind,
            moduleID: record.moduleID,
            title: record.title,
            contentRevision: record.contentRevision,
            assetRelativePath: record.assetRelativePath
        )
    }
}

enum QuestionBankModuleReaderDataService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.baoger07122.kaogongreview.nativebeta",
        category: "question-bank-module-load"
    )

    static func load(
        container: ModelContainer,
        paperID: String,
        moduleID: String
    ) throws -> QuestionBankModuleReaderSnapshot {
        let serviceStartedAt = ProcessInfo.processInfo.systemUptime
        let readStartedAt = serviceStartedAt
        let context = ModelContext(container)
        let questionKind = QuestionBankRepository.questionKind
        let materialKind = QuestionBankRepository.materialKind
        let paperKind = QuestionBankRepository.paperKind
        let moduleKind = QuestionBankRepository.moduleKind
        let assetKind = QuestionBankRepository.assetKind

        let modulePredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID
                && $0.moduleID == moduleID
                && ($0.kind == questionKind || $0.kind == materialKind)
        }
        let moduleRecords = try context.fetch(FetchDescriptor(predicate: modulePredicate))
        let summaryPredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID
                && ($0.kind == paperKind || ($0.kind == moduleKind && $0.stableID == moduleID))
        }
        let summaryRecords = try context.fetch(FetchDescriptor(predicate: summaryPredicate))
        let assetPredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID && $0.kind == assetKind
        }
        let assetRecords = try context.fetch(FetchDescriptor(predicate: assetPredicate))

        let moduleRows = moduleRecords.map(QuestionBankReaderRecordRow.init)
        let summaryRows = summaryRecords.map(QuestionBankReaderRecordRow.init)
        let assetRows = assetRecords.map(QuestionBankReaderAssetRow.init)
        let assetPayloadByteCount = assetRecords.reduce(0) { $0 + $1.payload.count }
        let payloadByteCount = moduleRows.reduce(0) { $0 + $1.payload.count }
            + summaryRows.reduce(0) { $0 + $1.payload.count }
            + assetPayloadByteCount
        let readMilliseconds = (ProcessInfo.processInfo.systemUptime - readStartedAt) * 1_000

        let decodeStartedAt = ProcessInfo.processInfo.systemUptime
        let decoder = JSONDecoder()
        let module = summaryRows.first(where: { $0.kind == moduleKind })
            .flatMap { try? decoder.decode(QuestionBankModule.self, from: $0.payload) }
        let paper = summaryRows.first(where: { $0.kind == paperKind })
            .flatMap { try? decoder.decode(QuestionBankPaper.self, from: $0.payload) }

        var decodedQuestions: [(row: QuestionBankReaderRecordRow, question: QuestionBankQuestion)] = []
        var materialsByID: [String: QuestionBankMaterial] = [:]
        var questionDecodeFailures = 0
        var materialDecodeFailures = 0
        for row in moduleRows {
            guard !Task.isCancelled else { throw CancellationError() }
            switch row.kind {
            case questionKind:
                if let question = try? decoder.decode(QuestionBankQuestion.self, from: row.payload) {
                    decodedQuestions.append((row, question))
                } else {
                    questionDecodeFailures += 1
                }
            case materialKind:
                if let material = try? decoder.decode(QuestionBankMaterial.self, from: row.payload) {
                    materialsByID[row.stableID] = material
                } else {
                    materialDecodeFailures += 1
                }
            default:
                break
            }
        }
        let decodeMilliseconds = (ProcessInfo.processInfo.systemUptime - decodeStartedAt) * 1_000

        let orderingStartedAt = ProcessInfo.processInfo.systemUptime
        decodedQuestions.sort {
            if $0.question.number != $1.question.number {
                return $0.question.number < $1.question.number
            }
            return $0.question.id < $1.question.id
        }
        let paperTitle = paper?.title ?? summaryRows.first(where: { $0.kind == paperKind })?.title ?? ""
        let moduleTitle = module?.title ?? ""
        let overviewCandidates = decodedQuestions.map { entry in
            QuestionBankOverviewCandidate(
                id: entry.question.id,
                paperID: entry.question.paperID,
                paperTitle: paperTitle,
                questionNumber: entry.question.number,
                moduleID: entry.question.moduleID,
                moduleTitle: moduleTitle,
                moduleSequence: module?.sequence ?? Int.max,
                type: entry.question.type,
                subject: entry.question.subject
            )
        }
        let questionsByID = Dictionary(
            decodedQuestions.map { ($0.question.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedQuestions = QuestionBankModulePracticeOrdering
            .orderedQuestionIDs(from: overviewCandidates)
            .compactMap { questionsByID[$0] }
        let questionSnapshots = orderedQuestions.enumerated().map { index, entry in
            QuestionBankModuleReaderQuestionSnapshot(
                compoundID: entry.row.compoundID,
                question: entry.question,
                localOrdinal: index + 1
            )
        }
        let readingSteps = QuestionBankReadingSequence.steps(for: orderedQuestions.map(\.question))
        let referencedAssetIDs = Set(
            orderedQuestions.flatMap { entry in
                [entry.question.stemImageAssetID]
                    + entry.question.options.map(\.imageAssetID)
                    + [entry.question.materialID].compactMap { materialsByID[$0]?.imageAssetID }
            }.filter { !$0.isEmpty }
        )
        let assetsByID = Dictionary(
            assetRows
                .filter { referencedAssetIDs.contains($0.reference.stableID) }
                .map { ($0.reference.stableID, $0.reference) },
            uniquingKeysWith: { first, _ in first }
        )
        var revisionTokens = Set(moduleRows.map(\.revisionToken))
        revisionTokens.formUnion(summaryRows.map(\.revisionToken))
        revisionTokens.formUnion(
            assetRows.filter { referencedAssetIDs.contains($0.reference.stableID) }.map(\.revisionToken)
        )
        let orderingMilliseconds = (ProcessInfo.processInfo.systemUptime - orderingStartedAt) * 1_000

        logger.info("module stage=read paper=\(paperID, privacy: .private(mask: .hash)) module=\(moduleID, privacy: .private(mask: .hash)) rows=\(moduleRows.count, privacy: .public) summaryRows=\(summaryRows.count, privacy: .public) assetRows=\(assetRows.count, privacy: .public) payloadBytes=\(payloadByteCount, privacy: .public) elapsedMs=\(readMilliseconds, format: .fixed(precision: 1))")
        logger.info("module stage=decode questionRows=\(moduleRows.filter { $0.kind == questionKind }.count, privacy: .public) materialRows=\(moduleRows.filter { $0.kind == materialKind }.count, privacy: .public) decodedQuestions=\(decodedQuestions.count, privacy: .public) decodedMaterials=\(materialsByID.count, privacy: .public) questionFailures=\(questionDecodeFailures, privacy: .public) materialFailures=\(materialDecodeFailures, privacy: .public) elapsedMs=\(decodeMilliseconds, format: .fixed(precision: 1))")
        logger.info("module stage=order questions=\(questionSnapshots.count, privacy: .public) materials=\(materialsByID.count, privacy: .public) referencedAssets=\(assetsByID.count, privacy: .public) elapsedMs=\(orderingMilliseconds, format: .fixed(precision: 1))")

        return QuestionBankModuleReaderSnapshot(
            module: module,
            paper: paper,
            questions: questionSnapshots,
            readingSteps: readingSteps,
            materialsByID: materialsByID,
            assetsByID: assetsByID,
            revisionTokens: revisionTokens,
            questionRecordCount: moduleRows.filter { $0.kind == questionKind }.count,
            materialRecordCount: moduleRows.filter { $0.kind == materialKind }.count,
            referencedAssetCount: assetsByID.count,
            payloadByteCount: payloadByteCount,
            serviceStartedAt: serviceStartedAt
        )
    }

    static func loadQuestionUpdates(
        container: ModelContainer,
        paperID: String,
        moduleID: String,
        questionIDs: Set<String>
    ) throws -> [QuestionBankReaderQuestionRefresh] {
        guard !questionIDs.isEmpty else { return [] }
        let startedAt = ProcessInfo.processInfo.systemUptime
        let context = ModelContext(container)
        let questionKind = QuestionBankRepository.questionKind
        let requestedIDs = Array(questionIDs)
        let descriptorPredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID
                && $0.moduleID == moduleID
                && $0.kind == questionKind
                && requestedIDs.contains($0.stableID)
        }
        var descriptor = FetchDescriptor<QuestionBankRecord>(predicate: descriptorPredicate)
        descriptor.fetchLimit = requestedIDs.count
        let records = try context.fetch(descriptor)
        let decoder = JSONDecoder()
        var updates: [QuestionBankReaderQuestionRefresh] = []
        updates.reserveCapacity(records.count)
        var payloadBytes = 0
        for record in records {
            guard !Task.isCancelled else { throw CancellationError() }
            let row = QuestionBankReaderRecordRow(record)
            payloadBytes += row.payload.count
            guard let question = try? decoder.decode(QuestionBankQuestion.self, from: row.payload) else {
                continue
            }
            guard question.id == row.stableID, question.paperID == row.paperID else { continue }
            updates.append(
                QuestionBankReaderQuestionRefresh(
                    compoundID: row.compoundID,
                    stableID: row.stableID,
                    question: question,
                    revisionToken: row.revisionToken,
                    payloadByteCount: row.payload.count
                )
            )
        }
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        logger.info("module stage=question-refresh paper=\(paperID, privacy: .private(mask: .hash)) module=\(moduleID, privacy: .private(mask: .hash)) requested=\(questionIDs.count, privacy: .public) found=\(records.count, privacy: .public) decoded=\(updates.count, privacy: .public) payloadBytes=\(payloadBytes, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1))")
        return updates
    }
}
