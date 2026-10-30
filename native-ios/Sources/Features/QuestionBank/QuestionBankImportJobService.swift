import CryptoKit
import Foundation
import SwiftData

enum QuestionBankImportJobPhase: String, Codable, Sendable {
    case acquiringSource
    case preparing
    case awaitingConfirmation
    case committing
    case completed
    case cancelled
    case failed
    case interrupted
}

struct QuestionBankImportJobProgress: Sendable {
    var jobID: String
    var phase: QuestionBankImportJobPhase
    var phaseLabel: String
    var processedCount: Int
    var totalCount: Int
    var message: String
}

struct QuestionBankBatchSourceSnapshot: Codable, Equatable, Sendable {
    var sourceID: String
    var batchID: String
    var revision: String
    var sourceSHA256: String
    var metadataPayload: Data
    var paperID: String
    var importedAt: Date
    var sourceQuestionCount: Int
    var sourceMaterialCount: Int
    var uniqueQuestionCount: Int
    var duplicateQuestionCount: Int
    var pendingQuestionCount: Int
    var uniqueMaterialCount: Int
    var duplicateMaterialCount: Int
    var pendingMaterialCount: Int

    init(_ row: QuestionBankBatchSourceRecord) {
        sourceID = row.sourceID
        batchID = row.batchID
        revision = row.revision
        sourceSHA256 = row.sourceSHA256
        metadataPayload = row.metadataPayload
        paperID = row.paperID
        importedAt = row.importedAt
        sourceQuestionCount = row.sourceQuestionCount
        sourceMaterialCount = row.sourceMaterialCount
        uniqueQuestionCount = row.uniqueQuestionCount
        duplicateQuestionCount = row.duplicateQuestionCount
        pendingQuestionCount = row.pendingQuestionCount
        uniqueMaterialCount = row.uniqueMaterialCount
        duplicateMaterialCount = row.duplicateMaterialCount
        pendingMaterialCount = row.pendingMaterialCount
    }
}

struct QuestionBankImportJobPreview: Sendable {
    var records: [QuestionBankStoredRow]
    var batchSources: [QuestionBankBatchSourceSnapshot]
    var revisionToken: String
    var batchPreparation: QuestionBankBatchPreview?
    var batchPreparationError: String?
    var batchReplacingPaperID: String?
    var packageUpdatePreview: QuestionBankBatchPackageUpdatePreview?
    var globalQuestionOwners: [String: Set<String>]
}

struct QuestionBankImportCommitResult: Sendable {
    var batchSummary: QuestionBankBatchPreview?
    var payloadBackupFileName: String?
}

struct QuestionBankRecoveredImport: Sendable {
    var jobID: String
    var prepared: QuestionBankPreparedImport
    var preview: QuestionBankImportJobPreview
}

enum QuestionBankImportJobFailure: LocalizedError, Equatable {
    case anotherImportIsActive
    case missingJob
    case missingPreparedImport
    case stalePreview
    case changedPreparedImport
    case stagedAssetChanged(String)
    case databaseTransaction(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .anotherImportIsActive:
            "已有真题导入任务正在准备或等待确认，请先完成或取消该任务。"
        case .missingJob:
            "找不到这次导入任务；请重新选择文件。"
        case .missingPreparedImport:
            "这次导入尚未形成可恢复预览；请重新选择文件。"
        case .stalePreview:
            "本机题目或批次关联在预览后发生变化，请核对刷新后的预览再提交。"
        case .changedPreparedImport:
            "待提交数据与已校验的导入包不一致；没有写入题库。"
        case .stagedAssetChanged(let path):
            "待导入图片在预览后发生变化（\(path)）；没有写入题库。"
        case .databaseTransaction(let reason):
            "题库事务没有完成，所有题目和索引写入已回滚：\(reason)"
        case .cancelled:
            "导入已取消。"
        }
    }
}

enum QuestionBankImportJobStore {
    static let jobKind = "question-bank-import-job"

    static func root(create: Bool = true) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ).appendingPathComponent("QuestionBankImportJobs", isDirectory: true)
        if create { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        return base
    }

    static func directory(for jobID: String, create: Bool = true) throws -> URL {
        guard UUID(uuidString: jobID) != nil else { throw QuestionBankImportJobFailure.missingJob }
        let root = try root(create: create)
        guard let directory = QuestionBankAssetStore.url(for: jobID, under: root) else {
            throw QuestionBankImportJobFailure.missingJob
        }
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return directory
    }

    static func child(_ path: String, for jobID: String) throws -> URL {
        let root = try directory(for: jobID)
        guard let url = QuestionBankAssetStore.url(for: path, under: root) else {
            throw QuestionBankImportJobFailure.missingJob
        }
        return url
    }

    static func fetch(_ jobID: String, in context: ModelContext) throws -> QuestionBankImportJobRecord? {
        let predicate = #Predicate<QuestionBankImportJobRecord> { $0.jobID == jobID }
        return try context.fetch(FetchDescriptor<QuestionBankImportJobRecord>(predicate: predicate)).first
    }

    static func persistProgress(
        _ progress: QuestionBankImportJobProgress,
        in container: ModelContainer
    ) {
        do {
            let context = ModelContext(container)
            guard let job = try fetch(progress.jobID, in: context) else { return }
            try context.transaction {
                job.phase = progress.phase.rawValue
                job.phaseLabel = progress.phaseLabel
                job.processedCount = progress.processedCount
                job.totalCount = progress.totalCount
                job.updatedAt = Date()
            }
        } catch {
            // A later phase write or final transaction reports persistence failures.
        }
    }

    static func update(
        _ jobID: String,
        in container: ModelContainer,
        _ change: (QuestionBankImportJobRecord) throws -> Void
    ) throws {
        let context = ModelContext(container)
        guard let job = try fetch(jobID, in: context) else { throw QuestionBankImportJobFailure.missingJob }
        try context.transaction {
            try change(job)
            job.updatedAt = Date()
        }
    }

    static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct QuestionBankImportSnapshotFingerprint: Codable {
    var records: [QuestionBankStoredRow]
    var sources: [QuestionBankBatchSourceSnapshot]
    var associationRows: [String]
    var batchRows: [String]
}

