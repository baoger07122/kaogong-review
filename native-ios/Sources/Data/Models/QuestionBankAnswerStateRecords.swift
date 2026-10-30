import Foundation
import SwiftData

@Model
final class QuestionBankAnswerStateRecord {
    @Attribute(.unique) var compoundID: String
    var paperID: String
    var questionID: String
    var selectedOptionID: String?
    var isRevealed: Bool
    /// A tombstone prevents an older migration snapshot from restoring a cleared answer.
    var isCleared: Bool
    var mutationRevision: Int
    var updatedAt: Date

    init(
        compoundID: String,
        paperID: String,
        questionID: String,
        selectedOptionID: String? = nil,
        isRevealed: Bool = false,
        isCleared: Bool = false,
        mutationRevision: Int = 1,
        updatedAt: Date = .now
    ) {
        self.compoundID = compoundID
        self.paperID = paperID
        self.questionID = questionID
        self.selectedOptionID = selectedOptionID
        self.isRevealed = isRevealed
        self.isCleared = isCleared
        self.mutationRevision = mutationRevision
        self.updatedAt = updatedAt
    }
}

@Model
final class QuestionBankAnswerStateMigrationRecord {
    @Attribute(.unique) var migrationID: String
    var sourceKind: String
    var formatVersion: Int
    var phaseRawValue: String
    /// Original legacy strings are retained after completion as a recoverable backup.
    var sourceBackupPayload: Data
    var sourceDigest: String
    var cursor: Int
    var sourceItemCount: Int
    var processedItemCount: Int
    var lastError: String?
    var updatedAt: Date

    init(
        migrationID: String,
        sourceKind: String,
        sourceBackupPayload: Data,
        sourceDigest: String,
        formatVersion: Int = 1,
        phaseRawValue: String = "backedUp",
        cursor: Int = 0,
        sourceItemCount: Int = 0,
        processedItemCount: Int = 0,
        lastError: String? = nil,
        updatedAt: Date = .now
    ) {
        self.migrationID = migrationID
        self.sourceKind = sourceKind
        self.formatVersion = formatVersion
        self.phaseRawValue = phaseRawValue
        self.sourceBackupPayload = sourceBackupPayload
        self.sourceDigest = sourceDigest
        self.cursor = cursor
        self.sourceItemCount = sourceItemCount
        self.processedItemCount = processedItemCount
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

@Model
final class QuestionBankAnswerStateScopeClearRecord {
    @Attribute(.unique) var scopeID: String
    var paperID: String?
    var updatedAt: Date

    init(scopeID: String, paperID: String? = nil, updatedAt: Date = .now) {
        self.scopeID = scopeID
        self.paperID = paperID
        self.updatedAt = updatedAt
    }
}

struct QuestionBankAnswerStateValue: Codable, Equatable, Sendable, Identifiable {
    let compoundID: String
    let paperID: String
    let questionID: String
    var selectedOptionID: String?
    var isRevealed: Bool
    var isCleared: Bool
    var mutationRevision: Int
    var updatedAt: Date

    var id: String { compoundID }

    var hasAnswer: Bool {
        !isCleared && (selectedOptionID != nil || isRevealed)
    }

    init(
        compoundID: String,
        paperID: String,
        questionID: String,
        selectedOptionID: String?,
        isRevealed: Bool,
        isCleared: Bool,
        mutationRevision: Int,
        updatedAt: Date
    ) {
        self.compoundID = compoundID
        self.paperID = paperID
        self.questionID = questionID
        self.selectedOptionID = selectedOptionID
        self.isRevealed = isRevealed
        self.isCleared = isCleared
        self.mutationRevision = mutationRevision
        self.updatedAt = updatedAt
    }

    init(record: QuestionBankAnswerStateRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        questionID = record.questionID
        selectedOptionID = record.selectedOptionID
        isRevealed = record.isRevealed
        isCleared = record.isCleared
        mutationRevision = record.mutationRevision
        updatedAt = record.updatedAt
    }

    static func empty(compoundID: String) -> Self? {
        guard let marker = compoundID.range(of: "::\(QuestionBankRepository.questionKind)::", options: .backwards) else {
            return nil
        }
        let paperID = String(compoundID[..<marker.lowerBound])
        let questionID = String(compoundID[marker.upperBound...])
        guard !paperID.isEmpty, !questionID.isEmpty else { return nil }
        return Self(
            compoundID: compoundID,
            paperID: paperID,
            questionID: questionID,
            selectedOptionID: nil,
            isRevealed: false,
            isCleared: false,
            mutationRevision: 0,
            updatedAt: .distantPast
        )
    }
}

struct QuestionBankAnswerStateBackup: Codable, Equatable, Sendable, Identifiable {
    let compoundID: String
    let paperID: String
    let questionID: String
    let selectedOptionID: String?
    let isRevealed: Bool
    let isCleared: Bool
    let mutationRevision: Int
    let updatedAt: Date

    var id: String { compoundID }

    init(
        compoundID: String,
        paperID: String,
        questionID: String,
        selectedOptionID: String?,
        isRevealed: Bool,
        isCleared: Bool,
        mutationRevision: Int,
        updatedAt: Date
    ) {
        self.compoundID = compoundID
        self.paperID = paperID
        self.questionID = questionID
        self.selectedOptionID = selectedOptionID
        self.isRevealed = isRevealed
        self.isCleared = isCleared
        self.mutationRevision = mutationRevision
        self.updatedAt = updatedAt
    }

    init(record: QuestionBankAnswerStateRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        questionID = record.questionID
        selectedOptionID = record.selectedOptionID
        isRevealed = record.isRevealed
        isCleared = record.isCleared
        mutationRevision = record.mutationRevision
        updatedAt = record.updatedAt
    }

    init(value: QuestionBankAnswerStateValue) {
        compoundID = value.compoundID
        paperID = value.paperID
        questionID = value.questionID
        selectedOptionID = value.selectedOptionID
        isRevealed = value.isRevealed
        isCleared = value.isCleared
        mutationRevision = value.mutationRevision
        updatedAt = value.updatedAt
    }
}
