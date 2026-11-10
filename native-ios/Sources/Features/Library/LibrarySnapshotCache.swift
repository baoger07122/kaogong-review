import Foundation

extension Notification.Name {
    static let legacyBackupRestoreDidComplete = Notification.Name("LegacyBackupRestoreDidComplete")
}

/// Keeps parsed card data stable while a navigation transition redraws the library root.
/// SwiftData records are read only on the main thread that owns the view's ModelContext.
final class LibrarySnapshotCache {
    private struct WordNameRevision: Equatable {
        let compoundID: String
        let updatedAt: Date?
        let indexPayloadCount: Int
    }

    private struct WordNameEntry {
        let updatedAt: Date?
        let indexPayloadCount: Int
        let value: String
    }

    private struct ExamTitleRevision: Equatable {
        let compoundID: String
        let updatedAt: Date?
        let indexPayload: Data?
    }

    private struct Entry {
        let updatedAt: Date?
        let payloadCount: Int
        let indexPayloadCount: Int
        let includesImages: Bool
        let reviewSource: LibraryReviewSource
        let snapshot: LibraryRecordSnapshot
    }

    private var entries: [String: Entry] = [:]
    private var names: [String: WordNameEntry] = [:]
    private var cachedWordNameRevision: [WordNameRevision]?
    private var cachedWordNames: [String: String] = [:]
    private var cachedExamTitleRevision: [ExamTitleRevision]?
    private var cachedExamTitles: [String: String] = [:]
    private(set) var examTitleRevision = 0

    func wordNames(in records: [StoredRecord]) -> [String: String] {
        let wordRecords = records.filter { $0.collection == "words" }
        let revision = wordRecords.map { record in
            WordNameRevision(
                compoundID: record.compoundID,
                updatedAt: record.updatedAt,
                indexPayloadCount: record.indexPayload?.count ?? 0
            )
        }
        if cachedWordNameRevision == revision { return cachedWordNames }

        var result: [String: String] = [:]
        var changed = false
        for record in wordRecords {
            let indexPayloadCount = record.indexPayload?.count ?? 0
            if let cached = names[record.recordID],
               cached.updatedAt == record.updatedAt,
               cached.indexPayloadCount == indexPayloadCount {
                result[record.recordID] = cached.value
                continue
            }
            let object = record.indexObject ?? [:]
            let name = ["name", "words", "title", "text"]
                .compactMap { object[$0] as? String }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "未命名词语"
            names[record.recordID] = WordNameEntry(
                updatedAt: record.updatedAt,
                indexPayloadCount: indexPayloadCount,
                value: name
            )
            result[record.recordID] = name
            changed = true
        }
        if names.count != result.count {
            names = names.filter { result[$0.key] != nil }
            changed = true
        }
        if changed { entries.removeAll() }
        cachedWordNameRevision = revision
        cachedWordNames = result
        return result
    }

    func examTitles(in records: [StoredRecord]) -> [String: String] {
        let exams = records.filter { $0.collection == "exams" }.sorted { $0.recordID < $1.recordID }
        let revision = exams.map {
            ExamTitleRevision(
                compoundID: $0.compoundID,
                updatedAt: $0.updatedAt,
                indexPayload: $0.indexPayload
            )
        }
        if cachedExamTitleRevision == revision { return cachedExamTitles }

        let previous = cachedExamTitles
        var result: [String: String] = [:]
        for record in exams {
            let object = record.indexObject ?? [:]
            let title = ["title", "name", "text"]
                .compactMap { object[$0] as? String }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ?? record.title
            result[record.recordID] = title
        }
        let changedExamIDs = Set(previous.keys).union(result.keys).filter { previous[$0] != result[$0] }
        if !changedExamIDs.isEmpty {
            let changedIDs = Set(changedExamIDs)
            entries = entries.filter { _, entry in
                entry.reviewSource != .mock || !changedIDs.contains(entry.snapshot.sourceExamID)
            }
            examTitleRevision &+= 1
        }
        cachedExamTitleRevision = revision
        cachedExamTitles = result
        return result
    }

