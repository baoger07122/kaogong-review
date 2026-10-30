import Foundation
import SwiftData

enum QuestionBankRecordChangeSignal {
    static let notification = Notification.Name("QuestionBankRecordsDidChange")
    static let paperIDsKey = "paperIDs"
    static let recordChangesKey = "recordChanges"

    enum Kind: String, Equatable, Sendable {
        case structure
        case questionContent
        case questionAnalysis
        case questionLinks
    }

    struct RecordChange: Equatable, Sendable {
        let paperID: String
        let recordID: String
        let kind: Kind

        fileprivate var userInfoValue: [String: String] {
            ["paperID": paperID, "recordID": recordID, "kind": kind.rawValue]
        }
    }

    /// Legacy broad invalidation. Readers treat events without `recordChanges` as structural.
    static func post(paperIDs: Set<String>) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [paperIDsKey: Array(paperIDs)]
        )
    }

    static func postQuestionChange(paperID: String, questionID: String, kind: Kind = .questionContent) {
        post(recordChanges: [RecordChange(paperID: paperID, recordID: questionID, kind: kind)])
    }

    static func postStructureChange(paperIDs: Set<String>) {
        post(recordChanges: paperIDs.sorted().map {
            RecordChange(paperID: $0, recordID: "", kind: .structure)
        })
    }

    static func post(recordChanges: [RecordChange]) {
        let paperIDs = Set(recordChanges.map(\.paperID))
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [
                paperIDsKey: Array(paperIDs),
                recordChangesKey: recordChanges.map(\.userInfoValue)
            ]
        )
    }

    /// `nil` means an older producer sent only paper IDs and requires a broad refresh.
    static func recordChanges(for paperID: String, notification: Notification) -> [RecordChange]? {
        recordChanges(notification: notification)?.filter { $0.paperID == paperID }
    }

    static func recordChanges(notification: Notification) -> [RecordChange]? {
        guard let rawChanges = notification.userInfo?[recordChangesKey] as? [[String: String]] else {
            return nil
        }
        guard !rawChanges.isEmpty else { return nil }
        let changes = rawChanges.compactMap { value -> RecordChange? in
            guard let changedPaperID = value["paperID"],
                  let recordID = value["recordID"],
                  let rawKind = value["kind"],
                  let kind = Kind(rawValue: rawKind) else { return nil }
            return RecordChange(paperID: changedPaperID, recordID: recordID, kind: kind)
        }
        guard changes.count == rawChanges.count else { return nil }
        return changes
    }

    static func affects(_ paperID: String, notification: Notification) -> Bool {
        guard let paperIDs = notification.userInfo?[paperIDsKey] as? [String] else { return true }
        return paperIDs.isEmpty || paperIDs.contains(paperID)
    }

    static func affectsAny(_ paperIDs: [String], notification: Notification) -> Bool {
        guard let changedPaperIDs = notification.userInfo?[paperIDsKey] as? [String] else { return true }
        return paperIDs.isEmpty || changedPaperIDs.isEmpty || !Set(changedPaperIDs).isDisjoint(with: paperIDs)
    }

    /// Nil signals an older untyped event and requires a broad compatibility reload.
    /// Typed analysis/link events produce an empty array because they do not affect
    /// the home directory's search or filter metadata.
    static func catalogChanges(notification: Notification) -> [RecordChange]? {
        guard let changes = recordChanges(notification: notification) else { return nil }
        return changes.filter { $0.kind == .structure || $0.kind == .questionContent }
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
