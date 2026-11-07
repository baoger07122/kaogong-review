import Foundation

enum LegacyWordReviewRestorePolicy {
    static func shouldPreserveLocalRecord(
        collection: String,
        includesCollection: Bool,
        wordRecordID: String,
        importedWordIDs: Set<String>,
        importedReviewRecordIDs: Set<String>,
        recordID: String
    ) -> Bool {
        guard collection == "word_review_plans" || collection == "word_review_history",
              !includesCollection,
              importedWordIDs.contains(wordRecordID),
              !importedReviewRecordIDs.contains("\(collection):\(recordID)") else { return false }
        return true
    }
}
