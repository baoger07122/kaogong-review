import SwiftData
import SwiftUI
import UIKit

/// The parent can finish editing before entering drawing mode without observing every keystroke.
@MainActor
final class LibraryInlineNoteSession: ObservableObject {
    var finishEditing: ((@escaping (Bool) -> Void) -> Void)?

    func finish(completion: @escaping (Bool) -> Void) {
        guard let finishEditing else { completion(true); return }
        finishEditing(completion)
    }
}

private struct LibraryInlineNoteRenderKey: Equatable {
    let documentID: String
    let version: String
    let html: String

    var rendererVersion: String {
        "\(documentID)|\(version)|\(html.utf8.count)|\(html.hashValue)"
    }
}

private struct LibraryInlineNotePreparationKey: Equatable {
    let note: LibraryInlineNoteRenderKey
    let isEditing: Bool
}

@MainActor
private struct PreparedLibraryInlineNote {
    let key: LibraryInlineNoteRenderKey
    let result: NativeRichTextDisplayRenderResult
}

@MainActor
struct LibraryInlineNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let readNote: () -> String
    private let writeNote: (String, ModelContext) throws -> Void
    private let renderDocumentID: String
    private let renderVersion: () -> String
    let session: LibraryInlineNoteSession
    let title: String
    @StateObject private var editorSession = NativeRichTextEditorSession()
    @State private var editing = false
    @State private var draft = ""
    @State private var saved = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isFinishing = false
    @State private var preparedNote: PreparedLibraryInlineNote?
    @State private var errorMessage: String?
    @State private var displayWarning: String?

    private let noteCanvasMinimumHeight: CGFloat = 360

    init(record: StoredRecord, session: LibraryInlineNoteSession, title: String = "错题笔记") {
        self.session = session
        self.title = title
        renderDocumentID = record.compoundID
        renderVersion = { record.updatedAt.map { String($0.timeIntervalSince1970) } ?? "" }
        readNote = {
            let object = record.jsonObject ?? [:]
            if let note = object["note"] as? String { return note }
            return ["content", "errorNote", "analysis"].compactMap { object[$0] as? String }.first ?? ""
        }
        writeNote = { draft, modelContext in
            var object = record.jsonObject ?? [:]
            object["note"] = draft
            object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.updatedAt = .now
            try modelContext.save()
        }
    }

    init(
        session: LibraryInlineNoteSession,
        title: String,
        readNote: @escaping () -> String,
        writeNote: @escaping (String, ModelContext) throws -> Void,
        renderDocumentID: String = "inline-note",
        renderVersion: @escaping () -> String = { "" }
    ) {
        self.session = session
        self.title = title
        self.renderDocumentID = renderDocumentID
        self.renderVersion = renderVersion
        self.readNote = readNote
        self.writeNote = writeNote
    }

    private var storedNote: String { readNote() }

    private var noteRenderKey: LibraryInlineNoteRenderKey {
        let version = questionBankContextVersion
        return LibraryInlineNoteRenderKey(
            documentID: renderDocumentID,
            version: version,
            html: storedNote
        )
    }

    private var questionBankContextVersion: String {
        "\(renderVersion())|\(storedNote.utf8.count)"
    }

    private var currentPreparedNote: PreparedLibraryInlineNote? {
        guard preparedNote?.key == noteRenderKey else { return nil }
        return preparedNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "note.text")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if editing {
                    Button("完成") { finishEditing() }
                        .font(.system(size: 12))
                        .accessibilityIdentifier("library-inline-note-finish")
                }
            }
            if editing {
                NativeRichTextEditor(
                    html: $draft,
                    minHeight: noteCanvasMinimumHeight,
                    documentStyle: true,
                    focusOnAppear: true,
                    preparedInitialHTML: currentPreparedNote?.key.html,
                    preparedInitialAttributedText: currentPreparedNote?.result.attributedText,
                    editorSession: editorSession
                )
                .accessibilityIdentifier("library-inline-note-editor")
                .padding(.horizontal, 8)
            } else {
                noteDisplay
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard storedNote.isEmpty || currentPreparedNote.map({ !$0.result.usedSafeFallback }) == true else { return }
                        draft = storedNote
                        saved = draft
                        editing = true
                    }
            }
            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试保存") { save() }
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
            } else if let displayWarning, !editing {
                Text(displayWarning)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { session.finishEditing = { completion in finishEditing(completion: completion) } }
        .onChange(of: draft) { _, _ in
            guard editing, !isFinishing else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(1_400)) } catch { return }
                save()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            saveTask?.cancel()
            let latest = editorSession.latestHTML() ?? draft
            if latest != draft { draft = latest }
            _ = save(latest)
        }
        .onDisappear {
            saveTask?.cancel()
            if editing { finishEditing { _ in } }
            session.finishEditing = nil
        }
        .task(id: LibraryInlineNotePreparationKey(note: noteRenderKey, isEditing: editing)) {
            let key = noteRenderKey
            await prepareNote(for: key)
        }
    }

    @MainActor
    private func prepareNote(for key: LibraryInlineNoteRenderKey) {
        guard !editing, !key.html.isEmpty else { return }
        let result = NativeRichTextDisplayRenderer.render(key.html)
        guard !Task.isCancelled, !editing, key == noteRenderKey else { return }
        preparedNote = PreparedLibraryInlineNote(key: key, result: result)
    }

    @ViewBuilder private var noteDisplay: some View {
        if storedNote.isEmpty {
            Text("点击添加错题笔记")
                .font(AppTheme.noteBodyFont)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: noteCanvasMinimumHeight, alignment: .topLeading)
        } else {
            if let currentPreparedNote {
                NativeRichTextDisplay(
                    html: storedNote,
                    preparedSnapshot: currentPreparedNote.result,
                    renderVersion: currentPreparedNote.key.rendererVersion,
                    minHeight: noteCanvasMinimumHeight,
                    accessibilityIdentifier: "library-inline-note-display",
                    onFallback: { displayWarning = "富文本预览已降级，原笔记完整保留；当前不能编辑此笔记" }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text("笔记正在准备显示…")
                    .font(AppTheme.noteBodyFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: noteCanvasMinimumHeight, alignment: .topLeading)
                    .accessibilityIdentifier("library-inline-note-display-loading")
            }
        }
    }

    private func finishEditing(completion: @escaping (Bool) -> Void = { _ in }) {
        guard editing else { completion(true); return }
        guard !isFinishing else { completion(false); return }
        isFinishing = true
        saveTask?.cancel()
        editorSession.endEditing { latestHTML in
            let latestDraft = latestHTML ?? self.draft
            self.draft = latestDraft
            guard self.save(latestDraft) else {
                self.isFinishing = false
                completion(false)
                return
            }
            self.editing = false
            self.isFinishing = false
            completion(true)
        }
    }

    @discardableResult private func save(_ content: String? = nil) -> Bool {
        guard editing else { return true }
        let content = content ?? draft
        guard content != saved else { return true }
        do {
            try writeNote(content, modelContext)
            saved = content
            errorMessage = nil
            return true
        } catch {
            errorMessage = "笔记未保存，原内容未更改：\(error.localizedDescription)"
            return false
        }
    }
}
