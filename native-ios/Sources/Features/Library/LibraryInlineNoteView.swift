import SwiftData
import SwiftUI
import UIKit

private enum LibraryInlineNoteSaveError: LocalizedError {
    case invalidRecordPayload

    var errorDescription: String? {
        switch self {
        case .invalidRecordPayload:
            return "原题目数据无法解析，笔记未写入，也没有覆盖原记录。"
        }
    }
}

private enum LibraryInlineNoteSaveStatus: Equatable {
    case saved
    case saving
    case failed

    var title: String {
        switch self {
        case .saved: "已保存"
        case .saving: "保存中…"
        case .failed: "保存失败"
        }
    }

    var color: Color {
        switch self {
        case .saved: AppTheme.success
        case .saving: .secondary
        case .failed: AppTheme.danger
        }
    }
}

@MainActor
private final class LibraryInlineNotePendingDrafts {
    static let shared = LibraryInlineNotePendingDrafts()
    private var drafts: [String: String] = [:]

    func draft(for id: String) -> String? { drafts[id] }
    func save(_ draft: String, for id: String) { drafts[id] = draft }
    func remove(_ id: String) { drafts.removeValue(forKey: id) }
}

/// The parent can finish editing before entering drawing mode without observing every keystroke.
@MainActor
final class LibraryInlineNoteSession: ObservableObject {
    @Published private(set) var isEditing = false
    var finishEditing: ((@escaping (Bool) -> Void) -> Void)?

    func setEditing(_ value: Bool) {
        isEditing = value
    }

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
    let editableAttributedText: NSAttributedString?
}

