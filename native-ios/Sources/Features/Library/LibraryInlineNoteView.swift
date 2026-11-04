import SwiftData
import SwiftUI
import UIKit

private enum LibraryInlineNoteSaveError: LocalizedError {
    case invalidRecordPayload
    case versionConflict

    var errorDescription: String? {
        switch self {
        case .invalidRecordPayload:
            return "原题目数据无法解析，笔记未写入，也没有覆盖原记录。"
        case .versionConflict:
            return "题目记录已在其他位置更新；本地笔记草稿已保留，没有覆盖新记录。"
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
    private let writeNote: (String, LibraryInlineNotePreparedSave?, String, ModelContext) throws -> String
    private let currentRecordVersion: () -> String
    private let currentRecordPayload: () -> Data?
    private let recordCollection: String
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
    @State private var lastEnqueuedContent: String?
    @State private var activeBaseVersion = ""
    @State private var activeBasePayload: Data?
    @State private var restoredDraftVersion: UInt64 = 0
    @State private var didAttemptDraftRestoreForAppearance = false
    @State private var draftRestoreAppearanceID = UUID()
    @State private var isRestoringDraft = false
    @State private var finishCompletionsWaitingForRestore: [(Bool) -> Void] = []
    @State private var saveStatus: LibraryInlineNoteSaveStatus = .saved
    @State private var isFinishing = false
    @State private var preparedNote: PreparedLibraryInlineNote?
    @State private var errorMessage: String?
    @State private var displayWarning: String?
    @State private var editingInitialHTML: String?
    @State private var editingInitialAttributedText: NSAttributedString?
    @State private var initialSelectionOffset: Int?
    @State private var initialSelectionWidth: CGFloat?

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
        currentRecordVersion = {
            LibraryInlineNoteSaveService.versionKey(updatedAt: record.updatedAt, payload: record.payload)
        }
        currentRecordPayload = { record.payload }
        recordCollection = record.collection
        self.readNote = readNote ?? {
            let object = record.jsonObject ?? [:]
            if let note = object["note"] as? String { return note }
            return ["content", "errorNote", "analysis"].compactMap { object[$0] as? String }.first ?? ""
        }
        writeNote = { content, prepared, expectedVersion, modelContext in
            let currentVersion = LibraryInlineNoteSaveService.versionKey(
                updatedAt: record.updatedAt,
                payload: record.payload
            )
            guard currentVersion == expectedVersion else { throw LibraryInlineNoteSaveError.versionConflict }
            if let storedNote = record.jsonObject?["note"] as? String, storedNote == content {
                return currentVersion
            }
            guard let prepared, prepared.content == content else {
                throw LibraryInlineNoteSaveError.invalidRecordPayload
            }
            let previousPayload = record.payload
            let previousIndexPayload = record.indexPayload
            let previousUpdatedAt = record.updatedAt
            let wasAutosaveEnabled = modelContext.autosaveEnabled
            modelContext.autosaveEnabled = false
            defer { modelContext.autosaveEnabled = wasAutosaveEnabled }
            record.replacePayload(prepared.payload, indexPayload: prepared.indexPayload)
            record.updatedAt = prepared.updatedAt
            do {
                let contextSaveStart = ProcessInfo.processInfo.systemUptime
                try modelContext.save()
                LibraryPerformanceLog.markIfSlow(
                    "note.save.context bytes=\(prepared.payload.count)",
                    since: contextSaveStart
                )
                LibraryPerformanceLog.event(
                    "note.save.persisted id=\(LibraryPerformanceLog.shortIdentifier(record.compoundID)) beforeBytes=\(previousPayload.count) afterBytes=\(prepared.payload.count)"
                )
                return prepared.version
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
        currentRecordVersion = renderVersion
        currentRecordPayload = { nil }
        recordCollection = ""
        self.writeNote = { content, _, expectedVersion, modelContext in
            try writeNote(content, modelContext)
            return expectedVersion
        }
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
            }
            if editing {
                NativeRichTextEditor(
                    html: $draft,
                    minHeight: noteCanvasMinimumHeight,
                    documentStyle: true,
                    focusOnAppear: true,
                    initialSelectionOffset: initialSelectionOffset,
                    initialSelectionWidth: initialSelectionWidth,
                    preparedInitialHTML: editingInitialHTML,
                    preparedInitialAttributedText: editingInitialAttributedText,
                    editorSession: editorSession,
                    onEditingEnded: { finishEditing() }
                )
                .accessibilityIdentifier("library-inline-note-editor")
                .padding(.horizontal, 8)
            } else {
                if saveStatus != .saved && (draft != saved || errorMessage != nil) {
                    pendingDraftDisplay
                        .padding(.horizontal, 8)
                } else {
                    noteDisplay
                        .padding(.horizontal, 8)
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
            activeBaseVersion = currentRecordVersion()
            activeBasePayload = currentRecordPayload()
            guard !didAttemptDraftRestoreForAppearance else { return }
            didAttemptDraftRestoreForAppearance = true
            isRestoringDraft = true
            let appearanceID = draftRestoreAppearanceID
            LibraryInlineNoteSaveService.shared.whenIdle(recordID: renderDocumentID) { _ in
                Task { await restorePendingDraft(for: appearanceID) }
            }
        }
        .onChange(of: draft) { _, _ in
            guard editing, !isFinishing else { return }
            guard draft != lastEnqueuedContent else { return }
            guard draft != saved
                    || LibraryInlineNoteSaveService.shared.hasPending(recordID: renderDocumentID)
                    || saveStatus == .failed else {
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
            if latest != saved
                || LibraryInlineNoteSaveService.shared.hasPending(recordID: renderDocumentID)
                || saveStatus == .failed {
                enqueueSave(
                    latest,
                    preparedAttributedText: editorSession.latestAttributedText(),
                    requiresBackgroundTime: true
                )
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if editing { finishEditing { _ in } }
            session.setEditing(false)
            session.finishEditing = nil
            didAttemptDraftRestoreForAppearance = false
            draftRestoreAppearanceID = UUID()
            if isRestoringDraft {
                isRestoringDraft = false
                resolveFinishCompletionsWaitingForRestore(allowSuccess: false)
            }
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
                .contentShape(Rectangle())
                .onTapGesture {
                    beginEditing(
                        html: "",
                        snapshot: NSAttributedString(string: "", attributes: [.font: UIFont.systemFont(ofSize: 16)]),
                        selectionOffset: 0,
                        sourceWidth: nil
                    )
                }
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
                    },
                    onTapTextOffset: { offset, snapshot, width in
                        guard currentPreparedNote.editableAttributedText != nil else {
                            displayWarning = "笔记超出安全编辑范围，原内容已保留为只读。"
                            return
                        }
                        beginEditing(
                            html: storedNote,
                            snapshot: snapshot,
                            selectionOffset: offset,
                            sourceWidth: width
                        )
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
            if storedNote != draft {
                Label("题目当前保存内容", systemImage: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                NativeRichTextDisplay(
                    html: storedNote,
                    minHeight: min(noteCanvasMinimumHeight, 160),
                    accessibilityIdentifier: "library-inline-note-current-version"
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Divider()
            }
            Label("未保存草稿", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.warning)
            NativeRichTextDisplay(
                html: draft,
                minHeight: noteCanvasMinimumHeight,
                accessibilityIdentifier: "library-inline-note-pending-draft",
                onTapTextOffset: { offset, snapshot, width in
                    beginEditing(
                        html: draft,
                        snapshot: snapshot,
                        selectionOffset: offset,
                        sourceWidth: width
                    )
                }
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func beginEditing(
        html: String,
        snapshot: NSAttributedString,
        selectionOffset: Int,
        sourceWidth: CGFloat?
    ) {
        saved = storedNote
        activeBaseVersion = currentRecordVersion()
        activeBasePayload = currentRecordPayload()
        lastEnqueuedContent = nil
        draft = html
        editingInitialHTML = html
        editingInitialAttributedText = snapshot.copy() as? NSAttributedString ?? snapshot
        initialSelectionOffset = max(0, min(selectionOffset, snapshot.length))
        initialSelectionWidth = sourceWidth
        editing = true
        session.setEditing(true)
        errorMessage = nil
        displayWarning = nil
    }

    private func restorePendingDraft(for appearanceID: UUID) async {
        guard appearanceID == draftRestoreAppearanceID else { return }
        if LibraryInlineNoteSaveService.shared.hasPending(recordID: renderDocumentID) {
            LibraryInlineNoteSaveService.shared.whenIdle(recordID: renderDocumentID) { _ in
                Task { await restorePendingDraft(for: appearanceID) }
            }
            return
        }
        defer {
            if appearanceID == draftRestoreAppearanceID {
                isRestoringDraft = false
                resolveFinishCompletionsWaitingForRestore()
            }
        }
        do {
            guard let pending = try await LibraryInlineNoteDraftStorage.load(recordID: renderDocumentID) else { return }
            guard appearanceID == draftRestoreAppearanceID else { return }
            guard !editing else { return }
            if pending.content == storedNote {
                try await LibraryInlineNoteDraftStorage.removeIfContentMatches(
                    recordID: renderDocumentID,
                    content: pending.content
                )
                LibraryInlineNoteSaveService.shared.markExistingContentConfirmed(recordID: renderDocumentID)
                draft = storedNote
                saved = storedNote
                errorMessage = nil
                saveStatus = .saved
                return
            }

            saved = storedNote
            draft = pending.content
            activeBaseVersion = pending.baseVersion
            activeBasePayload = currentRecordPayload()
            restoredDraftVersion = pending.draftVersion
            errorMessage = "已恢复上次未完成的笔记草稿，正在尝试保存。"
            saveStatus = .saving
            enqueueSave(
                pending.content,
                baseVersion: pending.baseVersion,
                basePayload: activeBasePayload,
                atLeastDraftVersion: pending.draftVersion
            )
        } catch {
            guard appearanceID == draftRestoreAppearanceID else { return }
            errorMessage = "笔记草稿读取失败：\(error.localizedDescription)"
            saveStatus = .failed
        }
    }

    private func resolveFinishCompletionsWaitingForRestore(allowSuccess: Bool = true) {
        guard !isRestoringDraft, !finishCompletionsWaitingForRestore.isEmpty else { return }
        let completions = finishCompletionsWaitingForRestore
        finishCompletionsWaitingForRestore = []
        LibraryInlineNoteSaveService.shared.whenIdle(recordID: renderDocumentID) { saved in
            let canProceed = allowSuccess && saved && self.saveStatus != .failed
            completions.forEach { $0(canProceed) }
        }
    }

    private func finishWhenCurrentSaveSettles(_ completion: @escaping (Bool) -> Void) {
        if isRestoringDraft {
            finishCompletionsWaitingForRestore.append(completion)
            return
        }
        LibraryInlineNoteSaveService.shared.whenIdle(recordID: renderDocumentID) { saved in
            completion(saved && self.saveStatus != .failed)
        }
    }

    private func finishEditing(completion: @escaping (Bool) -> Void = { _ in }) {
        guard editing else {
            finishWhenCurrentSaveSettles(completion)
            return
        }
        guard !isFinishing else { completion(false); return }
        isFinishing = true
        saveTask?.cancel()
        editorSession.endEditing { latestHTML in
            let latestDraft = latestHTML ?? self.draft
            let latestAttributedText = self.editorSession.latestAttributedText()
            let hasQueuedSave = LibraryInlineNoteSaveService.shared.hasPending(recordID: self.renderDocumentID)
            let unchanged = latestDraft == self.saved && !hasQueuedSave && self.saveStatus != .failed
            self.draft = latestDraft
            self.editing = false
            self.session.setEditing(false)
            self.editingInitialHTML = nil
            self.editingInitialAttributedText = nil
            self.initialSelectionOffset = nil
            self.initialSelectionWidth = nil
            self.isFinishing = false
            if unchanged {
                self.saveStatus = .saved
                self.finishWhenCurrentSaveSettles(completion)
                return
            }
            self.enqueueSave(
                latestDraft,
                preparedAttributedText: latestAttributedText,
                onCompletion: { result in
                    switch result {
                    case .success: completion(true)
                    case .failure: completion(false)
                    }
                }
            )
        }
    }

    private func enqueueSave(
        _ content: String,
        preparedAttributedText: NSAttributedString? = nil,
        baseVersion: String? = nil,
        basePayload: Data? = nil,
        atLeastDraftVersion: UInt64? = nil,
        requiresBackgroundTime: Bool = false,
        onCompletion: ((Result<String, Error>) -> Void)? = nil
    ) {
        saveStatus = .saving
        errorMessage = nil
        let effectiveBaseVersion = baseVersion ?? activeBaseVersion
        let effectiveBasePayload = basePayload ?? activeBasePayload
        lastEnqueuedContent = content
        let revision = LibraryInlineNoteSaveService.shared.enqueue(
            recordID: renderDocumentID,
            baseVersion: effectiveBaseVersion,
            basePayload: effectiveBasePayload,
            collection: recordCollection,
            content: content,
            atLeastDraftVersion: atLeastDraftVersion ?? restoredDraftVersion,
            requiresBackgroundTime: requiresBackgroundTime,
            commit: { prepared, expectedVersion in
                try self.writeNote(content, prepared, expectedVersion, self.modelContext)
            },
            completion: { result in
                onCompletion?(result)
                switch result {
                case .success(let version):
                    self.saved = content
                    self.activeBaseVersion = version
                    self.activeBasePayload = self.currentRecordPayload()
                    self.errorMessage = nil
                    self.saveStatus = self.draft == content ? .saved : .saving
                    self.onSaved?(content)
                    if let attributedText = preparedAttributedText ?? self.editorSession.latestAttributedText() {
                        self.preparedNote = PreparedLibraryInlineNote(
                            key: self.noteRenderKey,
                            result: NativeRichTextDisplayRenderResult(
                                attributedText: attributedText.copy() as? NSAttributedString ?? attributedText,
                                usedSafeFallback: false
                            ),
                            editableAttributedText: attributedText.copy() as? NSAttributedString ?? attributedText
                        )
                    }
                case .failure(let error):
                    self.errorMessage = "笔记未保存，原记录未覆盖：\(error.localizedDescription)"
                    self.saveStatus = .failed
                }
            }
        )
        restoredDraftVersion = revision
    }
}
