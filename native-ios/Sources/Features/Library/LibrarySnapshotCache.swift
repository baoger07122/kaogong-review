import Foundation

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

    private struct Entry {
        let updatedAt: Date?
        let includesImages: Bool
        let snapshot: LibraryRecordSnapshot
    }

    private var entries: [String: Entry] = [:]
    private var names: [String: WordNameEntry] = [:]
    private var cachedWordNameRevision: [WordNameRevision]?
    private var cachedWordNames: [String: String] = [:]

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

    func snapshot(
        record: StoredRecord,
        linkedWordNamesByID: [String: String],
        includeImages: Bool
    ) -> LibraryRecordSnapshot {
        if let cached = entries[record.compoundID],
           cached.updatedAt == record.updatedAt,
           cached.includesImages == includeImages {
            return cached.snapshot
        }
        let value = LibraryRecordSnapshot(
            record: record,
            linkedWordNamesByID: linkedWordNamesByID,
            includeImages: includeImages
        )
        entries[record.compoundID] = Entry(
            updatedAt: record.updatedAt,
            includesImages: includeImages,
            snapshot: value
        )
        return value
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
    }

    private var sortedQuery: Query?
    private var sortedRecords: [StoredRecord] = []
    private var quantityTypesRevision: [RecordRevision]?
    private var quantityTypesValue: [String] = []

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
            selectedQuantityType: selectedQuantityType
        )
        guard sortedQuery != query else { return sortedRecords }

        let isQuantityContext = scope.subject == "数量关系" && scope.module == nil
        let validQuantityTypes = Set(quantityTypes(records: records))
        sortedRecords = records.filter { record in
            guard record.collection == kind.collection, scope.contains(record) else { return false }
            if isQuantityContext, kind == .errors || kind == .notes {
                if selectedQuantityType == "未分类" {
                    guard !validQuantityTypes.contains(record.module ?? "") else { return false }
                } else if !selectedQuantityType.isEmpty {
                    guard record.module == selectedQuantityType else { return false }
                }
            }
            if kind == .stickies && !scope.hasModuleContext { return false }
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
}