    func snapshot(
        record: StoredRecord,
        linkedWordNamesByID: [String: String],
        includeImages: Bool,
        reviewSource: LibraryReviewSource = .pending,
        sourceExamTitlesByID: [String: String] = [:]
    ) -> LibraryRecordSnapshot {
        let payloadCount = record.payload.count
        let indexPayloadCount = record.indexPayload?.count ?? 0
        if let cached = entries[record.compoundID],
           cached.updatedAt == record.updatedAt,
           cached.payloadCount == payloadCount,
           cached.indexPayloadCount == indexPayloadCount,
           cached.includesImages == includeImages,
           cached.reviewSource == reviewSource {
            return cached.snapshot
        }
        let previousImageSnapshot = entries[record.compoundID]?.snapshot
        let value = LibraryRecordSnapshot(
            record: record,
            linkedWordNamesByID: linkedWordNamesByID,
            sourceExamTitlesByID: sourceExamTitlesByID,
            reviewSource: reviewSource,
            includeImages: includeImages,
            previousImageSnapshot: previousImageSnapshot
        )
        entries[record.compoundID] = Entry(
            updatedAt: record.updatedAt,
            payloadCount: payloadCount,
            indexPayloadCount: indexPayloadCount,
            includesImages: includeImages,
            reviewSource: reviewSource,
            snapshot: value
        )
        return value
    }

    func invalidate() {
        entries.removeAll()
        names.removeAll()
        cachedWordNameRevision = nil
        cachedWordNames.removeAll()
        cachedExamTitleRevision = nil
        cachedExamTitles.removeAll()
    }
}

@MainActor
final class LibraryRecordListCache {
    private struct RecordRevision: Equatable {
        let compoundID: String
        let collection: String
        let subject: String?
        let module: String?
        let createdAt: Date?
        let updatedAt: Date?
        let payloadCount: Int
        let indexPayloadCount: Int

        init(_ record: StoredRecord) {
            compoundID = record.compoundID
            collection = record.collection
            subject = record.subject
            module = record.module
            createdAt = record.createdAt
            updatedAt = record.updatedAt
            payloadCount = record.payload.count
            indexPayloadCount = record.indexPayload?.count ?? 0
        }
    }

    private struct Query: Equatable {
        let records: [RecordRevision]
        let kind: LibraryContentKind
        let subject: String?
        let module: String?
        let selectedQuantityType: String
        let reviewSource: LibraryReviewSource
    }

    private var sortedQuery: Query?
    private var sortedRecords: [StoredRecord] = []
    private var sortedVisibleErrorRevisions: [LibraryVisibleErrorRecordRevision] = []
    private var quantityTypesRevision: [RecordRevision]?
    private var quantityTypesValue: [String] = []
    private var visibleErrorQuery: LibraryVisibleErrorRecordQuery?
    private var visibleErrorRecordIDsValue: [String] = []
    private var tagIndexRevision: [RecordRevision]?
    private var tagIndexByCompoundID: [String: [String]] = [:]
    private let reviewSourceCache = LibraryReviewSourceClassificationCache()

    func reviewSources(for records: [StoredRecord]) -> [String: LibraryReviewSource] {
        reviewSourceCache.classifications(for: records)
    }

    func sortedScopedRecords(
        records: [StoredRecord],
        kind: LibraryContentKind,
        scope: LibraryScope,
        selectedQuantityType: String
    ) -> [StoredRecord] {
        let revisions = records.map(RecordRevision.init)
        let query = Query(
            records: revisions,
            kind: kind,
            subject: scope.subject,
            module: scope.module,
            selectedQuantityType: selectedQuantityType,
            reviewSource: scope.reviewSource
        )
        guard sortedQuery != query else { return sortedRecords }

        let isQuantityContext = scope.subject == "数量关系" && scope.module == nil
        let validQuantityTypes = Set(quantityTypes(records: records))
        let reviewSources = reviewSourceCache.classifications(for: records)
        sortedRecords = records.filter { record in
            guard record.collection == kind.collection, scope.contains(record) else { return false }
            if kind != .words,
               reviewSources[record.compoundID] != scope.reviewSource { return false }
            if isQuantityContext, kind == .errors || kind == .notes {
                if selectedQuantityType == "未分类" {
                    guard !validQuantityTypes.contains(record.module ?? "") else { return false }
                } else if !selectedQuantityType.isEmpty {
                    guard record.module == selectedQuantityType else { return false }
                }
            }
            if kind == .words && !scope.isLogicFill { return false }
            return true
        }.sorted { left, right in
            let leftDate = kind == .errors
                ? (left.createdAt ?? left.updatedAt ?? .distantPast)
                : (left.updatedAt ?? left.createdAt ?? .distantPast)
            let rightDate = kind == .errors
                ? (right.createdAt ?? right.updatedAt ?? .distantPast)
                : (right.updatedAt ?? right.createdAt ?? .distantPast)
            if leftDate != rightDate { return leftDate > rightDate }
            return left.recordID > right.recordID
        }
        sortedVisibleErrorRevisions = kind == .errors
            ? sortedRecords.map { Self.visibleErrorRevision(for: $0) }
            : []
        sortedQuery = query
        return sortedRecords
    }

