import CryptoKit
import Foundation
import SwiftData

enum QuestionBankBatchLinkStatus: String, Equatable, Sendable {
    case unique
    case duplicate
    case suspected
    case conflict

    var isPending: Bool { self == .suspected || self == .conflict }
}

struct QuestionBankBatchPreview: Equatable, Sendable {
    var uniqueQuestions: Int
    var duplicateQuestions: Int
    var suspectedQuestions: Int
    var conflictingQuestions: Int
    var uniqueMaterials: Int
    var duplicateMaterials: Int
    var pendingMaterials: Int
}

struct QuestionBankBatchPreparedMaterialLink: Sendable {
    var compoundID: String
    var batchID: String
    var sourcePaperID: String
    var sourceMaterialID: String
    var canonicalPaperID: String?
    var canonicalMaterialID: String?
    var fingerprint: String
    var status: QuestionBankBatchLinkStatus
    var pendingReason: String?
}

struct QuestionBankBatchPreparedQuestionLink: Sendable {
    var compoundID: String
    var batchID: String
    var sourcePaperID: String
    var sourceQuestionID: String
    var canonicalPaperID: String?
    var canonicalQuestionID: String?
    var fingerprint: String
    var status: QuestionBankBatchLinkStatus
    var pendingReason: String?
}

struct QuestionBankBatchSourceSummary: Sendable {
    var sourceID: String
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
}

struct QuestionBankBatchPreparation: Sendable {
    var metadata: QuestionBankBatchMetadata
    var batchID: String
    var replacingPaperID: String?
    var metadataPayload: Data
    var sourceSummaries: [QuestionBankBatchSourceSummary]
    var materialLinks: [QuestionBankBatchPreparedMaterialLink]
    var questionLinks: [QuestionBankBatchPreparedQuestionLink]
    var currentSourcePreview: QuestionBankBatchPreview
}

enum QuestionBankBatchFailure: LocalizedError {
    case invalidMetadata(String)
    case invalidSource(String)
    case sourceIdentityUsedElsewhere(String)
    case conflictingReplacementTargets(String)
    case missingIncomingAsset(String)

    var errorDescription: String? {
        switch self {
        case .invalidMetadata(let reason): reason
        case .invalidSource(let reason): "批次来源无法建立安全索引：\(reason)"
        case .sourceIdentityUsedElsewhere(let sourceID):
            "来源标识“\(sourceID)”已属于另一批次。若这是不同来源，请使用新的 sourceID；旧批次数据未更改。"
        case .conflictingReplacementTargets(let sourceID):
            "来源标识“\(sourceID)”对应的原试卷与本次匹配到的另一套试卷不同。为避免替错数据，请更换来源标识或先处理重复试卷。"
        case .missingIncomingAsset(let name): "批次比对时找不到待导入图片“\(name)”，没有写入索引。"
        }
    }
}

@MainActor
enum QuestionBankBatchRepository {
    private struct SourceInput {
        var sourceID: String
        var revision: String
        var sha256: String
        var metadataPayload: Data
        var paperID: String
        var importedAt: Date
        var materials: [QuestionBankMaterial]
        var questions: [QuestionBankQuestion]
        var assets: [String: AssetValue]
    }

    private struct AssetValue {
        var stagedURL: URL?
        var storedRelativePath: String?
    }

    private struct MaterialProfile {
        var paperID: String
        var materialID: String
        var fingerprint: String
        var textKey: String
        var imageDigest: String?
        var missingImage: Bool
    }

    private struct QuestionProfile {
        var paperID: String
        var questionID: String
        var fingerprint: String
        var structureKey: String
        var imageDigests: Set<String>
        var missingImage: Bool
    }

    private struct LinkCounts {
        var unique = 0
        var duplicate = 0
        var suspected = 0
        var conflict = 0

        var pending: Int { suspected + conflict }
    }

