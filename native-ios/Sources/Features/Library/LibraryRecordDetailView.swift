import Foundation
import CoreFoundation
import ImageIO
import SwiftData
import SwiftUI
import UIKit

private struct LibraryRedoAttempt: Equatable {
    var selectedLetters: Set<String> = []
    var submitted = false
}

private struct LibraryDetailAttribute: Identifiable {
    let key: String
    let label: String
    let value: String
    var choices: [String] = []
    var id: String { key }
}

@MainActor
private final class LibraryRedoAttemptSession: ObservableObject {
    static let shared = LibraryRedoAttemptSession()
    @Published private var attempts: [String: LibraryRedoAttempt] = [:]

    func attempt(for recordID: String) -> LibraryRedoAttempt {
        attempts[recordID] ?? LibraryRedoAttempt()
    }

    func update(_ recordID: String, _ change: (inout LibraryRedoAttempt) -> Void) {
        guard !recordID.isEmpty else { return }
        var attempt = attempts[recordID] ?? LibraryRedoAttempt()
        change(&attempt)
        attempts[recordID] = attempt
    }
}

struct LibraryRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @Query(filter: #Predicate<StoredRecord> { record in record.collection == "words" || record.collection == "errors" || record.collection == "exams" }) private var records: [StoredRecord]
    let kind: LibraryContentKind
    let scope: LibraryScope
    let record: StoredRecord?
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onCancelEditRequest: () -> Void = {}
    var orderedRecordIDs: [String] = []
    var onNavigateToRecord: ((String) -> Void)? = nil
    var onOpenLinkedWord: ((String) -> Void)? = nil
    var onOpenLinkedError: ((String) -> Void)? = nil

    @State private var object: [String: Any]
    @State private var imageSourceIdentities: [String: LibraryDetailImageSourceIdentity]
    @State private var payloadDecodeFailed = false
    @State private var lastLocallySavedNoteUpdate: Date?

    @State private var showDelete = false
    @AppStorage("native.library.errors.redoMode") private var redoPracticeEnabled = false
    @StateObject private var noteSession = LibraryInlineNoteSession()
    @StateObject private var redoSession = LibraryRedoAttemptSession.shared
    @State private var showWordSelection = false
    @State private var linkedWordCreationCategory: WordCategory?
    @State private var linkedWordDetailTarget: LinkedWordDetailTarget?
    @State private var linkedQuestionBankContext: QuestionBankQuestionAnalysisContext?
    @State private var linkedQuestionFallbackObject: [String: Any] = [:]
    @State private var editingAttribute: LibraryDetailAttribute?
    @State private var editingErrorCauses: LibraryDetailAttribute?
    @State private var detailAttributeSaveError: String?
    @State private var isMaterialPaneOpen = false
    @State private var splitDoodleLayoutDirection: LibraryDoodleLayoutDirection = .vertical
    @State private var splitDoodleErrorMessage: String?
    @State private var pendingEditorRequestID: String?
    @State private var pendingEditorTransitionRecordID: String?
    @State private var editorTransitionErrorMessage: String?
    @State private var didHandOffEditRequest = false

    init(
        kind: LibraryContentKind,
        scope: LibraryScope,
        record: StoredRecord,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancelEditRequest: @escaping () -> Void = {},
        orderedRecordIDs: [String] = [],
        onNavigateToRecord: ((String) -> Void)? = nil,
        onOpenLinkedWord: ((String) -> Void)? = nil,
        onOpenLinkedError: ((String) -> Void)? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.record = record
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onCancelEditRequest = onCancelEditRequest
        self.orderedRecordIDs = orderedRecordIDs
        self.onNavigateToRecord = onNavigateToRecord
        self.onOpenLinkedWord = onOpenLinkedWord
        self.onOpenLinkedError = onOpenLinkedError
        if let decodedObject = record.jsonObject {
            _object = State(initialValue: decodedObject)
            _imageSourceIdentities = State(initialValue: Self.makeImageSourceIdentities(for: decodedObject))
            _payloadDecodeFailed = State(initialValue: false)
        } else {
            _object = State(initialValue: [:])
            _imageSourceIdentities = State(initialValue: [:])
            _payloadDecodeFailed = State(initialValue: true)
        }
    }

    var body: some View {
        detailBehavior
    }

    private var detailBehavior: some View {
        detailStateTracking
            .task(id: linkedQuestionContextKey) { loadLinkedQuestionContext() }
    }

    private var detailStateTracking: some View {
        detailNavigationDestination
            .onChange(of: record?.updatedAt) { _, newValue in
                guard let record else { return }
                if let newValue,
                   let lastSavedAt = lastLocallySavedNoteUpdate,
                   newValue == lastSavedAt {
                    lastLocallySavedNoteUpdate = nil
                    return
                }
                if let decodedObject = record.jsonObject {
                    refreshObject(decodedObject)
                    payloadDecodeFailed = false
                } else {
                    refreshObject([:])
                    payloadDecodeFailed = true
                }
            }
            .onChange(of: activeRecordID) { _, newRecordID in
                if doodleSession.isPresented, doodleSession.targetRecordID != newRecordID {
                    doodleSession.dismiss(reopenOnSaveFailure: false) { error in
                        if let error { splitDoodleErrorMessage = error }
                    }
                }
                if let pendingEditorRequestID {
                    onCancelEditRequest()
                    LibraryPerformanceLog.editorTransition(
                        "menu-action",
                        recordID: pendingEditorTransitionRecordID ?? pendingEditorRequestID,
                        details: "cancelled-after-record-change",
                        completes: true,
                        transitionKey: "menu-action"
                    )
                    didHandOffEditRequest = false
                }
                isMaterialPaneOpen = false
                pendingEditorRequestID = nil
                pendingEditorTransitionRecordID = nil
                editorTransitionErrorMessage = nil
                didHandOffEditRequest = false
            }
            .onChange(of: doodleSession.activeSplitDrawingPane) { oldPane, newPane in
                guard doodleSession.isPresented,
                      let oldPane,
                      let newPane,
                      oldPane != newPane else { return }
                doodleSession.canvas.controller.beginDrawingReload()
                doodleSession.canvas.drawingData = doodleSession.splitDrawingData(
                    for: newPane,
                    layout: splitDoodleLayoutDirection
                )
                doodleSession.canvas.legacyPreviewDataURL = ""
            }
    }

    private var detailNavigationDestination: some View {
        detailSheets
            .navigationDestination(item: $linkedWordDetailTarget) { target in
                if let word = records.first(where: { $0.collection == "words" && $0.recordID == target.recordID }) {
                    WordLibraryRecordDetailView(
                        record: word,
                        showsReviewAction: true,
                        onOpenLinkedError: onOpenLinkedError
                    )
                }
            }
    }

    private var detailSheets: some View {
        detailToolbarContainer
            .sheet(item: $linkedWordCreationCategory) { category in
                NavigationStack {
                    LibraryRecordEditorView(
                        kind: .words,
                        scope: LibraryScope(subject: "言语理解", module: "逻辑填空"),
                        preferredType: category.rawValue,
                        onSaved: linkNewWord
                    )
                }
            }
            .sheet(item: $editingAttribute) { attribute in
                LibraryDetailAttributeEditor(attribute: attribute) { value in
                    saveDetailAttribute(attribute, value: value)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingErrorCauses) { attribute in
                LibraryErrorCauseEditor(attribute: attribute) { value in
                    saveDetailAttribute(attribute, value: value)
                }
                .presentationDetents([.medium, .large])
            }
    }

    private var detailToolbarContainer: some View {
        detailNavigationContainer
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    detailToolbar
                }
                .documentToolbarBackground()
            }
    }

    private var detailNavigationContainer: some View {
        detailContent
            .navigationTitle(detailNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
            .toolbar(.visible, for: .navigationBar)
            .onAppear(perform: resetEditorRequestAfterReturn)
            .onAppear {
                if isRedoPractice {
                    redoSession.update(activeRecordID) { $0 = LibraryRedoAttempt() }
                }
            }
            .onChange(of: activeRecordID) { _, newValue in
                if isRedoPractice {
                    redoSession.update(newValue) { $0 = LibraryRedoAttempt() }
                }
            }
            .onDisappear(perform: invalidateEditorRequestOnExit)
            .alert(
                Text(splitDoodleErrorMessage == nil ? "无法打开编辑" : "涂鸦未保存"),
                isPresented: Binding(
                    get: { editorTransitionErrorMessage != nil || splitDoodleErrorMessage != nil },
                    set: {
                        if !$0 {
                            editorTransitionErrorMessage = nil
                            splitDoodleErrorMessage = nil
                        }
                    }
            )) {
                Button("好", role: .cancel) {
                    editorTransitionErrorMessage = nil
                    splitDoodleErrorMessage = nil
                }
            } message: {
                Text(splitDoodleErrorMessage ?? editorTransitionErrorMessage ?? "")
            }
    }

    private var detailNavigationTitle: String {
        SubjectModuleTitle.errorDetailTitle(
            recordModule: record?.module,
            payloadModule: object["module"] as? String,
            questionBankModule: displayQuestionBankContext?.typeMapping.module
        )
    }

    private var detailContent: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width.isFinite ? max(0, proxy.size.width) : 0
            let layoutDirection = splitLayoutDirection(for: proxy.size)
            ZStack {
                if payloadDecodeFailed {
                    NativeStatusCard(
                        title: "错题详情暂时无法读取",
                        detail: "原始记录数据无法解析。笔记和编辑保存已阻止，以保留数据库中的原始内容。",
                        systemImage: "exclamationmark.triangle",
                        color: AppTheme.warning
                    )
                    .padding(16)
                    .accessibilityIdentifier("library-record-detail-payload-error")
                } else if showsDetachedDataAnalysisMaterial {
                    dataAnalysisSplitLayout(
                        availableSize: proxy.size,
                        layoutDirection: splitDoodleLayoutDirection
                    )
                } else {
                    detailScrollView(availableWidth: availableWidth)
                }
                detailModal
            }
            .overlay(alignment: .top) {
                if pendingEditorRequestID != nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在打开…")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("正在打开编辑")
                }
            }
            .onAppear {
                if !doodleSession.isPresented || !doodleSession.isSplitDrawingSession {
                    splitDoodleLayoutDirection = layoutDirection
                }
            }
            .onChange(of: layoutDirection) { _, newDirection in
                handleSplitDoodleLayoutChange(to: newDirection)
            }
        }
    }

    private func detailScrollView(availableWidth: CGFloat) -> some View {
        detailReadingScrollView(availableWidth: availableWidth, separatesDataAnalysisMaterial: false, showsDoodle: true)
    }

    @ViewBuilder
    private func dataAnalysisSplitLayout(
        availableSize: CGSize,
        layoutDirection: LibraryDoodleLayoutDirection
    ) -> some View {
        if layoutDirection == .horizontal {
            let contentWidth = max(0, availableSize.width - 36)
            let materialWidth = contentWidth * 0.49
            let questionWidth = contentWidth - materialWidth
            HStack(alignment: .top, spacing: 12) {
                dataAnalysisMaterialPane(availableWidth: materialWidth)
                    .frame(width: materialWidth)
                    .frame(maxHeight: .infinity)
                detailReadingScrollView(
                    availableWidth: questionWidth,
                    separatesDataAnalysisMaterial: true,
                    showsDoodle: false,
                    splitDoodlePane: .question
                )
                .frame(width: questionWidth)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
        } else {
            let materialHeight = max(130, availableSize.height * 0.38)
            let contentWidth = max(0, availableSize.width - 16)
            VStack(spacing: 8) {
                dataAnalysisMaterialPane(availableWidth: contentWidth)
                    .frame(height: materialHeight)
                detailReadingScrollView(
                    availableWidth: contentWidth,
                    separatesDataAnalysisMaterial: true,
                    showsDoodle: false,
                    splitDoodlePane: .question
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
        }
    }

    private func dataAnalysisMaterialPane(availableWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("材料")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("收起材料") { isMaterialPaneOpen = false }
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("library-data-analysis-material-close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    dataAnalysisMaterialBlock
                    imagesBlock(availableWidth: max(1, availableWidth - 24))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .overlay {
                    LibraryDoodleSplitContentLayer(
                        session: doodleSession,
                        targetRecordID: activeRecordID,
                        pane: .material,
                        layoutDirection: splitDoodleLayoutDirection,
                        drawingData: splitDoodleBinding(for: .material)
                    )
                }
            }
            .accessibilityIdentifier("library-data-analysis-material-scroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func detailReadingScrollView(
        availableWidth: CGFloat,
        separatesDataAnalysisMaterial: Bool,
        showsDoodle: Bool,
        splitDoodlePane: LibraryDoodlePane? = nil
    ) -> some View {
        let readingColumnWidth = min(availableWidth.isFinite ? max(0, availableWidth) : 0, 920)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if kind == .errors {
                    errorClassificationAndMasteryRow
                }
                reviewContent(metadata)
                if kind == .errors && isDataAnalysis {
                    if !separatesDataAnalysisMaterial {
                        dataAnalysisMaterialAction
                        dataAnalysisMaterialBlock
                        imagesBlock(availableWidth: max(0, readingColumnWidth - 32))
                    }
                    questionBlock
                } else {
                    questionBankMaterialBlock
                    questionBlock
                    imagesBlock(availableWidth: max(0, readingColumnWidth - 32))
                }
                optionsBlock
                redoFeedbackBlock
                    .opacity(isRedoPractice ? 1 : 0)
                    .allowsHitTesting(isRedoPractice)
                    .accessibilityHidden(!isRedoPractice)
                reviewContent(answerAndSource)
                reviewContent(explanationBlock)
                reviewContent(comparisonBlock)
                reviewContent(linkedErrorBlock)
                reviewContent(reviewBlock)
                reviewContent(noteBlock)
                reviewContent(dateBlock)
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)
            .padding(.bottom, 14)
            .frame(width: readingColumnWidth, alignment: .leading)
            .overlay {
                if let splitDoodlePane {
                    LibraryDoodleSplitContentLayer(
                        session: doodleSession,
                        targetRecordID: activeRecordID,
                        pane: splitDoodlePane,
                        layoutDirection: splitDoodleLayoutDirection,
                        drawingData: splitDoodleBinding(for: splitDoodlePane)
                    )
                } else if showsDoodle {
                    LibraryDoodleContentLayer(
                        session: doodleSession,
                        targetRecordID: activeRecordID
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.white)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded(navigateFromHorizontalSwipe)
        )
        .accessibilityIdentifier(displayQuestionBankContext.map {
            "question-bank-detail-scroll-\($0.question.id)"
        } ?? (separatesDataAnalysisMaterial ? "library-record-detail-question-scroll" : "library-record-detail-scroll"))
    }

    @ViewBuilder
    private var dataAnalysisMaterialAction: some View {
        if kind == .errors, isDataAnalysis, hasDataAnalysisMaterial {
            Button {
                isMaterialPaneOpen = true
            } label: {
                Label("弹出材料", systemImage: "rectangle.split.2x1")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("library-data-analysis-material-open")
        }
    }

    private var hasDataAnalysisMaterial: Bool {
        !(firstText(["dataAnalysisMaterialText"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !imageValues.isEmpty
    }

    private var showsDetachedDataAnalysisMaterial: Bool {
        kind == .errors && isDataAnalysis && hasDataAnalysisMaterial && isMaterialPaneOpen
    }

    private func splitLayoutDirection(for size: CGSize) -> LibraryDoodleLayoutDirection {
        size.width >= 900 && size.width > size.height ? .horizontal : .vertical
    }

    private func handleSplitDoodleLayoutChange(to newDirection: LibraryDoodleLayoutDirection) {
        guard newDirection != splitDoodleLayoutDirection else { return }
        guard isMaterialPaneOpen, doodleSession.isPresented, doodleSession.isSplitDrawingSession else {
            splitDoodleLayoutDirection = newDirection
            return
        }

        doodleSession.commitCurrentDrawing {
            doodleSession.dismiss(reopenOnSaveFailure: false) { error in
                splitDoodleLayoutDirection = newDirection
                if let error { splitDoodleErrorMessage = error }
            }
        }
    }

    private func splitDoodleStorageKey(
        pane: LibraryDoodlePane,
        layout: LibraryDoodleLayoutDirection
    ) -> String {
        LibraryDoodleSession.splitDrawingStorageKey(pane: pane, layout: layout)
    }

    private func splitDoodleBinding(for pane: LibraryDoodlePane) -> Binding<String> {
        let layout = splitDoodleLayoutDirection
        return Binding(
            get: { doodleSession.splitDrawingData(for: pane, layout: layout) },
            set: { value in
                doodleSession.updateSplitDrawingData(value, for: pane, layout: layout)
            }
        )
    }

    private func storedSplitDoodleValues(in payload: [String: Any]) -> [String: String] {
        let storedByLayout = payload["splitDoodleDrawings"] as? [String: Any] ?? [:]
        var values: [String: String] = [:]
        for layout in LibraryDoodleLayoutDirection.allCases {
            let storedByPane = storedByLayout[layout.rawValue] as? [String: Any] ?? [:]
            for pane in LibraryDoodlePane.allCases {
                values[splitDoodleStorageKey(pane: pane, layout: layout)] = storedByPane[pane.rawValue] as? String ?? ""
            }
        }
        return values
    }

    private func saveSplitDoodleChanges(record: StoredRecord, context: ModelContext) -> String? {
        let changedValues = doodleSession.pendingSplitDrawingValues()
        guard !changedValues.isEmpty else { return nil }
        guard let error = LibraryDoodlePersistence.saveSplitDrawings(
            record: record,
            context: context,
            drawingValues: changedValues
        ) else {
            doodleSession.markSplitDrawingValuesSaved()
            return nil
        }
        return error
    }

    private func navigateFromHorizontalSwipe(_ value: DragGesture.Value) {
        guard kind == .errors,
              !doodleSession.isPresented,
              !noteSession.isEditing,
              let onNavigateToRecord,
              let record,
              let currentIndex = orderedRecordIDs.firstIndex(of: record.recordID),
              abs(value.translation.width) >= 80,
              abs(value.translation.height) <= max(36, abs(value.translation.width) * 0.35)
        else { return }

        let nextIndex = currentIndex + (value.translation.width < 0 ? 1 : -1)
        guard orderedRecordIDs.indices.contains(nextIndex) else { return }
        onNavigateToRecord(orderedRecordIDs[nextIndex])
    }

    @ViewBuilder
    private var detailModal: some View {
        if showDelete {
            NativeDeleteDialog(
                title: "删除错题",
                message: "删除后无法在 App 内恢复。",
                onDelete: { showDelete = false; onDelete() },
                onCancel: { showDelete = false }
            )
        } else if showWordSelection {
            LibraryRelationSelectionDialog(
                collection: "words",
                candidates: records.filter {
                    LibraryRelationCandidateScope.includes(
                        candidateCollection: $0.collection,
                        targetCollection: "words"
                    )
                },
                selection: linkedWordSelection,
                onClose: { showWordSelection = false },
                onCreateWord: { category in
                    showWordSelection = false
                    linkedWordCreationCategory = category
                }
            )
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 8) {
            detailToolbarActions
        }
        .frame(minHeight: 44)
        .id(doodleSession.isPresented ? "record-toolbar-doodle" : "record-toolbar-detail")
    }

    @ViewBuilder
    private var detailToolbarActions: some View {
        if doodleSession.isPresented {
            toolbarPlaceholder
            toolbarPlaceholder
        } else {
            Button(action: openDoodle) { Image(systemName: "pencil.and.scribble") }
                .accessibilityLabel("涂鸦")
            if pendingEditorRequestID != nil {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("正在打开编辑")
            } else {
                questionActionsMenu
            }
        }
    }

    private var toolbarPlaceholder: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var questionActionsMenu: some View {
        legacyQuestionActionsMenu
    }

    private var legacyQuestionActionsMenu: some View {
        Menu {
            Button {
                requestEdit()
            } label: {
                Label("编辑错题", systemImage: "pencil")
            }
            .disabled(pendingEditorRequestID != nil)
            if supportsRedoMode {
                Button {
                    toggleRedoMode()
                } label: {
                    Label(redoModeActionTitle, systemImage: redoModeActionImage)
                }
            }
            Button(role: .destructive) {
                noteSession.finish { saved in
                    if saved { showDelete = true }
                }
            } label: {
                Label("删除错题", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("题目操作")
        .accessibilityIdentifier("library-record-actions")
    }

    private func requestEdit() {
        guard pendingEditorRequestID == nil, !doodleSession.isPresented else { return }
        let requestID = activeRecordID
        let transitionRecordID = record?.recordID ?? requestID
        pendingEditorRequestID = requestID
        pendingEditorTransitionRecordID = transitionRecordID
        editorTransitionErrorMessage = nil
        LibraryPerformanceLog.editorTransition(
            "menu-action",
            recordID: transitionRecordID,
            details: "edit-request",
            begins: true,
            transitionKey: "menu-action"
        )

        guard noteSession.isEditing || noteSession.hasPendingChanges else {
            handoffEditRequest(
                requestID: requestID,
                transitionRecordID: transitionRecordID,
                detail: "note-clean-fast-path"
            )
            return
        }

        LibraryPerformanceLog.editorTransition(
            "menu-note-finish",
            recordID: transitionRecordID,
            details: "waiting-for-note-save",
            begins: true,
            transitionKey: "note-finish"
        )
        noteSession.finish { saved in
            LibraryPerformanceLog.editorTransition(
                "menu-note-finish",
                recordID: transitionRecordID,
                details: "saved=\(saved)",
                completes: true,
                transitionKey: "note-finish"
            )
            guard self.pendingEditorRequestID == requestID, self.activeRecordID == requestID else { return }
            guard saved else {
                self.editorTransitionErrorMessage = self.noteSession.finishFailureMessage
                    ?? "笔记尚未成功保存，编辑页面没有打开。"
                self.pendingEditorRequestID = nil
                self.pendingEditorTransitionRecordID = nil
                LibraryPerformanceLog.editorTransition(
                    "menu-action",
                    recordID: transitionRecordID,
                    details: "note-save-failed",
                    completes: true,
                    transitionKey: "menu-action"
                )
                return
            }
            self.handoffEditRequest(
                requestID: requestID,
                transitionRecordID: transitionRecordID,
                detail: "note-saved"
            )
        }
    }

    private func handoffEditRequest(requestID: String, transitionRecordID: String, detail: String) {
        guard pendingEditorRequestID == requestID, activeRecordID == requestID else { return }
        didHandOffEditRequest = true
        onEdit()
        LibraryPerformanceLog.editorTransition(
            "menu-action",
            recordID: transitionRecordID,
            details: detail,
            completes: true,
            transitionKey: "menu-action"
        )
    }

    private func resetEditorRequestAfterReturn() {
        guard pendingEditorRequestID != nil else { return }
        pendingEditorRequestID = nil
        pendingEditorTransitionRecordID = nil
        didHandOffEditRequest = false
    }

    private func invalidateEditorRequestOnExit() {
        guard let pendingEditorRequestID else { return }
        let wasHandedOff = didHandOffEditRequest
        let transitionRecordID = pendingEditorTransitionRecordID ?? pendingEditorRequestID
        self.pendingEditorRequestID = nil
        pendingEditorTransitionRecordID = nil
        didHandOffEditRequest = false
        onCancelEditRequest()
        if !wasHandedOff {
            LibraryPerformanceLog.editorTransition(
                "menu-action",
                recordID: transitionRecordID,
                details: "cancelled-after-detail-exit",
                completes: true,
                transitionKey: "menu-action"
            )
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            let isDifficult = (object["isDifficult"] as? Bool) ?? (object["isDifficult"] as? NSNumber)?.boolValue ?? false
            let needsReview = (object["needsReview"] as? Bool) ?? (object["needsReview"] as? NSNumber)?.boolValue ?? false
            if isDifficult || needsReview || displayQuestionBankContext != nil {
                HStack(spacing: 6) {
                    if isDifficult || displayQuestionBankContext?.currentQuestion.isDifficult == true {
                        editableMetadataBadge(
                            "难题",
                            color: AppTheme.danger,
                            key: "isDifficult",
                            value: isDifficult ? "是" : "否",
                            choices: ["否", "是"]
                        )
                    }
                    if needsReview || displayQuestionBankContext?.currentQuestion.needsReview == true {
                        editableMetadataBadge(
                            "待复习",
                            color: AppTheme.warning,
                            key: "needsReview",
                            value: needsReview ? "是" : "否",
                            choices: ["否", "是"]
                        )
                    }
                }
            }
            if isQuantityRelations {
                metadataTextLine("题型", value: QuantityQuestionTypeCatalog.displayName(for: activeModule))
                metadataTextLine("题目结构", value: firstText(["quantityStructure"]) ?? "")
                metadataTagLine("考点", values: knowledgePoints, emphasis: .strong)
                metadataTagLine(errorCauseLabel, values: quantityErrorCauseValues, emphasis: .subtle)
            } else {
                if displayQuestionBankContext != nil, !activeModule.isEmpty {
                    metadataTextLine("题型", value: activeModule)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("question-bank-detail-question-type")
                }
                metadataTagLine(knowledgePointLabel, values: knowledgePoints, emphasis: .strong)
                if LibraryErrorCauseCompatibility.usesLineEditor(subject: activeSubject, module: activeModule) {
                    lineCauseMetadata
                } else if isAnalogyReasoning {
                    metadataTextLine(errorCauseLabel, value: firstText(["errorCause", "cause", "reason"]) ?? "")
                } else {
                    metadataTagLine(errorCauseLabel, values: splitTags(firstText(["errorCause", "cause", "reason"]) ?? ""), emphasis: .subtle)
                }
                if LibraryErrorCauseCompatibility.isCenterUnderstanding(subject: activeSubject, module: activeModule) {
                    let centerTrap = firstText(["centerComprehensionTrap"]) ?? ""
                    if !clean(centerTrap).isEmpty {
                        metadataTextLine("陷阱", value: centerTrap)
                    }
                }
                if isGraphReasoning {
                    metadataTextLine("图形规律", value: firstText(["graphRule", "patternRule"]) ?? "")
                    metadataTextLine("识别思路", value: firstText(["recognition", "recognitionPath"]) ?? "")
                }
            }
            let reminder = firstText(["reminder"]) ?? ""
            if !isAnalogyReasoning || !reminder.isEmpty {
                metadataTextLine(isAnalogyReasoning ? "常识" : "提醒", value: reminder)
            }
        }
    }

    @ViewBuilder private var questionBankMaterialBlock: some View {
        if let context = displayQuestionBankContext, let material = context.material {
            VStack(alignment: .leading, spacing: 9) {
                Text("共用材料")
                    .font(AppTheme.sectionTitleFont)
                if !material.text.isEmpty {
                    Text(verbatim: material.text)
                        .font(AppTheme.questionTextFont)
                        .lineSpacing(AppTheme.questionLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !material.imageAssetID.isEmpty,
                   let asset = context.assetsByID[material.imageAssetID] {
                    LegacyQuestionBankAssetImage(asset: asset, sizing: .material)
                }
                ForEach(Array(context.materialSourceRows.enumerated()), id: \.offset) { _, row in
                    supportingLine("材料来源", value: row, systemImage: "books.vertical.fill")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(detailBackground, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var dataAnalysisMaterialBlock: some View {
        let material = firstText(["dataAnalysisMaterialText"]) ?? ""
        if !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: cleanMultiline(material))
                    .font(detailQuestionFont)
                    .lineSpacing(AppTheme.questionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder private func imagesBlock(availableWidth: CGFloat) -> some View {
        if !imageValues.isEmpty {
            let widthFractions = LibraryImageDisplaySetting.widthFractions(
                from: object["imageDisplayMetadata"],
                count: imageValues.count
            )
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(imageValues.enumerated()), id: \.offset) { index, source in
                    let metadata = (object["imageDisplayMetadata"] as? [[String: Any]] ?? [])
                    let imageMetadataID = index < metadata.count ? (metadata[index]["id"] as? String ?? "") : ""
                    if let asset = displayQuestionBankContext?.assetsByID[source] {
                        LegacyQuestionBankAssetImage(asset: asset, sizing: .stem)
                            .frame(maxWidth: max(1, availableWidth * CGFloat(widthFractions[index])), alignment: .leading)
                    } else {
                        LibraryDetailImage(
                            source: source,
                            cacheKey: imageCacheKey(kind: "image", index: index, source: source, metadataID: imageMetadataID),
                            availableWidth: availableWidth,
                            widthFraction: widthFractions[index],
                            showsFrame: false
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 3)
        }
    }

    @ViewBuilder private var questionBlock: some View {
        if let rawQuestion = firstText(["question", "title", "name", "text", "content"]),
           !clean(rawQuestion).isEmpty {
            Text(cleanMultiline(rawQuestion))
                .font(detailQuestionFont)
                .lineSpacing(AppTheme.questionLineSpacing)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(webBorder, lineWidth: 0.8)
                }
                .accessibilityIdentifier(
                    displayQuestionBankContext.map { "question-bank-detail-stem-\($0.question.id)" }
                        ?? "library-record-detail-stem"
                )
        }
    }

    @ViewBuilder private var optionsBlock: some View {
        let options = stringArray("options") ?? []
        let optionImages = optionImageValues
        let optionCount = max(options.count, optionImages.count)
        if optionCount > 0 {
            VStack(spacing: 8) {
                ForEach(0..<optionCount, id: \.self) { index in
                    let option = index < options.count ? options[index] : ""
                    let optionImage = index < optionImages.count ? optionImages[index] : ""
                    let letter = String(UnicodeScalar(65 + index)!)
                    let canShowCurrentFeedback = isRedoPractice && redoAttempt.submitted
                    let correct = isRedoPractice
                        ? (canShowCurrentFeedback && answerLetters.contains(letter))
                        : answerLetters.contains(letter)
                    let chosen = isRedoPractice
                        ? redoAttempt.selectedLetters.contains(letter)
                        : userAnswerLetters.contains(letter)
                    let hasText = !clean(option).isEmpty
                    let row = optionRow(
                        option,
                        image: optionImage,
                        letter: letter,
                        index: index,
                        hasText: hasText,
                        correct: correct,
                        chosen: chosen
                    )
                    let paddedRow = row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Group {
                        if isRedoPractice && !redoAttempt.submitted {
                            Button {
                                redoSession.update(activeRecordID) { attempt in
                                    if answerLetters.count == 1 {
                                        attempt.selectedLetters = [letter]
                                    } else if attempt.selectedLetters.contains(letter) {
                                        attempt.selectedLetters.remove(letter)
                                    } else {
                                        attempt.selectedLetters.insert(letter)
                                    }
                                    attempt.submitted = !answerLetters.isEmpty
                                }
                            } label: {
                                paddedRow
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选项\(letter)：\(clean(option))")
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        } else {
                            paddedRow
                        }
                    }
                    .background(optionBackground(correct: correct, chosen: chosen), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                optionBorderColor(correct: correct, chosen: chosen),
                                lineWidth: (chosen || correct) ? 1 : 0.8
                            )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func optionRow(
        _ option: String,
        image: String,
        letter: String,
        index: Int,
        hasText: Bool,
        correct: Bool,
        chosen: Bool
    ) -> some View {
        HStack(
            alignment: StudyOptionRowLayout.verticalAlignment(hasText: hasText),
            spacing: 8
        ) {
            StudyOptionMarker(
                letter: letter,
                state: optionMarkerState(correct: correct, chosen: chosen),
                diameter: 26,
                font: .system(size: 14)
            )
            VStack(alignment: .leading, spacing: 8) {
                if hasText {
                    optionText(option)
                        .lineSpacing(5.5)
                }
                if !image.isEmpty {
                    if let asset = displayQuestionBankContext?.assetsByID[image] {
                        LegacyQuestionBankAssetImage(asset: asset, sizing: .option)
                    } else {
                        let optionImageIDs = object["optionImageIDs"] as? [String] ?? []
                        let optionImageID = optionImageIDs.indices.contains(index) ? optionImageIDs[index] : ""
                        LibraryDetailImage(
                            source: image,
                            cacheKey: imageCacheKey(kind: "option", index: index, source: image, metadataID: optionImageID),
                            availableWidth: nil,
                            widthFraction: LibraryImageDisplaySetting.maximumWidthFraction
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.firstTextBaseline]
            }
        }
    }

    private var answerAndSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let accuracy = formattedAccuracy {
                supportingLine("参考正确率", value: accuracy, systemImage: "chart.bar.fill")
            }
            questionSourceBlock
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var questionSourceBlock: some View {
        if !questionSourceRows.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label("题目来源", systemImage: "books.vertical.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Text(questionSourceRows.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("question-source-rows")
            .padding(.vertical, 2)
        }
    }

    private var questionSourceRows: [String] {
        if let context = displayQuestionBankContext, !context.sourceRows.isEmpty {
            return context.sourceRows
        }
        if kind == .errors, scope.reviewSource == .mock {
            let examID = firstText(["sourceExamId"]) ?? ""
            let examObject = records.first(where: { $0.collection == "exams" && $0.recordID == examID })?.indexObject
            let linkedTitle = [examObject?["name"] as? String, examObject?["title"] as? String]
                .compactMap { $0 }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let title = clean(firstText(["sourceExamTitle", "mockExamTitle"]) ?? linkedTitle ?? "")
            let cleanedNumber = firstText(["questionNumber"]).map { clean($0) } ?? ""
            let number = cleanedNumber.isEmpty ? nil : cleanedNumber
            let questionNumber = number.map { $0.contains("第") || $0.contains("题") ? $0 : "第\($0)题" }
            return [([title.isEmpty ? "未关联套卷" : title] + (questionNumber.map { [$0] } ?? [])).joined(separator: " · ")]
        }
        guard let source = firstText(["questionSource", "source"]) else {
            if kind == .errors, scope.reviewSource == .real {
                let cleanedNumber = firstText(["questionNumber"]).map { clean($0) } ?? ""
                let number = cleanedNumber.isEmpty ? nil : cleanedNumber
                let displayNumber = number.map { $0.contains("第") || $0.contains("题") ? $0 : "第\($0)题" }
                return [(["真题来源未填写"] + (displayNumber.map { [$0] } ?? [])).joined(separator: " · ")]
            }
            if kind == .errors, scope.reviewSource == .pending { return ["来源待确认"] }
            return []
        }
        let fallbackNumber = sourceQuestionNumber(in: firstText(["questionNumber"]) ?? "")
        var seen = Set<String>()
        return source.components(separatedBy: .newlines).compactMap { rawRow in
            let cleanedRow = clean(rawRow)
            guard !cleanedRow.isEmpty else { return nil }
            let number = sourceQuestionNumber(in: cleanedRow) ?? fallbackNumber
            let fileNameInput = cleanedRow.replacingOccurrences(
                of: #"[·／/\-\s]*(?:原)?第?\s*\d+\s*题"#,
                with: "",
                options: .regularExpression
            )
            let fileName = QuestionBankSourceDisplay.cleanedFileName(fileNameInput)
            guard !fileName.isEmpty else { return nil }
            let row = number.map { "\(fileName)·第\($0)题" } ?? fileName
            return seen.insert(row).inserted ? row : nil
        }
    }

    private func sourceQuestionNumber(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) { return trimmed }
        guard let range = trimmed.range(
            of: #"(?:原)?第?\s*\d+\s*题"#,
            options: .regularExpression
        ) else { return nil }
        let digits = String(trimmed[range].filter { $0.isNumber })
        return digits.isEmpty ? nil : digits
    }

    @ViewBuilder private var explanationBlock: some View {
        if let explanation = firstText(["explanation"]),
           !clean(explanation).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("解析", systemImage: "text.book.closed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(cleanMultiline(explanation))
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            .padding(.top, 5)
        }
    }

    @ViewBuilder private var comparisonBlock: some View {
        let words = linkedWordRecords
        if isLogicFillError || !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("关联词语库")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if isLogicFillError {
                        Button("选择关联") { showWordSelection = true }
                            .font(.system(size: 12, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                if words.isEmpty {
                    Text("尚未关联词语，可在这里直接选择词语库内容")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                ForEach(words, id: \.compoundID) { word in
                    Button {
                        if let onOpenLinkedWord { onOpenLinkedWord(word.recordID) }
                        else { linkedWordDetailTarget = LinkedWordDetailTarget(recordID: word.recordID) }
                    } label: {
                        let wordSnapshot = LibraryRecordSnapshot(record: word)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wordSnapshot.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                                if !wordSnapshot.summary.isEmpty {
                                    Text(wordSnapshot.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    private var noteBlock: some View {
        Group {
            if let record {
                LibraryInlineNoteView(
                    record: record,
                    session: noteSession,
                    readNote: {
                        if let note = object["note"] as? String { return note }
                        return ["content", "errorNote", "analysis"]
                            .compactMap { object[$0] as? String }
                            .first ?? ""
                    },
                    onSaved: { note in
                        object["note"] = note
                        lastLocallySavedNoteUpdate = record.updatedAt
                    }
                )
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var linkedErrorBlock: some View {
        if displayQuestionBankContext != nil, !linkedErrorRecords.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label("关联错题", systemImage: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(linkedErrorRecords, id: \.compoundID) { error in
                    let snapshot = LibraryRecordSnapshot(record: error)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.title).font(.system(size: 13, weight: .medium))
                        if !snapshot.summary.isEmpty {
                            Text(snapshot.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var reviewBlock: some View {
        if let value = firstText(["reviewNote", "reviewPlan", "nextReviewAt"]), !clean(value).isEmpty {
            let key = existingAttributeKey(["reviewNote", "reviewPlan", "nextReviewAt"], fallback: "reviewNote")
            let content = VStack(alignment: .leading, spacing: 8) {
                Label("复盘记录", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(cleanMultiline(value))
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canEditReviewAttributes {
                Button {
                    beginAttributeEdit(key: key, label: "复盘记录", value: cleanMultiline(value))
                } label: { content }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.top, 4)
            } else {
                content.padding(.top, 4)
            }
        }
    }

    private enum MetadataTagEmphasis: Equatable { case strong, subtle }

    @ViewBuilder
    private func metadataTagLine(_ label: String, values: [String], emphasis: MetadataTagEmphasis) -> some View {
        let cleanedValues = values.map(clean).filter { !$0.isEmpty }
        if !cleanedValues.isEmpty {
            let row = HStack(alignment: .top, spacing: 6) {
                Text("\(label)：")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 3)
                    .fixedSize(horizontal: true, vertical: false)
                NativeTagFlow(spacing: 5) {
                    ForEach(cleanedValues, id: \.self) { value in
                        Text(value)
                            .font(.system(size: 12.5, weight: emphasis == .strong ? .medium : .regular))
                            .foregroundStyle(emphasis == .strong ? AppTheme.accent : Color.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                emphasis == .strong ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canEditReviewAttributes {
                Button {
                    let key = attributeKey(for: label)
                    beginAttributeEdit(key: key, label: label, value: cleanedValues.joined(separator: "、"))
                } label: { row }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            } else {
                row
            }
        }
    }

    @ViewBuilder private func metadataTextLine(_ label: String, value: String) -> some View {
        let cleanedValue = clean(value)
        if !cleanedValue.isEmpty {
            let row = HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(label)：")
                Text(cleanedValue)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(.primary)
            if canEditReviewAttributes {
                Button {
                    let key = attributeKey(for: label)
                    beginAttributeEdit(key: key, label: label, value: cleanedValue)
                } label: { row }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            } else {
                row
            }
        }
    }

    private func editableMetadataText(_ label: String, value: String, key: String, choices: [String] = []) -> some View {
        Group {
            if canEditReviewAttributes {
                Button {
                    beginAttributeEdit(key: key, label: label, value: value, choices: choices)
                } label: {
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor(value))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(statusColor(value).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(value))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(statusColor(value).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder private func editableMetadataBadge(
        _ title: String,
        color: Color,
        key: String,
        value: String,
        choices: [String]
    ) -> some View {
        if canEditReviewAttributes {
            Button {
                beginAttributeEdit(key: key, label: title, value: value, choices: choices)
            } label: { metadataBadge(title, color: color) }
                .buttonStyle(.plain)
        } else {
            metadataBadge(title, color: color)
        }
    }

    private func supportingLine(_ label: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("\(label)：")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .regular))
    }

    private func optionText(_ option: String) -> Text {
        Text(cleanMultiline(option))
            .font(.system(size: 15, weight: .regular))
    }

    private var answerLetters: Set<String> { letterSet(firstText(["correctOption", "answer", "correctAnswer"])) }
    private var userAnswerLetters: Set<String> { letterSet(firstText(["userOption", "myAnswer"])) }

    private var redoAttempt: LibraryRedoAttempt { redoSession.attempt(for: activeRecordID) }

    private var isRedoPractice: Bool {
        supportsRedoMode && redoPracticeEnabled
    }

    private var supportsRedoMode: Bool {
        kind == .errors
            && record?.isShenlunRecord != true
            && object["questionBankPaperID"] == nil
            && object["questionBankQuestionID"] == nil
            && displayQuestionBankContext == nil
    }

    private var shouldShowExplanation: Bool {
        if let displayQuestionBankContext {
            return displayQuestionBankContext.isAnswerRevealed
        }
        return !isRedoPractice || (redoAttempt.submitted && !answerLetters.isEmpty)
    }

    private var canShowReviewContentInCurrentMode: Bool {
        !isRedoPractice || shouldShowExplanation
    }

    private func reviewContent<Content: View>(_ content: Content) -> some View {
        let visible = canShowReviewContentInCurrentMode
        return content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }

    @ViewBuilder private var redoFeedbackBlock: some View {
        if redoAttempt.submitted {
            let isCorrect = !answerLetters.isEmpty && redoAttempt.selectedLetters == answerLetters
            VStack(alignment: .leading, spacing: 7) {
                Label(isCorrect ? "本次回答正确" : "本次回答错误", systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCorrect ? StudyOptionFeedbackPalette.correct : StudyOptionFeedbackPalette.incorrect)
                Text("正确答案：\(answerLetters.sorted().joined())")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("library-redo-correct-answer")
                Button("重新作答") {
                    redoSession.update(activeRecordID) { $0 = LibraryRedoAttempt() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 4)
        } else if answerLetters.isEmpty {
            Text(redoAttempt.selectedLetters.isEmpty
                ? "暂无标准答案；选择只会保留本次记录"
                : "已记录你的选择；暂无标准答案，暂不显示解析")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func letterSet(_ value: String?) -> Set<String> {
        Set((value ?? "").uppercased().filter { "ABCD".contains($0) }.map(String.init))
    }
    private func optionBackground(correct: Bool, chosen: Bool) -> Color {
        if isRedoPractice && !redoAttempt.submitted { return .white }
        guard displayQuestionBankContext == nil || questionBankShowsAnswer else { return .white }
        if correct { return StudyOptionFeedbackPalette.correctBackground }
        if chosen { return StudyOptionFeedbackPalette.incorrectBackground }
        return .white
    }

    private func optionMarkerState(correct: Bool, chosen: Bool) -> StudyOptionMarkerState {
        if isRedoPractice && !redoAttempt.submitted {
            return chosen ? .selectedFilled : .unselected
        }
        guard questionBankShowsAnswer || displayQuestionBankContext == nil else {
            return chosen ? .selected : .unselected
        }
        if correct { return .correct }
        if chosen { return .incorrect }
        return .unselected
    }

    private func optionBorderColor(correct: Bool, chosen: Bool) -> Color {
        if isRedoPractice && !redoAttempt.submitted { return webBorder }
        guard displayQuestionBankContext == nil || questionBankShowsAnswer else { return webBorder }
        return correct ? StudyOptionFeedbackPalette.correct : (chosen ? StudyOptionFeedbackPalette.incorrect : webBorder)
    }

    private var questionBankShowsAnswer: Bool {
        guard let displayQuestionBankContext else { return false }
        return displayQuestionBankContext.isAnswerRevealed
            && !displayQuestionBankContext.currentQuestion.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func metadataBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var entryClassificationBadge: some View {
        Group {
            if entryClassification == "错题" {
                Text(entryClassification)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 196 / 255, green: 47 / 255, blue: 50 / 255))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color(red: 253 / 255, green: 235 / 255, blue: 236 / 255), in: RoundedRectangle(cornerRadius: 6))
            } else {
                metadataBadge(entryClassification, color: entryClassificationColor)
            }
        }
            .accessibilityLabel("题目分类：\(entryClassification)")
    }

    private var errorClassificationAndMasteryRow: some View {
        HStack(spacing: 7) {
            entryClassificationBadge
            Menu {
                ForEach(["未掌握", "已掌握"], id: \.self) { value in
                    Button {
                        let attribute = LibraryDetailAttribute(
                            key: existingAttributeKey(["status", "masteryStatus"], fallback: "status"),
                            label: "掌握状态",
                            value: masteryStatus,
                            choices: ["未掌握", "已掌握"]
                        )
                        if let message = saveDetailAttribute(attribute, value: value) {
                            detailAttributeSaveError = message
                        }
                    } label: {
                        if masteryStatus == value { Label(value, systemImage: "checkmark") }
                        else { Text(value) }
                    }
                }
            } label: {
                Group {
                    if masteryStatus == "未掌握" {
                        Text(masteryStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 168 / 255, green: 86 / 255, blue: 18 / 255))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Color(red: 255 / 255, green: 241 / 255, blue: 227 / 255), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(masteryStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusColor(masteryStatus))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(statusColor(masteryStatus).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("掌握状态：\(masteryStatus)")
            Spacer(minLength: 0)
        }
        .alert("掌握状态未保存", isPresented: Binding(
            get: { detailAttributeSaveError != nil },
            set: { if !$0 { detailAttributeSaveError = nil } }
        )) {
            Button("好", role: .cancel) { detailAttributeSaveError = nil }
        } message: {
            Text(detailAttributeSaveError ?? "")
        }
    }

    @ViewBuilder
    private var lineCauseMetadata: some View {
        let values = LibraryErrorCauseCompatibility.splitLines(LibraryErrorCauseCompatibility.rawCause(in: object))
        if !values.isEmpty {
            let row = HStack(alignment: .top, spacing: 6) {
                Text("\(errorCauseLabel)：")
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .padding(.top, 2)
                NativeTagFlow(spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color(red: 165 / 255, green: 91 / 255, blue: 26 / 255))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(red: 255 / 255, green: 244 / 255, blue: 230 / 255), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if canEditReviewAttributes {
                Button {
                    editingErrorCauses = LibraryDetailAttribute(
                        key: "errorCause",
                        label: errorCauseLabel,
                        value: values.joined(separator: "\n")
                    )
                } label: { row }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            } else {
                row
            }
        }
    }

    private var webBorder: Color { Color(red: 240.0 / 255.0, green: 240.0 / 255.0, blue: 242.0 / 255.0) }

    private var detailQuestionFont: Font { .system(size: 14.5, weight: .regular) }

    private var detailBackground: Color { Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0) }

    private var canEditReviewAttributes: Bool {
        supportsRedoMode && !isRedoPractice
    }

    private var masteryStatus: String {
        firstText(["status", "masteryStatus"]).map(clean) ?? "未掌握"
    }

    private var entryClassification: String {
        switch clean(firstText(["type"]) ?? "") {
        case "不确定题", "不确定": "不确定"
        case "不会做": "不会做"
        default: "错题"
        }
    }

    private var entryClassificationColor: Color {
        switch entryClassification {
        case "不确定": AppTheme.warning
        case "不会做": AppTheme.danger
        default: AppTheme.accent
        }
    }

    private var redoModeActionTitle: String {
        redoPracticeEnabled ? "错题模式" : "重做模式"
    }

    private var redoModeActionImage: String { redoPracticeEnabled ? "doc.text" : "arrow.counterclockwise" }

    private func toggleRedoMode() {
        if !redoPracticeEnabled {
            redoSession.update(activeRecordID) { $0 = LibraryRedoAttempt() }
        }
        redoPracticeEnabled.toggle()
    }

    private func existingAttributeKey(_ keys: [String], fallback: String) -> String {
        keys.first { key in
            if let value = object[key] as? String {
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let values = object[key] as? [String] { return !values.isEmpty }
            return object[key] != nil
        } ?? keys.first(where: { object[$0] != nil }) ?? fallback
    }

    private func attributeKey(for label: String) -> String {
        if label.contains("逻辑结构") {
            return existingAttributeKey(["logicStructure", "questionLogicStructure"], fallback: "logicStructure")
        }
        if label == "结构",
           LibraryErrorCauseCompatibility.isCenterUnderstanding(subject: activeSubject, module: activeModule) {
            return existingAttributeKey(["knowledgePoints", "knowledgePoint", "point", "topic"], fallback: "knowledgePoints")
        }
        if label.contains("考点") || label.contains("知识") {
            return existingAttributeKey(["knowledgePoints", "knowledgePoint", "point", "topic"], fallback: "knowledgePoints")
        }
        if label.contains("弱项") {
            return existingAttributeKey(["weaknessTags"], fallback: "weaknessTags")
        }
        if label.contains("错因") || label.contains("原因") {
            if isQuantityRelations { return "errorCause" }
            return existingAttributeKey(["errorCause", "cause", "reason"], fallback: "errorCause")
        }
        if label == "陷阱",
           LibraryErrorCauseCompatibility.isCenterUnderstanding(subject: activeSubject, module: activeModule) {
            return "centerComprehensionTrap"
        }
        if label == "提醒" || label == "常识" { return "reminder" }
        if label.contains("结构") { return "quantityStructure" }
        if label.contains("规律") { return existingAttributeKey(["graphRule", "patternRule"], fallback: "graphRule") }
        if label.contains("识别") { return existingAttributeKey(["recognition", "recognitionPath"], fallback: "recognition") }
        if label.contains("题型") { return "module" }
        return label
    }

    private func beginAttributeEdit(
        key: String,
        label: String,
        value: String,
        choices: [String] = []
    ) {
        guard canEditReviewAttributes else { return }
        let rawValue = object[key]
        let resolvedValue: String
        if let values = rawValue as? [String] {
            resolvedValue = values.joined(separator: "、")
        } else if let boolean = rawValue as? Bool {
            resolvedValue = boolean ? "是" : "否"
        } else if let number = rawValue as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            resolvedValue = number.boolValue ? "是" : "否"
        } else {
            resolvedValue = value
        }
        let inferredChoices = (rawValue is Bool || (rawValue as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true)
            ? ["否", "是"] : choices
        editingAttribute = LibraryDetailAttribute(key: key, label: label, value: resolvedValue, choices: inferredChoices)
    }

    private func saveDetailAttribute(_ attribute: LibraryDetailAttribute, value: String) -> String? {
        guard let record else { return "题目记录不存在，修改未保存。" }
        var updated = object
        let originalValue = updated[attribute.key]
        if originalValue is Bool || (originalValue as? NSNumber).map({ CFGetTypeID($0) == CFBooleanGetTypeID() }) == true {
            updated[attribute.key] = value == "是"
        } else if originalValue is [String] {
            updated[attribute.key] = value
                .split(whereSeparator: { "、,，\n".contains($0) })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            updated[attribute.key] = value
        }
        if isQuantityRelations, attribute.key == "errorCause" {
            LibraryQuantityErrorCauseCompatibility.markAuthoritative(in: &updated)
        }
        updated["updatedAt"] = ISO8601DateFormatter().string(from: .now)
        guard JSONSerialization.isValidJSONObject(updated),
              let payload = try? JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys]) else {
            return "字段格式无效，修改未保存。"
        }

        let previousPayload = record.payload
        let previousIndexPayload = record.indexPayload
        let previousUpdatedAt = record.updatedAt
        let previousModule = record.module
        let wasAutosaveEnabled = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = wasAutosaveEnabled }
        record.replacePayload(payload)
        if attribute.key == "module" { record.module = value }
        record.updatedAt = .now
        do {
            try modelContext.save()
            object = updated
            return nil
        } catch {
            record.payload = previousPayload
            record.indexPayload = previousIndexPayload
            record.updatedAt = previousUpdatedAt
            record.module = previousModule
            return "保存失败：\(error.localizedDescription)"
        }
    }

    private var knowledgePoints: [String] {
        if let values = stringArray("knowledgePoints"), !values.isEmpty { return values }
        return textValues(["knowledgePoint", "point", "topic"])
            .flatMap { $0.split(whereSeparator: { "、,，".contains($0) }).map(String.init) }
    }

    private var displayQuestionBankContext: QuestionBankQuestionAnalysisContext? {
        linkedQuestionBankContext
    }

    private var linkedQuestionContextKey: String {
        guard kind == .errors,
              let paperID = object["questionBankPaperID"] as? String,
              let questionID = object["questionBankQuestionID"] as? String else { return "" }
        let question = (object["question"] as? String ?? object["title"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let options = object["options"] as? [String] ?? []
        let imageReferences = (object["images"] as? [String] ?? [])
            + (object["optionImages"] as? [String] ?? [])
        let hasLinkedImageReference = imageReferences.contains { value in
            !value.isEmpty && value.count < 256 && !value.contains("://") && !value.hasPrefix("/")
        }
        let materialID = (object["materialID"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.isEmpty || options.isEmpty || hasLinkedImageReference || !materialID.isEmpty else {
            return ""
        }
        return "\(paperID)|\(questionID)"
    }

    @MainActor
    private func loadLinkedQuestionContext() {
        guard !linkedQuestionContextKey.isEmpty,
              kind == .errors,
              let paperID = object["questionBankPaperID"] as? String,
              let questionID = object["questionBankQuestionID"] as? String else {
            linkedQuestionBankContext = nil
            linkedQuestionFallbackObject = [:]
            return
        }
        let context = QuestionBankQuestionAnalysisContext.linkedErrorContext(
            paperID: paperID,
            questionID: questionID,
            selectedOption: object["userOption"] as? String ?? "",
            context: modelContext
        )
        linkedQuestionBankContext = context
        linkedQuestionFallbackObject = context?.detailObject ?? [:]
    }

    private var imageValues: [String] {
        if let values = object["images"] as? [String], !values.isEmpty { return values }
        if let values = linkedQuestionFallbackObject["images"] as? [String], !values.isEmpty { return values }
        return firstText(["image"]).map { [$0] } ?? []
    }

    private var linkedWordRecords: [StoredRecord] {
        let ids = Set(linkedWordIDs)
        return records.filter { $0.collection == "words" && ids.contains($0.recordID) }
    }

    private var linkedWordIDs: [String] {
        guard let record else { return [] }
        let reverseIDs = records.compactMap { word -> String? in
            guard word.collection == "words" else { return nil }
            let wordObject = word.compatibilityIndexObject ?? [:]
            let directIDs = wordObject["linkedErrors"] as? [String] ?? []
            let legacyIDs = wordObject["relatedErrorIds"] as? [String] ?? []
            return (directIDs + legacyIDs).contains(record.recordID) ? word.recordID : nil
        }
        let existingWordIDs = Set(records.filter { $0.collection == "words" }.map(\.recordID))
        return LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
            (object["linkedWordIds"] as? [String] ?? []) + reverseIDs,
            existingIDs: existingWordIDs
        )
    }

    private var linkedErrorRecords: [StoredRecord] {
        let ids = Set(object["linkedErrorRecordIDs"] as? [String] ?? [])
        return records.filter { $0.collection == "errors" && ids.contains($0.recordID) }
    }

    private var optionImageValues: [String] {
        if let values = object["optionImages"] as? [String], !values.isEmpty { return values }
        return linkedQuestionFallbackObject["optionImages"] as? [String] ?? []
    }

    private var weaknessTags: [String] {
        if let values = stringArray("weaknessTags"), !values.isEmpty { return values }
        return textValues(["weaknessTags"])
            .flatMap { $0.split(whereSeparator: { "、,，".contains($0) }).map(String.init) }
    }

    private var quantityErrorCauseValues: [String] {
        LibraryQuantityErrorCauseCompatibility.values(in: object)
    }

    private var isLogicFillError: Bool {
        activeSubject == "言语理解" && activeModule == "逻辑填空"
    }

    private var isLogicJudgment: Bool {
        activeSubject == "判断推理" && activeModule == "逻辑判断"
    }

    private var isAnalogyReasoning: Bool {
        activeSubject == "判断推理" && activeModule == "类比推理"
    }

    private var isDataAnalysis: Bool {
        activeSubject == "资料分析"
    }

    private var isQuantityRelations: Bool {
        activeSubject == "数量关系"
    }

    private var isGraphReasoning: Bool {
        activeSubject == "判断推理" && activeModule == "图形推理"
    }

    private var knowledgePointLabel: String {
        if isLogicJudgment { return "题干逻辑结构" }
        if LibraryErrorCauseCompatibility.isCenterUnderstanding(subject: activeSubject, module: activeModule) { return "结构" }
        return "考点"
    }
    private var errorCauseLabel: String {
        if isLogicJudgment { return "选项逻辑作用" }
        if isAnalogyReasoning { return "二级辨析" }
        return "错因"
    }

    private func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let createdAt = record?.createdAt {
                Text("收录于 \(Self.dateFormatter.string(from: createdAt))")
            }
            if let updatedAt = record?.updatedAt {
                Text("上次更新 \(Self.dateFormatter.string(from: updatedAt))")
            }
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private var linkedWordSelection: Binding<[String]> {
        Binding(
            get: { linkedWordIDs },
            set: { newIDs in
                if let record {
                    try? LibraryRecordRepository.updateLinkedWords(
                        error: record,
                        newIDs: newIDs,
                        wordRecords: records,
                        context: modelContext
                    )
                }
            }
        )
    }

    private func linkNewWord(_ id: String) {
        var ids = linkedWordIDs
        if !ids.contains(id) { ids.append(id) }
        if let record {
            try? LibraryRecordRepository.updateLinkedWords(
                error: record,
                newIDs: ids,
                wordRecords: records,
                context: modelContext
            )
        }
    }

    private var formattedAccuracy: String? {
        let legacyAccuracy = displayQuestionBankContext?.currentQuestion.accuracy.map {
            String(format: "%.0f", $0 > 1 ? $0 : $0 * 100)
        }
        let raw = firstText(["accuracy", "correctRate"]) ?? legacyAccuracy
        guard let raw, !clean(raw).isEmpty else { return nil }
        let value = clean(raw)
        return value.contains("%") ? value : "\(value)%"
    }

    private func statusColor(_ value: String) -> Color {
        if value.contains("不确定") { return AppTheme.warning }
        if value.contains("已掌握") { return AppTheme.success }
        return AppTheme.danger
    }

    private func textValues(_ keys: [String]) -> [String] {
        firstText(keys).map { [$0] } ?? []
    }

    private func openDoodle() {
        if let pendingEditorRequestID {
            let transitionRecordID = pendingEditorTransitionRecordID ?? record?.recordID ?? pendingEditorRequestID
            self.pendingEditorRequestID = nil
            pendingEditorTransitionRecordID = nil
            didHandOffEditRequest = false
            onCancelEditRequest()
            LibraryPerformanceLog.editorTransition(
                "menu-action",
                recordID: transitionRecordID,
                details: "cancelled-for-doodle",
                completes: true,
                transitionKey: "menu-action"
            )
        }
        let openStart = ProcessInfo.processInfo.systemUptime
        LibraryPerformanceLog.event("doodle.tap id=\(LibraryPerformanceLog.shortIdentifier(activeRecordID))")
        let opensSplitDoodle = isMaterialPaneOpen && showsDetachedDataAnalysisMaterial
        let targetRecord = record
        let targetContext = modelContext
        let targetSession = doodleSession
        let drawingData = firstText(["pencilKitData", "drawingData"]) ?? ""
        let targetID = activeRecordID
        let targetPayload = targetRecord?.jsonObject ?? object
        let storedSplitValues = opensSplitDoodle ? storedSplitDoodleValues(in: targetPayload) : [:]
        let hasPendingValuesForTarget = doodleSession.hasPendingSplitDrawingChanges
            && doodleSession.splitDrawingRecordID == targetID
        let initialSplitValues = hasPendingValuesForTarget ? doodleSession.splitDrawingValues : storedSplitValues
        let initialSplitBaseline = hasPendingValuesForTarget
            ? doodleSession.splitDrawingBaselineValues()
            : storedSplitValues
        let initialPane: LibraryDoodlePane? = opensSplitDoodle ? .material : nil
        let initialDrawing = opensSplitDoodle
            ? initialSplitValues[splitDoodleStorageKey(pane: .material, layout: splitDoodleLayoutDirection)] ?? ""
            : drawingData
        doodleSession.present(
            targetRecordID: targetID,
            drawingData: initialDrawing,
            legacyPreviewDataURL: opensSplitDoodle ? "" : (drawingData.isEmpty
                ? (firstText(["drawingPreview", "doodle", "drawingDataURL"]) ?? "") : ""),
            source: "library-record-detail",
            splitDrawingPane: initialPane,
            splitDrawingValues: initialSplitValues,
            splitDrawingBaseline: initialSplitBaseline,
            splitDrawingLayoutDirection: splitDoodleLayoutDirection,
            interactionStartedAt: openStart,
            onFirstCanvasFrame: {
                noteSession.finish { _ in }
            },
            onSave: { updatedDrawing, legacyPreviewCleared, _, _ in
                guard let targetRecord else { return "涂鸦未保存：题目记录已不存在。" }
                if targetSession.hasPendingSplitDrawingChanges,
                   targetSession.splitDrawingRecordID == targetID,
                   let error = saveSplitDoodleChanges(record: targetRecord, context: targetContext) {
                    return error
                }
                if opensSplitDoodle { return nil }
                return LibraryDoodlePersistence.save(
                    record: targetRecord,
                    context: targetContext,
                    drawingData: updatedDrawing,
                    legacyPreviewCleared: legacyPreviewCleared
                )
            }
        )
    }

    private var activeRecordID: String {
        record?.compoundID ?? ""
    }

    private func imageCacheKey(kind: String, index: Int, source: String, metadataID: String) -> String {
        let slot = "\(kind):\(index)"
        let identity = imageSourceIdentities[slot]
        let version = identity?.source == source ? identity?.cacheToken : nil
        return "detail-\(activeRecordID)-\(slot)-\(metadataID.isEmpty ? "legacy" : metadataID)-\(version ?? "untracked")"
    }

    private func refreshObject(_ value: [String: Any]) {
        imageSourceIdentities = Self.reconciledImageSourceIdentities(for: value, previous: imageSourceIdentities)
        object = value
    }

    private static func makeImageSourceIdentities(for object: [String: Any]) -> [String: LibraryDetailImageSourceIdentity] {
        reconciledImageSourceIdentities(for: object, previous: [:])
    }

    private static func reconciledImageSourceIdentities(
        for object: [String: Any],
        previous: [String: LibraryDetailImageSourceIdentity]
    ) -> [String: LibraryDetailImageSourceIdentity] {
        var result: [String: LibraryDetailImageSourceIdentity] = [:]
        let imageValues = (object["images"] as? [String]).flatMap { $0.isEmpty ? nil : $0 }
            ?? (object["image"] as? String).map { [$0] }
            ?? []
        let optionValues = object["optionImages"] as? [String] ?? []
        for (kind, values) in [("image", imageValues), ("option", optionValues)] {
            for (index, source) in values.enumerated() where !source.isEmpty {
                let slot = "\(kind):\(index)"
                if let existing = previous[slot], existing.source == source {
                    result[slot] = existing
                } else {
                    result[slot] = LibraryDetailImageSourceIdentity(source: source, cacheToken: UUID().uuidString)
                }
            }
        }
        return result
    }

    private var activeSubject: String {
        let localSubject = record?.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return localSubject.isEmpty
            ? (displayQuestionBankContext?.typeMapping.subject ?? scope.subject ?? "")
            : localSubject
    }

    private var activeModule: String {
        let localModule = record?.module?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return localModule.isEmpty
            ? (displayQuestionBankContext?.typeMapping.module ?? scope.module ?? "")
            : localModule
    }

    private func firstText(_ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
            if let value = linkedQuestionFallbackObject[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = linkedQuestionFallbackObject[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }
    private func stringArray(_ key: String) -> [String]? {
        if let values = object[key] as? [String], !values.isEmpty { return values }
        if let values = object[key] as? [[String: Any]] { return values.compactMap { ($0["text"] ?? $0["content"] ?? $0["value"]) as? String } }
        if let values = linkedQuestionFallbackObject[key] as? [String], !values.isEmpty { return values }
        return nil
    }
    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "(?:^|\\s)[.#]?[a-zA-Z][^{}\\n]{0,80}\\{[^}]*\\}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanMultiline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private struct LibraryDetailImageSourceIdentity {
    let source: String
    let cacheToken: String
}

private struct LibraryDetailImage: View {
    let source: String
    let cacheKey: String
    let availableWidth: CGFloat?
    let widthFraction: Double
    var showsFrame = true
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var appearanceRevision: UInt64 = 0

    var body: some View {
        Group {
            if showsFrame {
                imageContent
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                    }
            } else {
                imageContent
            }
        }
        .task(id: "\(cacheKey)|\(appearanceRevision)") {
            didFail = false
            if let cached = LibraryImageLoader.cachedImage(cacheKey: cacheKey, maximumPixelSize: 2_400) {
                image = cached
                LibraryPerformanceLog.event("image.cache-hit id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
                return
            }
            LibraryPerformanceLog.event("image.request id=\(LibraryPerformanceLog.shortIdentifier(cacheKey)) pixel=2400")
            let loadedImage = await LibraryImageLoader.image(
                from: source,
                cacheKey: cacheKey,
                maximumPixelSize: 2_400,
                requestID: UUID()
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
            didFail = loadedImage == nil
            if loadedImage == nil {
                LibraryPerformanceLog.event("image.decode-failed id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
            }
        }
        .onChange(of: cacheKey) { _, newValue in
            image = LibraryImageLoader.cachedImage(cacheKey: newValue, maximumPixelSize: 2_400)
            didFail = false
        }
        .onAppear {
            appearanceRevision &+= 1
            image = LibraryImageLoader.cachedImage(cacheKey: cacheKey, maximumPixelSize: 2_400)
            didFail = false
        }
        .onDisappear { image = nil }
    }

    private var imageContent: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .frame(height: 120)
                    .overlay {
                        if didFail {
                            Label("图片无法加载", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .frame(width: availableWidth.map { max(1, $0 * CGFloat(widthFraction)) })
        .frame(maxWidth: availableWidth == nil ? .infinity : nil)
    }
}

@MainActor
private struct LibraryDetailAttributeEditor: View {
    @Environment(\.dismiss) private var dismiss
    let attribute: LibraryDetailAttribute
    let onSave: (String) -> String?
    @State private var value: String
    @State private var errorMessage: String?

    init(attribute: LibraryDetailAttribute, onSave: @escaping (String) -> String?) {
        self.attribute = attribute
        self.onSave = onSave
        _value = State(initialValue: attribute.value)
    }

    private var choices: [String] {
        guard !attribute.choices.isEmpty else { return [] }
        return attribute.choices.contains(value) ? attribute.choices : attribute.choices + [value]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if choices.isEmpty {
                    TextEditor(text: $value)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 180)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("library-detail-attribute-editor")
                } else {
                    Picker(attribute.label, selection: $value) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                    }
                    .accessibilityIdentifier("library-detail-attribute-picker")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(attribute.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        if let error = onSave(value) {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

@MainActor
private struct LibraryErrorCauseEditor: View {
    @Environment(\.dismiss) private var dismiss
    let attribute: LibraryDetailAttribute
    let onSave: (String) -> String?
    @State private var value: String
    @State private var errorMessage: String?

    init(attribute: LibraryDetailAttribute, onSave: @escaping (String) -> String?) {
        self.attribute = attribute
        self.onSave = onSave
        _value = State(initialValue: attribute.value)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                LibraryErrorCauseLineFields(text: $value)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 12)).foregroundStyle(AppTheme.danger)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(attribute.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let error = onSave(value) { errorMessage = error }
                        else { dismiss() }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private final class LegacyQuestionBankImageBox: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

private enum LegacyQuestionBankImageCache {
    static let images: NSCache<NSString, LegacyQuestionBankImageBox> = {
        let cache = NSCache<NSString, LegacyQuestionBankImageBox>()
        cache.countLimit = 48
        cache.totalCostLimit = 80 * 1_024 * 1_024
        return cache
    }()

    static func cachedImage(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)?.image
    }

    static func decode(url: URL, cacheKey: String, maximumPixelSize: Int) -> LegacyQuestionBankImageBox? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              !Task.isCancelled else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled else { return nil }
        let box = LegacyQuestionBankImageBox(image: UIImage(cgImage: image))
        let cost = max(1, image.bytesPerRow * image.height)
        images.setObject(box, forKey: cacheKey as NSString, cost: cost)
        return box
    }
}

private struct LegacyQuestionBankAssetImage: View {
    enum Sizing: String {
        case material
        case stem
        case option
    }

    let asset: QuestionBankAssetReference
    let sizing: Sizing
    @State private var image: UIImage?
    @State private var failedToLoad = false

    private var cacheKey: String {
        [asset.compoundID, asset.assetRelativePath ?? "", String(asset.contentRevision), sizing.rawValue]
            .joined(separator: "|")
    }

    var body: some View {
        Group {
            if let image {
                imageView(image)
            } else if failedToLoad {
                Label("图片无法读取", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: 72)
            }
        }
        .task(id: cacheKey) {
            image = nil
            failedToLoad = false
            if let cached = LegacyQuestionBankImageCache.cachedImage(for: cacheKey) {
                image = cached
                return
            }
            guard let url = LegacyQuestionBankAssetStore.url(for: asset.assetRelativePath) else {
                failedToLoad = true
                return
            }
            let key = cacheKey
            let maximumPixelSize = sizing == .option ? 900 : 2_400
            let decodeTask = Task.detached(priority: .userInitiated) {
                LegacyQuestionBankImageCache.decode(
                    url: url,
                    cacheKey: key,
                    maximumPixelSize: maximumPixelSize
                )
            }
            let result = await withTaskCancellationHandler {
                await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            guard !Task.isCancelled, cacheKey == key else { return }
            image = result?.image
            failedToLoad = result == nil
        }
        .onAppear {
            image = LegacyQuestionBankImageCache.cachedImage(for: cacheKey)
            failedToLoad = false
        }
    }

    @ViewBuilder
    private func imageView(_ image: UIImage) -> some View {
        switch sizing {
        case .material, .stem:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .option:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 126, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