struct QuestionBankImportFetchedSnapshot {
    var records: [QuestionBankRecord]
    var sources: [QuestionBankBatchSourceRecord]
    var batches: [QuestionBankBatchRecord]
    var materialLinks: [QuestionBankBatchMaterialLinkRecord]
    var questionLinks: [QuestionBankBatchQuestionLinkRecord]
    var storedRows: [QuestionBankStoredRow]
    var sourceSnapshots: [QuestionBankBatchSourceSnapshot]
    var globalQuestionOwners: [String: Set<String>]
    var revisionToken: String
}

enum QuestionBankImportSnapshotBuilder {
    static func single(
        plan: QuestionBankImportPlan,
        metadata: QuestionBankBatchMetadata?,
        in context: ModelContext
    ) throws -> QuestionBankImportFetchedSnapshot {
        guard let paper = plan.paper else { throw QuestionBankImportFailure.invalidPlan }
        return try build(
            targetPaperIDs: [paper.id],
            duplicateKeys: [paper.duplicateKey],
            sourceIDs: Set([metadata?.sourceID.trimmedNonempty].compactMap { $0 }),
            batchIDs: Set([metadata?.identityKey].compactMap { $0 }),
            questionIDs: Set(plan.questions.map(\.id)),
            in: context
        )
    }

    static func batch(
        package: QuestionBankBatchPackagePlan,
        in context: ModelContext
    ) throws -> QuestionBankImportFetchedSnapshot {
        try build(
            targetPaperIDs: Set(package.paperPlans.compactMap { $0.paper?.id }),
            duplicateKeys: [],
            sourceIDs: [],
            batchIDs: [],
            questionIDs: Set(package.paperPlans.flatMap { $0.questions.map(\.id) }),
            in: context
        )
    }

    private static func build(
        targetPaperIDs: Set<String>,
        duplicateKeys: Set<String>,
        sourceIDs: Set<String>,
        batchIDs: Set<String>,
        questionIDs: Set<String>,
        in context: ModelContext
    ) throws -> QuestionBankImportFetchedSnapshot {
        let paperKind = QuestionBankRepository.paperKind
        let targetIDs = Array(targetPaperIDs)
        let normalizedKeys = Array(duplicateKeys)
        var headers: [QuestionBankRecord] = []
        if !targetIDs.isEmpty || !normalizedKeys.isEmpty {
            let predicate = #Predicate<QuestionBankRecord> {
                $0.kind == paperKind
                    && (targetIDs.contains($0.stableID)
                        || normalizedKeys.contains($0.normalizedPaperKey ?? ""))
            }
            headers = try context.fetch(FetchDescriptor<QuestionBankRecord>(predicate: predicate))
        }
        var paperIDs = targetPaperIDs.union(headers.map(\.paperID))
        let sourceIDValues = Array(sourceIDs)
        let initialBatchIDs = Array(batchIDs)
        let initialPaperIDs = Array(paperIDs)
        var sources: [QuestionBankBatchSourceRecord] = []
        if !sourceIDValues.isEmpty || !initialBatchIDs.isEmpty || !initialPaperIDs.isEmpty {
            let predicate = #Predicate<QuestionBankBatchSourceRecord> {
                sourceIDValues.contains($0.sourceID)
                    || initialBatchIDs.contains($0.batchID)
                    || initialPaperIDs.contains($0.paperID)
            }
            sources = try context.fetch(FetchDescriptor<QuestionBankBatchSourceRecord>(predicate: predicate))
        }
        let relevantBatchIDs = batchIDs.union(sources.map(\.batchID))
        let batchIDValues = Array(relevantBatchIDs)
        if !batchIDValues.isEmpty {
            let predicate = #Predicate<QuestionBankBatchSourceRecord> { batchIDValues.contains($0.batchID) }
            sources = try context.fetch(FetchDescriptor<QuestionBankBatchSourceRecord>(predicate: predicate))
        }
        paperIDs.formUnion(sources.map(\.paperID))

        let recordPaperIDs = Array(paperIDs)
        let incomingQuestionIDs = Array(questionIDs)
        let questionKind = QuestionBankRepository.questionKind
        var records: [QuestionBankRecord] = []
        if !recordPaperIDs.isEmpty || !incomingQuestionIDs.isEmpty {
            let predicate = #Predicate<QuestionBankRecord> {
                recordPaperIDs.contains($0.paperID)
                    || ($0.kind == questionKind && incomingQuestionIDs.contains($0.stableID))
            }
            records = try context.fetch(FetchDescriptor<QuestionBankRecord>(predicate: predicate))
        }
        var byCompoundID: [String: QuestionBankRecord] = [:]
        for row in headers + records { byCompoundID[row.compoundID] = row }
        records = byCompoundID.values.sorted { $0.compoundID < $1.compoundID }

        var batches: [QuestionBankBatchRecord] = []
        var materialLinks: [QuestionBankBatchMaterialLinkRecord] = []
        var questionLinks: [QuestionBankBatchQuestionLinkRecord] = []
        if !batchIDValues.isEmpty {
            let batchPredicate = #Predicate<QuestionBankBatchRecord> { batchIDValues.contains($0.identityKey) }
            batches = try context.fetch(FetchDescriptor<QuestionBankBatchRecord>(predicate: batchPredicate))
            let materialPredicate = #Predicate<QuestionBankBatchMaterialLinkRecord> { batchIDValues.contains($0.batchID) }
            materialLinks = try context.fetch(FetchDescriptor<QuestionBankBatchMaterialLinkRecord>(predicate: materialPredicate))
            let questionPredicate = #Predicate<QuestionBankBatchQuestionLinkRecord> { batchIDValues.contains($0.batchID) }
            questionLinks = try context.fetch(FetchDescriptor<QuestionBankBatchQuestionLinkRecord>(predicate: questionPredicate))
        }

        let rows = records.map { row in
            QuestionBankStoredRow(
                compoundID: row.compoundID,
                paperID: row.paperID,
                kind: row.kind,
                stableID: row.stableID,
                moduleID: row.moduleID,
                questionNumber: row.questionNumber,
                sequence: row.sequence,
                year: row.year,
                examType: row.examType,
                normalizedPaperKey: row.normalizedPaperKey,
                title: row.title,
                searchText: row.searchText,
                payload: row.payload,
                contentRevision: row.contentRevision,
                assetRelativePath: row.assetRelativePath
            )
        }.sorted { $0.compoundID < $1.compoundID }
        let sourceSnapshots = sources.map(QuestionBankBatchSourceSnapshot.init)
            .sorted { $0.sourceID < $1.sourceID }
        var owners: [String: Set<String>] = [:]
        for row in records where row.kind == questionKind && questionIDs.contains(row.stableID) {
            owners[row.stableID, default: []].insert(row.paperID)
        }
        let associationRows = materialLinks.map {
            "m|\($0.compoundID)|\($0.batchID)|\($0.sourcePaperID)|\($0.sourceMaterialID)|\($0.canonicalPaperID ?? "")|\($0.canonicalMaterialID ?? "")|\($0.fingerprint)|\($0.status)|\($0.pendingReason ?? "")"
        } + questionLinks.map {
            "q|\($0.compoundID)|\($0.batchID)|\($0.sourcePaperID)|\($0.sourceQuestionID)|\($0.canonicalPaperID ?? "")|\($0.canonicalQuestionID ?? "")|\($0.fingerprint)|\($0.status)|\($0.pendingReason ?? "")"
        }
        let batchRows = batches.map {
            "\($0.identityKey)|\($0.family)|\($0.year)|\($0.displayName)|\($0.metadataPayload.base64EncodedString())|\($0.sourceCount)|\($0.uniqueMaterialCount)|\($0.uniqueQuestionCount)|\($0.pendingCount)"
        }
        let fingerprint = QuestionBankImportSnapshotFingerprint(
            records: rows,
            sources: sourceSnapshots,
            associationRows: associationRows.sorted(),
            batchRows: batchRows.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let token = QuestionBankImportJobStore.sha256(try encoder.encode(fingerprint))
        return QuestionBankImportFetchedSnapshot(
            records: records,
            sources: sources,
            batches: batches,
            materialLinks: materialLinks,
            questionLinks: questionLinks,
            storedRows: rows,
            sourceSnapshots: sourceSnapshots,
            globalQuestionOwners: owners,
            revisionToken: token
        )
    }
}

