import Foundation
import SwiftData

enum QuestionBankRecordChangeSignal {
    static let notification = Notification.Name("QuestionBankRecordsDidChange")
    static let paperIDsKey = "paperIDs"

    @MainActor
    static func post(paperIDs: Set<String>) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [paperIDsKey: Array(paperIDs)]
        )
    }

    static func affects(_ paperID: String, notification: Notification) -> Bool {
        guard let paperIDs = notification.userInfo?[paperIDsKey] as? [String] else { return true }
        return paperIDs.isEmpty || paperIDs.contains(paperID)
    }

    static func affectsAny(_ paperIDs: [String], notification: Notification) -> Bool {
        guard let changedPaperIDs = notification.userInfo?[paperIDsKey] as? [String] else { return true }
        return paperIDs.isEmpty || changedPaperIDs.isEmpty || !Set(changedPaperIDs).isDisjoint(with: paperIDs)
    }
}

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
    var contentRevision: Int = 0
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
        contentRevision: Int = 0,
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
        self.contentRevision = contentRevision
        self.assetRelativePath = assetRelativePath
    }

    func replacePayload(_ value: Data) {
        payload = value
        contentRevision &+= 1
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
        contentRevision &+= 1
        assetRelativePath = row.assetRelativePath
    }
}