    static func prepare(
        metadata: QuestionBankBatchMetadata,
        plan: QuestionBankImportPlan,
        records: [QuestionBankRecord],
        sourceRecords: [QuestionBankBatchSourceRecord],
        replacingPaperID: String? = nil,
        now: Date = Date()
    ) throws -> QuestionBankBatchPreparation {
        if let reason = metadata.validationError { throw QuestionBankBatchFailure.invalidMetadata(reason) }
        guard let paper = plan.paper else { throw QuestionBankBatchFailure.invalidSource("缺少试卷元数据。") }
        guard !plan.sourceFileSHA256.isEmpty else { throw QuestionBankBatchFailure.invalidSource("缺少原始文件摘要。") }
        let stableSourceID = metadata.sourceID.trimmedNonempty
        let metadataEncoder = JSONEncoder()
        metadataEncoder.outputFormatting = [.sortedKeys]
        let incomingMetadataPayload = try metadataEncoder.encode(metadata)

        if sourceRecords.contains(where: { $0.sourceID == stableSourceID && $0.batchID != metadata.identityKey }) {
            throw QuestionBankBatchFailure.sourceIdentityUsedElsewhere(stableSourceID)
        }
        let previousSource = sourceRecords.first { $0.sourceID == stableSourceID }
        let detectedDuplicate = QuestionBankRepository.duplicatePaper(for: paper, in: records)
        if let previousSource,
           !records.contains(where: {
               $0.paperID == previousSource.paperID && $0.kind == QuestionBankRepository.paperKind
           }) {
            throw QuestionBankBatchFailure.invalidSource("来源 \(stableSourceID) 的原试卷记录已不存在。")
        }
        if let previousSource, let detectedDuplicate, previousSource.paperID != detectedDuplicate.paperID {
            throw QuestionBankBatchFailure.conflictingReplacementTargets(stableSourceID)
        }
        if let replacingPaperID, let detectedDuplicate,
           replacingPaperID != detectedDuplicate.paperID,
           previousSource?.paperID != detectedDuplicate.paperID {
            throw QuestionBankBatchFailure.conflictingReplacementTargets(stableSourceID)
        }
        let resolvedReplacingPaperID = previousSource?.paperID
            ?? detectedDuplicate?.paperID
            ?? replacingPaperID
        let incomingDate = previousSource.map {
            $0.sourceSHA256 == plan.sourceFileSHA256 && $0.revision == metadata.revision.trimmedNonempty
                && $0.metadataPayload == incomingMetadataPayload ? $0.importedAt : now
        } ?? now

        let omittedPaperIDs = Set([resolvedReplacingPaperID, paper.id].compactMap { $0 })
        let existingInputs = try sourceRecords
            .filter { $0.batchID == metadata.identityKey && $0.sourceID != stableSourceID && !omittedPaperIDs.contains($0.paperID) }
            .sorted { left, right in
                if left.importedAt != right.importedAt { return left.importedAt < right.importedAt }
                return left.sourceID < right.sourceID
            }
            .map { try storedInput(from: $0, records: records) }

        let incoming = try incomingInput(metadata: metadata, metadataPayload: incomingMetadataPayload,
            plan: plan, paper: paper, now: incomingDate)
        let inputs = existingInputs + [incoming]
        var plannedMaterials: [QuestionBankBatchPreparedMaterialLink] = []
        var plannedQuestions: [QuestionBankBatchPreparedQuestionLink] = []
        var materialCanonicals: [String: (paperID: String, materialID: String)] = [:]
        var canonicalMaterials: [MaterialProfile] = []
        var canonicalQuestions: [QuestionProfile] = []
        var materialCounts: [String: LinkCounts] = [:]
        var questionCounts: [String: LinkCounts] = [:]

        for input in inputs {
            for material in input.materials {
                let profile = try materialProfile(material, input: input)
                let sourceKey = recordKey(input.paperID, material.id)
                let decision = materialDecision(profile, canonicals: canonicalMaterials)
                let canonical: (paperID: String, materialID: String)?
                switch decision.status {
                case .unique:
                    canonical = (input.paperID, material.id)
                    canonicalMaterials.append(profile)
                case .duplicate:
                    canonical = decision.canonical.map { ($0.paperID, $0.materialID) }
                case .suspected, .conflict:
                    canonical = nil
                }
                if let canonical { materialCanonicals[sourceKey] = canonical }
                else { materialCanonicals.removeValue(forKey: sourceKey) }
                plannedMaterials.append(QuestionBankBatchPreparedMaterialLink(
                    compoundID: linkID(metadata.identityKey, input.paperID, material.id),
                    batchID: metadata.identityKey, sourcePaperID: input.paperID,
                    sourceMaterialID: material.id, canonicalPaperID: canonical?.paperID,
                    canonicalMaterialID: canonical?.materialID, fingerprint: profile.fingerprint,
                    status: decision.status, pendingReason: decision.reason
                ))
                var counts = materialCounts[input.sourceID, default: LinkCounts()]
                add(decision.status, to: &counts)
                materialCounts[input.sourceID] = counts
                _ = sourceKey
            }

            for question in input.questions {
                let materialCanonical: (paperID: String, materialID: String)?
                if question.materialID.trimmedNonempty.isEmpty {
                    materialCanonical = nil
                } else {
                    materialCanonical = materialCanonicals[recordKey(input.paperID, question.materialID)]
                }
                let profile = try questionProfile(question, input: input, materialCanonical: materialCanonical)
                let dependencyMissing = !question.materialID.trimmedNonempty.isEmpty && materialCanonical == nil
                let decision: (status: QuestionBankBatchLinkStatus, canonical: QuestionProfile?, reason: String?)
                if dependencyMissing {
                    decision = (.conflict, nil, "依赖材料尚未精确归并；材料与题目均保留待处理。")
                } else {
                    decision = questionDecision(profile, canonicals: canonicalQuestions)
                }
                let canonical: QuestionProfile?
                switch decision.status {
                case .unique:
                    canonical = profile
                    canonicalQuestions.append(profile)
                case .duplicate:
                    canonical = decision.canonical
                case .suspected, .conflict:
                    canonical = nil
                }
                plannedQuestions.append(QuestionBankBatchPreparedQuestionLink(
                    compoundID: linkID(metadata.identityKey, input.paperID, question.id),
                    batchID: metadata.identityKey, sourcePaperID: input.paperID,
                    sourceQuestionID: question.id, canonicalPaperID: canonical?.paperID,
                    canonicalQuestionID: canonical?.questionID, fingerprint: profile.fingerprint,
                    status: decision.status, pendingReason: decision.reason
                ))
                var counts = questionCounts[input.sourceID, default: LinkCounts()]
                add(decision.status, to: &counts)
                questionCounts[input.sourceID] = counts
            }
        }

        let summaries = inputs.map { input in
            let m = materialCounts[input.sourceID, default: LinkCounts()]
            let q = questionCounts[input.sourceID, default: LinkCounts()]
            return QuestionBankBatchSourceSummary(
                sourceID: input.sourceID, revision: input.revision, sourceSHA256: input.sha256,
                metadataPayload: input.metadataPayload,
                paperID: input.paperID, importedAt: input.importedAt,
                sourceQuestionCount: input.questions.count, sourceMaterialCount: input.materials.count,
                uniqueQuestionCount: q.unique, duplicateQuestionCount: q.duplicate,
                pendingQuestionCount: q.pending, uniqueMaterialCount: m.unique,
                duplicateMaterialCount: m.duplicate, pendingMaterialCount: m.pending
            )
        }
        let currentM = materialCounts[stableSourceID, default: LinkCounts()]
        let currentQ = questionCounts[stableSourceID, default: LinkCounts()]
        return QuestionBankBatchPreparation(
            metadata: metadata, batchID: metadata.identityKey,
            replacingPaperID: resolvedReplacingPaperID,
            metadataPayload: incomingMetadataPayload, sourceSummaries: summaries,
            materialLinks: plannedMaterials, questionLinks: plannedQuestions,
            currentSourcePreview: QuestionBankBatchPreview(
                uniqueQuestions: currentQ.unique, duplicateQuestions: currentQ.duplicate,
                suspectedQuestions: currentQ.suspected, conflictingQuestions: currentQ.conflict,
                uniqueMaterials: currentM.unique, duplicateMaterials: currentM.duplicate,
                pendingMaterials: currentM.pending
            )
        )
    }

