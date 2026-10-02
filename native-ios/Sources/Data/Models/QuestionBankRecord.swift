import Foundation
import SwiftData

/// Question-bank rows live in their own SwiftData entity so the learning-library
/// queries for StoredRecord never have to load a complete exam bank.
@Model
final class QuestionBankRecord {
    @Attribute(.unique) var compoundID: String
    var paperID: String
    var kind: String
    var stableID: String
    var moduleID: String?
    var questionNumber: Int?
    var sequence: Int?
    var year: Int?
    var examType: String?
    var normalizedPaperKey: String?
    var title: String?
    var searchText: String
    var payload: Data
    /// Relative to Application Support/QuestionBankAssets; image bytes stay on disk.
    var assetRelativePath: String?

    init(
        compoundID: String,
        paperID: String,
        kind: String,
        stableID: String,
        moduleID: String? = nil,
        questionNumber: Int? = nil,
        sequence: Int? = nil,
        year: Int? = nil,
        examType: String? = nil,
        normalizedPaperKey: String? = nil,
        title: String? = nil,
        searchText: String = "",
        payload: Data,
        assetRelativePath: String? = nil
    ) {
        self.compoundID = compoundID
        self.paperID = paperID
        self.kind = kind
        self.stableID = stableID
        self.moduleID = moduleID
        self.questionNumber = questionNumber
        self.sequence = sequence
        self.year = year
        self.examType = examType
        self.normalizedPaperKey = normalizedPaperKey
        self.title = title
        self.searchText = searchText
        self.payload = payload
        self.assetRelativePath = assetRelativePath
    }

    func update(from row: QuestionBankStoredRow) {
        paperID = row.paperID
        kind = row.kind
        stableID = row.stableID
        moduleID = row.moduleID
        questionNumber = row.questionNumber
        sequence = row.sequence
        year = row.year
        examType = row.examType
        normalizedPaperKey = row.normalizedPaperKey
        title = row.title
        searchText = row.searchText
        payload = row.payload
        assetRelativePath = row.assetRelativePath
    }
}