@MainActor
struct LibraryInlineNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let readNote: () -> String
    private let writeNote: (String, ModelContext) throws -> Void
    private let onSaved: ((String) -> Void)?
    private let renderDocumentID: String
    private let renderVersion: () -> String
    let session: LibraryInlineNoteSession
    let title: String
    @StateObject private var editorSession = NativeRichTextEditorSession()
    @State private var editing = false
    @State private var draft = ""
    @State private var saved = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var persistTask: Task<Void, Never>?
    @State private var pendingSaveContent: String?
    @State private var pendingSaveAttributedText: NSAttributedString?
    @State private var saveStatus: LibraryInlineNoteSaveStatus = .saved
    @State private var isFinishing = false
    @State private var preparedNote: PreparedLibraryInlineNote?
    @State private var errorMessage: String?
    @State private var displayWarning: String?
    @State private var editingInitialHTML: String?
    @State private var editingInitialAttributedText: NSAttributedString?

    private let noteCanvasMinimumHeight: CGFloat = 360

    init(
        record: StoredRecord,
        session: LibraryInlineNoteSession,
        title: String = "错题笔记",
        readNote: (() -> String)? = nil,
        onSaved: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.title = title
        self.onSaved = onSaved
        renderDocumentID = record.compoundID
        renderVersion = { record.updatedAt.map { String($0.timeIntervalSince1970) } ?? "" }
        self.readNote = readNote ?? {
            let object = record.jsonObject ?? [:]
            if let note = object["note"] as? String { return note }
            return ["content", "errorNote", "analysis"].compactMap { object[$0] as? String }.first ?? ""
        }
        writeNote = { draft, modelContext in
            let payloadDecodeStart = ProcessInfo.processInfo.systemUptime
            guard var object = record.jsonObject else {
                LibraryPerformanceLog.event(
                    "note.save.invalid-payload id=\(LibraryPerformanceLog.shortIdentifier(record.compoundID)) bytes=\(record.payload.count)"
                )
                throw LibraryInlineNoteSaveError.invalidRecordPayload
            }
            LibraryPerformanceLog.markIfSlow(
                "note.save.decode bytes=\(record.payload.count)",
                since: payloadDecodeStart
            )
            object["note"] = draft
            object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            let payloadEncodeStart = ProcessInfo.processInfo.systemUptime
            let updatedPayload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            LibraryPerformanceLog.markIfSlow(
                "note.save.encode bytes=\(updatedPayload.count)",
                since: payloadEncodeStart
            )
            let previousPayload = record.payload
            let previousIndexPayload = record.indexPayload
            let previousUpdatedAt = record.updatedAt
            let wasAutosaveEnabled = modelContext.autosaveEnabled
            modelContext.autosaveEnabled = false
            defer { modelContext.autosaveEnabled = wasAutosaveEnabled }
            let indexRebuildStart = ProcessInfo.processInfo.systemUptime
            record.replacePayload(updatedPayload)
            LibraryPerformanceLog.markIfSlow(
                "note.save.index-rebuild bytes=\(updatedPayload.count)",
                since: indexRebuildStart
            )
            record.updatedAt = .now
            do {
                let contextSaveStart = ProcessInfo.processInfo.systemUptime
                try modelContext.save()
                LibraryPerformanceLog.markIfSlow(
                    "note.save.context bytes=\(updatedPayload.count)",
                    since: contextSaveStart
                )
                LibraryPerformanceLog.event(
                    "note.save.persisted id=\(LibraryPerformanceLog.shortIdentifier(record.compoundID)) beforeBytes=\(previousPayload.count) afterBytes=\(updatedPayload.count)"
                )
            } catch {
                record.payload = previousPayload
                record.indexPayload = previousIndexPayload
                record.updatedAt = previousUpdatedAt
                throw error
            }
        }
    }

    init(
        session: LibraryInlineNoteSession,
        title: String,
        readNote: @escaping () -> String,
        writeNote: @escaping (String, ModelContext) throws -> Void,
        renderDocumentID: String = "inline-note",
        renderVersion: @escaping () -> String = { "" },
        onSaved: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.title = title
        self.onSaved = onSaved
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
                Text(saveStatus.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(saveStatus.color)
                    .accessibilityIdentifier("library-inline-note-save-status")
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
                    preparedInitialHTML: editingInitialHTML,
                    preparedInitialAttributedText: editingInitialAttributedText,
                    editorSession: editorSession
                )
                .accessibilityIdentifier("library-inline-note-editor")
                .padding(.horizontal, 8)
            } else {
                if saveStatus != .saved && draft != saved {
                    pendingDraftDisplay
                        .padding(.horizontal, 8)
                } else {
                    noteDisplay
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard storedNote.isEmpty || currentPreparedNote?.editableAttributedText != nil else {
                                displayWarning = "笔记超出安全编辑范围，原内容已保留为只读。"
                                return
                            }
                            draft = storedNote
                            saved = draft
                            editingInitialHTML = storedNote
                            editingInitialAttributedText = currentPreparedNote?.editableAttributedText
                                ?? NSAttributedString(string: "")
                            editing = true
                            session.setEditing(true)
                            displayWarning = nil
                        }
                }
            }
            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试保存") { enqueueSave(draft, preparedAttributedText: editorSession.latestAttributedText()) }
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
        .onAppear {
            session.finishEditing = { completion in finishEditing(completion: completion) }
            saved = storedNote
            if let pendingDraft = LibraryInlineNotePendingDrafts.shared.draft(for: renderDocumentID), pendingDraft != storedNote {
                draft = pendingDraft
                errorMessage = "上次笔记保存未完成，草稿已保留。"
                saveStatus = .failed
            }
        }
        .onChange(of: draft) { _, _ in
            guard editing, !isFinishing else { return }
            guard draft != saved else {
                saveTask?.cancel()
                saveStatus = .saved
                errorMessage = nil
                return
            }
            saveStatus = .saving
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(1_400)) } catch { return }
                enqueueSave(draft)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            saveTask?.cancel()
            let latest = editorSession.latestHTML() ?? draft
            if latest != draft { draft = latest }
            enqueueSave(latest, preparedAttributedText: editorSession.latestAttributedText())
        }
        .onDisappear {
            saveTask?.cancel()
            if editing { finishEditing { _ in } }
            session.setEditing(false)
            session.finishEditing = nil
        }
        .task(id: LibraryInlineNotePreparationKey(note: noteRenderKey, isEditing: editing)) {
            let key = noteRenderKey
            await prepareNote(for: key)
        }
    }

    @MainActor
    private func prepareNote(for key: LibraryInlineNoteRenderKey) async {
        guard !editing, !key.html.isEmpty else { return }
        if let preparedNote,
           preparedNote.key.documentID == key.documentID,
           preparedNote.key.html == key.html {
            self.preparedNote = PreparedLibraryInlineNote(
                key: key,
                result: preparedNote.result,
                editableAttributedText: preparedNote.editableAttributedText
            )
            return
        }
        let result = NativeRichTextDisplayRenderer.render(key.html)
        let editableAttributedText: NSAttributedString?
        if result.usedSafeFallback {
            let html = key.html
            let runs = await Task.detached(priority: .utility) {
                NativeRichTextFallbackParser.parseForEditing(html)
            }.value
            guard !Task.isCancelled else { return }
            editableAttributedText = runs.flatMap {
                NativeRichTextDisplayRenderer.editableAttributedText(from: $0)
            }
        } else {
            editableAttributedText = result.attributedText.copy() as? NSAttributedString ?? result.attributedText
        }
        guard !Task.isCancelled, !editing, key == noteRenderKey else { return }
        let displayResult: NativeRichTextDisplayRenderResult
        if result.usedSafeFallback, let editableAttributedText {
            displayResult = NativeRichTextDisplayRenderResult(
                attributedText: editableAttributedText,
                usedSafeFallback: true
            )
        } else {
            displayResult = result
        }
        preparedNote = PreparedLibraryInlineNote(
            key: key,
            result: displayResult,
            editableAttributedText: editableAttributedText
        )
        if result.usedSafeFallback, editableAttributedText == nil {
            displayWarning = "预览已降级；笔记过长或含有未闭合附件，当前仅保留原内容并以只读方式显示。"
        }
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
                    onFallback: {
                        displayWarning = currentPreparedNote.editableAttributedText == nil
                            ? "预览已降级；笔记过长或含有未闭合附件，当前仅保留原内容并以只读方式显示。"
                            : "预览已切换为安全模式；编辑时会保留正文和已有附件。"
                    }
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

    private var pendingDraftDisplay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("未保存草稿", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.warning)
            NativeRichTextDisplay(
                html: draft,
                minHeight: noteCanvasMinimumHeight,
                accessibilityIdentifier: "library-inline-note-pending-draft"
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func finishEditing(completion: @escaping (Bool) -> Void = { _ in }) {
        guard editing else { completion(true); return }
        guard !isFinishing else { completion(false); return }
        isFinishing = true
        saveTask?.cancel()
        editorSession.endEditing { latestHTML in
            let latestDraft = latestHTML ?? self.draft
            let latestAttributedText = self.editorSession.latestAttributedText()
            let baselineAttributedText = self.editingInitialAttributedText ?? NSAttributedString(string: "")
            let unchanged = latestAttributedText?.isEqual(to: baselineAttributedText) == true
                || latestDraft == self.saved
            self.draft = latestDraft
            self.editing = false
            self.session.setEditing(false)
            self.editingInitialHTML = nil
            self.editingInitialAttributedText = nil
            self.isFinishing = false
            if unchanged {
                self.draft = self.saved
                self.saveStatus = .saved
                completion(true)
                return
            }
            self.enqueueSave(latestDraft, preparedAttributedText: latestAttributedText)
            completion(true)
        }
    }

    private func enqueueSave(
        _ content: String,
        preparedAttributedText: NSAttributedString? = nil
    ) {
        if content == saved {
            pendingSaveContent = nil
            pendingSaveAttributedText = nil
            if persistTask == nil { saveStatus = .saved }
            return
        }
        pendingSaveContent = content
        pendingSaveAttributedText = preparedAttributedText
        saveStatus = .saving
        errorMessage = nil
        guard persistTask == nil else { return }
        persistTask = Task { @MainActor in
            await Task.yield()
            while !Task.isCancelled, let content = self.pendingSaveContent {
                let attributedText = self.pendingSaveAttributedText
                self.pendingSaveContent = nil
                self.pendingSaveAttributedText = nil
                guard self.persist(content, preparedAttributedText: attributedText) else {
                    self.persistTask = nil
                    return
                }
            }
            if self.pendingSaveContent == nil, self.draft == self.saved {
                self.saveStatus = .saved
            }
            self.persistTask = nil
        }
    }

    @discardableResult private func persist(
        _ content: String,
        preparedAttributedText: NSAttributedString? = nil
    ) -> Bool {
        guard content != saved else {
            saveStatus = .saved
            LibraryInlineNotePendingDrafts.shared.remove(renderDocumentID)
            return true
        }
        do {
            try writeNote(content, modelContext)
            saved = content
            errorMessage = nil
            saveStatus = .saved
            LibraryInlineNotePendingDrafts.shared.remove(renderDocumentID)
            onSaved?(content)
            if let attributedText = preparedAttributedText ?? editorSession.latestAttributedText() {
                preparedNote = PreparedLibraryInlineNote(
                    key: noteRenderKey,
                    result: NativeRichTextDisplayRenderResult(
                        attributedText: attributedText.copy() as? NSAttributedString ?? attributedText,
                        usedSafeFallback: false
                    ),
                    editableAttributedText: attributedText.copy() as? NSAttributedString ?? attributedText
                )
            }
            return true
        } catch {
            errorMessage = "笔记未保存，原内容未更改：\(error.localizedDescription)"
            draft = content
            saveStatus = .failed
            LibraryInlineNotePendingDrafts.shared.save(content, for: renderDocumentID)
            return false
        }
    }
}
