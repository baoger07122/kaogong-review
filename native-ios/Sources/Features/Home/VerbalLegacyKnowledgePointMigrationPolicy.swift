import Foundation

struct VerbalLegacyKnowledgePointMigrationPlan: Equatable {
    let references: [LibraryKnowledgePointReference]
    let didChange: Bool
    let hasUnresolvedNameOnlyReference: Bool
}

enum VerbalLegacyKnowledgePointMigrationPolicy {
    static func plan(
        references: [LibraryKnowledgePointReference],
        source: LibraryKnowledgePointReference,
        destination: LibraryKnowledgePointReference,
        nameOnlyCandidates: [LibraryKnowledgePointReference],
        nameOnlyResolution: LibraryKnowledgePointReference? = nil
    ) -> VerbalLegacyKnowledgePointMigrationPlan {
        let candidates = LibraryKnowledgePointReferencePolicy.uniqueReferences(nameOnlyCandidates)
        let isValidResolution = nameOnlyResolution.map { candidate in
            candidate == destination || (candidates.contains(candidate) && candidate != source)
        } ?? false
        var didChange = false
        var hasUnresolvedNameOnlyReference = false

        let migrated = references.map { reference -> LibraryKnowledgePointReference in
            if reference.module == source.module,
               reference.typeID == source.typeID,
               reference.name == source.name {
                didChange = true
                return destination
            }

            guard reference.module == nil,
                  reference.typeID == nil,
                  reference.name == source.name else { return reference }

            if candidates.count == 1, candidates[0] == source {
                didChange = true
                return destination
            }
            guard isValidResolution, let nameOnlyResolution else {
                hasUnresolvedNameOnlyReference = true
                return reference
            }
            didChange = didChange || nameOnlyResolution != reference
            return nameOnlyResolution
        }

        return VerbalLegacyKnowledgePointMigrationPlan(
            references: LibraryKnowledgePointReferencePolicy.uniqueReferences(migrated),
            didChange: didChange,
            hasUnresolvedNameOnlyReference: hasUnresolvedNameOnlyReference
        )
    }
}
