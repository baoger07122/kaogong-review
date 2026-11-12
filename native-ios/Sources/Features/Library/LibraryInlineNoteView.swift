import SwiftData
import SwiftUI
import UIKit
import PhotosUI

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

private enum LibraryInlineNotePhotoError: LocalizedError {
    case noData
    case loadFailed(String)
    case tooLarge
    case decodeFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .noData: "相册没有返回图片数据。"
        case .loadFailed(let message): "读取图片失败：\(message)"
        case .tooLarge: "图片超过笔记允许的大小，请选择较小的图片。"
        case .decodeFailed: "无法识别所选图片。"
        case .encodeFailed: "图片压缩失败，请换一张图片重试。"
        }
    }
}

private enum LibraryInlineNoteSaveStatus: Equatable {
    case saved
    case debouncing
    case queued
    case writing
    case failed

    var title: String {
        switch self {
        case .saved: "已保存"
        case .debouncing: "等待保存…"
        case .queued: "等待写入…"
        case .writing: "保存中…"
        case .failed: "保存失败"
        }
    }

    var color: Color {
        switch self {
        case .saved: AppTheme.success
        case .debouncing, .queued, .writing: .secondary
        case .failed: AppTheme.danger
        }
    }
}

/// The parent can finish editing before entering drawing mode without observing every keystroke.
@MainActor
final class LibraryInlineNoteSession: ObservableObject {
    @Published private(set) var isEditing = false
    @Published private(set) var hasPendingChanges = false
    @Published private(set) var finishFailureMessage: String?
    var finishEditing: ((@escaping (Bool) -> Void) -> Void)?
    private(set) weak var noteAnchorView: UIView?
    private var focusRevealSessionID: UUID?
    private var keyboardShowObserver: NSObjectProtocol?

    func setNoteAnchor(_ view: UIView?) { noteAnchorView = view }

    func setEditing(_ value: Bool) {
        isEditing = value
        if value { hasPendingChanges = true }
        else { resetFocusReveal() }
    }

    func resetFocusReveal() {
        focusRevealSessionID = nil
        if let keyboardShowObserver {
            NotificationCenter.default.removeObserver(keyboardShowObserver)
            self.keyboardShowObserver = nil
        }
    }

    func revealWritableArea(in textView: UITextView, sessionID: UUID) {
        guard focusRevealSessionID != sessionID else { return }
        focusRevealSessionID = sessionID
        revealWritableAreaNow(in: textView, sessionID: sessionID)

        guard let window = textView.window,
              window.keyboardLayoutGuide.layoutFrame.height < 80,
              textView.inputAccessoryView?.window == nil else { return }
        keyboardShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak textView] _ in
            guard let self, let textView else { return }
            Task { @MainActor in
                self.revealWritableAreaNow(in: textView, sessionID: sessionID)
                self.resetKeyboardObserver()
            }
        }
    }

    private func revealWritableAreaNow(in textView: UITextView, sessionID: UUID) {
        guard focusRevealSessionID == sessionID,
              let window = textView.window,
              let anchor = noteAnchorView,
              anchor.window === window else { return }

        window.layoutIfNeeded()
        var ancestor = textView.superview
        var outerScrollView: UIScrollView?
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                outerScrollView = scrollView
                break
            }
            ancestor = view.superview
        }
        guard let scrollView = outerScrollView else { return }
        scrollView.layoutIfNeeded()

        let viewport = scrollView.convert(scrollView.bounds, to: window)
        var visibleBottom = viewport.maxY - scrollView.adjustedContentInset.bottom
        let keyboardFrame = window.keyboardLayoutGuide.layoutFrame
        if keyboardFrame.height > 80, keyboardFrame.minY < visibleBottom {
            visibleBottom = keyboardFrame.minY
        }
        if let accessory = textView.inputAccessoryView, accessory.window === window {
            let accessoryFrame = accessory.convert(accessory.bounds, to: window)
            if accessoryFrame.height > 0, accessoryFrame.minY < visibleBottom {
                visibleBottom = accessoryFrame.minY
            }
        }

        let position = textView.selectedTextRange?.end ?? textView.endOfDocument
        let caret = textView.convert(textView.caretRect(for: position), to: window)
        let visibleHeight = max(1, visibleBottom - viewport.minY)
        let writingSpace = min(160, max(48, visibleHeight * 0.42))
        let neededDelta = max(0, caret.maxY + writingSpace - visibleBottom)
        guard neededDelta > 1 else { return }

        let noteTop = anchor.convert(anchor.bounds, to: window).minY
        let titlePreservingDelta = max(0, noteTop - viewport.minY - 20)
        let maximumOffset = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let scrollCapacity = max(0, maximumOffset - scrollView.contentOffset.y)
        let delta = min(neededDelta, titlePreservingDelta, scrollCapacity)
        guard delta > 1 else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + delta),
            animated: true
        )
    }

    private func resetKeyboardObserver() {
        guard let keyboardShowObserver else { return }
        NotificationCenter.default.removeObserver(keyboardShowObserver)
        self.keyboardShowObserver = nil
    }

    func setPendingChanges(_ value: Bool) {
        hasPendingChanges = value
    }

    func setFinishFailureMessage(_ value: String?) {
        finishFailureMessage = value
    }

    func finish(completion: @escaping (Bool) -> Void) {
        guard isEditing || hasPendingChanges else {
            finishFailureMessage = nil
            completion(true)
            return
        }
        guard let finishEditing else {
            finishFailureMessage = "笔记仍有未完成的保存，暂时无法离开。"
            completion(false)
            return
        }
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
    let editorDocumentRevision: UInt64?
}

