import Foundation

@main
enum LibraryInlineNoteFinishPolicyBehavior {
    static func main() {
        let session = UUID()
        let before = LibraryInlineNoteFinishRevision(
            documentID: "record-203",
            sessionID: session,
            revision: 7,
            html: "<p>输入中的旧快照</p>"
        )
        let after = LibraryInlineNoteFinishRevision(
            documentID: "record-203",
            sessionID: session,
            revision: 8,
            html: "<p>结束输入后提交的最终内容</p>"
        )
        precondition(
            LibraryInlineNoteFinishPolicy.finalRevision(
                beforeEnding: before,
                endedHTML: after.html,
                afterEnding: after
            ) == after,
            "finish must use the newer final editor revision when endEditing diverges from the pre-save snapshot"
        )
        precondition(
            LibraryInlineNoteFinishPolicy.finalRevision(
                beforeEnding: before,
                endedHTML: "<p>没有匹配快照的新内容</p>",
                afterEnding: nil
            ) == nil,
            "finish must refuse to save divergent endEditing text without a matching rich-text snapshot"
        )

        precondition(
            LibraryInlineNoteFinishPolicy.saveIsConfirmed(
                finalRevision: after,
                confirmedVersion: 12,
                expectedVersion: 12,
                confirmedHTML: after.html,
                persistedHTML: after.html
            ),
            "finish must accept only the matching confirmed version and persisted note field"
        )
        precondition(
            !LibraryInlineNoteFinishPolicy.saveIsConfirmed(
                finalRevision: after,
                confirmedVersion: 12,
                expectedVersion: 12,
                confirmedHTML: after.html,
                persistedHTML: before.html
            ),
            "a save-service receipt must not hide a different StoredRecord.note value"
        )

        let recovery = LibraryInlineNoteFinishPolicy.recoveryAfterSaveFailure(finalHTML: after.html)
        precondition(recovery.draft == after.html, "save failure must retain the final draft")
        precondition(recovery.keepsEditorOpen, "save failure must keep the editor available for retry")
        precondition(recovery.unlocksInput, "save failure must allow the retained draft to be edited")
    }
}
