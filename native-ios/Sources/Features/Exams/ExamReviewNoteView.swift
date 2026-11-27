import SwiftData
import SwiftUI

@MainActor
final class ExamReviewNoteDrafts {
    struct Draft: Equatable {
        let original: ExamReviewNote
        var note: ExamReviewNote
    }

    var drafts: [String: Draft] = [:]
}

struct ExamReviewNoteContent: View {
    let note: ExamReviewNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if note.bodyPreview != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本套表现").font(.system(size: 13, weight: .semibold))
                    NativeRichTextDisplay(html: note.html, tableAppearance: .libraryContent)
                }
            }
            if !note.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下次怎么改")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(note.nextAction)
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct ExamReviewNoteCard: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session = NativeRichTextEditorSession()
    @State private var sessionID = UUID()
    @State private var edit: ExamReviewNoteDrafts.Draft?
    @State private var errorMessage: String?
    @State private var saved = false
    let record: StoredRecord
    let note: ExamReviewNote
    let padding: CGFloat
    let drafts: ExamReviewNoteDrafts

    init(record: StoredRecord, note: ExamReviewNote, padding: CGFloat, drafts: ExamReviewNoteDrafts) {
        self.record = record
        self.note = note
        self.padding = padding
        self.drafts = drafts
        _edit = State(initialValue: drafts.drafts[record.recordID])
    }

    var body: some View {
        let hasNote = note.summary != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("复盘备注")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if edit == nil {
                    Button(hasNote ? "编辑备注" : "写备注", action: beginEditing)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("exam-review-note-edit")
                }
            }
            if let edit {
                noteForm(edit.note)
            } else if hasNote {
                ExamReviewNoteContent(note: note)
            } else {
                Text("还没有复盘备注")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.warning)
            } else if saved {
                Text("备注已保存")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard(padding: padding)
        .onChange(of: edit) { _, draft in drafts.drafts[record.recordID] = draft }
        .onDisappear {
            if let snapshot = session.captureSnapshot(), snapshot.userEditRevision > 0 {
                edit?.note.html = snapshot.html
            }
            drafts.drafts[record.recordID] = edit
        }
    }

    private func noteForm(_ startingNote: ExamReviewNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("本套表现")
            NativeRichTextEditor(
                html: Binding(
                    get: { edit?.note.html ?? startingNote.html },
                    set: { edit?.note.html = $0 }
                ),
                minHeight: 84,
                tableAppearance: .libraryContent,
                editorSession: session,
                editorDocumentID: "exam-review:\(record.recordID)",
                editorSessionID: sessionID,
                defersPhotoPickerToParent: false
            )
            .accessibilityIdentifier("exam-review-note-body")

            fieldLabel("下次怎么改")
            TextField(
                "写一个下次做卷可以执行的调整",
                text: Binding(
                    get: { edit?.note.nextAction ?? startingNote.nextAction },
                    set: { edit?.note.nextAction = $0 }
                ),
                axis: .vertical
            )
            .font(.system(size: 15))
            .lineLimit(2...8)
            .padding(8)
            .background(AppTheme.groupedBackground, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("exam-review-note-next-action")

            HStack {
                Spacer()
                Button("取消", action: cancelEditing)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                Button(action: save) {
                    Text("保存备注")
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exam-review-note-save")
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
    }

    private func beginEditing() {
        sessionID = UUID()
        edit = .init(original: note, note: note)
        saved = false
        errorMessage = nil
    }

    private func cancelEditing() {
        edit = nil
        drafts.drafts[record.recordID] = nil
        errorMessage = nil
    }

    private func save() {
        guard var draft = edit else { return }
        session.commitCompositionIfNeeded()
        guard session.canFinishEditing else {
            errorMessage = "请完成当前输入或附件操作后再保存。"
            return
        }
        if let snapshot = session.captureSnapshot(), snapshot.userEditRevision > 0 {
            draft.note.html = snapshot.html
        }
        draft.note.nextAction = draft.note.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        edit = draft
        do {
            try ExamRepository.saveReviewNote(draft.note, replacing: draft.original, in: record, context: modelContext)
            edit = nil
            drafts.drafts[record.recordID] = nil
            errorMessage = nil
            saved = true
        } catch {
            errorMessage = "保存失败。\(error.localizedDescription)"
        }
    }
}