@MainActor
struct LibraryInlineNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var saveService = LibraryInlineNoteSaveService.shared
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
    @State private var saveTask: Task<Void, Never>?
    @State private var currentDraftVersion: UInt64?
    @State private var activeBaseVersion = ""
    @State private var activeBasePayload: Data?
    @State private var editingSessionID = UUID()
    @State private var didAttemptDraftRestoreForAppearance = false
    @State private var draftRestoreAppearanceID = UUID()
    @State private var isRestoringDraft = false
    @State private var suppressNextDraftChange = false
    @State private var finishCompletionsWaitingForRestore: [(Bool) -> Void] = []
    @State private var finishCompletionsWaitingForCommit: [(Bool) -> Void] = []
    @State private var isFinishing = false
    @State private var preparedNote: PreparedLibraryInlineNote?
    @State private var transientErrorMessage: String?
    @State private var displayWarning: String?
    @State private var editingInitialHTML: String?
    @State private var editingInitialAttributedText: NSAttributedString?
    @State private var initialSelectionOffset: Int?
    @State private var initialSelectionWidth: CGFloat?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var photoImportTarget: NativeRichTextInsertionTarget?
    @State private var photoImportRequestID: UUID?
    @State private var photoLoadTask: Task<Void, Never>?

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

    private var noteSaveState: LibraryInlineNoteRecordSaveState {
        saveService.state(recordID: renderDocumentID)
    }

    private var hasPendingDraft: Bool {
        noteSaveState.latestContent != noteSaveState.confirmedContent || noteSaveState.phase == .failed
    }

    private var saveStatus: LibraryInlineNoteSaveStatus {
        switch noteSaveState.phase {
        case .idle, .saved: .saved
        case .debouncing: .debouncing
        case .queued: .queued
        case .writing: .writing
        case .failed: .failed
        }
    }

    private var errorMessage: String? {
        if let transientErrorMessage { return transientErrorMessage }
        if let saveError = noteSaveState.errorMessage { return saveError }
        guard let notice = editorSession.mediaNotice, notice.documentID == renderDocumentID else { return nil }
        return notice.message
    }

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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .disabled(isFinishing || !editorSession.canFinishEditing)
                        .accessibilityIdentifier("library-inline-note-done")
                }
            }
            .background(alignment: .topLeading) {
                LibraryInlineNoteAnchor(session: session)
                    .frame(width: 1, height: 1)
            }
            if editing {
                NativeRichTextEditor(
                    html: $draft,
                    minHeight: noteCanvasMinimumHeight,
                    documentStyle: true,
                    noteFormatting: true,
                    focusOnAppear: true,
                    initialSelectionOffset: initialSelectionOffset,
                    initialSelectionWidth: initialSelectionWidth,
                    preparedInitialHTML: editingInitialHTML,
                    preparedInitialAttributedText: editingInitialAttributedText,
                    editorSession: editorSession,
                    editorDocumentID: renderDocumentID,
                    editorSessionID: editingSessionID,
                    onFocusReady: { textView in
                        session.revealWritableArea(in: textView, sessionID: editingSessionID)
                    }
                )
                .accessibilityIdentifier("library-inline-note-editor")
                .padding(.horizontal, 8)
            } else {
                if hasPendingDraft || errorMessage != nil {
                    pendingDraftDisplay
                        .padding(.horizontal, 8)
                } else {
                    noteDisplay
                        .padding(.horizontal, 8)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .fixedSize(horizontal: false, vertical: true)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
            } else if let displayWarning, !editing {
                Text(displayWarning)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .onChange(of: editorSession.imageImportRequest) { _, _ in advanceImageImportRequest() }
        .onChange(of: editorSession.isComposingText) { _, isComposing in
            if !isComposing { advanceImageImportRequest() }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            photoLoadTask?.cancel()
            photoLoadTask = Task { @MainActor in await loadAndInsertPhoto(item) }
        }
        .onChange(of: isPhotoPickerPresented) { _, presented in
            guard !presented else { return }
            Task { @MainActor in
                await Task.yield()
                guard !isPhotoPickerPresented, selectedPhoto == nil,
                      let requestID = photoImportRequestID else { return }
                finishImageImport(requestID: requestID)
            }
        }
        .onAppear {
            session.finishEditing = { completion in finishEditing(completion: completion) }
            saveService.markExistingContentConfirmed(
                recordID: renderDocumentID,
                content: storedNote,
                recordVersion: currentRecordVersion(),
                payload: currentRecordPayload()
            )
            let state = saveService.state(recordID: renderDocumentID)
            activeBaseVersion = state.latestBaseVersion ?? currentRecordVersion()
            activeBasePayload = state.latestBasePayload ?? currentRecordPayload()
            if state.latestContent != state.confirmedContent || state.phase == .failed {
                setDraftWithoutScheduling(state.latestContent)
                currentDraftVersion = state.latestDraftVersion
            } else {
                setDraftWithoutScheduling(storedNote)
            }
            updateSessionPendingState()
            guard !didAttemptDraftRestoreForAppearance else { return }
            didAttemptDraftRestoreForAppearance = true
            isRestoringDraft = true
            session.setPendingChanges(true)
            let appearanceID = draftRestoreAppearanceID
            LibraryInlineNoteSaveService.shared.whenIdle(recordID: renderDocumentID) { _ in
                Task { await restorePendingDraft(for: appearanceID) }
            }
        }
        .onChange(of: draft) { _, _ in
            if suppressNextDraftChange {
                suppressNextDraftChange = false
                return
            }
            guard editing, !isFinishing, !isRestoringDraft else { return }
            saveTask?.cancel()
            let content = draft
            let version = saveService.registerDraft(
                recordID: renderDocumentID,
                content: content,
                baseVersion: activeBaseVersion,
                basePayload: activeBasePayload
            )
            currentDraftVersion = version
            let state = saveService.state(recordID: renderDocumentID)
            updateSessionPendingState()
            guard state.phase != .saved || content != state.confirmedContent else {
                transientErrorMessage = nil
                return
            }
            saveService.markDebouncing(recordID: renderDocumentID, draftVersion: version)
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(1_400)) } catch { return }
                guard !Task.isCancelled,
                      self.editing,
                      !self.isFinishing,
                      self.draft == content,
                      self.saveService.state(recordID: self.renderDocumentID).latestDraftVersion == version else { return }
                guard !self.editorSession.isComposingText else { return }
                let snapshot = self.editorSession.captureSnapshot()
                guard let snapshot else { return }
                let latestContent = snapshot.html
                let latestVersion: UInt64
                if latestContent == content {
                    latestVersion = version
                } else {
                    self.setDraftWithoutScheduling(latestContent)
                    latestVersion = self.saveService.registerDraft(
                        recordID: self.renderDocumentID,
                        content: latestContent,
                        baseVersion: self.activeBaseVersion,
                        basePayload: self.activeBasePayload
                    )
                    self.currentDraftVersion = latestVersion
                }
                self.enqueueSave(
                    latestContent,
                    draftVersion: latestVersion,
                    editorSnapshot: snapshot
                )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            saveTask?.cancel()
            guard !editorSession.isMediaOperationInProgress else { return }
            editorSession.commitCompositionIfNeeded()
            let snapshot = editorSession.isComposingText ? nil : editorSession.captureSnapshot()
            let latest = snapshot?.html ?? draft
            if latest != draft { setDraftWithoutScheduling(latest) }
            let state = saveService.state(recordID: renderDocumentID)
            if latest != state.confirmedContent || saveService.hasPending(recordID: renderDocumentID) || state.phase == .failed {
                let version = saveService.registerDraft(
                    recordID: renderDocumentID,
                    content: latest,
                    baseVersion: activeBaseVersion,
                    basePayload: activeBasePayload
                )
                currentDraftVersion = version
                enqueueSave(
                    latest,
                    draftVersion: version,
                    editorSnapshot: snapshot,
                    requiresBackgroundTime: true
                )
            }
        }
        .onDisappear {
            saveTask?.cancel()
            photoLoadTask?.cancel()
            if editorSession.isMediaOperationInProgress {
                editorSession.cancelMediaOperation(
                    sessionID: editingSessionID,
                    message: "切换题目时已取消图片插入，没有把图片写入其他题目。"
                )
            }
            if let requestID = photoImportRequestID {
                finishImageImport(requestID: requestID)
            }
            isPhotoPickerPresented = false
            if editing {
                editorSession.commitCompositionIfNeeded()
                let snapshot = editorSession.captureSnapshot()
                let latest = snapshot?.html ?? draft
                let version = saveService.registerDraft(
                    recordID: renderDocumentID,
                    content: latest,
                    baseVersion: activeBaseVersion,
                    basePayload: activeBasePayload
                )
                currentDraftVersion = version
                if latest != saveService.state(recordID: renderDocumentID).confirmedContent
                    || saveService.state(recordID: renderDocumentID).phase == .failed {
                    enqueueSave(
                        latest,
                        draftVersion: version,
                        editorSnapshot: snapshot,
                        requiresBackgroundTime: true
                    )
                }
                editorSession.deactivate(sessionID: editingSessionID)
            }
            session.setEditing(false)
            updateSessionPendingState()
            session.finishEditing = nil
            didAttemptDraftRestoreForAppearance = false
            draftRestoreAppearanceID = UUID()
            if isRestoringDraft {
                isRestoringDraft = false
                updateSessionPendingState()
                resolveFinishCompletionsWaitingForRestore(allowSuccess: false)
            }
        }
        .task(id: LibraryInlineNotePreparationKey(note: noteRenderKey, isEditing: editing)) {
            let key = noteRenderKey
            await prepareNote(for: key)
        }
        .onChange(of: noteSaveState) { _, _ in updateSessionPendingState() }
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
                editableAttributedText: preparedNote.editableAttributedText,
                editorDocumentRevision: preparedNote.editorDocumentRevision
            )
            return
        }
        let result = NativeRichTextDisplayRenderer.render(key.html, noteFormatting: true)
        let editableAttributedText: NSAttributedString?
        if result.usedSafeFallback {
            let html = key.html
            let runs = await Task.detached(priority: .utility) {
                NativeRichTextFallbackParser.parseForEditing(html)
            }.value
            guard !Task.isCancelled else { return }
            editableAttributedText = runs.flatMap {
                guard let editable = NativeRichTextDisplayRenderer.editableAttributedText(from: $0) else { return nil }
                return NativeRichTextDisplayRenderer.applyingNoteFormatting(
                    to: NativeRichTextDisplayRenderResult(attributedText: editable, usedSafeFallback: true),
                    sourceHTML: html
                ).attributedText
            }
        } else {
            editableAttributedText = result.attributedText.copy() as? NSAttributedString ?? result.attributedText
        }
        guard !Task.isCancelled, !editing, key == noteRenderKey else { return }
        let displayResult: NativeRichTextDisplayRenderResult
        if result.usedSafeFallback, let editableAttributedText {
            let fallbackResult = NativeRichTextDisplayRenderResult(
                attributedText: editableAttributedText,
                usedSafeFallback: true
            )
            displayResult = NativeRichTextDisplayRenderer.applyingNoteFormatting(to: fallbackResult, sourceHTML: key.html)
        } else {
            displayResult = result
        }
        preparedNote = PreparedLibraryInlineNote(
            key: key,
            result: displayResult,
            editableAttributedText: editableAttributedText,
            editorDocumentRevision: nil
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
                    noteFormatting: true,
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
                    accessibilityIdentifier: "library-inline-note-current-version",
                    noteFormatting: true
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
                noteFormatting: true,
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
            Button(saveStatus == .failed ? "重试保存" : "保存") {
                retryPendingDraft()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.blue)
            .disabled(saveService.hasPending(recordID: renderDocumentID))
            .accessibilityIdentifier("library-inline-note-pending-save")
        }
    }

    private func beginEditing(
        html: String,
        snapshot: NSAttributedString,
        selectionOffset: Int,
        sourceWidth: CGFloat?
    ) {
        editorSession.clearMediaNotice(for: renderDocumentID)
        let state = saveService.state(recordID: renderDocumentID)
        let isResumingPendingDraft = html != storedNote && state.latestContent == html
        if !isResumingPendingDraft {
            activeBaseVersion = currentRecordVersion()
            activeBasePayload = currentRecordPayload()
        } else {
            activeBaseVersion = state.latestBaseVersion ?? activeBaseVersion
            activeBasePayload = state.latestBasePayload ?? activeBasePayload
        }
        currentDraftVersion = isResumingPendingDraft ? state.latestDraftVersion : nil
        setDraftWithoutScheduling(html)
        editingInitialHTML = html
        editingInitialAttributedText = snapshot.copy() as? NSAttributedString ?? snapshot
        initialSelectionOffset = max(0, min(selectionOffset, snapshot.length))
        initialSelectionWidth = sourceWidth
        editingSessionID = UUID()
        editorSession.activate(documentID: renderDocumentID, sessionID: editingSessionID)
        editing = true
        session.setEditing(true)
        session.setPendingChanges(true)
        transientErrorMessage = nil
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
                updateSessionPendingState()
                resolveFinishCompletionsWaitingForRestore()
            }
        }
        do {
            guard let pending = try await LibraryInlineNoteDraftStorage.shared.load(recordID: renderDocumentID) else {
                let state = saveService.state(recordID: renderDocumentID)
                if state.latestContent != state.confirmedContent, state.phase == .debouncing {
                    activeBaseVersion = state.latestBaseVersion ?? activeBaseVersion
                    activeBasePayload = state.latestBasePayload ?? activeBasePayload
                    currentDraftVersion = state.latestDraftVersion
                    enqueueSave(state.latestContent, draftVersion: state.latestDraftVersion)
                }
                return
            }
            guard appearanceID == draftRestoreAppearanceID else { return }
            guard !editing else { return }
            let currentState = saveService.state(recordID: renderDocumentID)
            if currentState.latestDraftVersion > pending.draftVersion {
                if currentState.latestContent != currentState.confirmedContent {
                    try await LibraryInlineNoteDraftStorage.shared.write(
                        LibraryInlineNoteDraftSnapshot(
                            recordID: renderDocumentID,
                            baseVersion: currentState.latestBaseVersion ?? currentRecordVersion(),
                            draftVersion: currentState.latestDraftVersion,
                            content: currentState.latestContent,
                            updatedAt: .now
                        )
                    )
                }
                try await LibraryInlineNoteDraftStorage.shared.removeIfMatching(
                    recordID: renderDocumentID,
                    draftVersion: pending.draftVersion
                )
                setDraftWithoutScheduling(currentState.latestContent)
                activeBaseVersion = currentState.latestBaseVersion ?? activeBaseVersion
                activeBasePayload = currentState.latestBasePayload ?? activeBasePayload
                currentDraftVersion = currentState.latestDraftVersion
                if currentState.latestContent != currentState.confirmedContent,
                   currentState.phase == .debouncing,
                   !saveService.hasPending(recordID: renderDocumentID) {
                    enqueueSave(currentState.latestContent, draftVersion: currentState.latestDraftVersion)
                }
                return
            }
            if pending.content == storedNote {
                try await LibraryInlineNoteDraftStorage.shared.removeIfMatching(
                    recordID: renderDocumentID,
                    draftVersion: pending.draftVersion
                )
                saveService.markExistingContentConfirmed(
                    recordID: renderDocumentID,
                    content: storedNote,
                    recordVersion: currentRecordVersion(),
                    payload: currentRecordPayload()
                )
                setDraftWithoutScheduling(storedNote)
                transientErrorMessage = nil
                return
            }

            activeBaseVersion = pending.baseVersion
            activeBasePayload = currentRecordPayload()
            let adopted = saveService.restoreDraft(
                recordID: renderDocumentID,
                content: pending.content,
                draftVersion: pending.draftVersion,
                baseVersion: pending.baseVersion,
                basePayload: activeBasePayload
            )
            guard adopted else {
                let state = saveService.state(recordID: renderDocumentID)
                try await LibraryInlineNoteDraftStorage.shared.removeIfMatching(
                    recordID: renderDocumentID,
                    draftVersion: pending.draftVersion
                )
                setDraftWithoutScheduling(state.latestContent)
                activeBaseVersion = state.latestBaseVersion ?? activeBaseVersion
                activeBasePayload = state.latestBasePayload ?? activeBasePayload
                currentDraftVersion = state.latestDraftVersion
                if state.latestContent != state.confirmedContent,
                   state.phase != .failed,
                   !saveService.hasPending(recordID: renderDocumentID) {
                    enqueueSave(state.latestContent, draftVersion: state.latestDraftVersion)
                }
                return
            }
            setDraftWithoutScheduling(pending.content)
            currentDraftVersion = pending.draftVersion
            if saveService.state(recordID: renderDocumentID).phase == .failed {
                transientErrorMessage = nil
            } else {
                transientErrorMessage = "已恢复上次未完成的笔记草稿，正在尝试保存。"
                enqueueSave(pending.content, draftVersion: pending.draftVersion)
            }
        } catch {
            guard appearanceID == draftRestoreAppearanceID else { return }
            transientErrorMessage = "笔记草稿读取失败：\(error.localizedDescription)"
        }
    }

    private func resolveFinishCompletionsWaitingForRestore(allowSuccess: Bool = true) {
        guard !isRestoringDraft, !finishCompletionsWaitingForRestore.isEmpty else { return }
        let completions = finishCompletionsWaitingForRestore
        finishCompletionsWaitingForRestore = []
        saveService.whenIdle(recordID: renderDocumentID) { saved in
            let canProceed = allowSuccess && saved && self.saveService.state(recordID: self.renderDocumentID).phase != .failed
            self.updateFinishResult(canProceed)
            completions.forEach { $0(canProceed) }
        }
    }

    private func finishWhenCurrentSaveSettles(_ completion: @escaping (Bool) -> Void) {
        if isRestoringDraft {
            finishCompletionsWaitingForRestore.append(completion)
            return
        }
        if transientErrorMessage?.hasPrefix("笔记草稿读取失败：") == true {
            updateFinishResult(false)
            completion(false)
            return
        }
        let state = saveService.state(recordID: renderDocumentID)
        if !saveService.hasPending(recordID: renderDocumentID),
           state.latestContent != state.confirmedContent,
           state.phase == .debouncing {
            activeBaseVersion = state.latestBaseVersion ?? activeBaseVersion
            activeBasePayload = state.latestBasePayload ?? activeBasePayload
            enqueueSave(state.latestContent, draftVersion: state.latestDraftVersion)
        }
        saveService.whenIdle(recordID: renderDocumentID) { saved in
            let canProceed = saved && self.saveService.state(recordID: self.renderDocumentID).phase != .failed
            self.updateFinishResult(canProceed)
            completion(canProceed)
        }
    }

    private func finishEditing(completion: @escaping (Bool) -> Void = { _ in }) {
        guard editing else {
            finishWhenCurrentSaveSettles(completion)
            return
        }
        if isFinishing {
            finishCompletionsWaitingForCommit.append(completion)
            return
        }
        guard editorSession.canFinishEditing else {
            transientErrorMessage = "笔记编辑器仍在处理输入，请稍后重试。"
            updateFinishResult(false)
            completion(false)
            return
        }
        isFinishing = true
        saveTask?.cancel()
        guard let snapshot = editorSession.captureSnapshot() else {
            isFinishing = false
            transientErrorMessage = "无法读取当前笔记内容，编辑页面没有打开。"
            resolveFinishCompletions(primary: completion, result: false)
            return
        }
        let latestDraft = snapshot.html
        let currentState = saveService.state(recordID: renderDocumentID)
        if latestDraft == storedNote, !saveService.hasPending(recordID: renderDocumentID) {
            saveService.markExistingContentConfirmed(
                recordID: renderDocumentID,
                content: storedNote,
                recordVersion: currentRecordVersion(),
                payload: currentRecordPayload(),
                allowDiscardingUnqueuedDraft: true
            )
            let confirmed = saveService.state(recordID: renderDocumentID)
            if confirmed.confirmedContent == latestDraft {
                editorSession.setInputLocked(true)
                finishEditorAfterConfirmedSave(
                    version: confirmed.confirmedDraftVersion,
                    content: latestDraft,
                    completion: completion
                )
                return
            }
        }
        if latestDraft == currentState.confirmedContent,
           !saveService.hasPending(recordID: renderDocumentID),
           currentState.phase != .failed {
            editorSession.setInputLocked(true)
            finishEditorAfterConfirmedSave(
                version: currentState.confirmedDraftVersion,
                content: latestDraft,
                completion: completion
            )
            return
        }
        setDraftWithoutScheduling(latestDraft)
        editorSession.setInputLocked(true)
        let version = saveService.registerDraft(
            recordID: renderDocumentID,
            content: latestDraft,
            baseVersion: activeBaseVersion,
            basePayload: activeBasePayload
        )
        currentDraftVersion = version
        let state = saveService.state(recordID: renderDocumentID)
        if state.confirmedDraftVersion == version,
           state.confirmedContent == latestDraft,
           !saveService.hasPending(recordID: renderDocumentID) {
            finishEditorAfterConfirmedSave(version: version, content: latestDraft, completion: completion)
            return
        }
        enqueueSave(
            latestDraft,
            draftVersion: version,
            editorSnapshot: snapshot,
            onCompletion: { result in
                switch result {
                case .success:
                    self.finishEditorAfterConfirmedSave(version: version, content: latestDraft, completion: completion)
                case .failure(let error):
                    self.editorSession.setInputLocked(false)
                    self.isFinishing = false
                    self.transientErrorMessage = "笔记未保存，原记录未覆盖：\(error.localizedDescription)"
                    self.resolveFinishCompletions(primary: completion, result: false)
                }
            }
        )
    }

    private func finishEditorAfterConfirmedSave(
        version: UInt64,
        content: String,
        completion: @escaping (Bool) -> Void
    ) {
        let state = saveService.state(recordID: renderDocumentID)
        guard state.confirmedDraftVersion == version, state.confirmedContent == content else {
            editorSession.setInputLocked(false)
            isFinishing = false
            transientErrorMessage = "最新笔记版本尚未确认写入，编辑器仍保持打开。"
            resolveFinishCompletions(primary: completion, result: false)
            return
        }
        editorSession.endEditing { _ in
            guard self.saveService.state(recordID: self.renderDocumentID).confirmedDraftVersion == version else {
                self.editorSession.setInputLocked(false)
                self.isFinishing = false
                self.transientErrorMessage = "保存期间笔记又有更新，请核对后再完成。"
                self.resolveFinishCompletions(primary: completion, result: false)
                return
            }
            self.editing = false
            self.session.setEditing(false)
            self.editingInitialHTML = nil
            self.editingInitialAttributedText = nil
            self.initialSelectionOffset = nil
            self.initialSelectionWidth = nil
            self.isFinishing = false
            self.transientErrorMessage = nil
            self.updateSessionPendingState()
            self.resolveFinishCompletions(primary: completion, result: true)
        }
    }

    private func resolveFinishCompletions(primary: @escaping (Bool) -> Void, result: Bool) {
        updateFinishResult(result)
        primary(result)
        let additional = finishCompletionsWaitingForCommit
        finishCompletionsWaitingForCommit = []
        additional.forEach { $0(result) }
    }

    private var finishFailureDescription: String {
        if let transientErrorMessage, !transientErrorMessage.isEmpty { return transientErrorMessage }
        if let errorMessage, !errorMessage.isEmpty { return errorMessage }
        return "笔记尚未成功保存，编辑页面没有打开。"
    }

    private func updateFinishResult(_ succeeded: Bool) {
        session.setFinishFailureMessage(succeeded ? nil : finishFailureDescription)
        updateSessionPendingState()
    }

    private func updateSessionPendingState() {
        let state = saveService.state(recordID: renderDocumentID)
        let draftRestoreFailed = transientErrorMessage?.hasPrefix("笔记草稿读取失败：") == true
        session.setPendingChanges(
            editing
                || isRestoringDraft
                || draftRestoreFailed
                || state.latestContent != state.confirmedContent
                || state.phase == .failed
                || saveService.hasPending(recordID: renderDocumentID)
        )
        if !session.hasPendingChanges { session.setFinishFailureMessage(nil) }
    }

    private func advanceImageImportRequest() {
        guard let request = editorSession.imageImportRequest,
              request.insertMenuDismissed,
              photoImportRequestID == nil else { return }
        guard editing,
              request.documentID == renderDocumentID,
              request.sessionID == editingSessionID else {
            finishImageImport(
                requestID: request.id,
                errorMessage: "笔记编辑会话已切换，图片没有插入。"
            )
            return
        }
        guard !editorSession.isComposingText else {
            editorSession.commitCompositionIfNeeded()
            return
        }
        guard let target = editorSession.captureInsertionTarget(for: request) else {
            finishImageImport(
                requestID: request.id,
                errorMessage: "无法确定当前笔记中的插入位置，请点选正文后重试。"
            )
            return
        }
        photoImportTarget = target
        photoImportRequestID = request.id
        transientErrorMessage = nil
        isPhotoPickerPresented = true
    }

    @MainActor
    private func loadAndInsertPhoto(_ item: PhotosPickerItem) async {
        guard let requestID = photoImportRequestID,
              let target = photoImportTarget,
              editorSession.imageImportRequest?.id == requestID else { return }
        defer {
            selectedPhoto = nil
            photoLoadTask = nil
        }

        do {
            let sourceData: Data
            do {
                guard let loaded = try await item.loadTransferable(type: Data.self) else {
                    throw LibraryInlineNotePhotoError.noData
                }
                sourceData = loaded
            } catch let error as LibraryInlineNotePhotoError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LibraryInlineNotePhotoError.loadFailed(error.localizedDescription)
            }
            try Task.checkCancellation()
            guard editorSession.imageImportRequest?.id == requestID,
                  editorSession.matches(target) else {
                throw NativeRichTextEditorError.editorSessionChanged
            }
            guard sourceData.count <= 8 * 1024 * 1024 else { throw LibraryInlineNotePhotoError.tooLarge }
            guard let image = UIImage(data: sourceData) else { throw LibraryInlineNotePhotoError.decodeFailed }
            guard let compressed = image.jpegData(compressionQuality: 0.82) else { throw LibraryInlineNotePhotoError.encodeFailed }
            guard compressed.count <= 8 * 1024 * 1024 else { throw LibraryInlineNotePhotoError.tooLarge }
            let dataURL = "data:image/jpeg;base64,\(compressed.base64EncodedString())"
            guard dataURL.utf8.count <= NativeRichTextImageLimits.maximumEncodedBytes else {
                throw LibraryInlineNotePhotoError.tooLarge
            }

            editorSession.insertImage(dataURL, target: target) { result in
                switch result {
                case .success:
                    self.finishImageImport(requestID: requestID)
                case .failure(let error):
                    self.finishImageImport(
                        requestID: requestID,
                        errorMessage: "图片插入失败：\(error.localizedDescription)"
                    )
                }
            }
        } catch is CancellationError {
            finishImageImport(requestID: requestID)
        } catch {
            finishImageImport(
                requestID: requestID,
                errorMessage: "图片插入失败：\(error.localizedDescription)"
            )
        }
    }

    private func finishImageImport(requestID: UUID, errorMessage: String? = nil) {
        guard photoImportRequestID == requestID || editorSession.imageImportRequest?.id == requestID else { return }
        if let errorMessage { transientErrorMessage = errorMessage }
        photoImportTarget = nil
        photoImportRequestID = nil
        photoLoadTask?.cancel()
        photoLoadTask = nil
        selectedPhoto = nil
        isPhotoPickerPresented = false
        editorSession.finishImageImport(requestID: requestID)
    }

    private func retryPendingDraft() {
        let state = saveService.state(recordID: renderDocumentID)
        let content = state.latestContent
        let version: UInt64
        if state.latestDraftVersion == 0 || content == state.confirmedContent {
            version = saveService.registerDraft(
                recordID: renderDocumentID,
                content: draft,
                baseVersion: activeBaseVersion,
                basePayload: activeBasePayload
            )
        } else {
            version = state.latestDraftVersion
            activeBaseVersion = state.latestBaseVersion ?? activeBaseVersion
            activeBasePayload = state.latestBasePayload ?? activeBasePayload
        }
        currentDraftVersion = version
        transientErrorMessage = nil
        enqueueSave(state.latestDraftVersion == 0 || content == state.confirmedContent ? draft : content, draftVersion: version)
    }

    private func setDraftWithoutScheduling(_ value: String) {
        guard draft != value else { return }
        suppressNextDraftChange = true
        draft = value
    }

    private func enqueueSave(
        _ content: String,
        draftVersion: UInt64,
        editorSnapshot: NativeRichTextEditorSnapshot? = nil,
        baseVersion: String? = nil,
        basePayload: Data? = nil,
        requiresBackgroundTime: Bool = false,
        onCompletion: ((Result<String, Error>) -> Void)? = nil
    ) {
        transientErrorMessage = nil
        let state = saveService.state(recordID: renderDocumentID)
        let effectiveBaseVersion = baseVersion ?? state.latestBaseVersion ?? activeBaseVersion
        let effectiveBasePayload = basePayload ?? state.latestBasePayload ?? activeBasePayload
        saveService.enqueue(
            recordID: renderDocumentID,
            draftVersion: draftVersion,
            baseVersion: effectiveBaseVersion,
            basePayload: effectiveBasePayload,
            collection: recordCollection,
            content: content,
            requiresBackgroundTime: requiresBackgroundTime,
            commit: { prepared, expectedVersion in
                try self.writeNote(content, prepared, expectedVersion, self.modelContext)
            },
            completion: { result in
                switch result {
                case .success(let version):
                    self.activeBaseVersion = version
                    self.activeBasePayload = self.currentRecordPayload()
                    if !self.editing, let editorSnapshot, editorSnapshot.html == content {
                        let attributedText = editorSnapshot.attributedText
                        self.preparedNote = PreparedLibraryInlineNote(
                            key: self.noteRenderKey,
                            result: NativeRichTextDisplayRenderResult(
                                attributedText: attributedText.copy() as? NSAttributedString ?? attributedText,
                                usedSafeFallback: false
                            ),
                            editableAttributedText: attributedText.copy() as? NSAttributedString ?? attributedText,
                            editorDocumentRevision: editorSnapshot.documentRevision
                        )
                    }
                    if self.saveService.state(recordID: self.renderDocumentID).latestDraftVersion == draftVersion {
                        self.transientErrorMessage = nil
                        self.onSaved?(content)
                    }
                case .failure(let error):
                    if self.saveService.state(recordID: self.renderDocumentID).latestDraftVersion == draftVersion {
                        self.transientErrorMessage = "笔记未保存，原记录未覆盖：\(error.localizedDescription)"
                    }
                }
                onCompletion?(result)
            }
        )
    }
}

@MainActor
private struct LibraryInlineNoteAnchor: UIViewRepresentable {
    let session: LibraryInlineNoteSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        session.setNoteAnchor(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        session.setNoteAnchor(view)
    }
}
