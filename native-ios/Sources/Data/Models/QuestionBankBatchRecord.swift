import Foundation
import SwiftData

/// Batch rows are indexes only. Question/material payloads and asset bytes remain
/// owned by the original QuestionBankRecord rows and asset generations.
@Model
final class QuestionBankBatchRecord {
    @Attribute(.unique) var identityKey: String
    var family: String
    var year: Int
    var displayName: String
    var metadataPayload: Data
    var sourceCount: Int
    var uniqueMaterialCount: Int
    var uniqueQuestionCount: Int
    var pendingCount: Int

    init(identityKey: String, family: String, year: Int, displayName: String,
         metadataPayload: Data, sourceCount: Int = 0, uniqueMaterialCount: Int = 0,
         uniqueQuestionCount: Int = 0, pendingCount: Int = 0) {
        self.identityKey = identityKey
        self.family = family
        self.year = year
        self.displayName = displayName
        self.metadataPayload = metadataPayload
        self.sourceCount = sourceCount
        self.uniqueMaterialCount = uniqueMaterialCount
        self.uniqueQuestionCount = uniqueQuestionCount
        self.pendingCount = pendingCount
    }
}

@Model
final class QuestionBankBatchSourceRecord {
    @Attribute(.unique) var sourceID: String
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

    init(sourceID: String, batchID: String, revision: String, sourceSHA256: String,
         metadataPayload: Data = Data(),
         paperID: String, importedAt: Date, sourceQuestionCount: Int, sourceMaterialCount: Int,
         uniqueQuestionCount: Int, duplicateQuestionCount: Int, pendingQuestionCount: Int,
         uniqueMaterialCount: Int, duplicateMaterialCount: Int, pendingMaterialCount: Int) {
        self.sourceID = sourceID
        self.batchID = batchID
        self.revision = revision
        self.sourceSHA256 = sourceSHA256
        self.metadataPayload = metadataPayload
        self.paperID = paperID
        self.importedAt = importedAt
        self.sourceQuestionCount = sourceQuestionCount
        self.sourceMaterialCount = sourceMaterialCount
        self.uniqueQuestionCount = uniqueQuestionCount
        self.duplicateQuestionCount = duplicateQuestionCount
        self.pendingQuestionCount = pendingQuestionCount
        self.uniqueMaterialCount = uniqueMaterialCount
        self.duplicateMaterialCount = duplicateMaterialCount
        self.pendingMaterialCount = pendingMaterialCount
    }
}

@Model
final class QuestionBankBatchMaterialLinkRecord {
    @Attribute(.unique) var compoundID: String
    var batchID: String
    var sourcePaperID: String
    var sourceMaterialID: String
    var canonicalPaperID: String?
    var canonicalMaterialID: String?
    var fingerprint: String
    var status: String
    var pendingReason: String?

    init(compoundID: String, batchID: String, sourcePaperID: String, sourceMaterialID: String,
         canonicalPaperID: String?, canonicalMaterialID: String?, fingerprint: String,
         status: String, pendingReason: String? = nil) {
        self.compoundID = compoundID
        self.batchID = batchID
        self.sourcePaperID = sourcePaperID
        self.sourceMaterialID = sourceMaterialID
        self.canonicalPaperID = canonicalPaperID
        self.canonicalMaterialID = canonicalMaterialID
        self.fingerprint = fingerprint
        self.status = status
        self.pendingReason = pendingReason
    }
}

@Model
final class QuestionBankBatchQuestionLinkRecord {
    @Attribute(.unique) var compoundID: String
    var batchID: String
    var sourcePaperID: String
    var sourceQuestionID: String
    var canonicalPaperID: String?
    var canonicalQuestionID: String?
    var fingerprint: String
    var status: String
    var pendingReason: String?

    init(compoundID: String, batchID: String, sourcePaperID: String, sourceQuestionID: String,
         canonicalPaperID: String?, canonicalQuestionID: String?, fingerprint: String,
         status: String, pendingReason: String? = nil) {
        self.compoundID = compoundID
        self.batchID = batchID
        self.sourcePaperID = sourcePaperID
        self.sourceQuestionID = sourceQuestionID
        self.canonicalPaperID = canonicalPaperID
        self.canonicalQuestionID = canonicalQuestionID
        self.fingerprint = fingerprint
        self.status = status
        self.pendingReason = pendingReason
    }
}
