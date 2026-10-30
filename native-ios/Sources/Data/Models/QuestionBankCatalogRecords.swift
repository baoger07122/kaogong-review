import Foundation
import SwiftData

/// Rebuildable directory metadata. QuestionBankRecord remains the authority for
/// the full imported question and its user-authored analysis fields.
@Model
final class QuestionBankCatalogPaperRecord {
    @Attribute(.unique) var sourceCompoundID: String
    var paperID: String
    var title: String
    var year: Int
    var examType: String
    var volume: String = ""
    var searchText: String = ""
    var provinceCode: String?
    var provinceName: String?
    var provinceLabelsData: Data = Data("[]".utf8)
    var questionCount: Int
    var sourceRevision: Int
    var metadataReadyVersion: Int
    var generationID: String

    init(
        sourceCompoundID: String,
        paperID: String,
        title: String,
        year: Int,
        examType: String,
        volume: String = "",
        searchText: String = "",
        provinceCode: String? = nil,
        provinceName: String? = nil,
        provinceLabelsData: Data = Data("[]".utf8),
        questionCount: Int = 0,
        sourceRevision: Int,
        metadataReadyVersion: Int,
        generationID: String
    ) {
        self.sourceCompoundID = sourceCompoundID
        self.paperID = paperID
        self.title = title
        self.year = year
        self.examType = examType
        self.volume = volume
        self.searchText = searchText
        self.provinceCode = provinceCode
        self.provinceName = provinceName
        self.provinceLabelsData = provinceLabelsData
        self.questionCount = questionCount
        self.sourceRevision = sourceRevision
        self.metadataReadyVersion = metadataReadyVersion
        self.generationID = generationID
    }
}

@Model
final class QuestionBankCatalogModuleRecord {
    @Attribute(.unique) var sourceCompoundID: String
    var paperID: String
    var moduleID: String
    var title: String
    var sequence: Int
    var questionCount: Int
    var sourceRevision: Int
    var metadataReadyVersion: Int
    var generationID: String

    init(
        sourceCompoundID: String,
        paperID: String,
        moduleID: String,
        title: String,
        sequence: Int,
        questionCount: Int = 0,
        sourceRevision: Int,
        metadataReadyVersion: Int,
        generationID: String
    ) {
        self.sourceCompoundID = sourceCompoundID
        self.paperID = paperID
        self.moduleID = moduleID
        self.title = title
        self.sequence = sequence
        self.questionCount = questionCount
        self.sourceRevision = sourceRevision
        self.metadataReadyVersion = metadataReadyVersion
        self.generationID = generationID
    }
}

@Model
final class QuestionBankCatalogQuestionRecord {
    @Attribute(.unique) var sourceCompoundID: String
    var paperID: String
    var stableID: String
    var moduleID: String
    var originalNumber: Int
    var moduleSequence: Int
    var questionTypeSequence: Int = 0
    var searchText: String = ""
    var coarseModule: String
    var coarseQuestionType: String
    var materialID: String
    var isDifficult: Bool
    var needsReview: Bool
    /// JSON string arrays only; never question text or the source payload.
    var knowledgePointsData: Data
    var weaknessTagsData: Data
    var sourceRevision: Int
    var metadataReadyVersion: Int
    var generationID: String

    init(
        sourceCompoundID: String,
        paperID: String,
        stableID: String,
        moduleID: String,
        originalNumber: Int,
        moduleSequence: Int,
        questionTypeSequence: Int = 0,
        searchText: String = "",
        coarseModule: String,
        coarseQuestionType: String,
        materialID: String,
        isDifficult: Bool,
        needsReview: Bool,
        knowledgePointsData: Data,
        weaknessTagsData: Data,
        sourceRevision: Int,
        metadataReadyVersion: Int,
        generationID: String
    ) {
        self.sourceCompoundID = sourceCompoundID
        self.paperID = paperID
        self.stableID = stableID
        self.moduleID = moduleID
        self.originalNumber = originalNumber
        self.moduleSequence = moduleSequence
        self.questionTypeSequence = questionTypeSequence
        self.searchText = searchText
        self.coarseModule = coarseModule
        self.coarseQuestionType = coarseQuestionType
        self.materialID = materialID
        self.isDifficult = isDifficult
        self.needsReview = needsReview
        self.knowledgePointsData = knowledgePointsData
        self.weaknessTagsData = weaknessTagsData
        self.sourceRevision = sourceRevision
        self.metadataReadyVersion = metadataReadyVersion
        self.generationID = generationID
    }
}

@Model
final class QuestionBankCatalogProgressRecord {
    @Attribute(.unique) var indexID: String
    var stateRawValue: String
    var metadataReadyVersion: Int
    var buildGeneration: String?
    var readyGeneration: String?
    var lastCompoundID: String?
    var paperQuestionCountsData: Data
    var moduleQuestionCountsData: Data
    var indexedSourceRowCount: Int
    var totalSourceRowCount: Int? = nil
    /// Changes whenever the ready directory rows or their visibility state change.
    var catalogRevision: Int = 0
    var invalidatedPaperID: String?
    var invalidatedModuleID: String?
    var invalidatedQuestionID: String?
    var updatedAt: Date

    init(indexID: String, metadataReadyVersion: Int, updatedAt: Date = .now) {
        self.indexID = indexID
        stateRawValue = "notStarted"
        self.metadataReadyVersion = metadataReadyVersion
        buildGeneration = nil
        readyGeneration = nil
        lastCompoundID = nil
        paperQuestionCountsData = Data("{}".utf8)
        moduleQuestionCountsData = Data("{}".utf8)
        indexedSourceRowCount = 0
        totalSourceRowCount = nil
        catalogRevision = 0
        invalidatedPaperID = nil
        invalidatedModuleID = nil
        invalidatedQuestionID = nil
        self.updatedAt = updatedAt
    }
}