    /// Called from inside the same ModelContext.transaction as the source paper rows.
    static func apply(_ prepared: QuestionBankBatchPreparation,
                      batches: [QuestionBankBatchRecord],
                      sources: [QuestionBankBatchSourceRecord],
                      materialLinks: [QuestionBankBatchMaterialLinkRecord],
                      questionLinks: [QuestionBankBatchQuestionLinkRecord],
                      replacingPaperID: String?,
                      context: ModelContext) {
        let existingMaterials = Dictionary(materialLinks.filter { $0.batchID == prepared.batchID }
            .map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
        let existingQuestions = Dictionary(questionLinks.filter { $0.batchID == prepared.batchID }
            .map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
        let desiredMaterialIDs = Set(prepared.materialLinks.map(\.compoundID))
        let desiredQuestionIDs = Set(prepared.questionLinks.map(\.compoundID))
        for row in materialLinks where row.batchID == prepared.batchID && !desiredMaterialIDs.contains(row.compoundID) {
            context.delete(row)
        }
        for row in questionLinks where row.batchID == prepared.batchID && !desiredQuestionIDs.contains(row.compoundID) {
            context.delete(row)
        }

        let incomingSourceIDs = Set(prepared.sourceSummaries.map(\.sourceID))
        for row in sources where row.batchID == prepared.batchID && !incomingSourceIDs.contains(row.sourceID) {
            context.delete(row)
        }
        for summary in prepared.sourceSummaries {
            if let row = sources.first(where: { $0.sourceID == summary.sourceID }) {
                row.batchID = prepared.batchID
                row.revision = summary.revision
                row.sourceSHA256 = summary.sourceSHA256
                row.metadataPayload = summary.metadataPayload
                row.paperID = summary.paperID
                row.importedAt = summary.importedAt
                row.sourceQuestionCount = summary.sourceQuestionCount
                row.sourceMaterialCount = summary.sourceMaterialCount
                row.uniqueQuestionCount = summary.uniqueQuestionCount
                row.duplicateQuestionCount = summary.duplicateQuestionCount
                row.pendingQuestionCount = summary.pendingQuestionCount
                row.uniqueMaterialCount = summary.uniqueMaterialCount
                row.duplicateMaterialCount = summary.duplicateMaterialCount
                row.pendingMaterialCount = summary.pendingMaterialCount
            } else {
                context.insert(QuestionBankBatchSourceRecord(
                    sourceID: summary.sourceID, batchID: prepared.batchID,
                    revision: summary.revision, sourceSHA256: summary.sourceSHA256,
                    metadataPayload: summary.metadataPayload,
                    paperID: summary.paperID, importedAt: summary.importedAt,
                    sourceQuestionCount: summary.sourceQuestionCount,
                    sourceMaterialCount: summary.sourceMaterialCount,
                    uniqueQuestionCount: summary.uniqueQuestionCount,
                    duplicateQuestionCount: summary.duplicateQuestionCount,
                    pendingQuestionCount: summary.pendingQuestionCount,
                    uniqueMaterialCount: summary.uniqueMaterialCount,
                    duplicateMaterialCount: summary.duplicateMaterialCount,
                    pendingMaterialCount: summary.pendingMaterialCount
                ))
            }
        }

        for link in prepared.materialLinks {
            if let existing = existingMaterials[link.compoundID] {
                existing.canonicalPaperID = link.canonicalPaperID
                existing.canonicalMaterialID = link.canonicalMaterialID
                existing.fingerprint = link.fingerprint
                existing.status = link.status.rawValue
                existing.pendingReason = link.pendingReason
            } else {
                context.insert(QuestionBankBatchMaterialLinkRecord(
                    compoundID: link.compoundID, batchID: link.batchID,
                    sourcePaperID: link.sourcePaperID, sourceMaterialID: link.sourceMaterialID,
                    canonicalPaperID: link.canonicalPaperID, canonicalMaterialID: link.canonicalMaterialID,
                    fingerprint: link.fingerprint, status: link.status.rawValue,
                    pendingReason: link.pendingReason
                ))
            }
        }
        for link in prepared.questionLinks {
            if let existing = existingQuestions[link.compoundID] {
                existing.canonicalPaperID = link.canonicalPaperID
                existing.canonicalQuestionID = link.canonicalQuestionID
                existing.fingerprint = link.fingerprint
                existing.status = link.status.rawValue
                existing.pendingReason = link.pendingReason
            } else {
                context.insert(QuestionBankBatchQuestionLinkRecord(
                    compoundID: link.compoundID, batchID: link.batchID,
                    sourcePaperID: link.sourcePaperID, sourceQuestionID: link.sourceQuestionID,
                    canonicalPaperID: link.canonicalPaperID, canonicalQuestionID: link.canonicalQuestionID,
                    fingerprint: link.fingerprint, status: link.status.rawValue,
                    pendingReason: link.pendingReason
                ))
            }
        }

        let uniqueMaterialCount = prepared.materialLinks.filter { $0.status == .unique }.count
        let uniqueQuestionCount = prepared.questionLinks.filter { $0.status == .unique }.count
        let pendingCount = prepared.materialLinks.filter { $0.status.isPending }.count
            + prepared.questionLinks.filter { $0.status.isPending }.count
        if let batch = batches.first(where: { $0.identityKey == prepared.batchID }) {
            batch.family = prepared.metadata.family.rawValue
            batch.year = prepared.metadata.year
            batch.displayName = prepared.metadata.displayName
            batch.metadataPayload = prepared.metadataPayload
            batch.sourceCount = prepared.sourceSummaries.count
            batch.uniqueMaterialCount = uniqueMaterialCount
            batch.uniqueQuestionCount = uniqueQuestionCount
            batch.pendingCount = pendingCount
        } else {
            context.insert(QuestionBankBatchRecord(
                identityKey: prepared.batchID, family: prepared.metadata.family.rawValue,
                year: prepared.metadata.year, displayName: prepared.metadata.displayName,
                metadataPayload: prepared.metadataPayload, sourceCount: prepared.sourceSummaries.count,
                uniqueMaterialCount: uniqueMaterialCount, uniqueQuestionCount: uniqueQuestionCount,
                pendingCount: pendingCount
            ))
        }

        if let replacingPaperID {
            detachPaperFromBatches(replacingPaperID, targetBatchID: prepared.batchID,
                batches: batches, sources: sources, materialLinks: materialLinks,
                questionLinks: questionLinks, context: context)
        }
    }

    static func detachPaperFromBatches(_ paperID: String, targetBatchID: String? = nil,
        batches: [QuestionBankBatchRecord], sources: [QuestionBankBatchSourceRecord],
        materialLinks: [QuestionBankBatchMaterialLinkRecord],
        questionLinks: [QuestionBankBatchQuestionLinkRecord], context: ModelContext) {
        let oldBatchIDs = Set(sources.filter { row in
            row.paperID == paperID && (targetBatchID.map { $0 != row.batchID } ?? true)
        }.map(\.batchID))
        for oldBatchID in oldBatchIDs {
            let removedSources = sources.filter { $0.paperID == paperID && $0.batchID == oldBatchID }
            let remainingSources = sources.filter { $0.batchID == oldBatchID && $0.paperID != paperID }
            let batchMaterials = materialLinks.filter { $0.batchID == oldBatchID }
            let batchQuestions = questionLinks.filter { $0.batchID == oldBatchID }
            let removedCanonicalMaterial = batchMaterials.contains {
                $0.sourcePaperID == paperID && $0.status == QuestionBankBatchLinkStatus.unique.rawValue
            }
            for source in removedSources { context.delete(source) }
            for link in batchMaterials {
                if link.sourcePaperID == paperID {
                    context.delete(link)
                } else if link.canonicalPaperID == paperID {
                    link.canonicalPaperID = nil
                    link.canonicalMaterialID = nil
                    link.status = QuestionBankBatchLinkStatus.conflict.rawValue
                    link.pendingReason = "原规范材料所在试卷已整卷替换；来源保留并待重新核对。"
                }
            }
            for link in batchQuestions {
                if link.sourcePaperID == paperID {
                    context.delete(link)
                } else if link.canonicalPaperID == paperID
                    || (removedCanonicalMaterial && link.status == QuestionBankBatchLinkStatus.duplicate.rawValue) {
                    link.canonicalPaperID = nil
                    link.canonicalQuestionID = nil
                    link.status = QuestionBankBatchLinkStatus.conflict.rawValue
                    link.pendingReason = "规范来源或材料所在试卷已整卷替换；来源保留并待重新核对。"
                }
            }

            if remainingSources.isEmpty {
                for link in batchMaterials where link.sourcePaperID != paperID { context.delete(link) }
                for link in batchQuestions where link.sourcePaperID != paperID { context.delete(link) }
                if let batch = batches.first(where: { $0.identityKey == oldBatchID }) { context.delete(batch) }
                continue
            }

            for source in remainingSources {
                let sourceMaterials = batchMaterials.filter { $0.sourcePaperID == source.paperID }
                let sourceQuestions = batchQuestions.filter { $0.sourcePaperID == source.paperID }
                source.uniqueMaterialCount = sourceMaterials.filter { $0.status == QuestionBankBatchLinkStatus.unique.rawValue }.count
                source.duplicateMaterialCount = sourceMaterials.filter { $0.status == QuestionBankBatchLinkStatus.duplicate.rawValue }.count
                source.pendingMaterialCount = sourceMaterials.filter {
                    QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending == true
                }.count
                source.uniqueQuestionCount = sourceQuestions.filter { $0.status == QuestionBankBatchLinkStatus.unique.rawValue }.count
                source.duplicateQuestionCount = sourceQuestions.filter { $0.status == QuestionBankBatchLinkStatus.duplicate.rawValue }.count
                source.pendingQuestionCount = sourceQuestions.filter {
                    QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending == true
                }.count
            }
            if let batch = batches.first(where: { $0.identityKey == oldBatchID }) {
                batch.sourceCount = remainingSources.count
                batch.uniqueMaterialCount = batchMaterials.filter {
                    $0.sourcePaperID != paperID && $0.status == QuestionBankBatchLinkStatus.unique.rawValue
                }.count
                batch.uniqueQuestionCount = batchQuestions.filter {
                    $0.sourcePaperID != paperID && $0.status == QuestionBankBatchLinkStatus.unique.rawValue
                }.count
                batch.pendingCount = batchMaterials.filter {
                    $0.sourcePaperID != paperID && QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending == true
                }.count + batchQuestions.filter {
                    $0.sourcePaperID != paperID && QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending == true
                }.count
            }
        }
    }

    private static func storedInput(from source: QuestionBankBatchSourceRecord,
                                    records: [QuestionBankRecord]) throws -> SourceInput {
        let rows = records.filter { $0.paperID == source.paperID }
        guard rows.contains(where: { $0.kind == QuestionBankRepository.paperKind }) else {
            throw QuestionBankBatchFailure.invalidSource("来源 \(source.sourceID) 的原始试卷记录已不存在。")
        }
        let assetValues = Dictionary(rows.filter { $0.kind == QuestionBankRepository.assetKind }.compactMap { row -> (String, AssetValue)? in
            guard let asset = row.decoded(QuestionBankAsset.self) else { return nil }
            return (asset.id, AssetValue(stagedURL: nil, storedRelativePath: row.assetRelativePath))
        }, uniquingKeysWith: { first, _ in first })
        let materialRows = rows.filter { $0.kind == QuestionBankRepository.materialKind }
        let questionRows = rows.filter { $0.kind == QuestionBankRepository.questionKind }
        let materials = materialRows.compactMap { $0.decoded(QuestionBankMaterial.self) }
        let questions = questionRows.compactMap { $0.decoded(QuestionBankQuestion.self) }
        guard materials.count == materialRows.count, questions.count == questionRows.count else {
            throw QuestionBankBatchFailure.invalidSource("来源 \(source.sourceID) 存在损坏的材料或题目记录。")
        }
        guard materials.count == source.sourceMaterialCount, questions.count == source.sourceQuestionCount else {
            throw QuestionBankBatchFailure.invalidSource("来源 \(source.sourceID) 的台账计数与原始试卷记录不一致。")
        }
        return SourceInput(sourceID: source.sourceID, revision: source.revision,
            sha256: source.sourceSHA256, metadataPayload: source.metadataPayload,
            paperID: source.paperID, importedAt: source.importedAt,
            materials: materials, questions: questions, assets: assetValues)
    }

    private static func incomingInput(metadata: QuestionBankBatchMetadata, metadataPayload: Data,
                                      plan: QuestionBankImportPlan,
                                      paper: QuestionBankPaper, now: Date) throws -> SourceInput {
        guard let staging = plan.stagingDirectory else {
            throw QuestionBankBatchFailure.invalidSource("缺少图片暂存目录。")
        }
        var assets: [String: AssetValue] = [:]
        for asset in plan.assets {
            guard let url = QuestionBankAssetStore.url(for: asset.path, under: staging),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw QuestionBankBatchFailure.missingIncomingAsset(asset.fileName)
            }
            assets[asset.id] = AssetValue(stagedURL: url, storedRelativePath: nil)
        }
        return SourceInput(sourceID: metadata.sourceID.trimmedNonempty, revision: metadata.revision.trimmedNonempty,
            sha256: plan.sourceFileSHA256, metadataPayload: metadataPayload,
            paperID: paper.id, importedAt: now,
            materials: plan.materials, questions: plan.questions, assets: assets)
    }

    private static func materialProfile(_ material: QuestionBankMaterial, input: SourceInput) throws -> MaterialProfile {
        let image = try imageDigest(material.imageAssetID, input: input)
        let text = normalize(material.text)
        let missing = image == "<missing>"
        let fingerprint = hash([text, image ?? "no-image"])
        return MaterialProfile(paperID: input.paperID, materialID: material.id,
            fingerprint: fingerprint, textKey: text, imageDigest: image, missingImage: missing)
    }

    private static func materialDecision(_ profile: MaterialProfile, canonicals: [MaterialProfile])
        -> (status: QuestionBankBatchLinkStatus, canonical: MaterialProfile?, reason: String?) {
        if profile.missingImage {
            return (.conflict, nil, "材料图片缺失，无法进行精确比较。")
        }
        if profile.textKey.isEmpty && profile.imageDigest == nil {
            return (.unique, nil, nil)
        }
        if let exact = canonicals.first(where: { $0.fingerprint == profile.fingerprint }) {
            return (.duplicate, exact, nil)
        }
        if let sameText = canonicals.first(where: { !profile.textKey.isEmpty && $0.textKey == profile.textKey }) {
            return (.conflict, sameText, "材料文字相同但图片字节不同；请人工核对。")
        }
        if let image = profile.imageDigest,
           let sameImage = canonicals.first(where: { $0.imageDigest == image }) {
            return (.suspected, sameImage, "存在相同图片但材料文字不同；保留来源并待人工核对。")
        }
        return (.unique, nil, nil)
    }

    private static func questionProfile(_ question: QuestionBankQuestion, input: SourceInput,
                                        materialCanonical: (paperID: String, materialID: String)?) throws -> QuestionProfile {
        let stemImage = try imageDigest(question.stemImageAssetID, input: input)
        var optionParts: [(text: String, image: String?)] = []
        for option in question.options {
            optionParts.append((normalize(option.text), try imageDigest(option.imageAssetID, input: input)))
        }
        let optionTextKeys = optionParts.map(\.text).sorted()
        let optionContentKeys = optionParts.map { hash([$0.text, $0.image ?? "no-image"]) }.sorted()
        let answerMatches = zip(question.options, optionParts).filter { $0.0.id == question.answer }
        let answerContent: String
        if answerMatches.count == 1, let selected = answerMatches.first {
            answerContent = hash([selected.1.text, selected.1.image ?? "no-image"])
        } else {
            answerContent = "<invalid-answer>"
        }
        let answerContentCount = optionParts.filter {
            hash([$0.text, $0.image ?? "no-image"]) == answerContent
        }.count
        let answerIsAmbiguous = answerContent == "<invalid-answer>" || answerContentCount != 1
        let normalizedStem = normalize(question.stem)
        let dependency = materialCanonical.map { recordKey($0.paperID, $0.materialID) } ?? "no-material"
        let answerText = answerMatches.first?.1.text ?? "<invalid-answer>"
        let structure = [normalize(question.subject), normalize(question.type), normalizedStem,
                         String(optionTextKeys.count)] + optionTextKeys
        let common = structure + [answerText, dependency]
        let full = common + [answerContent, stemImage ?? "no-image", String(optionContentKeys.count)] + optionContentKeys
        let imageDigests = Set(([stemImage] + optionParts.map { $0.image }).compactMap { value -> String? in
            guard let value, value != "<missing>" else { return nil }
            return value
        })
        let missingImage = stemImage == "<missing>" || optionParts.contains { $0.image == "<missing>" }
        return QuestionProfile(paperID: input.paperID, questionID: question.id,
            fingerprint: hash(full), structureKey: hash(structure), imageDigests: imageDigests,
            missingImage: missingImage || answerIsAmbiguous)
    }

    private static func questionDecision(_ profile: QuestionProfile, canonicals: [QuestionProfile])
        -> (status: QuestionBankBatchLinkStatus, canonical: QuestionProfile?, reason: String?) {
        if profile.missingImage {
            return (.conflict, nil, "题目图片缺失，或正确选项内容重复而无法唯一对应；请人工核对。")
        }
        if let exact = canonicals.first(where: { $0.fingerprint == profile.fingerprint }) {
            return (.duplicate, exact, nil)
        }
        if let sameStructure = canonicals.first(where: { $0.structureKey == profile.structureKey }) {
            return (.conflict, sameStructure, "题干和选项结构相同，但答案、材料依赖或图片不一致；请人工核对。")
        }
        if !profile.imageDigests.isEmpty,
           let sameImage = canonicals.first(where: { !profile.imageDigests.isDisjoint(with: $0.imageDigests) }) {
            return (.suspected, sameImage, "题目含有与批次现有题目相同的图片；保留来源并待人工核对。")
        }
        return (.unique, nil, nil)
    }

    private static func imageDigest(_ assetID: String, input: SourceInput) throws -> String? {
        guard !assetID.trimmedNonempty.isEmpty else { return nil }
        guard let asset = input.assets[assetID] else { return "<missing>" }
        let url: URL?
        if let staged = asset.stagedURL { url = staged }
        else { url = QuestionBankAssetStore.url(for: asset.storedRelativePath) }
        guard let url, let bytes = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return "<missing>" }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ value: String) -> String {
        let compatibility = value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let collapsed = compatibility.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func hash(_ parts: [String]) -> String {
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func recordKey(_ paperID: String, _ recordID: String) -> String {
        "\(component(paperID))::\(component(recordID))"
    }

    private static func linkID(_ batchID: String, _ paperID: String, _ recordID: String) -> String {
        "\(batchID)::\(recordKey(paperID, recordID))"
    }

    private static func component(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func add(_ status: QuestionBankBatchLinkStatus, to counts: inout LinkCounts) {
        switch status {
        case .unique: counts.unique += 1
        case .duplicate: counts.duplicate += 1
        case .suspected: counts.suspected += 1
        case .conflict: counts.conflict += 1
        }
    }
}
