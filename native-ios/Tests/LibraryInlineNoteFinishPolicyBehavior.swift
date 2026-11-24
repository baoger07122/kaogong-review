import Foundation

@main
enum LibraryInlineNoteFinishPolicyBehavior {
    static func main() {
        verifyMetadataRebaseWithTableNote()
        verifyDurableDraftReceipts()
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

    private static func verifyDurableDraftReceipts() {
        let originalNoteDigest = String(repeating: "a", count: 64)
        let originalRecordVersion = "first:" + String(repeating: "b", count: 64)
        let updatedRecordVersion = "second:" + String(repeating: "c", count: 64)
        let shortNote = "<p>几点说明</p>"
        let tableNote = "<table><tr><td>词义</td></tr></table>"
        let requested = LibraryInlineNoteDraftSnapshot(
            recordID: "error-39", baseVersion: originalRecordVersion, draftVersion: 4,
            content: shortNote, updatedAt: .now, baseNoteDigest: originalNoteDigest
        )
        let newer = LibraryInlineNoteDraftSnapshot(
            recordID: "error-39", baseVersion: updatedRecordVersion, draftVersion: 5,
            content: shortNote, updatedAt: .now, baseNoteDigest: originalNoteDigest
        )
        precondition(newer.confirmsDurableWrite(of: requested),
                     "a newer copy of the same edit and original note satisfies the recovery write")
        precondition(!requested.confirmsDurableWrite(of: newer), "an older draft cannot satisfy a newer write")
        let differentContent = LibraryInlineNoteDraftSnapshot(
            recordID: newer.recordID, baseVersion: newer.baseVersion, draftVersion: 6,
            content: tableNote, updatedAt: .now, baseNoteDigest: originalNoteDigest
        )
        precondition(!differentContent.confirmsDurableWrite(of: requested),
                     "a newer draft containing a different note must survive the attempted save")
        let differentRecord = LibraryInlineNoteDraftSnapshot(
            recordID: "error-51", baseVersion: newer.baseVersion, draftVersion: 5,
            content: shortNote, updatedAt: .now, baseNoteDigest: originalNoteDigest
        )
        precondition(!differentRecord.confirmsDurableWrite(of: requested),
                     "a draft for another question cannot confirm this question's write")
        precondition(!newer.matchesBaseline(recordVersion: originalRecordVersion, noteDigest: "another-note"),
                     "an actual change to the saved note still conflicts")
        precondition(newer.matchesBaseline(
            recordVersion: newer.baseVersion.replacingOccurrences(of: "second:", with: "third:"), noteDigest: nil
        ), "a changed timestamp with the same record payload is safe")

        let legacyData = Data(#"{"recordID":"error-39","baseVersion":"legacy","draftVersion":3,"content":"<p>旧笔记</p>","updatedAt":0}"#.utf8)
        guard let legacy = try? JSONDecoder().decode(LibraryInlineNoteDraftSnapshot.self, from: legacyData) else {
            preconditionFailure("previously written recovery drafts must still decode")
        }
        precondition(legacy.baseNoteDigest == nil && legacy.matchesBaseline(recordVersion: "legacy", noteDigest: nil))
        precondition(!legacy.matchesBaseline(recordVersion: "different", noteDigest: originalNoteDigest))
    }

    private static func verifyMetadataRebaseWithTableNote() {
        let digest = String(repeating: "a", count: 64)
        let unrelatedPayloadDigest = String(repeating: "b", count: 64)
        let table = "<p>[[NATIVE_TABLE:eyJjZWxscyI6W1siQSJdXX0=]]</p>"
        let before: [String: Any] = ["note": table, "mastered": false]
        let latest: [String: Any] = ["note": table, "mastered": true]
        let expected = "previous-date:\(digest)"
        precondition(LibraryInlineNoteFinishPolicy.canRebaseMetadataChange(
            expectedVersion: expected,
            preparedBaseDigest: digest,
            preparedBaseNote: LibraryInlineNoteFinishPolicy.savedNote(in: before),
            latestSavedNote: LibraryInlineNoteFinishPolicy.savedNote(in: latest)
        ), "a metadata-only change must not block a table note save")
        precondition(!LibraryInlineNoteFinishPolicy.canRebaseMetadataChange(
            expectedVersion: expected,
            preparedBaseDigest: unrelatedPayloadDigest,
            preparedBaseNote: table,
            latestSavedNote: table
        ), "an unverifiable restored baseline must not be silently rewritten")
        precondition(!LibraryInlineNoteFinishPolicy.canRebaseMetadataChange(
            expectedVersion: expected,
            preparedBaseDigest: digest,
            preparedBaseNote: table,
            latestSavedNote: "<p>another editor changed the note</p>"
        ), "a real concurrent note change still conflicts")
        precondition(LibraryInlineNoteFinishPolicy.savedNote(in: ["note": "", "content": table]) == "",
                     "an explicitly blank note must not inherit stale legacy content")
        precondition(LibraryInlineNoteFinishPolicy.savedNote(in: ["errorNote": table]) == table,
                     "a legacy note is the comparison baseline when the official field is absent")
    }
}
