import Foundation

/// Keeps parsed card data stable while a navigation transition redraws the library root.
/// SwiftData records are read only on the main thread that owns the view's ModelContext.
final class LibrarySnapshotCache {
    private struct Entry {
        let updatedAt: Date?
        let includesImages: Bool
        let snapshot: LibraryRecordSnapshot
    }

    private var entries: [String: Entry] = [:]
    private var names: [String: (updatedAt: Date?, value: String)] = [:]

    func wordNames(in records: [StoredRecord]) -> [String: String] {
        var result: [String: String] = [:]
        var changed = false
        for record in records where record.collection == "words" {
            if let cached = names[record.recordID], cached.updatedAt == record.updatedAt {
                result[record.recordID] = cached.value
                continue
            }
            let object = record.indexObject ?? [:]
            let name = ["name", "words", "title", "text"]
                .compactMap { object[$0] as? String }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "未命名词语"
            names[record.recordID] = (record.updatedAt, name)
            result[record.recordID] = name
            changed = true
        }
        if names.count != result.count {
            names = names.filter { result[$0.key] != nil }
            changed = true
        }
        if changed { entries.removeAll() }
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
