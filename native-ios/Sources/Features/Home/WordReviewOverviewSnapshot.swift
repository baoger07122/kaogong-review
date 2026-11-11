import Foundation

struct WordReviewOverviewCacheKey: Hashable, Sendable {
    let revision: Int
    let reviewDay: Date
    let restoreGeneration: Int
}

struct WordReviewOverviewRecordInput: Sendable {
    let collection: String
    let recordID: String
    let payload: Data
    let createdAt: Date?
}

struct WordReviewEnrollmentCandidate: Equatable, Sendable {
    let wordRecordID: String
    let addedAt: Date
}

struct WordReviewCardSummary: Equatable, Identifiable, Sendable {
    let wordRecordID: String
    let title: String
    let categoryRawValue: String

    var id: String { wordRecordID }
}

struct WordReviewOverviewSnapshot: Sendable {
    let key: WordReviewOverviewCacheKey
    let cardsByID: [String: WordReviewCardSummary]
    let plansByID: [String: WordReviewPlan]
    let dueWordIDsByCategory: [String: [String]]
    let histories: [WordReviewHistory]
    let enrollmentCandidates: [WordReviewEnrollmentCandidate]
}

enum WordReviewOverviewSnapshotBuilder {
    private struct WordMetadata {
        let summary: WordReviewCardSummary
        let addedAt: Date
    }

    static func build(
        key: WordReviewOverviewCacheKey,
        records: [WordReviewOverviewRecordInput],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WordReviewOverviewSnapshot {
        var wordsByID: [String: WordMetadata] = [:]
        var planInputsByID: [String: Data] = [:]
        var history: [WordReviewHistory] = []
        let decoder = JSONDecoder()

        for input in records {
            guard !Task.isCancelled else { break }
            switch input.collection {
            case "words":
                guard let object = jsonObject(input.payload),
                      let metadata = wordMetadata(input, object: object, now: now) else { continue }
                wordsByID[input.recordID] = metadata
            case "word_review_plans":
                planInputsByID[input.recordID] = input.payload
            case "word_review_history":
                if let item = try? decoder.decode(WordReviewHistory.self, from: input.payload) {
                    history.append(item)
                }
            default:
                continue
            }
        }

        var plansByID: [String: WordReviewPlan] = [:]
        for (recordID, payload) in planInputsByID {
            if let plan = try? decoder.decode(WordReviewPlan.self, from: payload),
               plan.wordRecordID == recordID {
                plansByID[recordID] = plan
            }
        }

        var candidates: [WordReviewEnrollmentCandidate] = []
        for (recordID, metadata) in wordsByID {
            guard let existing = plansByID[recordID] else {
                candidates.append(.init(wordRecordID: recordID, addedAt: metadata.addedAt))
                continue
            }
            if WordReviewEnrollmentPolicy.backfilledPlan(existing, addedAt: metadata.addedAt, now: now, calendar: calendar) != nil {
                candidates.append(.init(wordRecordID: recordID, addedAt: metadata.addedAt))
            }
        }
        var dueByCategory = Dictionary(
            uniqueKeysWithValues: WordCategory.allCases.map { ($0.rawValue, [String]()) }
        )
        let duePlans = plansByID.values.compactMap { plan -> (WordReviewPlan, WordReviewCardSummary)? in
            guard !plan.isPaused,
                  let card = wordsByID[plan.wordRecordID]?.summary,
                  WordReviewSchedulingPolicy.isDue(plan.nextDueDate, on: key.reviewDay, calendar: calendar)
            else { return nil }
            return (plan, card)
        }.sorted { lhs, rhs in
            let leftDate = lhs.0.nextDueDate ?? .distantFuture
            let rightDate = rhs.0.nextDueDate ?? .distantFuture
            if calendar.startOfDay(for: leftDate) != calendar.startOfDay(for: rightDate) {
                return leftDate < rightDate
            }
            if lhs.1.title != rhs.1.title {
                return lhs.1.title.localizedStandardCompare(rhs.1.title) == .orderedAscending
            }
            return lhs.0.wordRecordID < rhs.0.wordRecordID
        }
        for (plan, card) in duePlans {
            dueByCategory[card.categoryRawValue, default: []].append(plan.wordRecordID)
        }

        history.sort { lhs, rhs in
            if lhs.reviewedAt != rhs.reviewedAt { return lhs.reviewedAt > rhs.reviewedAt }
            return lhs.id > rhs.id
        }
        candidates.sort { $0.wordRecordID < $1.wordRecordID }

        return WordReviewOverviewSnapshot(
            key: key,
            cardsByID: wordsByID.mapValues(\.summary),
            plansByID: plansByID,
            dueWordIDsByCategory: dueByCategory,
            histories: history,
            enrollmentCandidates: candidates
        )
    }

    private static func wordMetadata(
        _ input: WordReviewOverviewRecordInput,
        object: [String: Any],
        now: Date
    ) -> WordMetadata? {
        let category = (object["category"] as? String) ?? (object["type"] as? String) ?? ""
        guard WordReviewEnrollmentPolicy.isValidCategory(category),
              let typedCategory = WordCategory(rawValue: category) else { return nil }

        let terms = object["compareWords"] as? [[String: Any]] ?? []
        let names = terms.compactMap { item -> String? in
            guard let name = item["name"] as? String else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let sourceName = [object["name"] as? String, object["words"] as? String, object["title"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        let title = typedCategory.isComparison && !names.isEmpty
            ? names.joined(separator: "｜")
            : sourceName
        guard !title.isEmpty else { return nil }

        return WordMetadata(
            summary: WordReviewCardSummary(
                wordRecordID: input.recordID,
                title: title,
                categoryRawValue: category
            ),
            addedAt: input.createdAt ?? payloadDate(object["createdAt"]) ?? now
        )
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func payloadDate(_ value: Any?) -> Date? {
        if let value = value as? NSNumber {
            let raw = value.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let value = value as? String, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

@MainActor
final class WordReviewOverviewSnapshotCache {
    static let shared = WordReviewOverviewSnapshotCache()

    private var snapshots: [WordReviewOverviewCacheKey: WordReviewOverviewSnapshot] = [:]
    private var insertionOrder: [WordReviewOverviewCacheKey] = []

    func snapshot(for key: WordReviewOverviewCacheKey) -> WordReviewOverviewSnapshot? {
        snapshots[key]
    }

    func store(_ snapshot: WordReviewOverviewSnapshot) {
        snapshots[snapshot.key] = snapshot
        insertionOrder.removeAll { $0 == snapshot.key }
        insertionOrder.append(snapshot.key)
        while insertionOrder.count > 3 {
            snapshots.removeValue(forKey: insertionOrder.removeFirst())
        }
    }
}