    func quantityTypes(records: [StoredRecord]) -> [String] {
        let revisions = records.map(RecordRevision.init)
        guard quantityTypesRevision != revisions else { return quantityTypesValue }
        quantityTypesValue = QuantityQuestionTypeRepository.types(records: records)
        quantityTypesRevision = revisions
        return quantityTypesValue
    }

    func visibleErrorRecordIDs(
        records: [StoredRecord],
        scope: LibraryScope,
        selectedQuantityType: String,
        selectedTag: String,
        normalizedSearch: String,
        includesMastered: Bool,
        sourceExamTitleRevision: Int,
        sourceExamTitlesByID: () -> [String: String]
    ) -> [String] {
        let query = LibraryVisibleErrorRecordQuery(
            revisions: sortedVisibleErrorRevisions,
            collection: LibraryContentKind.errors.collection,
            subject: scope.subject,
            module: scope.module,
            quantityType: selectedQuantityType,
            reviewSource: scope.reviewSource.rawValue,
            sourceExamTitleRevision: sourceExamTitleRevision,
            selectedTag: selectedTag,
            normalizedSearch: normalizedSearch,
            includesMastered: includesMastered
        )
        guard visibleErrorQuery != query else { return visibleErrorRecordIDsValue }

        let examTitles = scope.reviewSource == .mock ? sourceExamTitlesByID() : [:]
        visibleErrorRecordIDsValue = records.compactMap { record in
            let indexObject = record.indexObject ?? [:]
            let object = record.makeCompatibilityIndexObject(from: indexObject) ?? indexObject
            let sourceExamID = object["sourceExamId"] as? String ?? ""
            let filterIndex = LibraryRecordFilterIndex(
                collection: record.collection,
                storedSubject: record.subject,
                indexObject: indexObject,
                compatibleObject: object,
                isMockReview: scope.reviewSource == .mock,
                sourceExamTitle: examTitles[sourceExamID] ?? ""
            )
            guard filterIndex.matches(
                selectedTag: selectedTag,
                normalizedSearch: normalizedSearch,
                includesMastered: includesMastered
            ) else { return nil }
            return record.recordID
        }
        visibleErrorQuery = query
        return visibleErrorRecordIDsValue
    }

    func availableTags(
        in records: [StoredRecord],
        buildTagValues: (StoredRecord) -> [String]
    ) -> [String] {
        let valuesByRecord = tagIndex(in: records, buildTagValues: buildTagValues)
        return Array(Set(valuesByRecord.values.flatMap { $0 })).sorted()
    }

    func records(
        matchingTag tag: String,
        in records: [StoredRecord],
        buildTagValues: (StoredRecord) -> [String]
    ) -> [StoredRecord] {
        guard !tag.isEmpty else { return records }
        let valuesByRecord = tagIndex(in: records, buildTagValues: buildTagValues)
        let matchingIDs = Set(valuesByRecord.compactMap { id, values in
            values.contains(tag) ? id : nil
        })
        return records.filter { matchingIDs.contains($0.compoundID) }
    }

    private func tagIndex(
        in records: [StoredRecord],
        buildTagValues: (StoredRecord) -> [String]
    ) -> [String: [String]] {
        let revision = records.map(RecordRevision.init)
        guard tagIndexRevision != revision else { return tagIndexByCompoundID }
        tagIndexByCompoundID = Dictionary(uniqueKeysWithValues: records.map { ($0.compoundID, buildTagValues($0)) })
        tagIndexRevision = revision
        return tagIndexByCompoundID
    }

    private static func visibleErrorRevision(for record: StoredRecord) -> LibraryVisibleErrorRecordRevision {
        LibraryVisibleErrorRecordRevision(
            compoundID: record.compoundID,
            recordID: record.recordID,
            collection: record.collection,
            subject: record.subject,
            module: record.module,
            createdAt: record.createdAt,
            dataVersion: LibraryRecordDataVersion(
                updatedAt: record.updatedAt,
                payloadByteCount: record.payload.count,
                indexPayloadByteCount: record.indexPayload?.count ?? 0
            )
        )
    }

    func invalidate() {
        sortedQuery = nil
        sortedRecords.removeAll()
        sortedVisibleErrorRevisions.removeAll()
        quantityTypesRevision = nil
        quantityTypesValue.removeAll()
        visibleErrorQuery = nil
        visibleErrorRecordIDsValue.removeAll()
        tagIndexRevision = nil
        tagIndexByCompoundID.removeAll()
    }
}
