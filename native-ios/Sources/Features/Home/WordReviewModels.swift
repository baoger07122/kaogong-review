import Foundation
import SwiftData

extension WordReviewPlan {
    static func decode(from record: StoredRecord) -> WordReviewPlan? {
        guard record.collection == "word_review_plans" else { return nil }
        return try? JSONDecoder().decode(Self.self, from: record.payload)
    }
}

struct WordReviewHistory: Codable, Equatable, Identifiable {
    var id: String
    var wordRecordID: String
    var title: String
    var categoryTitle: String
    var attemptType: WordReviewAttemptType
    var feedback: WordReviewFeedback
    var reviewedAt: Date
    var reviewRound: Int
    var previousDueDate: Date?
    var nextDueDate: Date?
    var isContextValidationPending: Bool? = nil

    static func decode(from record: StoredRecord) -> WordReviewHistory? {
        guard record.collection == "word_review_history" else { return nil }
        return try? JSONDecoder().decode(Self.self, from: record.payload)
    }
}

struct WordReviewTerm: Equatable, Identifiable {
    let id: String
    let name: String
    let meaning: String
    let coreFocus: String
    let quickDecision: String
}

struct WordReviewWordGroup: Equatable, Identifiable {
    let recordID: String
    let title: String
    let category: WordCategory
    let categoryTitle: String
    let commonMeaning: String
    let coreDifference: String
    let judgmentHint: String
    let meaning: String
    let pinyin: String
    let partOfSpeech: String
    let example: String
    let myUnderstanding: String
    let collocations: String
    let terms: [WordReviewTerm]

    var id: String { recordID }

    init?(record: StoredRecord) {
        guard record.collection == "words", let object = record.jsonObject else { return nil }
        let category = WordCategory(rawValue: object["category"] as? String ?? object["type"] as? String ?? "")
            ?? .idiomDefinition

        let terms = (object["compareWords"] as? [[String: Any]] ?? []).enumerated().compactMap { index, entry -> WordReviewTerm? in
            guard let name = entry["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return WordReviewTerm(
                id: "\(record.recordID):\(index)",
                name: name,
                meaning: entry["meaning"] as? String ?? "",
                coreFocus: entry["coreFocus"] as? String ?? entry["focus"] as? String ?? "",
                quickDecision: entry["quickDecision"] as? String ?? entry["decision"] as? String ?? ""
            )
        }
        let sourceName = [object["name"] as? String, object["words"] as? String, object["title"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        let title = category.isComparison && !terms.isEmpty
            ? terms.map(\.name).joined(separator: "｜")
            : sourceName
        guard !title.isEmpty else { return nil }

        self.recordID = record.recordID
        self.title = title
        self.category = category
        self.categoryTitle = category.title
        self.commonMeaning = object["commonMeaning"] as? String ?? ""
        self.coreDifference = object["compareNote"] as? String ?? object["coreDifference"] as? String ?? ""
        self.judgmentHint = object["judgmentHint"] as? String ?? ""
        self.meaning = object["meaning"] as? String ?? ""
        self.pinyin = object["pinyin"] as? String ?? ""
        self.partOfSpeech = object["pos"] as? String ?? object["partOfSpeech"] as? String ?? ""
        self.example = object["example"] as? String ?? ""
        self.myUnderstanding = object["myUnderstanding"] as? String ?? ""
        self.collocations = object["collocations"] as? String ?? ""
        self.terms = terms
    }
}
