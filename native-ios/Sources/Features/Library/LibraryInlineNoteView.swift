import SwiftData
import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

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

enum LibraryInlineNotePhotoError: LocalizedError {
    case noData
    case loadFailed(String)
    case tooLarge
    case decodeFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .noData: "相册没有返回图片数据。"
        case .loadFailed(let message): "读取图片失败：\(message)"
        case .tooLarge: "图片无法压缩到笔记可安全保存的范围（约 2.9 MB），请选较小的图片。"
        case .decodeFailed: "无法识别所选图片。"
        case .encodeFailed: "图片压缩失败，请换一张图片重试。"
        }
    }
}

private enum LibraryInlineNoteSaveStatus: Equatable {
    case saved
    case unsaved
    case debouncing
    case queued
    case writing
    case failed

    var title: String {
        switch self {
        case .saved: "已保存"
        case .unsaved: "未保存"
        case .debouncing: "等待保存…"
        case .queued: "等待写入…"
        case .writing: "保存中…"
        case .failed: "保存失败"
        }
    }

    var color: Color {
        switch self {
        case .saved: AppTheme.success
        case .unsaved: AppTheme.warning
        case .debouncing, .queued, .writing: .secondary
        case .failed: AppTheme.danger
        }
    }
}

enum LibraryInlineNoteCommitMode: Equatable {
    case automatic
    case explicit
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
    private var keyboardFrameObserver: NSObjectProtocol?
    private var pendingReveal: DispatchWorkItem?

    func setNoteAnchor(_ view: UIView?) { noteAnchorView = view }

    func setEditing(_ value: Bool) {
        isEditing = value
        if value { hasPendingChanges = true }
        else { resetFocusReveal() }
    }

    func resetFocusReveal() {
        focusRevealSessionID = nil
        pendingReveal?.cancel()
        pendingReveal = nil
        if let keyboardFrameObserver {
            NotificationCenter.default.removeObserver(keyboardFrameObserver)
            self.keyboardFrameObserver = nil
        }
    }

