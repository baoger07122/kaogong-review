import Foundation

enum LibraryWordErrorAssociationPolicy {
    static func resolvedErrorIDs(
        linkedErrors: [String]?,
        relatedErrorIDs: [String]?,
        reverseLinkedErrorIDs: [String],
        existingErrorIDs: Set<String>
    ) -> [String] {
        uniqueExistingIDs(
            (linkedErrors ?? []) + (relatedErrorIDs ?? []) + reverseLinkedErrorIDs,
            existingIDs: existingErrorIDs
        )
    }

    static func uniqueExistingIDs(_ ids: [String], existingIDs: Set<String>) -> [String] {
        var seen = Set<String>()
        return ids.filter { existingIDs.contains($0) && seen.insert($0).inserted }
    }
}
