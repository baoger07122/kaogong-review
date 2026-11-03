import Foundation

private struct RelationCandidate {
    let collection: String
    let id: String
}

@main
enum LibraryRelationCandidateBehavior {
    static func main() {
        let mixedCandidates = [
            RelationCandidate(collection: "errors", id: "question-stem"),
            RelationCandidate(collection: "words", id: "word-1"),
            RelationCandidate(collection: "notes", id: "note-1"),
            RelationCandidate(collection: "words", id: "word-2")
        ]

        let visibleWords = mixedCandidates.filter {
            LibraryRelationCandidateScope.includes(
                candidateCollection: $0.collection,
                targetCollection: "words"
            )
        }

        precondition(visibleWords.map(\.id) == ["word-1", "word-2"], "word relation candidates must exclude mixed error and note records")
        precondition(visibleWords.allSatisfy { $0.collection == "words" }, "only records from the requested collection should be visible")
    }
}
