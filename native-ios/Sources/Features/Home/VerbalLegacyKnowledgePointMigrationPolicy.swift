import Foundation

struct VerbalLegacyKnowledgePointMigrationPlan: Equatable {
    let references: [LibraryKnowledgePointReference]
    let didChange: Bool
    let hasAmbiguousLegacyReference: Bool
}

enum VerbalLegacyKnowledgePointMigrationPolicy {
    static func plan(
        references: [LibraryKnowledgePointReference],
        recordModule: String?,
        recordTypeID: String?,
        sourceModule: String,
        name: String,
        destinationTypeID: String
    ) -> VerbalLegacyKnowledgePointMigrationPlan {
        let normalizedRecordModule = recordModule?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTypeID = recordTypeID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeIsUnset = normalizedTypeID?.isEmpty ?? true
        let moduleMatches = normalizedRecordModule == sourceModule

        let hasAmbiguousLegacyReference = moduleMatches && !typeIsUnset && references.contains {
            $0.typeID == nil && $0.module == nil && $0.name == name
        }
        guard moduleMatches else {
            return VerbalLegacyKnowledgePointMigrationPlan(
                references: references,
                didChange: false,
                hasAmbiguousLegacyReference: false
            )
        }

        var didChange = false
        let migrated = references.map { reference -> LibraryKnowledgePointReference in
            let explicitlyReferencesSourceLegacyTag = reference.module == sourceModule
                && reference.typeID == nil
                && reference.name == name
            let safelyInferableNameOnlyReference = typeIsUnset
                && reference.module == nil
                && reference.typeID == nil
                && reference.name == name
            guard explicitlyReferencesSourceLegacyTag || safelyInferableNameOnlyReference else { return reference }
            didChange = true
            return LibraryKnowledgePointReference(
                module: sourceModule,
                typeID: destinationTypeID,
                name: name
            )
        }

        return VerbalLegacyKnowledgePointMigrationPlan(
            references: LibraryKnowledgePointReferencePolicy.uniqueReferences(migrated),
            didChange: didChange,
            hasAmbiguousLegacyReference: hasAmbiguousLegacyReference
        )
    }
}
