import Foundation

extension Notification.Name {
    static let legacyBackupRestoreDidComplete = Notification.Name("LegacyBackupRestoreDidComplete")
}

enum LibrarySnapshotSearch {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }
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
            examTitleRevision &+= 1
            let changedIDs = Set(changedExamIDs)
            entries = entries.filter { _, entry in
                entry.reviewSource != .mock || !changedIDs.contains(entry.snapshot.sourceExamID)
            }
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
        let errorTypeFilter: LibraryErrorTypeFilter
        let validErrorTypeIDs: Set<String>
        let reviewSource: LibraryReviewSource
    }

    private struct ErrorSequenceQuery: Equatable {
        let sortedQuery: Query?
        let tag: String
        let search: String
        let includesMastered: Bool
        let examTitleRevision: Int
    }

    private struct UnclassifiedAvailabilityQuery: Equatable {
        let records: [RecordRevision]
        let kind: LibraryContentKind
        let scope: LibraryScope
        let selectedTag: String
        let selectedKnowledgePoints: [LibraryKnowledgePointReference]
        let search: String
        let includesMasteredErrors: Bool
        let validErrorTypeIDs: Set<String>
        let quantityTypes: Set<String>
    }

    private struct KnowledgePointEntriesQuery: Equatable {
        let records: [RecordRevision]
        let key: String
    }

    private struct KnowledgePointReferenceIndexQuery: Equatable {
        let records: [RecordRevision]
        let subject: String?
    }

    private var sortedQuery: Query?
    private var sortedRecords: [StoredRecord] = []
    private var errorSequenceQuery: ErrorSequenceQuery?
    private var errorSequence: [String] = []
    private var unclassifiedAvailabilityQuery: UnclassifiedAvailabilityQuery?
    private var cachedUnclassifiedAvailability = false
    private var tagRevisions: [RecordRevision]?
    private var tagsByRecord: [String: [String]] = [:]
    private var knowledgePointEntriesQuery: KnowledgePointEntriesQuery?
    private var cachedKnowledgePointEntries: [LibraryKnowledgePointPickerEntry] = []
    private var knowledgePointReferenceIndexQuery: KnowledgePointReferenceIndexQuery?
    private var cachedKnowledgePointReferences: [String: [LibraryKnowledgePointReference]] = [:]
    private var quantityTypesRevision: [RecordRevision]?
    private var quantityTypesValue: [String] = []
    private let reviewSourceCache = LibraryReviewSourceClassificationCache()

    func reviewSources(for records: [StoredRecord]) -> [String: LibraryReviewSource] {
        reviewSourceCache.classifications(for: records)
    }

    func sortedScopedRecords(
        records: [StoredRecord],
        kind: LibraryContentKind,
        scope: LibraryScope,
        selectedQuantityType: String,
        errorTypeFilter: LibraryErrorTypeFilter,
        validErrorTypeIDs: Set<String>
    ) -> [StoredRecord] {
        let revisions = records.map(RecordRevision.init)
        let query = Query(
            records: revisions,
            kind: kind,
            subject: scope.subject,
            module: scope.module,
            selectedQuantityType: selectedQuantityType,
            errorTypeFilter: errorTypeFilter,
            validErrorTypeIDs: validErrorTypeIDs,
            reviewSource: scope.reviewSource
        )
        guard sortedQuery != query else { return sortedRecords }

        let isQuantityContext = scope.subject == "数量关系" && scope.module == nil
        let validQuantityTypes = isQuantityContext ? Set(quantityTypes(records: records)) : []
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
            if kind == .errors, errorTypeFilter != .all {
                return errorTypeFilter.includes(
                    record.indexObject?["errorTypeID"] as? String, validIDs: validErrorTypeIDs
                )
            }
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

    func visibleErrorIDs(
        tag: String,
        search: String,
        includesMastered: Bool,
        examTitleRevision: Int,
        build: () -> [String]
    ) -> [String] {
        let query = ErrorSequenceQuery(
            sortedQuery: sortedQuery, tag: tag, search: search, includesMastered: includesMastered,
            examTitleRevision: examTitleRevision
        )
        if errorSequenceQuery != query {
            errorSequence = build()
            errorSequenceQuery = query
        }
        return errorSequence
    }

    func hasVisibleUnclassifiedTypeRecord(
        records: [StoredRecord],
        kind: LibraryContentKind,
        scope: LibraryScope,
        selectedTag: String,
        selectedKnowledgePoints: [LibraryKnowledgePointReference],
        search: String,
        includesMasteredErrors: Bool,
        validErrorTypeIDs: Set<String>,
        quantityTypes: Set<String>,
        buildSnapshot: (StoredRecord) -> LibraryRecordSnapshot,
        knowledgePointMatches: (StoredRecord) -> Bool
    ) -> Bool {
        let query = UnclassifiedAvailabilityQuery(
            records: records.map(RecordRevision.init),
            kind: kind,
            scope: scope,
            selectedTag: selectedTag,
            selectedKnowledgePoints: selectedKnowledgePoints,
            search: search,
            includesMasteredErrors: includesMasteredErrors,
            validErrorTypeIDs: validErrorTypeIDs,
            quantityTypes: quantityTypes
        )
        guard unclassifiedAvailabilityQuery != query else { return cachedUnclassifiedAvailability }

        let isQuantityContext = scope.subject == "数量关系" && scope.module == nil
            && (kind == .errors || kind == .notes)
        let reviewSources = reviewSourceCache.classifications(for: records)
        cachedUnclassifiedAvailability = records.contains { record in
            guard record.collection == kind.collection,
                  scope.contains(record),
                  (kind == .words || reviewSources[record.compoundID] == scope.reviewSource)
            else { return false }

            if isQuantityContext {
                guard !quantityTypes.contains(record.module ?? "") else { return false }
            } else {
                guard kind == .errors,
                      LibraryErrorTypeFilter.unclassified.includes(
                        record.indexObject?["errorTypeID"] as? String,
                        validIDs: validErrorTypeIDs
                      ) else { return false }
            }

            let snapshot = buildSnapshot(record)
            guard selectedTag.isEmpty || snapshot.tags.contains(selectedTag) else { return false }
            guard knowledgePointMatches(record) else { return false }
            guard search.isEmpty || LibrarySnapshotSearch.normalize(snapshot.searchableText).contains(search) else { return false }
            guard kind != .errors || includesMasteredErrors || snapshot.status != "已掌握" else { return false }
            return true
        }
        unclassifiedAvailabilityQuery = query
        return cachedUnclassifiedAvailability
    }

    func tagIndex(
        for records: [StoredRecord],
        buildTags: (StoredRecord) -> [String]
    ) -> [String: [String]] {
        let revisions = records.map(RecordRevision.init)
        if tagRevisions != revisions {
            tagsByRecord = Dictionary(uniqueKeysWithValues: records.map { ($0.compoundID, buildTags($0)) })
            tagRevisions = revisions
        }
        return tagsByRecord
    }

    func knowledgePointEntries(
        records: [StoredRecord],
        key: String,
        build: () -> [LibraryKnowledgePointPickerEntry]
    ) -> [LibraryKnowledgePointPickerEntry] {
        let query = KnowledgePointEntriesQuery(records: records.map(RecordRevision.init), key: key)
        guard query != knowledgePointEntriesQuery else { return cachedKnowledgePointEntries }
        cachedKnowledgePointEntries = build()
        knowledgePointEntriesQuery = query
        return cachedKnowledgePointEntries
    }

    func knowledgePointReferenceIndex(
        records: [StoredRecord],
        subject: String?,
        build: () -> [String: [LibraryKnowledgePointReference]]
    ) -> [String: [LibraryKnowledgePointReference]] {
        let query = KnowledgePointReferenceIndexQuery(records: records.map(RecordRevision.init), subject: subject)
        guard query != knowledgePointReferenceIndexQuery else { return cachedKnowledgePointReferences }
        cachedKnowledgePointReferences = build()
        knowledgePointReferenceIndexQuery = query
        return cachedKnowledgePointReferences
    }

    func invalidate() {
        sortedQuery = nil
        sortedRecords.removeAll()
        quantityTypesRevision = nil
        quantityTypesValue.removeAll()
        errorSequenceQuery = nil
        errorSequence.removeAll()
        unclassifiedAvailabilityQuery = nil
        cachedUnclassifiedAvailability = false
        tagRevisions = nil
        tagsByRecord.removeAll()
        knowledgePointEntriesQuery = nil
        cachedKnowledgePointEntries.removeAll()
        knowledgePointReferenceIndexQuery = nil
        cachedKnowledgePointReferences.removeAll()
    }
}
