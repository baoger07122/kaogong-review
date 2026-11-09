import Foundation

@main
enum LibraryWordErrorAssociationBehavior {
    static func main() {
        let existingErrorIDs: Set<String> = ["error-a", "error-b", "error-c"]
        let resolved = LibraryWordErrorAssociationPolicy.resolvedErrorIDs(
            linkedErrors: ["error-b", "deleted-error", "error-b"],
            relatedErrorIDs: ["error-a", "error-c"],
            reverseLinkedErrorIDs: ["error-c", "error-a", "deleted-error"],
            existingErrorIDs: existingErrorIDs
        )
        precondition(resolved == ["error-b", "error-a", "error-c"],
            "direct, legacy, and reverse-only links are merged in stable order without deleted records")

        let cleared = LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
            [],
            existingIDs: existingErrorIDs
        )
        precondition(cleared.isEmpty, "an explicit empty selection stays empty")

        let selected = LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
            ["error-c", "deleted-error", "error-c", "error-a"],
            existingIDs: existingErrorIDs
        )
        precondition(selected == ["error-c", "error-a"],
            "saving a selection removes duplicates and skips deleted records")
    }
}