actor QuestionBankImportJobService {
    static let shared = QuestionBankImportJobService()
    private var isExecutingWrite = false

    func prepare(
        from sourceURL: URL,
        source: QuestionBankImportSource,
        in container: ModelContainer,
        onProgress: @escaping @Sendable (QuestionBankImportJobProgress) -> Void = { _ in }
    ) async throws -> (jobID: String, prepared: QuestionBankPreparedImport) {
        guard !isExecutingWrite else { throw QuestionBankImportJobFailure.anotherImportIsActive }
        isExecutingWrite = true
        defer { isExecutingWrite = false }
        let worker = Task.detached(priority: .userInitiated) {
            try Self.prepareSynchronously(from: sourceURL, source: source, in: container, onProgress: onProgress)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    func preview(
        jobID: String,
        planOverride: QuestionBankImportPlan? = nil,
        metadata: QuestionBankBatchMetadata? = nil,
        packageOverride: QuestionBankBatchPackagePlan? = nil,
        in container: ModelContainer
    ) async throws -> QuestionBankImportJobPreview {
        guard !isExecutingWrite else { throw QuestionBankImportJobFailure.anotherImportIsActive }
        return try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            guard let job = try QuestionBankImportJobStore.fetch(jobID, in: context),
                  QuestionBankImportJobPhase(rawValue: job.phase) == .awaitingConfirmation,
                  let payload = job.preparedImportPayload else {
                throw QuestionBankImportJobFailure.missingPreparedImport
            }
            let prepared = try JSONDecoder().decode(QuestionBankPreparedImport.self, from: payload)
            let result: QuestionBankImportJobPreview
            switch prepared {
            case .single(let savedPlan):
                let plan = planOverride ?? savedPlan
                let snapshot = try QuestionBankImportSnapshotBuilder.single(
                    plan: plan,
                    metadata: metadata,
                    in: context
                )
                var batchPreview: QuestionBankBatchPreview?
                var batchError: String?
                var replacingPaperID: String?
                if let metadata {
                    guard let paper = plan.paper else { throw QuestionBankImportFailure.invalidPlan }
                    let duplicate = QuestionBankRepository.duplicatePaper(for: paper, in: snapshot.records)
                    replacingPaperID = snapshot.sources.first(where: { $0.sourceID == metadata.sourceID })?.paperID
                        ?? duplicate?.paperID
                    do {
                        let preparation = try QuestionBankBatchRepository.prepare(
                            metadata: metadata,
                            plan: plan,
                            records: snapshot.records,
                            sourceRecords: snapshot.sources,
                            replacingPaperID: duplicate?.paperID
                        )
                        batchPreview = preparation.currentSourcePreview
                        replacingPaperID = preparation.replacingPaperID
                    } catch {
                        batchError = error.localizedDescription
                    }
                }
                result = QuestionBankImportJobPreview(
                    records: snapshot.storedRows,
                    batchSources: snapshot.sourceSnapshots,
                    revisionToken: snapshot.revisionToken,
                    batchPreparation: batchPreview,
                    batchPreparationError: batchError,
                    batchReplacingPaperID: replacingPaperID,
                    packageUpdatePreview: nil,
                    globalQuestionOwners: snapshot.globalQuestionOwners
                )
            case .batch(let savedPackage):
                let package = packageOverride ?? savedPackage
                let snapshot = try QuestionBankImportSnapshotBuilder.batch(package: package, in: context)
                let packagePreview = QuestionBankBatchPackageRepository.updatePreview(
                    for: package,
                    storedRows: snapshot.storedRows,
                    globalQuestionOwners: snapshot.globalQuestionOwners
                )
                result = QuestionBankImportJobPreview(
                    records: snapshot.storedRows,
                    batchSources: snapshot.sourceSnapshots,
                    revisionToken: snapshot.revisionToken,
                    batchPreparation: nil,
                    batchPreparationError: nil,
                    batchReplacingPaperID: nil,
                    packageUpdatePreview: packagePreview,
                    globalQuestionOwners: snapshot.globalQuestionOwners
                )
            }
            try QuestionBankImportJobStore.update(jobID, in: container) { job in
                job.previewSnapshotToken = result.revisionToken
                job.lastError = nil
            }
            return result
        }.value
    }

    func commitSingle(
        jobID: String,
        plan: QuestionBankImportPlan,
        decision: QuestionBankImportDecision,
        metadata: QuestionBankBatchMetadata?,
        expectedRevisionToken: String,
        in container: ModelContainer,
        onProgress: @escaping @Sendable (QuestionBankImportJobProgress) -> Void = { _ in }
    ) async throws -> QuestionBankImportCommitResult {
        guard !isExecutingWrite else { throw QuestionBankImportJobFailure.anotherImportIsActive }
        isExecutingWrite = true
        defer { isExecutingWrite = false }
        let worker = Task.detached(priority: .userInitiated) {
            do {
                return try Self.commitSingleSynchronously(
                    jobID: jobID, plan: plan, decision: decision, metadata: metadata,
                    expectedRevisionToken: expectedRevisionToken, in: container, onProgress: onProgress
                )
            } catch {
                Self.recordCommitFailure(jobID: jobID, error: error, plan: .single(plan), in: container)
                throw error
            }
        }
        // Once commit starts, its database transaction owns the outcome. A view task
        // disappearing cannot cancel a transaction halfway through.
        return try await worker.value
    }

    func commitBatch(
        jobID: String,
        package: QuestionBankBatchPackagePlan,
        confirmedNewQuestionKeys: Set<QuestionBankBatchQuestionKey>,
        expectedRevisionToken: String,
        in container: ModelContainer,
        onProgress: @escaping @Sendable (QuestionBankImportJobProgress) -> Void = { _ in }
    ) async throws -> QuestionBankBatchPackageCommitResult {
        guard !isExecutingWrite else { throw QuestionBankImportJobFailure.anotherImportIsActive }
        isExecutingWrite = true
        defer { isExecutingWrite = false }
        let worker = Task.detached(priority: .userInitiated) {
            do {
                return try Self.commitBatchSynchronously(
                    jobID: jobID, package: package, confirmedNewQuestionKeys: confirmedNewQuestionKeys,
                    expectedRevisionToken: expectedRevisionToken, in: container, onProgress: onProgress
                )
            } catch {
                Self.recordCommitFailure(jobID: jobID, error: error, plan: .batch(package), in: container)
                throw error
            }
        }
        return try await worker.value
    }

    func cancel(jobID: String, in container: ModelContainer) async {
        guard !isExecutingWrite else { return }
        var shouldDeleteDirectory = false
        do {
            try QuestionBankImportJobStore.update(jobID, in: container) { job in
                guard let phase = QuestionBankImportJobPhase(rawValue: job.phase),
                      phase == .awaitingConfirmation || phase == .failed || phase == .interrupted else {
                    return
                }
                job.phase = QuestionBankImportJobPhase.cancelled.rawValue
                job.phaseLabel = "已取消"
                job.preparedImportPayload = nil
                job.stagedAssetHashes = nil
                job.previewSnapshotToken = nil
                job.lastError = nil
                shouldDeleteDirectory = true
            }
        } catch {
            return
        }
        if shouldDeleteDirectory,
           let directory = try? QuestionBankImportJobStore.directory(for: jobID, create: false) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func recover(in container: ModelContainer) async throws -> [QuestionBankRecoveredImport] {
        guard !isExecutingWrite else { return [] }
        isExecutingWrite = true
        defer { isExecutingWrite = false }
        let worker = Task.detached(priority: .userInitiated) {
            try Self.recoverSynchronously(in: container)
        }
        return try await worker.value
    }

    private static func prepareSynchronously(
        from sourceURL: URL,
        source: QuestionBankImportSource,
        in container: ModelContainer,
        onProgress: @escaping @Sendable (QuestionBankImportJobProgress) -> Void
    ) throws -> (jobID: String, prepared: QuestionBankPreparedImport) {
        let context = ModelContext(container)
        let active = Set([
            QuestionBankImportJobPhase.acquiringSource.rawValue,
            QuestionBankImportJobPhase.preparing.rawValue,
            QuestionBankImportJobPhase.awaitingConfirmation.rawValue,
            QuestionBankImportJobPhase.committing.rawValue
        ])
        let activePredicate = #Predicate<QuestionBankImportJobRecord> { active.contains($0.phase) }
        guard try context.fetch(FetchDescriptor<QuestionBankImportJobRecord>(predicate: activePredicate)).isEmpty else {
            throw QuestionBankImportJobFailure.anotherImportIsActive
        }
        let jobID = UUID().uuidString.lowercased()
        let directory = try QuestionBankImportJobStore.directory(for: jobID)
        let ext = sourceURL.pathExtension.lowercased()
        let sourceRelativePath = "source.\(ext.isEmpty ? "bin" : ext)"
        let sourceDestination = try QuestionBankImportJobStore.child(sourceRelativePath, for: jobID)
        let fileName = sourceURL.lastPathComponent
        let job = QuestionBankImportJobRecord(
            jobID: jobID,
            phase: QuestionBankImportJobPhase.acquiringSource.rawValue,
            phaseLabel: "取得本地文件",
            processedCount: 0,
            totalCount: 1,
            sourceFileName: fileName,
            sourceRelativePath: sourceRelativePath
        )
        context.insert(job)
        try context.save()
        let send: @Sendable (QuestionBankImportJobPhase, String, Int, Int, String, Bool) -> Void = { phase, label, done, total, message, persist in
            let progress = QuestionBankImportJobProgress(
                jobID: jobID, phase: phase, phaseLabel: label,
                processedCount: done, totalCount: total, message: message
            )
            if persist { QuestionBankImportJobStore.persistProgress(progress, in: container) }
            onProgress(progress)
        }
        let preparationStage = directory.appendingPathComponent("prepared", isDirectory: true)
        do {
            send(.acquiringSource, "取得本地文件", 0, 1, "正在持久化来源文件", true)
            try QuestionBankPackageImporter.persistReadableSource(
                from: sourceURL, source: source, to: sourceDestination
            )
            try Task.checkCancellation()
            let sourceHash = try QuestionBankImportJobStore.sha256(fileAt: sourceDestination)
            try QuestionBankImportJobStore.update(jobID, in: container) { row in
                row.sourceSHA256 = sourceHash
                row.phase = QuestionBankImportJobPhase.preparing.rawValue
                row.phaseLabel = "准备导入包"
                row.processedCount = 1
                row.totalCount = 1
            }
            send(.preparing, "准备导入包", 0, 1, "开始解析并校验来源文件", true)
            let prepared = try QuestionBankPackageImporter.prepareSelection(
                from: sourceDestination,
                source: .trustedLocalFile,
                stagingDirectory: preparationStage,
                onProgress: { phase in
                    send(.preparing, phase.rawValue, 0, 1, phase.rawValue, false)
                },
                onWorkProgress: { update in
                    let persist = update.processedCount == update.totalCount
                        || update.processedCount.isMultiple(of: 10)
                    send(
                        .preparing,
                        update.phase.rawValue,
                        update.processedCount,
                        update.totalCount,
                        update.phase.rawValue,
                        persist
                    )
                }
            )
            try Task.checkCancellation()
            let encoded = try JSONEncoder().encode(prepared)
            let assetHashes = try stagedAssetHashes(for: prepared)
            try QuestionBankImportJobStore.update(jobID, in: container) { row in
                row.phase = QuestionBankImportJobPhase.awaitingConfirmation.rawValue
                row.phaseLabel = "等待用户确认"
                row.processedCount = 1
                row.totalCount = 1
                row.preparedImportPayload = encoded
                row.stagedAssetHashes = try JSONEncoder().encode(assetHashes)
                row.previewSnapshotToken = nil
                row.lastError = nil
            }
            send(.awaitingConfirmation, "等待用户确认", 1, 1, "来源已校验，正在生成预览", true)
            return (jobID, prepared)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: directory)
            try? QuestionBankImportJobStore.update(jobID, in: container) { row in
                row.phase = QuestionBankImportJobPhase.cancelled.rawValue
                row.phaseLabel = "已取消"
                row.preparedImportPayload = nil
                row.stagedAssetHashes = nil
                row.sourceRelativePath = ""
            }
            throw QuestionBankImportJobFailure.cancelled
        } catch {
            try? FileManager.default.removeItem(at: preparationStage)
            try? QuestionBankImportJobStore.update(jobID, in: container) { row in
                row.phase = QuestionBankImportJobPhase.failed.rawValue
                row.phaseLabel = "准备失败"
                row.preparedImportPayload = nil
                row.stagedAssetHashes = nil
                row.sourceRelativePath = ""
                row.lastError = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func commitSingleSynchronously(
        jobID: String,
        plan: QuestionBankImportPlan,
        decision: QuestionBankImportDecision,
        metadata: QuestionBankBatchMetadata?,
        expectedRevisionToken: String,
        in container: ModelContainer,
        onProgress: @escaping @Sendable (QuestionBankImportJobProgress) -> Void
    ) throws -> QuestionBankImportCommitResult {
        let context = ModelContext(container)
        guard let job = try QuestionBankImportJobStore.fetch(jobID, in: context),
              QuestionBankImportJobPhase(rawValue: job.phase) == .awaitingConfirmation,
              let payload = job.preparedImportPayload,
              let saved = try? JSONDecoder().decode(QuestionBankPreparedImport.self, from: payload),
              case .single(let savedPlan) = saved else {
            throw QuestionBankImportJobFailure.missingPreparedImport
        }
        guard try sourceHash(for: job) == job.sourceSHA256,
              job.sourceSHA256 == plan.sourceFileSHA256,
              plan.id == savedPlan.id,
              plan.sourceFileSHA256 == savedPlan.sourceFileSHA256,
              plan.paper?.id == savedPlan.paper?.id,
              plan.stagingDirectory?.standardizedFileURL == savedPlan.stagingDirectory?.standardizedFileURL else {
            throw QuestionBankImportJobFailure.changedPreparedImport
        }
        try verifyStagedAssetHashes(job: job, prepared: .single(plan))
        let effectiveMetadata = metadata
        let snapshot = try QuestionBankImportSnapshotBuilder.single(plan: plan, metadata: effectiveMetadata, in: context)
        guard snapshot.revisionToken == expectedRevisionToken,
              job.previewSnapshotToken == expectedRevisionToken else {
            try QuestionBankImportJobStore.update(jobID, in: container) { $0.lastError = QuestionBankImportJobFailure.stalePreview.errorDescription }
            throw QuestionBankImportJobFailure.stalePreview
        }
        guard let paper = plan.paper else { throw QuestionBankImportFailure.invalidPlan }
        let duplicate = QuestionBankRepository.duplicatePaper(for: paper, in: snapshot.records)
        let batchPreparation: QuestionBankBatchPreparation?
        if let effectiveMetadata {
            batchPreparation = try QuestionBankBatchRepository.prepare(
                metadata: effectiveMetadata,
                plan: plan,
                records: snapshot.records,
                sourceRecords: snapshot.sources,
                replacingPaperID: duplicate?.paperID
            )
        } else {
            batchPreparation = nil
        }
        try context.transaction {
            job.phase = QuestionBankImportJobPhase.committing.rawValue
            job.phaseLabel = "准备一次性写入"
            job.processedCount = 0
            job.totalCount = max(1, plan.modules.count + plan.materials.count + plan.questions.count + plan.assets.count)
            job.lastError = nil
        }
        onProgress(QuestionBankImportJobProgress(
            jobID: jobID, phase: .committing, phaseLabel: "准备一次性写入",
            processedCount: 0,
            totalCount: max(1, plan.modules.count + plan.materials.count + plan.questions.count + plan.assets.count),
            message: "正在写入题目和资源"
        ))
        var payloadBackupFileName: String?
        do {
            payloadBackupFileName = try QuestionBankRepository.commit(
                plan,
                decision: decision,
                records: snapshot.records,
                context: context,
                batchPreparation: batchPreparation,
                batches: snapshot.batches,
                sources: snapshot.sources,
                batchMaterialLinks: snapshot.materialLinks,
                batchQuestionLinks: snapshot.questionLinks,
                expectedSnapshotToken: expectedRevisionToken,
                importJobID: jobID,
                oldGenerationPaths: generationPaths(
                    in: snapshot.records,
                    paperIDs: Set([duplicate?.paperID, paper.id].compactMap { $0 })
                ),
                onAssetProgress: { processed, total in
                    onProgress(QuestionBankImportJobProgress(
                        jobID: jobID, phase: .committing, phaseLabel: "复制图片",
                        processedCount: processed, totalCount: total,
                        message: "正在复制并校验图片资源"
                    ))
                },
                onProgress: { processed, total in
                    let progress = QuestionBankImportJobProgress(
                        jobID: jobID, phase: .committing, phaseLabel: "写入题目",
                        processedCount: processed, totalCount: total,
                        message: "正在原子写入题目与批次索引"
                    )
                    onProgress(progress)
                }
            )
        } catch {
            context.rollback()
            try? QuestionBankImportJobStore.update(jobID, in: container) { row in
                row.phase = QuestionBankImportJobPhase.awaitingConfirmation.rawValue
                row.phaseLabel = "等待重新确认"
                row.stagedGenerationPaths = try JSONEncoder().encode([String]())
                row.lastError = error.localizedDescription
            }
            throw error
        }
        cleanupAfterSuccessfulCommit(jobID: jobID, in: container)
        QuestionBankRecordChangeSignal.postStructureChange(paperIDs: Set([duplicate?.paperID, paper.id].compactMap { $0 }))
        return QuestionBankImportCommitResult(
            batchSummary: batchPreparation?.currentSourcePreview,
            payloadBackupFileName: payloadBackupFileName
        )
    }

    private static func commitBatchSynchronously(
        jobID: String,
        package: QuestionBankBatchPackagePlan,
        confirmedNewQuestionKeys: Set<QuestionBankBatchQuestionKey>,
        expectedRevisionToken: String,
        in container: ModelContainer,
        onProgress: @escaping @Sendable (QuestionBankImportJobProgress) -> Void
    ) throws -> QuestionBankBatchPackageCommitResult {
        let context = ModelContext(container)
        guard let job = try QuestionBankImportJobStore.fetch(jobID, in: context),
              QuestionBankImportJobPhase(rawValue: job.phase) == .awaitingConfirmation,
              let payload = job.preparedImportPayload,
              let saved = try? JSONDecoder().decode(QuestionBankPreparedImport.self, from: payload),
              case .batch(let savedPackage) = saved else {
            throw QuestionBankImportJobFailure.missingPreparedImport
        }
        guard try sourceHash(for: job) == job.sourceSHA256,
              job.sourceSHA256 == package.sourceFileSHA256,
              package.id == savedPackage.id,
              package.sourceFileSHA256 == savedPackage.sourceFileSHA256,
              package.manifest == savedPackage.manifest,
              package.stagingDirectory?.standardizedFileURL == savedPackage.stagingDirectory?.standardizedFileURL else {
            throw QuestionBankImportJobFailure.changedPreparedImport
        }
        try verifyStagedAssetHashes(job: job, prepared: .batch(package))
        let snapshot = try QuestionBankImportSnapshotBuilder.batch(package: package, in: context)
        guard snapshot.revisionToken == expectedRevisionToken,
              job.previewSnapshotToken == expectedRevisionToken else {
            try QuestionBankImportJobStore.update(jobID, in: container) { $0.lastError = QuestionBankImportJobFailure.stalePreview.errorDescription }
            throw QuestionBankImportJobFailure.stalePreview
        }
        let total = max(1, package.paperPlans.reduce(0) { $0 + $1.modules.count + $1.materials.count + $1.questions.count + $1.assets.count })
        try context.transaction {
            job.phase = QuestionBankImportJobPhase.committing.rawValue
            job.phaseLabel = "准备一次性写入"
            job.processedCount = 0
            job.totalCount = total
            job.lastError = nil
        }
        onProgress(QuestionBankImportJobProgress(
            jobID: jobID, phase: .committing, phaseLabel: "准备一次性写入",
            processedCount: 0, totalCount: total, message: "正在写入整批试卷"
        ))
        do {
            let result = try QuestionBankBatchPackageRepository.commit(
                package,
                confirmedNewQuestionKeys: confirmedNewQuestionKeys,
                records: snapshot.records,
                context: context,
                globalQuestionOwners: snapshot.globalQuestionOwners,
                expectedSnapshotToken: expectedRevisionToken,
                importJobID: jobID,
                oldGenerationPaths: generationPaths(
                    in: snapshot.records,
                    paperIDs: Set(package.paperPlans.compactMap { $0.paper?.id })
                ),
                onAssetProgress: { processed, total in
                    onProgress(QuestionBankImportJobProgress(
                        jobID: jobID, phase: .committing, phaseLabel: "复制图片",
                        processedCount: processed, totalCount: total,
                        message: "正在复制并校验批量包图片"
                    ))
                },
                onProgress: { processed, total in
                    onProgress(QuestionBankImportJobProgress(
                        jobID: jobID, phase: .committing, phaseLabel: "写入批次实体",
                        processedCount: processed, totalCount: total,
                        message: "正在原子写入整批试卷与资源索引"
                    ))
                }
            )
            cleanupAfterSuccessfulCommit(jobID: jobID, in: container)
            QuestionBankRecordChangeSignal.postStructureChange(
                paperIDs: Set(package.paperPlans.compactMap { $0.paper?.id })
            )
            return result
        } catch {
            context.rollback()
            try? QuestionBankImportJobStore.update(jobID, in: container) { row in
                row.phase = QuestionBankImportJobPhase.awaitingConfirmation.rawValue
                row.phaseLabel = "等待重新确认"
                row.stagedGenerationPaths = try JSONEncoder().encode([String]())
                row.lastError = error.localizedDescription
            }
            throw error
        }
    }

    private static func recoverSynchronously(in container: ModelContainer) throws -> [QuestionBankRecoveredImport] {
        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<QuestionBankImportJobRecord>())
        for job in jobs {
            guard let phase = QuestionBankImportJobPhase(rawValue: job.phase) else { continue }
            switch phase {
            case .acquiringSource, .preparing:
                do {
                    try resumeInterruptedPreparation(jobID: job.jobID, in: container)
                } catch {
                    let preparationStage = try? QuestionBankImportJobStore.child("prepared", for: job.jobID)
                    if let preparationStage { try? FileManager.default.removeItem(at: preparationStage) }
                    try? QuestionBankImportJobStore.update(job.jobID, in: container) { row in
                        row.phase = QuestionBankImportJobPhase.failed.rawValue
                        row.phaseLabel = "恢复准备失败"
                        row.preparedImportPayload = nil
                        row.stagedAssetHashes = nil
                        row.sourceRelativePath = ""
                        row.lastError = error.localizedDescription
                    }
                    if let directory = try? QuestionBankImportJobStore.directory(for: job.jobID, create: false) {
                        try? FileManager.default.removeItem(at: directory)
                    }
                }
            case .interrupted:
                do {
                    try resumeInterruptedPreparation(jobID: job.jobID, in: container)
                } catch {
                    try? QuestionBankImportJobStore.update(job.jobID, in: container) { row in
                        row.phase = QuestionBankImportJobPhase.failed.rawValue
                        row.phaseLabel = "恢复准备失败"
                        row.preparedImportPayload = nil
                        row.stagedAssetHashes = nil
                        row.sourceRelativePath = ""
                        row.lastError = error.localizedDescription
                    }
                    if let directory = try? QuestionBankImportJobStore.directory(for: job.jobID, create: false) {
                        try? FileManager.default.removeItem(at: directory)
                    }
                }
            case .committing:
                guard removeUnreferencedStagedGenerations(for: job, in: container) else { continue }
                if job.preparedImportPayload != nil {
                    job.phase = QuestionBankImportJobPhase.awaitingConfirmation.rawValue
                    job.phaseLabel = "进程中断后等待重新确认"
                    job.stagedGenerationPaths = try JSONEncoder().encode([String]())
                } else {
                    job.phase = QuestionBankImportJobPhase.interrupted.rawValue
                    job.phaseLabel = "等待重新选择来源"
                }
            case .completed:
                cleanupAfterSuccessfulCommit(jobID: job.jobID, in: container)
            case .awaitingConfirmation, .cancelled, .failed:
                break
            }
        }
        try context.save()
        let refreshedContext = ModelContext(container)
        let awaiting = QuestionBankImportJobPhase.awaitingConfirmation.rawValue
        let readyPredicate = #Predicate<QuestionBankImportJobRecord> { $0.phase == awaiting }
        let readyJobs = try refreshedContext.fetch(FetchDescriptor<QuestionBankImportJobRecord>(predicate: readyPredicate))
        var recovered: [QuestionBankRecoveredImport] = []
        for job in readyJobs {
            guard let payload = job.preparedImportPayload,
                  let prepared = try? JSONDecoder().decode(QuestionBankPreparedImport.self, from: payload) else { continue }
            let preview: QuestionBankImportJobPreview
            switch prepared {
            case .single(let plan):
                preview = try makePreview(jobID: job.jobID, plan: plan, metadata: plan.batchMetadata, in: container)
            case .batch(let package):
                preview = try makePreview(jobID: job.jobID, package: package, in: container)
            }
            recovered.append(QuestionBankRecoveredImport(jobID: job.jobID, prepared: prepared, preview: preview))
        }
        return recovered.sorted { $0.jobID < $1.jobID }
    }

    private static func resumeInterruptedPreparation(jobID: String, in container: ModelContainer) throws {
        let context = ModelContext(container)
        guard let job = try QuestionBankImportJobStore.fetch(jobID, in: context),
              !job.sourceRelativePath.isEmpty else { throw QuestionBankImportJobFailure.missingJob }
        let sourceURL = try QuestionBankImportJobStore.child(job.sourceRelativePath, for: jobID)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw QuestionBankImportJobFailure.missingJob
        }
        let sourceHash = try QuestionBankImportJobStore.sha256(fileAt: sourceURL)
        guard job.sourceSHA256.isEmpty || job.sourceSHA256 == sourceHash else {
            throw QuestionBankImportJobFailure.changedPreparedImport
        }
        let directory = try QuestionBankImportJobStore.directory(for: jobID)
        let preparationStage = directory.appendingPathComponent("prepared", isDirectory: true)
        try? FileManager.default.removeItem(at: preparationStage)
        try QuestionBankImportJobStore.update(jobID, in: container) { row in
            row.phase = QuestionBankImportJobPhase.preparing.rawValue
            row.phaseLabel = "从持久化来源恢复"
            row.sourceSHA256 = sourceHash
            row.processedCount = 0
            row.totalCount = 1
        }
        let prepared = try QuestionBankPackageImporter.prepareSelection(
            from: sourceURL,
            source: .trustedLocalFile,
            stagingDirectory: preparationStage,
            onProgress: { _ in }
        )
        let encoded = try JSONEncoder().encode(prepared)
        let hashes = try stagedAssetHashes(for: prepared)
        try QuestionBankImportJobStore.update(jobID, in: container) { row in
            row.phase = QuestionBankImportJobPhase.awaitingConfirmation.rawValue
            row.phaseLabel = "恢复完成，等待用户确认"
            row.processedCount = 1
            row.totalCount = 1
            row.preparedImportPayload = encoded
            row.stagedAssetHashes = try JSONEncoder().encode(hashes)
            row.previewSnapshotToken = nil
            row.lastError = nil
        }
    }

    private static func removeUnreferencedStagedGenerations(
        for job: QuestionBankImportJobRecord,
        in container: ModelContainer
    ) -> Bool {
        guard let data = job.stagedGenerationPaths else { return true }
        guard let paths = try? JSONDecoder().decode([String].self, from: data) else { return false }
        guard !paths.isEmpty else { return true }
        do {
            let context = ModelContext(container)
            let assetKind = QuestionBankRepository.assetKind
            let predicate = #Predicate<QuestionBankRecord> { $0.kind == assetKind }
            let referenced = Set(try context.fetch(FetchDescriptor<QuestionBankRecord>(predicate: predicate))
                .compactMap { $0.assetRelativePath?.split(separator: "/").first.map(String.init) })
            let root = try QuestionBankAssetStore.root(create: false)
            for path in paths where !referenced.contains(path) {
                guard let url = QuestionBankAssetStore.url(for: path, under: root) else { return false }
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
            return true
        } catch {
            // Leave paths on the job so a later recovery can retry safely.
            return false
        }
    }

    private static func makePreview(
        jobID: String,
        plan: QuestionBankImportPlan,
        metadata: QuestionBankBatchMetadata?,
        in container: ModelContainer
    ) throws -> QuestionBankImportJobPreview {
        let context = ModelContext(container)
        let snapshot = try QuestionBankImportSnapshotBuilder.single(plan: plan, metadata: metadata, in: context)
        var batchPreparation: QuestionBankBatchPreview?
        var batchError: String?
        var replacingPaperID: String?
        if let metadata, let paper = plan.paper {
            let duplicate = QuestionBankRepository.duplicatePaper(for: paper, in: snapshot.records)
            do {
                let preparation = try QuestionBankBatchRepository.prepare(
                    metadata: metadata, plan: plan, records: snapshot.records,
                    sourceRecords: snapshot.sources, replacingPaperID: duplicate?.paperID
                )
                batchPreparation = preparation.currentSourcePreview
                replacingPaperID = preparation.replacingPaperID
            } catch {
                batchError = error.localizedDescription
            }
        }
        let result = QuestionBankImportJobPreview(
            records: snapshot.storedRows, batchSources: snapshot.sourceSnapshots,
            revisionToken: snapshot.revisionToken, batchPreparation: batchPreparation,
            batchPreparationError: batchError, batchReplacingPaperID: replacingPaperID,
            packageUpdatePreview: nil, globalQuestionOwners: snapshot.globalQuestionOwners
        )
        try QuestionBankImportJobStore.update(jobID, in: container) { $0.previewSnapshotToken = result.revisionToken }
        return result
    }

    private static func makePreview(
        jobID: String,
        package: QuestionBankBatchPackagePlan,
        in container: ModelContainer
    ) throws -> QuestionBankImportJobPreview {
        let context = ModelContext(container)
        let snapshot = try QuestionBankImportSnapshotBuilder.batch(package: package, in: context)
        let packagePreview = QuestionBankBatchPackageRepository.updatePreview(
            for: package, storedRows: snapshot.storedRows,
            globalQuestionOwners: snapshot.globalQuestionOwners
        )
        let result = QuestionBankImportJobPreview(
            records: snapshot.storedRows, batchSources: snapshot.sourceSnapshots,
            revisionToken: snapshot.revisionToken, batchPreparation: nil,
            batchPreparationError: nil, batchReplacingPaperID: nil,
            packageUpdatePreview: packagePreview, globalQuestionOwners: snapshot.globalQuestionOwners
        )
        try QuestionBankImportJobStore.update(jobID, in: container) { $0.previewSnapshotToken = result.revisionToken }
        return result
    }

    private static func stagedAssetHashes(for prepared: QuestionBankPreparedImport) throws -> [String: String] {
        var result: [String: String] = [:]
        func append(_ plan: QuestionBankImportPlan) throws {
            guard let stage = plan.stagingDirectory else { throw QuestionBankImportFailure.invalidPlan }
            for asset in plan.assets {
                try Task.checkCancellation()
                guard let file = QuestionBankAssetStore.url(for: asset.path, under: stage),
                      FileManager.default.fileExists(atPath: file.path) else {
                    throw QuestionBankImportFailure.missingStagingFile(asset.fileName)
                }
                let key = "\(plan.paper?.id ?? "")/\(asset.path)"
                result[key] = try QuestionBankImportJobStore.sha256(fileAt: file)
            }
        }
        switch prepared {
        case .single(let plan): try append(plan)
        case .batch(let package):
            for plan in package.paperPlans { try append(plan) }
        }
        return result
    }

    private static func verifyStagedAssetHashes(job: QuestionBankImportJobRecord, prepared: QuestionBankPreparedImport) throws {
        guard let data = job.stagedAssetHashes,
              let expected = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw QuestionBankImportJobFailure.missingPreparedImport
        }
        let actual = try stagedAssetHashes(for: prepared)
        guard actual == expected else {
            let changed = Set(actual.keys).symmetricDifference(expected.keys).sorted().first
                ?? actual.first(where: { expected[$0.key] != $0.value })?.key
                ?? "unknown"
            throw QuestionBankImportJobFailure.stagedAssetChanged(changed)
        }
    }

    private static func recordCommitFailure(
        jobID: String,
        error: Error,
        plan: QuestionBankPreparedImport,
        in container: ModelContainer
    ) {
        let preservePreview: Bool
        if let failure = error as? QuestionBankImportJobFailure {
            if case .stalePreview = failure { preservePreview = true }
            else { preservePreview = false }
        } else {
            preservePreview = error is QuestionBankImportFailure
                || error is QuestionBankWriteCoordinatorError
                || error is QuestionBankBatchFailure
                || error is QuestionBankBatchPackageFailure
        }
        try? QuestionBankImportJobStore.update(jobID, in: container) { job in
            job.phase = preservePreview
                ? QuestionBankImportJobPhase.awaitingConfirmation.rawValue
                : QuestionBankImportJobPhase.failed.rawValue
            job.phaseLabel = preservePreview ? "等待重新确认" : "写入失败"
            job.lastError = error.localizedDescription
            job.stagedGenerationPaths = try JSONEncoder().encode([String]())
            if !preservePreview {
                job.preparedImportPayload = nil
                job.stagedAssetHashes = nil
                job.previewSnapshotToken = nil
            }
        }
        guard !preservePreview else { return }
        plan.cleanup()
        try? QuestionBankImportJobStore.update(jobID, in: container) { $0.sourceRelativePath = "" }
        if let directory = try? QuestionBankImportJobStore.directory(for: jobID, create: false) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func generationPaths(in records: [QuestionBankRecord], paperIDs: Set<String>) -> [String] {
        Array(Set(records.compactMap { record -> String? in
            guard paperIDs.contains(record.paperID),
                  record.kind == QuestionBankRepository.assetKind,
                  let path = record.assetRelativePath else { return nil }
            return path.split(separator: "/").first.map(String.init)
        })).sorted()
    }

    private static func sourceHash(for job: QuestionBankImportJobRecord) throws -> String {
        guard !job.sourceRelativePath.isEmpty else { throw QuestionBankImportJobFailure.missingJob }
        let sourceURL = try QuestionBankImportJobStore.child(job.sourceRelativePath, for: job.jobID)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw QuestionBankImportJobFailure.missingJob
        }
        return try QuestionBankImportJobStore.sha256(fileAt: sourceURL)
    }

    private static func cleanupAfterSuccessfulCommit(jobID: String, in container: ModelContainer) {
        do {
            let context = ModelContext(container)
            guard let job = try QuestionBankImportJobStore.fetch(jobID, in: context),
                  QuestionBankImportJobPhase(rawValue: job.phase) == .completed else { return }
            let oldPaths = try JSONDecoder().decode([String].self, from: job.supersededGenerationPaths ?? Data("[]".utf8))
            let assetKind = QuestionBankRepository.assetKind
            let predicate = #Predicate<QuestionBankRecord> { $0.kind == assetKind }
            let referenced = Set(try context.fetch(FetchDescriptor<QuestionBankRecord>(predicate: predicate))
                .compactMap { $0.assetRelativePath?.split(separator: "/").first.map(String.init) })
            let root = try QuestionBankAssetStore.root(create: false)
            for path in oldPaths where !referenced.contains(path) {
                guard let directory = QuestionBankAssetStore.url(for: path, under: root) else { return }
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            }
            if let directory = try? QuestionBankImportJobStore.directory(for: jobID, create: false) {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            }
        } catch {
            // The completed job remains recoverable; a later reconciliation retries cleanup.
        }
    }
}
