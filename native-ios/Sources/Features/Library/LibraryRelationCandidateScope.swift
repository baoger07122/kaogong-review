import Foundation

enum LibraryRelationCandidateScope {
    static func includes(candidateCollection: String, targetCollection: String) -> Bool {
        !targetCollection.isEmpty && candidateCollection == targetCollection
    }
}