    func revealWritableArea(in textView: UITextView, sessionID: UUID) {
        guard textView.isFirstResponder else { return }
        if focusRevealSessionID != sessionID {
            resetFocusReveal()
            focusRevealSessionID = sessionID
            keyboardFrameObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                Task { @MainActor in
                    self.scheduleWritableAreaReveal(in: textView, sessionID: sessionID)
                }
            }
        }
        scheduleWritableAreaReveal(in: textView, sessionID: sessionID)
    }

    private func scheduleWritableAreaReveal(in textView: UITextView, sessionID: UUID) {
        pendingReveal?.cancel()
        let work = DispatchWorkItem { [weak self, weak textView] in
            guard let self, let textView else { return }
            Task { @MainActor in
                guard self.focusRevealSessionID == sessionID else { return }
                self.revealWritableAreaNow(in: textView, sessionID: sessionID)
            }
        }
        pendingReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func revealWritableAreaNow(in textView: UITextView, sessionID: UUID) {
        guard focusRevealSessionID == sessionID,
              textView.isFirstResponder,
              let window = textView.window,
              let anchor = noteAnchorView,
              anchor.window === window else { return }

        window.keyboardLayoutGuide.followsUndockedKeyboard = true
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
        let position = textView.selectedTextRange?.end ?? textView.endOfDocument
        let caret = textView.convert(textView.caretRect(for: position), to: window)
        let caretHitArea = CGRect(x: caret.minX - 1, y: caret.minY, width: max(caret.width, 2) + 2, height: max(caret.height, 2))
        let keyboardFrame = window.keyboardLayoutGuide.layoutFrame
        let keyboardIntersectsCaret = keyboardFrame.height > 80 && caretHitArea.intersects(keyboardFrame)
        let dockedKeyboardCoversCaret = keyboardFrame.width >= viewport.width * 0.8
            && keyboardFrame.height > 80
            && caret.maxY > keyboardFrame.minY
            && caret.minY < viewport.maxY
        if keyboardIntersectsCaret || dockedKeyboardCoversCaret {
            visibleBottom = min(visibleBottom, keyboardFrame.minY)
        }
        if let accessory = textView.inputAccessoryView, accessory.window === window {
            let accessoryFrame = accessory.convert(accessory.bounds, to: window)
            if accessoryFrame.height > 0, caretHitArea.intersects(accessoryFrame) {
                visibleBottom = accessoryFrame.minY
            }
        }

        let neededDelta = max(0, caret.maxY + 24 - visibleBottom)
        guard neededDelta > 1 else { return }

        let maximumOffset = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let scrollCapacity = max(0, maximumOffset - scrollView.contentOffset.y)
        let delta = min(neededDelta, scrollCapacity)
        guard delta > 1 else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + delta),
            animated: true
        )
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
    private let persistedNoteReader: () -> String?
    private let writeNote: (String, LibraryInlineNotePreparedSave?, String, ModelContext) throws -> String
    private let currentRecordVersion: () -> String
    private let currentRecordEditVersion: () -> String
    private let currentRecordPayload: () -> Data?
    private let recordCollection: String
    private let onSaved: ((String) -> Void)?
    private let onFinishConfirmed: ((String) -> Void)?
    private let commitMode: LibraryInlineNoteCommitMode
    private let renderDocumentID: String
    private let renderVersion: () -> String
    let session: LibraryInlineNoteSession
    let title: String
    @StateObject private var editorSession = NativeRichTextEditorSession()
    @State private var editing = false
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var currentDraftVersion: UInt64?
    @State private var manualDraftVersion: UInt64 = 0
    @State private var manualDraftHasVersionConflict = false
    @State private var activeBaseVersion = ""
    @State private var activeBasePayload: Data?
    @State private var editingSessionID = UUID()
    @State private var didAttemptDraftRestoreForAppearance = false
    @State private var draftRestoreAppearanceID = UUID()
    @State private var isRestoringDraft = false
    @State private var legacyDraftVersionAwaitingReplacement: UInt64?
    @State private var suppressNextDraftChange = false
    @State private var finishCompletionsWaitingForRestore: [(Bool) -> Void] = []
    @State private var finishCompletionsWaitingForCommit: [(Bool) -> Void] = []
    @State private var isFinishing = false
    @State private var isEndingProgrammaticTransition = false
    @State private var preparedNote: PreparedLibraryInlineNote?
    @State private var preparationFailureKey: LibraryInlineNoteRenderKey?
    @State private var preparedPendingDraft: PreparedLibraryInlineNote?
    @State private var pendingDraftPreparationFailureKey: LibraryInlineNoteRenderKey?
    @State private var transientErrorMessage: String?
    @State private var displayWarning: String?
    @State private var editingInitialHTML: String?
    @State private var editingInitialAttributedText: NSAttributedString?
    @State private var initialSelectionOffset: Int?
    @State private var initialSelectionWidth: CGFloat?
    @State private var isPhotoPickerPresented = false
    @State private var isInsertingPhoto = false
    @State private var photoImportTarget: NativeRichTextInsertionTarget?
    @State private var photoImportRequestID: UUID?
    @State private var photoLoadTask: Task<Void, Never>?

    private let noteCanvasMinimumHeight: CGFloat = 360

    init(
        record: StoredRecord,
        session: LibraryInlineNoteSession,
        title: String = "错题笔记",
        commitMode: LibraryInlineNoteCommitMode = .automatic,
        readNote: (() -> String)? = nil,
        onSaved: ((String) -> Void)? = nil,
        onFinishConfirmed: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.title = title
        self.commitMode = commitMode
        self.onSaved = onSaved
        self.onFinishConfirmed = onFinishConfirmed
        renderDocumentID = record.compoundID
        renderVersion = { record.updatedAt.map { String($0.timeIntervalSince1970) } ?? "" }
        currentRecordVersion = {
            "\(record.updatedAt.map { String($0.timeIntervalSince1970.bitPattern, radix: 16) } ?? "none"):\(record.payload.count)"
        }
        currentRecordEditVersion = {
            LibraryInlineNoteSaveService.versionKey(updatedAt: record.updatedAt, payload: record.payload)
        }
        currentRecordPayload = { record.payload }
        recordCollection = record.collection
        self.readNote = readNote ?? {
            let object = record.jsonObject ?? [:]
            if let note = object["note"] as? String { return note }
            return ["content", "errorNote", "analysis"].compactMap { object[$0] as? String }.first ?? ""
        }
        persistedNoteReader = { record.jsonObject?["note"] as? String }
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
        commitMode: LibraryInlineNoteCommitMode = .automatic,
        readNote: @escaping () -> String,
        writeNote: @escaping (String, ModelContext) throws -> Void,
        renderDocumentID: String = "inline-note",
        renderVersion: @escaping () -> String = { "" },
        onSaved: ((String) -> Void)? = nil,
        onFinishConfirmed: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.title = title
        self.commitMode = commitMode
        self.onSaved = onSaved
        self.onFinishConfirmed = onFinishConfirmed
        self.renderDocumentID = renderDocumentID
        self.renderVersion = renderVersion
        self.readNote = readNote
        persistedNoteReader = { readNote() }
        currentRecordVersion = renderVersion
        currentRecordEditVersion = renderVersion
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
        if commitMode == .explicit {
            return draft != storedNote || manualDraftHasVersionConflict || noteSaveState.phase == .failed
        }
        return noteSaveState.latestContent != noteSaveState.confirmedContent || noteSaveState.phase == .failed
    }

    private var shouldShowPendingDraftDisplay: Bool {
        hasPendingDraft || errorMessage != nil
    }

    private var saveStatus: LibraryInlineNoteSaveStatus {
        if commitMode == .explicit {
            if isFinishing { return .writing }
            return draft == storedNote && !manualDraftHasVersionConflict ? .saved : .unsaved
        }
        return switch noteSaveState.phase {
        case .idle, .saved: .saved
        case .debouncing: .debouncing
        case .queued: .queued
        case .writing: .writing
        case .failed: .failed
        }
    }

    private var noteSaveStatusTitle: String {
        if commitMode == .explicit {
            return isFinishing ? "保存中…" : (hasPendingDraft ? "未保存" : "已保存")
        }
        if editing, editorSession.hasUnsavedImageInsertion, saveStatus == .saved {
            return "等待保存…"
        }
        return saveStatus.title
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

    private var pendingDraftRenderKey: LibraryInlineNoteRenderKey {
        LibraryInlineNoteRenderKey(
            documentID: renderDocumentID,
            version: "\(questionBankContextVersion)|draft:\(max(currentDraftVersion ?? 0, manualDraftVersion))",
            html: draft
        )
    }

    private var questionBankContextVersion: String {
        "\(renderVersion())|\(storedNote.utf8.count)"
    }

    private var currentPreparedNote: PreparedLibraryInlineNote? {
        guard preparedNote?.key == noteRenderKey else { return nil }
        return preparedNote
    }

    private var currentPreparedPendingDraft: PreparedLibraryInlineNote? {
        guard preparedPendingDraft?.key == pendingDraftRenderKey else { return nil }
        return preparedPendingDraft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "note.text")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(isInsertingPhoto ? "正在插入图片…" : noteSaveStatusTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(saveStatus.color)
                    .accessibilityIdentifier("library-inline-note-save-status")
                if editing {
                    Button("完成") { finishEditing() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .disabled(isFinishing || isEndingProgrammaticTransition || editorSession.isMediaOperationInProgress || editorSession.isAuxiliaryPanelPresented)
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
                    usesStabilizedInlineNoteMeasurement: commitMode == .explicit,
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
                    },
                    onCaretChange: { textView in
                        session.revealWritableArea(in: textView, sessionID: editingSessionID)
                    }
                )
                .accessibilityIdentifier("library-inline-note-editor")
                .padding(.horizontal, 8)
                .padding(.bottom, 96)
            } else {
                if shouldShowPendingDraftDisplay {
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
        .sheet(isPresented: $isPhotoPickerPresented) {
            if let requestID = photoImportRequestID {
                LibraryInlineNotePhotoPicker(requestID: requestID) { finishedRequestID, provider in
                    guard photoImportRequestID == finishedRequestID else { return }
                    isPhotoPickerPresented = false
                    guard let provider else {
                        finishImageImport(requestID: finishedRequestID)
                        return
                    }
                    isInsertingPhoto = true
                    photoLoadTask?.cancel()
                    photoLoadTask = Task { @MainActor in
                        await loadAndInsertPhoto(provider, requestID: finishedRequestID)
                    }
                }
                .ignoresSafeArea()
            } else {
                Color.clear
            }
        }
        .onChange(of: editorSession.imageImportRequest) { _, _ in advanceImageImportRequest() }
        .onChange(of: editorSession.isComposingText) { _, isComposing in
            if !isComposing { advanceImageImportRequest() }
        }
        .onAppear {
            session.finishEditing = { completion in
                if commitMode == .explicit {
                    finishForProgrammaticTransition(completion: completion)
                } else {
                    finishEditing(completion: completion)
                }
            }
            saveService.markExistingContentConfirmed(
                recordID: renderDocumentID,
                content: storedNote,
                readVersion: currentRecordVersion()
            )
            let state = saveService.state(recordID: renderDocumentID)
            activeBaseVersion = state.latestBaseVersion ?? currentRecordEditVersion()
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
            if commitMode == .explicit {
                transientErrorMessage = nil
                updateSessionPendingState()
                return
            }
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
            if commitMode == .explicit {
                guard let snapshot = editorSession.captureSnapshot() else {
                    transientErrorMessage = "切到后台时无法读取当前输入，草稿仍保留在编辑会话中。"
                    return
                }
                if snapshot.html != draft { setDraftWithoutScheduling(snapshot.html) }
                persistManualRecoveryDraft(snapshot.html, sessionID: editingSessionID)
                if editorSession.isComposingText {
                    transientErrorMessage = "输入法仍在组合文字；当前内容已写入本地恢复草稿，点“完成”后再提交正式记录。"
                }
                updateSessionPendingState()
                return
            }
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
                if commitMode == .explicit {
                    if let snapshot {
                        if snapshot.html != draft { setDraftWithoutScheduling(snapshot.html) }
                        persistManualRecoveryDraft(snapshot.html, sessionID: editingSessionID)
                        if editorSession.isComposingText {
                            LibraryPerformanceLog.event(
                                "note.recovery-draft.composition id=\(LibraryPerformanceLog.shortIdentifier(renderDocumentID)) session=\(editingSessionID.uuidString.prefix(8))"
                            )
                        }
                    } else {
                        LibraryPerformanceLog.event(
                            "note.recovery-draft.skipped-composition id=\(LibraryPerformanceLog.shortIdentifier(renderDocumentID)) session=\(editingSessionID.uuidString.prefix(8))"
                        )
                    }
                } else {
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
            saveService.discardConfirmedStateIfIdle(recordID: renderDocumentID)
        }
        .task(id: LibraryInlineNotePreparationKey(note: noteRenderKey, isEditing: editing)) {
            let key = noteRenderKey
            await prepareNote(for: key)
        }
        .task(id: LibraryInlineNotePreparationKey(note: pendingDraftRenderKey, isEditing: editing || !shouldShowPendingDraftDisplay)) {
            guard !editing, shouldShowPendingDraftDisplay else { return }
            await preparePendingDraft(for: pendingDraftRenderKey)
        }
        .onChange(of: noteSaveState) { _, _ in updateSessionPendingState() }
    }

    @MainActor
    private func prepareNote(for key: LibraryInlineNoteRenderKey) async {
        guard !editing, !key.html.isEmpty else { return }
        preparationFailureKey = nil
        var installedPreparedNote = false
        defer {
            if !Task.isCancelled, !editing, key == noteRenderKey {
                if installedPreparedNote {
                    preparationFailureKey = nil
                } else {
                    preparationFailureKey = key
                }
            }
        }
        if let preparedNote,
           preparedNote.key.documentID == key.documentID,
           preparedNote.key.html == key.html {
            self.preparedNote = PreparedLibraryInlineNote(
                key: key,
                result: preparedNote.result,
                editableAttributedText: preparedNote.editableAttributedText,
                editorDocumentRevision: preparedNote.editorDocumentRevision
            )
            installedPreparedNote = true
            return
        }
        guard let prepared = await prepareNativeNotePreview(for: key) else { return }
        guard !Task.isCancelled, !editing, key == noteRenderKey else { return }
        preparedNote = prepared
        installedPreparedNote = true
        if prepared.result.usedSafeFallback, prepared.editableAttributedText == nil {
            displayWarning = "预览已降级；笔记过长或含有未闭合附件，当前仅保留原内容并以只读方式显示。"
        } else {
            displayWarning = nil
        }
    }

    @MainActor
    private func preparePendingDraft(for key: LibraryInlineNoteRenderKey) async {
        pendingDraftPreparationFailureKey = nil
        guard !editing, shouldShowPendingDraftDisplay else { return }
        if let preparedPendingDraft,
           preparedPendingDraft.key.documentID == key.documentID,
           preparedPendingDraft.key.html == key.html {
            self.preparedPendingDraft = PreparedLibraryInlineNote(
                key: key,
                result: preparedPendingDraft.result,
                editableAttributedText: preparedPendingDraft.editableAttributedText,
                editorDocumentRevision: preparedPendingDraft.editorDocumentRevision
            )
            return
        }
        guard let prepared = await prepareNativeNotePreview(for: key) else {
            guard !Task.isCancelled, !editing, shouldShowPendingDraftDisplay, key == pendingDraftRenderKey else { return }
            pendingDraftPreparationFailureKey = key
            return
        }
        guard !Task.isCancelled, !editing, shouldShowPendingDraftDisplay, key == pendingDraftRenderKey else { return }
        preparedPendingDraft = prepared
    }

    @MainActor
    private func prepareNativeNotePreview(for key: LibraryInlineNoteRenderKey) async -> PreparedLibraryInlineNote? {
        let html = key.html
        let parsed = await Task.detached(priority: .utility) { () -> (runs: [NativeRichTextFallbackRun], supportsEditing: Bool) in
            if let editableRuns = NativeRichTextFallbackParser.parseForEditing(html) {
                return (editableRuns, true)
            }
            return (NativeRichTextFallbackParser.parse(html), false)
        }.value
        guard !Task.isCancelled else { return nil }

        let editableSnapshot: NSAttributedString?
        if parsed.supportsEditing,
           NativeRichTextDisplayRenderer.supportsLosslessEditing(parsed.runs),
           let editable = NativeRichTextDisplayRenderer.editableAttributedText(from: parsed.runs) {
            editableSnapshot = NativeRichTextDisplayRenderer.applyingNoteFormatting(
                to: NativeRichTextDisplayRenderResult(attributedText: editable, usedSafeFallback: true),
                sourceHTML: html,
                cleanLegacyInjectedSpacing: true
            ).attributedText
        } else {
            editableSnapshot = nil
        }

        let result: NativeRichTextDisplayRenderResult
        if let editableSnapshot {
            result = NativeRichTextDisplayRenderResult(
                attributedText: editableSnapshot,
                usedSafeFallback: false
            )
        } else {
            result = NativeRichTextDisplayRenderer.renderFallbackPreview(
                parsed.runs,
                sourceHTML: html,
                noteFormatting: true,
                cleanLegacyInjectedSpacing: true
            )
        }
        return PreparedLibraryInlineNote(
            key: key,
            result: result,
            editableAttributedText: editableSnapshot,
            editorDocumentRevision: nil
        )
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
                    requiresPreparedSnapshot: true,
                    onFallback: {
                        displayWarning = currentPreparedNote.editableAttributedText == nil
                            ? "预览已降级；笔记过长或含有未闭合附件，当前仅保留原内容并以只读方式显示。"
                            : "预览已切换为安全模式；编辑时会保留正文和已有附件。"
                    },
                    onTapTextOffset: { offset, snapshot, width in
                        guard !currentPreparedNote.result.usedSafeFallback
                                || currentPreparedNote.editableAttributedText != nil else {
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
            } else if preparationFailureKey == noteRenderKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("笔记暂时无法显示")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.warning)
                    Text("原始笔记仍保留；安全预览暂时无法生成。")
                        .font(AppTheme.noteBodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("library-inline-note-safe-fallback")
                    Button("重试") {
                        let retryKey = noteRenderKey
                        Task { await prepareNote(for: retryKey) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .accessibilityIdentifier("library-inline-note-display-retry")
                }
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
                if storedNote.isEmpty {
                    Text("（暂无已保存笔记）")
                        .font(AppTheme.noteBodyFont)
                        .foregroundStyle(.secondary)
                } else if let currentPreparedNote {
                    NativeRichTextDisplay(
                        html: storedNote,
                        preparedSnapshot: currentPreparedNote.result,
                        renderVersion: currentPreparedNote.key.rendererVersion,
                        minHeight: min(noteCanvasMinimumHeight, 160),
                        accessibilityIdentifier: "library-inline-note-current-version",
                        noteFormatting: true,
                        requiresPreparedSnapshot: true
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text(preparationFailureKey == noteRenderKey
                         ? "当前保存内容仍保留，但安全预览暂时无法生成。"
                         : "当前保存内容正在准备安全预览…")
                        .font(AppTheme.noteBodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }
            Label("未保存草稿", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.warning)
            if let preparedDraft = currentPreparedPendingDraft {
                NativeRichTextDisplay(
                    html: draft,
                    preparedSnapshot: preparedDraft.result,
                    renderVersion: preparedDraft.key.rendererVersion,
                    minHeight: noteCanvasMinimumHeight,
                    accessibilityIdentifier: "library-inline-note-pending-draft",
                    noteFormatting: true,
                    requiresPreparedSnapshot: true,
                    onTapTextOffset: pendingDraftTapHandler(for: preparedDraft)
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                if preparedDraft.result.usedSafeFallback,
                   preparedDraft.editableAttributedText == nil {
                    Text("此草稿仅以安全文本预览，暂不支持直接编辑；原始草稿仍保留。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if pendingDraftPreparationFailureKey == pendingDraftRenderKey {
                Text("草稿原文仍保留；安全预览暂时无法生成。")
                    .font(AppTheme.noteBodyFont)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Button("重试预览") {
                    let retryKey = pendingDraftRenderKey
                    Task { await preparePendingDraft(for: retryKey) }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue)
            } else {
                Text("草稿正在准备安全预览…")
                    .font(AppTheme.noteBodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            }
            if commitMode == .explicit {
                manualDraftActions
            } else {
                Button(saveStatus == .failed ? "重试保存" : "保存") {
                    retryPendingDraft()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue)
                .disabled(saveService.hasPending(recordID: renderDocumentID))
                .accessibilityIdentifier("library-inline-note-pending-save")
            }
        }
    }

    @ViewBuilder private var manualDraftActions: some View {
        if manualDraftHasVersionConflict {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    rebaseDraftButton
                    keepCurrentDraftButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    rebaseDraftButton
                    keepCurrentDraftButton
                }
            }
        } else {
            Button("继续编辑") { resumePendingDraftEditing() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue)
                .disabled(currentPreparedPendingDraft?.editableAttributedText == nil)
        }
    }

    private var rebaseDraftButton: some View {
        Button("以恢复草稿为准") { confirmManualDraftRebase() }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.blue)
    }

    private var keepCurrentDraftButton: some View {
        Button("保留当前内容") { discardManualRecoveryDraft() }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func resumePendingDraftEditing() {
        guard let prepared = currentPreparedPendingDraft,
              let snapshot = prepared.editableAttributedText else {
            displayWarning = "当前恢复草稿无法安全转为可编辑格式；原文仍保留。"
            return
        }
        beginEditing(
            html: draft,
            snapshot: snapshot,
            selectionOffset: snapshot.length,
            sourceWidth: nil
        )
    }

    private func pendingDraftTapHandler(
        for preparedDraft: PreparedLibraryInlineNote
    ) -> ((Int, NSAttributedString, CGFloat) -> Void)? {
        guard preparedDraft.editableAttributedText != nil else { return nil }
        return { offset, snapshot, width in
            beginEditing(
                html: draft,
                snapshot: snapshot,
                selectionOffset: offset,
                sourceWidth: width
            )
        }
    }

    private func confirmManualDraftRebase() {
        guard commitMode == .explicit, manualDraftHasVersionConflict else { return }
        activeBaseVersion = currentRecordEditVersion()
        activeBasePayload = currentRecordPayload()
        manualDraftHasVersionConflict = false
        transientErrorMessage = "已选择以当前记录为保存基准。恢复草稿仍未保存，请继续编辑后点“完成”。"
        persistManualRecoveryDraft(draft, sessionID: editingSessionID)
        updateSessionPendingState()
    }

    private func discardManualRecoveryDraft() {
        guard commitMode == .explicit, manualDraftHasVersionConflict else { return }
        let recordID = renderDocumentID
        let discardThroughVersion = saveService.recoveryDraftVersionHighWatermark(recordID: recordID)
        setDraftWithoutScheduling(storedNote)
        currentDraftVersion = nil
        manualDraftVersion = 0
        manualDraftHasVersionConflict = false
        activeBaseVersion = currentRecordEditVersion()
        activeBasePayload = currentRecordPayload()
        transientErrorMessage = nil
        saveService.discardUncommittedDraft(
            recordID: renderDocumentID,
            content: storedNote,
            readVersion: currentRecordVersion()
        )
        Task {
            try? await LibraryInlineNoteDraftStorage.shared.removeDrafts(
                recordID: recordID,
                through: discardThroughVersion
            )
        }
        updateSessionPendingState()
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
        if commitMode == .explicit {
            if activeBaseVersion.isEmpty {
                activeBaseVersion = currentRecordEditVersion()
                activeBasePayload = currentRecordPayload()
            }
        } else if !isResumingPendingDraft {
            activeBaseVersion = currentRecordEditVersion()
            activeBasePayload = currentRecordPayload()
        } else {
            activeBaseVersion = state.latestBaseVersion ?? activeBaseVersion
            activeBasePayload = state.latestBasePayload ?? activeBasePayload
        }
        currentDraftVersion = commitMode == .explicit
            ? nil
            : (isResumingPendingDraft ? state.latestDraftVersion : nil)
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
        session.setFinishFailureMessage(nil)
    }

    private func restorePendingDraft(for appearanceID: UUID) async {
        guard appearanceID == draftRestoreAppearanceID else { return }
        if LibraryInlineNoteSaveService.shared.hasPending(recordID: renderDocumentID) {
            LibraryInlineNoteSaveService.shared.whenIdle(recordID: renderDocumentID) { _ in
                Task { await restorePendingDraft(for: appearanceID) }
            }
            return
        }
        if commitMode == .explicit {
            await restoreExplicitPendingDraft(for: appearanceID)
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
            saveService.observeRecoveryDraftVersion(recordID: renderDocumentID, version: pending.draftVersion)
            let currentState = saveService.state(recordID: renderDocumentID)
            if currentState.latestDraftVersion > pending.draftVersion {
                if currentState.latestContent != currentState.confirmedContent {
                    try await LibraryInlineNoteDraftStorage.shared.write(
                        LibraryInlineNoteDraftSnapshot(
                            recordID: renderDocumentID,
                            baseVersion: currentState.latestBaseVersion ?? currentRecordEditVersion(),
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
                    readVersion: currentRecordVersion()
                )
                setDraftWithoutScheduling(storedNote)
                transientErrorMessage = nil
                return
            }

            guard LibraryInlineNoteSaveService.hasPayloadDigest(pending.baseVersion) else {
                setDraftWithoutScheduling(pending.content)
                currentDraftVersion = pending.draftVersion
                legacyDraftVersionAwaitingReplacement = pending.draftVersion
                transientErrorMessage = "旧版笔记草稿基线无法验证：草稿已恢复并保留，未自动写回。请先对照当前保存内容；确认后再主动编辑并保存。"
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

    private func restoreExplicitPendingDraft(for appearanceID: UUID) async {
        guard appearanceID == draftRestoreAppearanceID else { return }
        defer {
            if appearanceID == draftRestoreAppearanceID {
                isRestoringDraft = false
                updateSessionPendingState()
                resolveFinishCompletionsWaitingForRestore()
            }
        }
        do {
            if let pending = try await LibraryInlineNoteDraftStorage.shared.load(recordID: renderDocumentID) {
                guard appearanceID == draftRestoreAppearanceID, !editing else { return }
                saveService.observeRecoveryDraftVersion(recordID: renderDocumentID, version: pending.draftVersion)
                if pending.content == storedNote {
                    try await LibraryInlineNoteDraftStorage.shared.removeDrafts(
                        recordID: renderDocumentID,
                        through: pending.draftVersion
                    )
                    setDraftWithoutScheduling(storedNote)
                    manualDraftHasVersionConflict = false
                    saveService.discardUncommittedDraft(
                        recordID: renderDocumentID,
                        content: storedNote,
                        readVersion: currentRecordVersion()
                    )
                    return
                }
                activeBaseVersion = pending.baseVersion
                activeBasePayload = currentRecordPayload()
                currentDraftVersion = pending.draftVersion
                manualDraftVersion = pending.draftVersion
                manualDraftHasVersionConflict = pending.baseVersion != currentRecordEditVersion()
                setDraftWithoutScheduling(pending.content)
                transientErrorMessage = manualDraftHasVersionConflict
                    ? "恢复草稿基于旧版题目记录。当前保存内容和恢复草稿都已保留；请选择采用哪一份，再编辑并点“完成”。"
                    : "已恢复未保存的笔记草稿。请继续编辑并点“完成”写入正式记录。"
                return
            }

            let state = saveService.state(recordID: renderDocumentID)
            guard state.latestContent != state.confirmedContent else { return }
            let baseVersion = state.latestBaseVersion ?? currentRecordEditVersion()
            activeBaseVersion = baseVersion
            activeBasePayload = currentRecordPayload()
            currentDraftVersion = state.latestDraftVersion
            manualDraftVersion = state.latestDraftVersion
            manualDraftHasVersionConflict = baseVersion != currentRecordEditVersion()
            setDraftWithoutScheduling(state.latestContent)
            transientErrorMessage = manualDraftHasVersionConflict
                ? "恢复草稿基于旧版题目记录。当前保存内容和恢复草稿都已保留；请选择采用哪一份，再编辑并点“完成”。"
                : "已恢复未保存的笔记草稿。请继续编辑并点“完成”写入正式记录。"
            persistManualRecoveryDraft(state.latestContent, sessionID: editingSessionID)
        } catch {
            guard appearanceID == draftRestoreAppearanceID else { return }
            transientErrorMessage = "笔记草稿读取失败：\(error.localizedDescription)"
        }
    }

    private func persistManualRecoveryDraft(_ content: String, sessionID: UUID) {
        guard commitMode == .explicit,
              sessionID == editingSessionID else { return }
        let recordID = renderDocumentID
        if content == storedNote {
            let discardThroughVersion = saveService.recoveryDraftVersionHighWatermark(recordID: recordID)
            Task {
                try? await LibraryInlineNoteDraftStorage.shared.removeDrafts(
                    recordID: recordID,
                    through: discardThroughVersion
                )
            }
            currentDraftVersion = nil
            manualDraftVersion = 0
            manualDraftHasVersionConflict = false
            saveService.discardUncommittedDraft(
                recordID: recordID,
                content: content,
                readVersion: currentRecordVersion()
            )
            return
        }

        let version = saveService.nextRecoveryDraftVersion(
            recordID: recordID,
            after: max(manualDraftVersion, currentDraftVersion ?? 0)
        )
        manualDraftVersion = version
        currentDraftVersion = version
        let snapshot = LibraryInlineNoteDraftSnapshot(
            recordID: recordID,
            baseVersion: activeBaseVersion,
            draftVersion: version,
            content: content,
            updatedAt: .now
        )
        Task {
            do {
                try await LibraryInlineNoteSaveService.shared.persistRecoveryDraft(
                    snapshot,
                    requiresBackgroundTime: true
                )
            } catch {
                guard self.renderDocumentID == recordID,
                      self.editingSessionID == sessionID else { return }
                self.transientErrorMessage = "未保存草稿无法写入本地恢复区：\(error.localizedDescription)"
                LibraryPerformanceLog.event(
                    "note.recovery-draft.failed id=\(LibraryPerformanceLog.shortIdentifier(recordID)) revision=\(version)"
                )
            }
        }
    }

    private func finishForProgrammaticTransition(completion: @escaping (Bool) -> Void) {
        guard commitMode == .explicit else {
            finishEditing(completion: completion)
            return
        }
        guard !isFinishing, !isEndingProgrammaticTransition else {
            completion(false)
            return
        }
        saveTask?.cancel()
        if !editing {
            isEndingProgrammaticTransition = true
            let documentID = renderDocumentID
            let sessionID = editingSessionID
            Task { @MainActor in
                do {
                    try await persistManualRecoveryDraftBeforeCommit(draft, sessionID: sessionID)
                    guard renderDocumentID == documentID,
                          editingSessionID == sessionID else {
                        isEndingProgrammaticTransition = false
                        session.setFinishFailureMessage("笔记会话已切换；未保存草稿仍保留。")
                        completion(false)
                        return
                    }
                    isEndingProgrammaticTransition = false
                    session.setFinishFailureMessage(nil)
                    updateSessionPendingState()
                    completion(true)
                } catch {
                    isEndingProgrammaticTransition = false
                    session.setFinishFailureMessage("本地恢复草稿写入失败，尚未切换页面；请重试。\(error.localizedDescription)")
                    completion(false)
                }
            }
            return
        }
        guard !editorSession.isMediaOperationInProgress,
              !editorSession.isAuxiliaryPanelPresented else {
            session.setFinishFailureMessage("请先结束图片插入或工具操作，笔记草稿仍保留。")
            completion(false)
            return
        }

        isEndingProgrammaticTransition = true
        editorSession.commitCompositionIfNeeded()
        let documentID = renderDocumentID
        let sessionID = editingSessionID
        Task { @MainActor in
            await Task.yield()
            guard self.editing,
                  self.renderDocumentID == documentID,
                  self.editingSessionID == sessionID,
                  self.editorSession.documentID == documentID,
                  self.editorSession.sessionID == sessionID else {
                self.editorSession.setInputLocked(false)
                self.isEndingProgrammaticTransition = false
                self.session.setFinishFailureMessage("笔记编辑会话已切换；未保存草稿仍保留。")
                completion(false)
                return
            }
            self.editorSession.commitCompositionIfNeeded()
            guard !self.editorSession.isComposingText,
                  let snapshot = self.editorSession.captureSnapshot(),
                  self.imageSnapshotIsValid(snapshot, documentID: documentID, sessionID: sessionID) else {
                self.editorSession.setInputLocked(false)
                self.isEndingProgrammaticTransition = false
                self.session.setFinishFailureMessage("无法读取完整笔记或图片快照；草稿仍保留。")
                completion(false)
                return
            }
            let beforeEnding = LibraryInlineNoteFinishRevision(
                documentID: documentID,
                sessionID: sessionID,
                revision: snapshot.documentRevision,
                html: snapshot.html
            )
            self.editorSession.setInputLocked(true)
            self.editorSession.endEditing { endedHTML in
                Task { @MainActor in
                    guard self.renderDocumentID == documentID,
                          self.editingSessionID == sessionID,
                          self.editorSession.documentID == documentID,
                          self.editorSession.sessionID == sessionID else {
                        self.editorSession.setInputLocked(false)
                        self.isEndingProgrammaticTransition = false
                        self.session.setFinishFailureMessage("结束输入时题目已切换；原草稿仍保留。")
                        completion(false)
                        return
                    }
                    let finalSnapshot = self.editorSession.captureSnapshot()
                    guard let final = LibraryInlineNoteFinishPolicy.finalRevision(
                        beforeEnding: beforeEnding,
                        endedHTML: endedHTML,
                        afterEnding: finalSnapshot.map {
                            LibraryInlineNoteFinishRevision(
                                documentID: documentID,
                                sessionID: sessionID,
                                revision: $0.documentRevision,
                                html: $0.html
                            )
                        }
                    ) else {
                        self.editorSession.setInputLocked(false)
                        self.isEndingProgrammaticTransition = false
                        self.session.setFinishFailureMessage("结束输入时笔记或图片快照不一致；草稿仍保留。")
                        completion(false)
                        return
                    }
                    let receipts = self.editorSession.insertionReceipts(forDocumentID: documentID, sessionID: sessionID)
                    if !receipts.isEmpty {
                        guard let finalSnapshot,
                              finalSnapshot.html == final.html,
                              finalSnapshot.documentRevision == final.revision,
                              self.imageSnapshotIsValid(finalSnapshot, documentID: documentID, sessionID: sessionID) else {
                            self.editorSession.setInputLocked(false)
                            self.isEndingProgrammaticTransition = false
                            self.session.setFinishFailureMessage("无法读取与图片回执匹配的本地草稿快照；草稿仍保留。")
                            completion(false)
                            return
                        }
                    }
                    self.setDraftWithoutScheduling(final.html)
                    do {
                        try await self.persistManualRecoveryDraftBeforeCommit(final.html, sessionID: sessionID)
                    } catch {
                        self.editorSession.setInputLocked(false)
                        self.isEndingProgrammaticTransition = false
                        self.session.setFinishFailureMessage("本地恢复草稿写入失败，尚未切换页面；请重试。\(error.localizedDescription)")
                        completion(false)
                        return
                    }
                    self.editorSession.setInputLocked(false)
                    self.editing = false
                    self.session.setEditing(false)
                    self.editingInitialHTML = nil
                    self.editingInitialAttributedText = nil
                    self.initialSelectionOffset = nil
                    self.initialSelectionWidth = nil
                    self.isEndingProgrammaticTransition = false
                    self.session.setFinishFailureMessage(nil)
                    self.updateSessionPendingState()
                    completion(true)
                }
            }
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
        if transientErrorMessage?.hasPrefix("旧版笔记草稿基线无法验证：") == true {
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
        guard !editorSession.isMediaOperationInProgress,
              !editorSession.isAuxiliaryPanelPresented else {
            transientErrorMessage = "请先完成当前笔记附件或工具操作，再点完成。"
            updateFinishResult(false)
            completion(false)
            return
        }
        isFinishing = true
        saveTask?.cancel()
        editorSession.commitCompositionIfNeeded()
        let documentID = renderDocumentID
        let sessionID = editingSessionID
        Task { @MainActor in
            await Task.yield()
            guard self.editing,
                  self.renderDocumentID == documentID,
                  self.editingSessionID == sessionID,
                  self.editorSession.documentID == documentID,
                  self.editorSession.sessionID == sessionID else {
                self.failFinishBeforeSave(
                    message: "笔记编辑会话已切换，原会话没有提交或覆盖新内容。",
                    completion: completion
                )
                return
            }
            self.editorSession.commitCompositionIfNeeded()
            guard !self.editorSession.isComposingText,
                  let snapshot = self.editorSession.captureSnapshot() else {
                self.failFinishBeforeSave(
                    message: "无法读取输入法提交后的笔记内容，草稿仍保留在编辑器中。",
                    completion: completion
                )
                return
            }
            guard self.imageSnapshotIsValid(snapshot, documentID: documentID, sessionID: sessionID) else {
                self.failFinishBeforeSave(
                    message: "当前笔记图片与富文本快照无法对应，原草稿仍保留；请重新打开笔记检查后再保存。",
                    completion: completion
                )
                return
            }
            let beforeEnding = LibraryInlineNoteFinishRevision(
                documentID: documentID,
                sessionID: sessionID,
                revision: snapshot.documentRevision,
                html: snapshot.html
            )
            LibraryPerformanceLog.event(
                "note.finish.snapshot id=\(LibraryPerformanceLog.shortIdentifier(documentID)) session=\(sessionID.uuidString.prefix(8)) revision=\(snapshot.documentRevision) bytes=\(snapshot.html.utf8.count)"
            )
            self.editorSession.setInputLocked(true)
            self.editorSession.endEditing { endedHTML in
                Task { @MainActor in
                    guard self.editing,
                          self.renderDocumentID == documentID,
                          self.editingSessionID == sessionID,
                          self.editorSession.documentID == documentID,
                          self.editorSession.sessionID == sessionID else {
                        self.failFinishBeforeSave(
                            message: "结束输入时编辑会话已切换，当前草稿仍保留。",
                            completion: completion
                        )
                        return
                    }
                    let finalEditorSnapshot = self.editorSession.captureSnapshot()
                    if let finalEditorSnapshot,
                       !self.imageSnapshotIsValid(finalEditorSnapshot, documentID: documentID, sessionID: sessionID) {
                        self.editorSession.setInputLocked(false)
                        self.isFinishing = false
                        self.transientErrorMessage = "结束输入时图片与笔记快照不一致，原草稿仍保留；请重试。"
                        self.resolveFinishCompletions(primary: completion, result: false)
                        return
                    }
                    let afterEnding = finalEditorSnapshot.map {
                        LibraryInlineNoteFinishRevision(
                            documentID: documentID,
                            sessionID: sessionID,
                            revision: $0.documentRevision,
                            html: $0.html
                        )
                    }
                    guard let finalRevision = LibraryInlineNoteFinishPolicy.finalRevision(
                        beforeEnding: beforeEnding,
                        endedHTML: endedHTML,
                        afterEnding: afterEnding
                    ) else {
                        self.editorSession.setInputLocked(false)
                        self.isFinishing = false
                        self.transientErrorMessage = "结束输入时笔记内容发生变化，但无法读取匹配的富文本快照；原草稿仍保留，请重试。"
                        self.resolveFinishCompletions(primary: completion, result: false)
                        return
                    }
                    let matchingEditorSnapshot: NativeRichTextEditorSnapshot?
                    if let finalEditorSnapshot,
                       finalEditorSnapshot.html == finalRevision.html,
                       finalEditorSnapshot.documentRevision == finalRevision.revision {
                        matchingEditorSnapshot = finalEditorSnapshot
                    } else if snapshot.html == finalRevision.html,
                              snapshot.documentRevision == finalRevision.revision {
                        matchingEditorSnapshot = snapshot
                    } else {
                        matchingEditorSnapshot = nil
                    }
                    if !self.editorSession.insertionReceipts(forDocumentID: documentID, sessionID: sessionID).isEmpty,
                       matchingEditorSnapshot == nil {
                        self.editorSession.setInputLocked(false)
                        self.isFinishing = false
                        self.transientErrorMessage = "无法读取与插图回执匹配的最终快照，原草稿仍保留；请重试。"
                        self.resolveFinishCompletions(primary: completion, result: false)
                        return
                    }
                    LibraryPerformanceLog.event(
                        "note.finish.final id=\(LibraryPerformanceLog.shortIdentifier(documentID)) session=\(sessionID.uuidString.prefix(8)) revision=\(finalRevision.revision) bytes=\(finalRevision.html.utf8.count) changed=\(finalRevision.html != beforeEnding.html)"
                    )
                    await self.commitFinishRevision(
                        finalRevision,
                        editorSnapshot: matchingEditorSnapshot,
                        completion: completion
                    )
                }
            }
        }
    }

    private func failFinishBeforeSave(message: String, completion: @escaping (Bool) -> Void) {
        LibraryPerformanceLog.event(
            "note.finish.failed-before-save id=\(LibraryPerformanceLog.shortIdentifier(renderDocumentID)) session=\(editingSessionID.uuidString.prefix(8))"
        )
        editorSession.setInputLocked(false)
        isFinishing = false
        transientErrorMessage = message
        resolveFinishCompletions(primary: completion, result: false)
    }

    private func imageSnapshotIsValid(
        _ snapshot: NativeRichTextEditorSnapshot,
        documentID: String,
        sessionID: UUID
    ) -> Bool {
        guard snapshot.hasConsistentImageMarkers else { return false }
        guard let latestReceipt = editorSession
            .insertionReceipts(forDocumentID: documentID, sessionID: sessionID)
            .max(by: { $0.revision < $1.revision }) else { return true }
        guard snapshot.documentRevision >= latestReceipt.revision else { return false }
        if snapshot.imageMarkers != latestReceipt.imageMarkers,
           snapshot.userEditRevision <= latestReceipt.userEditRevision {
            return false
        }
        return true
    }

    private func commitFinishRevision(
        _ finalRevision: LibraryInlineNoteFinishRevision,
        editorSnapshot: NativeRichTextEditorSnapshot?,
        completion: @escaping (Bool) -> Void
    ) async {
        let content = finalRevision.html
        setDraftWithoutScheduling(content)
        if commitMode == .explicit, manualDraftHasVersionConflict {
            editorSession.setInputLocked(false)
            isFinishing = false
            transientErrorMessage = "当前记录已变化。请先在草稿区选择“以恢复草稿为准”或“保留当前内容”，再完成保存。"
            resolveFinishCompletions(primary: completion, result: false)
            return
        }
        if commitMode == .explicit {
            do {
                try await persistManualRecoveryDraftBeforeCommit(content, sessionID: finalRevision.sessionID)
            } catch {
                failFinishBeforeSave(
                    message: "本地恢复草稿写入失败，正式笔记尚未提交；请重试。\(error.localizedDescription)",
                    completion: completion
                )
                return
            }
            guard editing,
                  renderDocumentID == finalRevision.documentID,
                  editingSessionID == finalRevision.sessionID else {
                failFinishBeforeSave(
                    message: "笔记会话已切换，正式记录没有写入；草稿仍保留。",
                    completion: completion
                )
                return
            }
        }
        let stateBeforeRegister = saveService.state(recordID: renderDocumentID)
        if commitMode != .explicit {
            if stateBeforeRegister.latestBaseVersion == nil {
                activeBaseVersion = currentRecordEditVersion()
                activeBasePayload = currentRecordPayload()
            } else {
                activeBaseVersion = stateBeforeRegister.latestBaseVersion ?? activeBaseVersion
                activeBasePayload = stateBeforeRegister.latestBasePayload ?? activeBasePayload
            }
        }

        if stateBeforeRegister.confirmedContent == content,
           !saveService.hasPending(recordID: renderDocumentID),
           stateBeforeRegister.phase != .failed,
           persistedNoteReader() == content {
            finishEditorAfterConfirmedSave(
                version: stateBeforeRegister.confirmedDraftVersion,
                finalRevision: finalRevision,
                content: content,
                editorSnapshot: editorSnapshot,
                completion: completion
            )
            return
        }

        let version = saveService.registerDraft(
            recordID: renderDocumentID,
            content: content,
            baseVersion: activeBaseVersion,
            basePayload: activeBasePayload
        )
        currentDraftVersion = version
        let registered = saveService.state(recordID: renderDocumentID)
        if registered.confirmedDraftVersion == version,
           registered.confirmedContent == content,
           !saveService.hasPending(recordID: renderDocumentID),
           persistedNoteReader() == content {
            finishEditorAfterConfirmedSave(
                version: version,
                finalRevision: finalRevision,
                content: content,
                editorSnapshot: editorSnapshot,
                completion: completion
            )
            return
        }

        enqueueSave(
            content,
            draftVersion: version,
            editorSnapshot: editorSnapshot,
            baseVersion: activeBaseVersion,
            basePayload: activeBasePayload,
            onCompletion: { result in
                switch result {
                case .success:
                    let confirmed = self.saveService.state(recordID: self.renderDocumentID)
                    guard LibraryInlineNoteFinishPolicy.saveIsConfirmed(
                        finalRevision: finalRevision,
                        confirmedVersion: confirmed.confirmedDraftVersion,
                        expectedVersion: version,
                        confirmedHTML: confirmed.confirmedContent,
                        persistedHTML: self.persistedNoteReader()
                    ) else {
                        self.failFinishBeforeSave(
                            message: "保存回执与题目实际笔记字段不一致，编辑器和草稿仍保留。请重试。",
                            completion: completion
                        )
                        return
                    }
                    self.finishEditorAfterConfirmedSave(
                        version: version,
                        finalRevision: finalRevision,
                        content: content,
                        editorSnapshot: editorSnapshot,
                        completion: completion
                    )
                case .failure(let error):
                    let recovery = LibraryInlineNoteFinishPolicy.recoveryAfterSaveFailure(finalHTML: content)
                    self.setDraftWithoutScheduling(recovery.draft)
                    if recovery.unlocksInput { self.editorSession.setInputLocked(false) }
                    self.isFinishing = false
                    if self.commitMode == .explicit,
                       let saveError = error as? LibraryInlineNoteSaveError,
                       case .versionConflict = saveError {
                        self.manualDraftHasVersionConflict = true
                        self.editing = false
                        self.session.setEditing(false)
                        self.editorSession.deactivate(sessionID: self.editingSessionID)
                        self.transientErrorMessage = "题目记录已变化；当前保存内容和恢复草稿都已保留，请在下方选择处理方式。"
                        self.updateSessionPendingState()
                        self.resolveFinishCompletions(primary: completion, result: false)
                        return
                    }
                    self.transientErrorMessage = "笔记未保存，原记录未覆盖：\(error.localizedDescription)"
                    self.resolveFinishCompletions(primary: completion, result: false)
                }
            }
        )
    }

    private func persistManualRecoveryDraftBeforeCommit(_ content: String, sessionID: UUID) async throws {
        guard commitMode == .explicit,
              sessionID == editingSessionID else { throw CancellationError() }
        let recordID = renderDocumentID
        if content == storedNote {
            try await LibraryInlineNoteDraftStorage.shared.removeDrafts(
                recordID: recordID,
                through: saveService.recoveryDraftVersionHighWatermark(recordID: recordID)
            )
            manualDraftVersion = 0
            return
        }

        let version = saveService.nextRecoveryDraftVersion(
            recordID: recordID,
            after: max(manualDraftVersion, currentDraftVersion ?? 0)
        )
        let snapshot = LibraryInlineNoteDraftSnapshot(
            recordID: recordID,
            baseVersion: activeBaseVersion,
            draftVersion: version,
            content: content,
            updatedAt: .now
        )
        try await saveService.persistRecoveryDraft(snapshot, requiresBackgroundTime: true)
        guard renderDocumentID == recordID,
              editingSessionID == sessionID,
              let persisted = try await LibraryInlineNoteDraftStorage.shared.load(recordID: recordID),
              persisted.content == content,
              persisted.baseVersion == activeBaseVersion else { throw CancellationError() }
        manualDraftVersion = persisted.draftVersion
        currentDraftVersion = persisted.draftVersion
    }

    private func installConfirmedPreview(
        content: String,
        editorSnapshot: NativeRichTextEditorSnapshot?
    ) {
        onSaved?(content)
        let key = LibraryInlineNoteRenderKey(
            documentID: renderDocumentID,
            version: questionBankContextVersion,
            html: content
        )
        if let editorSnapshot, editorSnapshot.html == content {
            let formatted = NativeRichTextDisplayRenderer.applyingNoteFormatting(
                to: NativeRichTextDisplayRenderResult(
                    attributedText: editorSnapshot.attributedText,
                    usedSafeFallback: false
                ),
                sourceHTML: content
            )
            preparedNote = PreparedLibraryInlineNote(
                key: key,
                result: formatted,
                editableAttributedText: formatted.attributedText.copy() as? NSAttributedString ?? formatted.attributedText,
                editorDocumentRevision: editorSnapshot.documentRevision
            )
            displayWarning = nil
        } else {
            // Do not re-import saved HTML on the main actor after commit. The
            // keyed preparation task supplies a bounded, non-WebKit preview.
            preparedNote = nil
            displayWarning = nil
        }
        preparationFailureKey = nil
    }

    private func finishEditorAfterConfirmedSave(
        version: UInt64,
        finalRevision: LibraryInlineNoteFinishRevision,
        content: String,
        editorSnapshot: NativeRichTextEditorSnapshot?,
        completion: @escaping (Bool) -> Void
    ) {
        let state = saveService.state(recordID: renderDocumentID)
        guard finalRevision.documentID == renderDocumentID,
              finalRevision.sessionID == editingSessionID,
              LibraryInlineNoteFinishPolicy.saveIsConfirmed(
                finalRevision: finalRevision,
                confirmedVersion: state.confirmedDraftVersion,
                expectedVersion: version,
                confirmedHTML: state.confirmedContent,
                persistedHTML: persistedNoteReader()
              ) else {
            editorSession.setInputLocked(false)
            isFinishing = false
            transientErrorMessage = "最新笔记版本尚未与题目实际保存内容对齐，编辑器仍保持打开。"
            resolveFinishCompletions(primary: completion, result: false)
            return
        }
        editorSession.confirmImageInsertionsSaved(
            documentID: finalRevision.documentID,
            sessionID: finalRevision.sessionID,
            revision: finalRevision.revision
        )
        removeSupersededLegacyDraftIfMatching()
        if commitMode == .explicit {
            manualDraftHasVersionConflict = false
            let recordID = renderDocumentID
            let recoveryVersion = manualDraftVersion
            manualDraftVersion = 0
            if recoveryVersion > 0 {
                Task {
                    try? await LibraryInlineNoteDraftStorage.shared.removeDrafts(
                        recordID: recordID,
                        through: recoveryVersion
                    )
                }
            }
        }
        installConfirmedPreview(content: content, editorSnapshot: editorSnapshot)
        onFinishConfirmed?(content)
        editing = false
        session.setEditing(false)
        editingInitialHTML = nil
        editingInitialAttributedText = nil
        initialSelectionOffset = nil
        initialSelectionWidth = nil
        isFinishing = false
        transientErrorMessage = nil
        updateSessionPendingState()
        LibraryPerformanceLog.event(
            "note.finish.preview-confirmed id=\(LibraryPerformanceLog.shortIdentifier(renderDocumentID)) session=\(finalRevision.sessionID.uuidString.prefix(8)) revision=\(finalRevision.revision) version=\(version) bytes=\(content.utf8.count)"
        )
        resolveFinishCompletions(primary: completion, result: true)
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
        if commitMode == .explicit {
            session.setPendingChanges(
                editing
                    || isEndingProgrammaticTransition
                    || isRestoringDraft
                    || manualDraftHasVersionConflict
                    || draft != storedNote
            )
            if !session.hasPendingChanges { session.setFinishFailureMessage(nil) }
            return
        }
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
        isInsertingPhoto = false
        transientErrorMessage = nil
        LibraryPerformanceLog.event(
            "note.photo.picker-open request=\(request.id.uuidString.prefix(8)) revision=\(target.revision)"
        )
        isPhotoPickerPresented = true
    }

    @MainActor
    private func loadAndInsertPhoto(_ provider: NSItemProvider, requestID: UUID) async {
        guard photoImportRequestID == requestID else { return }
        guard let target = photoImportTarget,
              editorSession.imageImportRequest?.id == requestID,
              editorSession.matches(target) else {
            finishImageImport(
                requestID: requestID,
                errorMessage: "插入位置已失效，图片没有加入笔记。请重新点选正文位置后重试。"
            )
            return
        }

        do {
            LibraryPerformanceLog.event("note.photo.selected request=\(requestID.uuidString.prefix(8))")
            let sourceData = try await loadImageData(from: provider)
            try Task.checkCancellation()
            guard photoImportRequestID == requestID,
                  editorSession.imageImportRequest?.id == requestID,
                  editorSession.matches(target) else {
                throw NativeRichTextEditorError.editorSessionChanged
            }
            guard !sourceData.isEmpty else { throw LibraryInlineNotePhotoError.noData }
            let compressed = try await Task.detached(priority: .userInitiated) {
                try LibraryInlineNotePhotoCodec.jpegData(from: sourceData)
            }.value
            let dataURL = "data:image/jpeg;base64,\(compressed.base64EncodedString())"
            let marker = Data(dataURL.utf8).base64EncodedString()
            guard compressed.count <= LibraryInlineNotePhotoCodec.maximumRoundTripBytes,
                  dataURL.utf8.count <= NativeRichTextFallbackImageLimits.maximumDataURLBytes,
                  marker.utf8.count <= NativeRichTextFallbackImageLimits.maximumMarkerPayloadBytes,
                  dataURL.utf8.count <= NativeRichTextImageLimits.maximumEncodedBytes else {
                throw LibraryInlineNotePhotoError.tooLarge
            }

            guard photoImportRequestID == requestID,
                  editorSession.imageImportRequest?.id == requestID,
                  editorSession.matches(target) else {
                throw NativeRichTextEditorError.editorSessionChanged
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
        LibraryPerformanceLog.event(
            "note.photo.finished request=\(requestID.uuidString.prefix(8)) success=\(errorMessage == nil)"
        )
        photoImportTarget = nil
        photoImportRequestID = nil
        photoLoadTask?.cancel()
        photoLoadTask = nil
        isInsertingPhoto = false
        isPhotoPickerPresented = false
        editorSession.finishImageImport(requestID: requestID)
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data {
        let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) ?? UTType.image.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: LibraryInlineNotePhotoError.loadFailed(error.localizedDescription))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: LibraryInlineNotePhotoError.noData)
                }
            }
        }
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

    private func removeSupersededLegacyDraftIfMatching() {
        guard let draftVersion = legacyDraftVersionAwaitingReplacement else { return }
        legacyDraftVersionAwaitingReplacement = nil
        let recordID = renderDocumentID
        Task {
            try? await LibraryInlineNoteDraftStorage.shared.removeIfMatching(
                recordID: recordID,
                draftVersion: draftVersion
            )
        }
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
        guard commitMode == .automatic || isFinishing else {
            LibraryPerformanceLog.event(
                "note.save.blocked-explicit-policy id=\(LibraryPerformanceLog.shortIdentifier(renderDocumentID)) session=\(editingSessionID.uuidString.prefix(8))"
            )
            return
        }
        transientErrorMessage = nil
        let state = saveService.state(recordID: renderDocumentID)
        let effectiveBaseVersion = baseVersion ?? state.latestBaseVersion ?? activeBaseVersion
        let effectiveBasePayload = basePayload ?? state.latestBasePayload ?? activeBasePayload
        LibraryPerformanceLog.event(
            "note.save.enqueue id=\(LibraryPerformanceLog.shortIdentifier(renderDocumentID)) session=\(editingSessionID.uuidString.prefix(8)) draft=\(draftVersion) bytes=\(content.utf8.count) snapshotRevision=\(editorSnapshot?.documentRevision.description ?? "none")"
        )
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
                    LibraryPerformanceLog.event(
                        "note.save.completed id=\(LibraryPerformanceLog.shortIdentifier(self.renderDocumentID)) draft=\(draftVersion) version=\(version)"
                    )
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
                        if let editorSnapshot {
                            self.editorSession.confirmImageInsertionsSaved(
                                documentID: self.renderDocumentID,
                                sessionID: self.editingSessionID,
                                revision: editorSnapshot.documentRevision
                            )
                        }
                        self.removeSupersededLegacyDraftIfMatching()
                        self.transientErrorMessage = nil
                        if !self.isFinishing { self.onSaved?(content) }
                    }
                case .failure(let error):
                    LibraryPerformanceLog.event(
                        "note.save.failed id=\(LibraryPerformanceLog.shortIdentifier(self.renderDocumentID)) draft=\(draftVersion) errorType=\(String(reflecting: type(of: error)))"
                    )
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
