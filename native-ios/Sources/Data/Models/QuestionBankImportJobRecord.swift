import Foundation
import SwiftData

@Model
final class QuestionBankImportJobRecord {
    @Attribute(.unique) var jobID: String
    var phase: String
    var phaseLabel: String
    var processedCount: Int
    var totalCount: Int
    var sourceFileName: String
    var sourceRelativePath: String
    var sourceSHA256: String
    var preparedImportPayload: Data?
    var stagedAssetHashes: Data?
    var previewSnapshotToken: String?
    var stagedGenerationPaths: Data?
    var supersededGenerationPaths: Data?
    var payloadBackupID: String?
    var payloadBackupRelativePath: String?
    var payloadBackupManifestSHA256: String?
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        jobID: String,
        phase: String,
        phaseLabel: String,
        processedCount: Int = 0,
        totalCount: Int = 0,
        sourceFileName: String,
        sourceRelativePath: String,
        sourceSHA256: String = "",
        preparedImportPayload: Data? = nil,
        stagedAssetHashes: Data? = nil,
        previewSnapshotToken: String? = nil,
        stagedGenerationPaths: Data? = nil,
        supersededGenerationPaths: Data? = nil,
        payloadBackupID: String? = nil,
        payloadBackupRelativePath: String? = nil,
        payloadBackupManifestSHA256: String? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.jobID = jobID
        self.phase = phase
        self.phaseLabel = phaseLabel
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.sourceFileName = sourceFileName
        self.sourceRelativePath = sourceRelativePath
        self.sourceSHA256 = sourceSHA256
        self.preparedImportPayload = preparedImportPayload
        self.stagedAssetHashes = stagedAssetHashes
        self.previewSnapshotToken = previewSnapshotToken
        self.stagedGenerationPaths = stagedGenerationPaths
        self.supersededGenerationPaths = supersededGenerationPaths
        self.payloadBackupID = payloadBackupID
        self.payloadBackupRelativePath = payloadBackupRelativePath
        self.payloadBackupManifestSHA256 = payloadBackupManifestSHA256
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
