import Foundation

struct LibraryInlineNoteFinishRevision: Equatable {
    let documentID: String
    let sessionID: UUID
    let revision: UInt64
    let html: String
}

struct LibraryInlineNoteFinishRecovery: Equatable {
    let draft: String
    let keepsEditorOpen: Bool
    let unlocksInput: Bool
}

enum LibraryInlineNoteFinishPolicy {
    static func finalRevision(
        beforeEnding: LibraryInlineNoteFinishRevision,
        endedHTML: String?,
        afterEnding: LibraryInlineNoteFinishRevision?
    ) -> LibraryInlineNoteFinishRevision? {
        if let afterEnding,
           afterEnding.documentID == beforeEnding.documentID,
           afterEnding.sessionID == beforeEnding.sessionID {
            if afterEnding.revision > beforeEnding.revision { return afterEnding }
            if afterEnding.revision == beforeEnding.revision,
               afterEnding.html == beforeEnding.html,
               (endedHTML == nil || endedHTML == beforeEnding.html) {
                return afterEnding
            }
            if afterEnding.revision == beforeEnding.revision,
               afterEnding.html == endedHTML {
                return afterEnding
            }
        }

        guard let endedHTML, endedHTML == beforeEnding.html else { return nil }
        return beforeEnding
    }

    static func saveIsConfirmed(
        finalRevision: LibraryInlineNoteFinishRevision,
        confirmedVersion: UInt64,
        expectedVersion: UInt64,
        confirmedHTML: String,
        persistedHTML: String?
    ) -> Bool {
        confirmedVersion == expectedVersion
            && confirmedHTML == finalRevision.html
            && persistedHTML == finalRevision.html
    }

    static func recoveryAfterSaveFailure(finalHTML: String) -> LibraryInlineNoteFinishRecovery {
        LibraryInlineNoteFinishRecovery(
            draft: finalHTML,
            keepsEditorOpen: true,
            unlocksInput: true
        )
    }
}
