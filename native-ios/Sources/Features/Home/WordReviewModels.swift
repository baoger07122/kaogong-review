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
    let coreFocus: String
    let quickDecision: String
}

struct WordReviewWordGroup: Equatable, Identifiable {
    let recordID: String
    let title: String
    let categoryTitle: String
    let commonMeaning: String
    let coreDifference: String
    let judgmentHint: String
    let terms: [WordReviewTerm]

    var id: String { recordID }

    init?(record: StoredRecord) {
        guard record.collection == "words",
              let object = record.jsonObject,
              let category = WordCategory(rawValue: object["category"] as? String ?? object["type"] as? String ?? ""),
              category.isComparison else { return nil }

        let terms = (object["compareWords"] as? [[String: Any]] ?? []).enumerated().compactMap { index, entry -> WordReviewTerm? in
            guard let name = entry["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return WordReviewTerm(
                id: "\(record.recordID):\(index)",
                name: name,
                coreFocus: entry["coreFocus"] as? String ?? entry["focus"] as? String ?? "",
                quickDecision: entry["quickDecision"] as? String ?? entry["decision"] as? String ?? ""
            )
        }
        let sourceName = [object["name"] as? String, object["words"] as? String, object["title"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        let title = terms.isEmpty ? sourceName : terms.map(\.name).joined(separator: "｜")
        guard !title.isEmpty else { return nil }

        self.recordID = record.recordID
        self.title = title
        self.categoryTitle = category == .idiomComparison ? "成语组" : "实词组"
        self.commonMeaning = object["commonMeaning"] as? String ?? ""
        self.coreDifference = object["compareNote"] as? String ?? object["coreDifference"] as? String ?? ""
        self.judgmentHint = object["judgmentHint"] as? String ?? ""
        self.terms = terms
    }
}
