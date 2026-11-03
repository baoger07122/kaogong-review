import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct LinkedRecordEditorTarget: Identifiable {
    let collection: String
    let recordID: String
    var id: String { "\(collection):\(recordID)" }
}

enum ErrorAnswerField: Hashable {
    case correct, selected
}

struct LibraryRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "errors"
            || record.collection == "notes"
            || record.collection == "stickies"
            || record.collection == "words"
            || record.collection == "exams"
            || record.collection == "keyvalue"
    }) private var records: [StoredRecord]

    let kind: LibraryContentKind
    let scope: LibraryScope
    let recordID: String?
    let onSaved: ((String) -> Void)?
    let dismissAfterSave: Bool
    @State private var draft: LibraryRecordDraft
    @State private var showDelete = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var restoredDraft = false
    @State private var linkedEditorTarget: LinkedRecordEditorTarget?
    @State private var splitMessage: String?
    @State private var showSmartSplit = false
    @State private var smartSplitDraft = ""
    @State private var activeTags: ManagedTagKind?
    @State private var activeRelation: String?
    @State private var expandedAnswerField: ErrorAnswerField?
    @State private var linkedWordDetailTarget: LinkedWordDetailTarget?
    @State private var linkedWordCreationCategory: WordCategory?
    @State private var showQuantityKnowledgePoints = false
    @State private var showQuantityWeaknessTags = false
    @State private var showQuantityQuestionTypes = false
    @State private var isCurrentAffairsSupplementExpanded = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var showDiscardDraftConfirmation = false
    @State private var questionImageWidthPreview: [String: Double] = [:]
    @State private var draftPersistenceCleared = false

    init(
        kind: LibraryContentKind,
        scope: LibraryScope,
        record: StoredRecord? = nil,
        preferredType: String = "",
        preferredSourceExamID: String? = nil,
        dismissAfterSave: Bool = true,
        onSaved: ((String) -> Void)? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.onSaved = onSaved
        self.dismissAfterSave = dismissAfterSave
        recordID = record?.recordID
        var initialDraft = LibraryRecordDraft(kind: kind, scope: scope, record: record)
        if record == nil, !preferredType.isEmpty {
            initialDraft.type = preferredType
        }
        if record == nil, kind == .words,
           let saved = LibraryDraftStore.load(kind: kind, scope: scope, category: initialDraft.type) {
            saved.applying(to: &initialDraft)
            _restoredDraft = State(initialValue: true)
        } else if record == nil, kind != .words,
                  let saved = LibraryDraftStore.load(kind: kind, scope: scope) {
            saved.applying(to: &initialDraft)
            _restoredDraft = State(initialValue: true)
        }
        if record == nil, let preferredSourceExamID {
            initialDraft.sourceExamID = preferredSourceExamID
            initialDraft.reviewSource = .mock
        }
        if kind == .errors, !QuestionBankErrorBookCategory.allCases.contains(where: { $0.rawValue == initialDraft.type }) {
            initialDraft.type = "错题"
        }
        if kind == .words,
           WordCategory(rawValue: initialDraft.type)?.isComparison == true {
            while initialDraft.wordCompareTerms.count < 2 {
                initialDraft.wordCompareTerms.append(.init(entryKind: initialDraft.wordEntryKind))
            }
            let names = initialDraft.wordCompareTerms
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !names.isEmpty { initialDraft.title = names.joined(separator: " vs ") }
        }
        _isCurrentAffairsSupplementExpanded = State(
            initialValue: !initialDraft.currentAffairsSupplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        configuredEditor
        .onChange(of: draftSnapshot) { _, snapshot in
            guard recordID == nil else { return }
            draftPersistenceCleared = false
            LibraryDraftStore.save(snapshot, kind: kind, scope: scope)
        }
        .onChange(of: selectedPhotos) { _, items in
            Task { await appendImages(items) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            commitPendingQuestionImageWidths()
            guard recordID == nil, !draftPersistenceCleared else { return }
            let snapshot = draftSnapshot
            Task { await LibraryDraftStore.flush(snapshot, kind: kind, scope: scope) }
        }
        .onDisappear {
            commitPendingQuestionImageWidths()
            guard recordID == nil, !draftPersistenceCleared else { return }
            let snapshot = draftSnapshot
            Task { await LibraryDraftStore.flush(snapshot, kind: kind, scope: scope) }
        }
        .onAppear {
            if kind != .words,
               let recordID,
               let currentRecord = records.first(where: { $0.collection == kind.collection && $0.recordID == recordID }) {
                draft.reviewSource = LibraryReviewSource.classify(currentRecord, records: records)
            }
            if recordID == nil, kind == .errors, scope.reviewSource == .mock,
               draft.sourceExamID.isEmpty,
               let remembered = LibraryMockExamMemory.selectedID(records: records) {
                if !remembered.isEmpty,
                   records.contains(where: { $0.collection == "exams" && $0.recordID == remembered && LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) == .mock }) {
                    draft.sourceExamID = remembered
                } else {
                    draft.sourceExamID = ""
                }
            }
        }
        .onChange(of: draft.reviewSource) { _, source in
            guard kind == .errors, !draft.sourceExamID.isEmpty else { return }
            guard let exam = records.first(where: { $0.collection == "exams" && $0.recordID == draft.sourceExamID }) else {
                draft.sourceExamID = ""
                return
            }
            if LibraryReviewSource.explicitValue(in: exam.indexObject ?? [:]) != source {
                draft.sourceExamID = ""
            }
        }
        .sheet(item: $linkedEditorTarget) { target in
            if let record = records.first(where: { $0.collection == target.collection && $0.recordID == target.recordID }) {
                NavigationStack {
                    LibraryRecordEditorView(
                        kind: target.collection == "errors" ? .errors : .notes,
                        scope: LibraryScope(subject: record.subject, module: record.module),
                        record: record
                    )
                }
            } else {
                NativeStatusCard(title: "记录不存在", detail: "该站内链接指向的记录可能已被删除", systemImage: "link.badge.plus", color: AppTheme.warning)
                    .padding(24)
            }
        }
        .sheet(item: $linkedWordCreationCategory) { category in
            NavigationStack {
                LibraryRecordEditorView(
                    kind: .words,
                    scope: LibraryScope(subject: "言语理解", module: "逻辑填空"),
                    preferredType: category.rawValue,
                    onSaved: { id in
                        if !draft.linkedWordIDs.contains(id) { draft.linkedWordIDs.append(id) }
                        linkedWordCreationCategory = nil
                    }
                )
            }
        }
        .navigationDestination(item: $linkedWordDetailTarget) { target in
            if let word = records.first(where: { $0.collection == "words" && $0.recordID == target.recordID }) {
                WordLibraryRecordDetailView(record: word)
            }
        }
        .overlay { editorDialogs }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if kind != .words {
                    contextCard
                }
                if kind == .notes || kind == .stickies { reviewSourcePicker }
                if kind == .errors && draft.reviewSource == .pending {
                    Label("请选择真题复盘或模拟题复盘后再保存。", systemImage: "exclamationmark.circle.fill")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.warning)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("library-error-source-required")
                }
                if hasPausedQuestionBankAssociation {
                    Label(
                        "已保留真题关联；当前保存只修改错题，不回写真题内容。",
                        systemImage: "info.circle.fill"
                    )
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if restoredDraft {
                    Label("已恢复上次未保存的草稿", systemImage: "clock.arrow.circlepath")
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 4)
                }
                if let saveErrorMessage {
                    Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.danger)
                        .padding(.horizontal, 4)
                }
                recordKindFields
            }
            .padding(.horizontal, kind == .errors ? 16 : 20)
            .padding(.top, kind == .errors ? 5 : 20)
            .padding(.bottom, 20)
            .frame(maxWidth: kind == .errors ? 920 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(kind == .errors || kind == .words ? Color.white : AppTheme.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
    }

    /// The record-category switch is intentionally type-erased at this stable routing
    /// boundary; each selected form remains a concrete view with its own smaller tree.
    private var recordKindFields: AnyView {
        switch kind {
        case .errors: AnyView(errorFields)
        case .notes: AnyView(noteFields)
        case .stickies: AnyView(stickyFields)
        case .words: AnyView(wordFields)
        }
    }

    private var configuredEditor: some View {
        editorContent
        .navigationTitle(recordID == nil ? "新增\(kind.rawValue)" : "编辑\(kind.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(recordID == nil)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : "保存", action: save)
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("library-record-save")
            }
            if recordID == nil {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: requestBackFromNewRecord) {
                        Label("返回", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("library-editor-back")
                    if kind != .words {
                        Menu {
                            Button("放弃草稿", role: .destructive) {
                                showDiscardDraftConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("草稿选项")
                    }
                }
            }
            if recordID != nil, kind != .errors {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    Button("删除", role: .destructive) { showDelete = true }
                }
            }
        }
        .confirmationDialog("删除\(kind.rawValue)", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove)
            Button("取消", role: .cancel) {}
        } message: { Text("删除后无法在 App 内恢复。") }
        .confirmationDialog("未保存的\(kind.rawValue)草稿", isPresented: $showDiscardDraftConfirmation, titleVisibility: .visible) {
            Button("保存并退出") { save() }
                .disabled(!canSave || isSaving)
                .accessibilityIdentifier("library-draft-save-exit")
            Button("放弃草稿", role: .destructive) { discardDraftAndExit() }
                .accessibilityIdentifier("library-draft-discard")
            Button("继续编辑") {}
                .accessibilityIdentifier("library-draft-continue")
        } message: {
            Text("继续编辑会保留草稿；保存并退出会保存当前记录；只有选择“放弃草稿”才会清除本分类和作用域的草稿。")
        }
    }

    private var editorDialogs: AnyView {
        var overlays: [AnyView] = []
        if showSmartSplit { overlays.append(AnyView(smartSplitDialog)) }
        if let activeTags {
            overlays.append(AnyView(LibraryTagSelectionDialog(
                kind: activeTags,
                module: draft.module,
                selection: activeTags == .knowledgePoint ? $draft.knowledgePoint : $draft.errorCause,
                onClose: { self.activeTags = nil },
                titleOverride: activeTags == .knowledgePoint ? knowledgePointLabel : errorCauseLabel
            )))
        }
        if showQuantityKnowledgePoints {
            overlays.append(AnyView(QuantityKnowledgePointSelectionDialog(
                currentType: draft.module,
                selection: $draft.knowledgePoint,
                onClose: { showQuantityKnowledgePoints = false }
            )))
        }
        if showQuantityWeaknessTags {
            overlays.append(AnyView(LibraryTagSelectionDialog(
                kind: .thinkingTrap,
                module: "数量关系-弱项",
                selection: $draft.weaknessTags,
                onClose: { showQuantityWeaknessTags = false },
                titleOverride: "弱项标签",
                maximumOverride: 8
            )))
        }
        if showQuantityQuestionTypes {
            overlays.append(AnyView(QuantityQuestionTypeSelectionDialog(
                selection: $draft.module,
                onClose: { showQuantityQuestionTypes = false }
            )))
        }
        if let activeRelation {
            overlays.append(AnyView(LibraryRelationSelectionDialog(
                collection: activeRelation,
                candidates: relationCandidates(collection: activeRelation),
                selection: relationBinding(activeRelation),
                onClose: { self.activeRelation = nil },
                onCreateWord: activeRelation == "words" ? { category in
                    self.activeRelation = nil
                    linkedWordCreationCategory = category
                } : nil
            )))
        }
        return AnyView(ZStack { ForEach(overlays.indices, id: \.self) { overlays[$0] } })
    }
    private var contextCard: some View {
        Group {
            if kind == .errors {
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            errorReviewSourcePicker
                            Spacer(minLength: 0)
                            recordTypePicker
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            errorReviewSourcePicker
                                .frame(maxWidth: 160, alignment: .leading)
                            recordTypePicker
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        subjectPicker
                        modulePicker
                        Spacer(minLength: 0)
                        addImagePicker
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                contextControlsRow
            }
        }
    }

    private var contextControlsRow: some View {
        HStack(spacing: 8) {
            subjectPicker
            modulePicker
            Spacer(minLength: 0)
            addImagePicker
        }
    }

    private var subjectPicker: some View {
        Menu {
            ForEach(SubjectDefinition.all) { subject in
                Button(subject.name) {
                    draft.subject = subject.name
                    draft.module = subject.name == "数量关系"
                        ? ""
                        : (subject.modules.first ?? "")
                }
            }
        } label: {
            compactProperty(title: "科目", value: draft.subject, image: "books.vertical")
        }
    }

    @ViewBuilder private var modulePicker: some View {
        if isQuantityRelations {
            Button { showQuantityQuestionTypes = true } label: {
                compactProperty(title: "题型", value: draft.module, image: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
        } else if let subject = SubjectDefinition.all.first(where: { $0.name == draft.subject }), !subject.modules.isEmpty {
            Menu {
                ForEach(subject.modules, id: \.self) { module in Button(module) { draft.module = module } }
            } label: {
                compactProperty(title: "模块", value: draft.module, image: "square.stack.3d.up")
            }
        }
    }

    private var errorReviewSourcePicker: some View {
        Picker("题目来源", selection: $draft.reviewSource) {
            Text("真题").tag(LibraryReviewSource.real)
            Text("模拟题").tag(LibraryReviewSource.mock)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("题目来源")
        .accessibilityIdentifier("library-error-source-segmented-control")
    }

    @ViewBuilder private var addImagePicker: some View {
        if kind == .errors, draft.images.isEmpty {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                ViewThatFits(in: .horizontal) {
                    Label("添加图片", systemImage: "photo.badge.plus")
                    Image(systemName: "photo.badge.plus")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加题干图片")
        }
    }

    private var reviewSourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeFieldLabel(title: "复盘来源")
            Picker("复盘来源", selection: $draft.reviewSource) {
                ForEach([LibraryReviewSource.real, .mock, .pending]) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 11))
    }

    private func compactProperty(title: String, value: String, image: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: image)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "未设置" : value)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 36)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.7)
        }
        .contentShape(Rectangle())
    }

    private var errorFields: some View {
        LibraryErrorEditorFieldsView(
            recordID: recordID,
            records: records,
            splitMessage: splitMessage,
            internalLinks: internalLinkCandidates,
            onOpenSmartSplit: openSmartSplit,
            onQuestionImageWidth: questionImageWidth,
            questionImageWidthBinding: questionImageWidthBinding,
            onCommitQuestionImageWidth: commitQuestionImageWidth,
            onOpenInternalLink: { link in
                linkedEditorTarget = LinkedRecordEditorTarget(collection: link.collection, recordID: link.recordID)
            },
            onOpenLinkedWord: { id in linkedWordDetailTarget = LinkedWordDetailTarget(recordID: id) },
            draft: $draft,
            selectedPhotos: $selectedPhotos,
            activeTags: $activeTags,
            activeRelation: $activeRelation,
            expandedAnswerField: $expandedAnswerField,
            showQuantityKnowledgePoints: $showQuantityKnowledgePoints,
            showQuantityWeaknessTags: $showQuantityWeaknessTags,
            isCurrentAffairsSupplementExpanded: $isCurrentAffairsSupplementExpanded,
            questionImageWidthPreview: $questionImageWidthPreview
        )
    }

    private var isLogicJudgment: Bool { draft.subject == "判断推理" && draft.module == "逻辑判断" }
    private var isAnalogyReasoning: Bool { draft.subject == "判断推理" && draft.module == "类比推理" }
    private var isDataAnalysis: Bool { draft.subject == "资料分析" }
    private var isQuantityRelations: Bool { draft.subject == "数量关系" }
    private var hasPausedQuestionBankAssociation: Bool {
        guard kind == .errors, !AppFeatureAvailability.questionBank else { return false }
        let paperID = (draft.original["questionBankPaperID"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let questionID = (draft.original["questionBankQuestionID"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !paperID.isEmpty || !questionID.isEmpty
    }
    private var knowledgePointLabel: String { isLogicJudgment ? "题干逻辑结构" : "考点" }
    private var errorCauseLabel: String {
        if isLogicJudgment { return "选项逻辑作用" }
        if isAnalogyReasoning { return "二级辨析" }
        return "错因"
    }

    private var recordTypePicker: some View {
        Picker("题目类型", selection: $draft.type) {
            Text("错题").tag("错题")
            Text("不确定题").tag("不确定题")
            Text("不会做").tag("不会做")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 235)
    }

    private func splitTags(_ rawValue: String) -> [String] {
        rawValue
            .split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var smartSplitDialog: some View {
        ErrorSmartSplitDialog(
            initialText: smartSplitDraft,
            errorMessage: splitMessage?.hasPrefix("已") == false ? splitMessage : nil,
            onCancel: {
                showSmartSplit = false
                splitMessage = nil
            },
            onApply: applySmartSplit
        )
    }

    private func errorSection<Content: View>(
        _ title: String,
        image: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: image)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .nativeCard(padding: 15)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.7)
        }
    }

    private var noteFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("笔记标题", text: $draft.title).textFieldStyle(NativeTextFieldStyle())
            Menu {
                Button("全部（不设置标签）") { draft.type = "" }
                ForEach(noteTypes) { item in Button(item.name) { draft.type = item.name } }
            } label: {
                NativePropertyRow(title: "笔记标签", value: draft.type.isEmpty ? "全部" : draft.type, systemImage: "tag") {}
                    .allowsHitTesting(false)
            }
            if isQuantityRelations {
                quantityTextInput(title: "题目结构", placeholder: "例如：矩形边界植树", text: $draft.quantityStructure)
                quantityTagInput(title: "考点", value: draft.knowledgePoint) {
                    showQuantityKnowledgePoints = true
                }
                quantityTagInput(title: "弱项标签", value: draft.weaknessTags) {
                    showQuantityWeaknessTags = true
                }
            } else {
                TextField("考点（可选）", text: $draft.knowledgePoint).textFieldStyle(NativeTextFieldStyle())
            }
            NativeFieldLabel(title: "正文")
            richEditor(text: $draft.content, height: 240)
            DisclosureGroup("思维导图") {
                NativeMindMapEditor(encodedDocument: $draft.mindMapData).padding(.top, 8)
            }
            DisclosureGroup("涂鸦与手写") {
                NativePencilDrawingEditor(
                    encodedData: $draft.pencilKitData,
                    legacyPreviewDataURL: draft.legacyDrawingPreview
                )
                .padding(.top, 8)
            }
            multiRelationSection(title: "关联错题", candidates: relationCandidates(collection: "errors"), selection: $draft.linkedErrorIDs)
            Text("正文使用 TextKit 2 原生富文本编辑器，思维导图和 PencilKit 手写数据随当前笔记保存。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .nativeCard()
    }

    private func quantityTagInput(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Text(value.isEmpty ? "选择或新增" : splitTags(value).joined(separator: "、"))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func quantityTextInput(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(size: 12.5, weight: .regular))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
    }

    private var stickyFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeRichTextEditor(html: $draft.content, minHeight: 170, mode: .compact)
            Menu {
                Button("无标签") { draft.type = "" }
                ForEach(stickyTags) { item in Button(item.name) { draft.type = item.name } }
            } label: {
                NativePropertyRow(title: "便签标签", value: draft.type.isEmpty ? "无标签" : draft.type, systemImage: "tag") {}
                    .allowsHitTesting(false)
            }
            HStack(spacing: 10) {
                ForEach(HomeRecordRepository.stickyColors, id: \.self) { hex in
                    Button { draft.colorHex = hex } label: {
                        Circle().fill(Color(homeHex: hex)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(draft.colorHex == hex ? AppTheme.accent : Color.primary.opacity(0.14), lineWidth: draft.colorHex == hex ? 2.5 : 0.7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Toggle("置顶", isOn: $draft.pinned).font(AppTheme.inputFont).fixedSize()
            }
        }
        .nativeCard()
    }

    private var wordFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                compactWordProperty(title: "当前模块", value: wordCategory.title, image: wordCategory.systemImage)
                Spacer(minLength: 8)
                if wordCategory.isComparison {
                    wordEntryKindPicker(selection: $draft.wordEntryKind)
                }
            }

            Divider().opacity(0.55)

            if wordCategory.isComparison {
                NativeFieldLabel(title: "共同语义")
                compactWordTextField("共同语义（可选）", text: $draft.commonMeaning, multiline: true)

                NativeFieldLabel(title: "辨析词语")
                ForEach($draft.wordCompareTerms) { $term in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            compactWordTextField("词语 / 常见搭配", text: $term.name)
                            if draft.wordCompareTerms.count > 2 {
                                Button(role: .destructive) {
                                    draft.wordCompareTerms.removeAll { $0.id == term.id }
                                    syncComparisonTitle()
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                            }
                        }
                        NativeRichTextEditor(
                            html: $term.meaning,
                            minHeight: 64,
                            mode: .minimal,
                            documentStyle: true
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: term.name) { _, _ in syncComparisonTitle() }
                }
                Button {
                    draft.wordCompareTerms.append(.init())
                } label: {
                    Label("增加词语", systemImage: "plus.circle")
                        .font(AppTheme.inputFont.weight(.semibold))
                }
                compactWordTextField("核心区别", text: $draft.compareNote, multiline: true)
            } else {
                HStack(spacing: 8) {
                    wordEntryKindPicker(selection: $draft.wordEntryKind)
                    compactWordTextField("词语 / 常见搭配", text: $draft.title)
                        .accessibilityIdentifier("library-word-title")
                }
                compactWordTextField("拼音（可选）", text: $draft.pinyin)
            }

            Menu {
                Button("未设置") { draft.sentiment = "" }
                ForEach(["褒义", "贬义", "中性"], id: \.self) { value in Button(value) { draft.sentiment = value } }
            } label: {
                compactWordProperty(
                    title: "感情色彩",
                    value: draft.sentiment.isEmpty ? "未设置" : draft.sentiment,
                    image: "face.smiling"
                )
            }
            .buttonStyle(.plain)
            if wordCategory == .wordDefinition {
                compactWordTextField("词性（例如：动词）", text: $draft.partOfSpeech)
            }
            NativeFieldLabel(title: wordCategory.isComparison ? "判断提示" : "释义")
            richEditor(text: $draft.content, height: 145)
            compactWordTextField("例句（可选）", text: $draft.example, multiline: true)
            if wordCategory == .wordDefinition {
                compactWordTextField("我的理解", text: $draft.myUnderstanding, multiline: true)
                compactWordTextField("常见搭配", text: $draft.collocations, multiline: true)
                compactWordTextField("来源", text: $draft.wordSource)
            }
            multiRelationSection(title: "关联错题", candidates: relationCandidates(collection: "errors"), selection: $draft.linkedErrorIDs)
        }
    }

    private var wordCategory: WordCategory {
        WordCategory(rawValue: draft.type) ?? .idiomDefinition
    }

    private func wordEntryKindPicker(selection: Binding<String>) -> some View {
        Menu {
            ForEach(WordEntryKind.allCases) { kind in
                Button(kind.title) { selection.wrappedValue = kind.rawValue }
            }
        } label: {
            HStack(spacing: 4) {
                Text(WordEntryKind(rawValue: selection.wrappedValue)?.title ?? WordEntryKind.word.title)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(height: 38, alignment: .center)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private func compactWordProperty(title: String, value: String, image: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: image).foregroundStyle(AppTheme.accent)
            Text(title).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
        }
        .font(.system(size: 12, weight: .regular))
        .padding(.horizontal, 10)
        .frame(height: 38, alignment: .center)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
        }
    }

    private func compactWordTextField(
        _ prompt: String,
        text: Binding<String>,
        multiline: Bool = false
    ) -> some View {
        TextField(prompt, text: text, axis: multiline ? .vertical : .horizontal)
            .font(AppTheme.inputFont)
            .lineLimit(multiline ? 2...5 : 1...1)
            .padding(.horizontal, 11)
            .padding(.vertical, multiline ? 10 : 0)
            .frame(minHeight: 40, alignment: .center)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
            }
    }

    private func ensureComparisonTerms() {
        guard wordCategory.isComparison else { return }
        while draft.wordCompareTerms.count < 2 { draft.wordCompareTerms.append(.init()) }
        syncComparisonTitle()
    }

    private func syncComparisonTitle() {
        guard wordCategory.isComparison else { return }
        let names = draft.wordCompareTerms.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !names.isEmpty { draft.title = names.joined(separator: " vs ") }
    }

    private func relationBinding(_ collection: String) -> Binding<[String]> {
        switch collection {
        case "exams": return Binding(get: { draft.sourceExamID.isEmpty ? [] : [draft.sourceExamID] }, set: { draft.sourceExamID = $0.first ?? "" })
        case "notes": return $draft.linkedNoteIDs
        default: return $draft.linkedWordIDs
        }
    }

    private func multiRelationSection(
        title: String,
        candidates: [StoredRecord],
        selection: Binding<[String]>
    ) -> some View {
        DisclosureGroup("\(title)（\(selection.wrappedValue.count)）") {
            if candidates.isEmpty {
                Text("暂无可关联内容").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(candidates, id: \.compoundID) { record in
                        Button {
                            var values = Set(selection.wrappedValue)
                            if values.contains(record.recordID) { values.remove(record.recordID) }
                            else { values.insert(record.recordID) }
                            selection.wrappedValue = Array(values).sorted()
                        } label: {
                            HStack {
                                Image(systemName: selection.wrappedValue.contains(record.recordID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.wrappedValue.contains(record.recordID) ? AppTheme.accent : .secondary)
                                Text(record.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(2)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func relationCandidates(collection: String) -> [StoredRecord] {
        records
            .filter {
                guard LibraryRelationCandidateScope.includes(
                    candidateCollection: $0.collection,
                    targetCollection: collection
                ), $0.recordID != recordID else { return false }
                if collection == "exams", kind == .errors {
                    return LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) == draft.reviewSource
                }
                return true
            }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    private func relationTitle(collection: String, id: String) -> String {
        guard !id.isEmpty else { return "未关联" }
        return records.first { $0.collection == collection && $0.recordID == id }?.title ?? "记录已不存在"
    }

    private func editor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(AppTheme.inputFont)
            .scrollContentBackground(.hidden)
            .frame(minHeight: height)
            .padding(8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private func richEditor(text: Binding<String>, height: CGFloat) -> some View {
        NativeRichTextEditor(
            html: text,
            minHeight: height,
            documentStyle: kind == .errors || kind == .words,
            internalLinks: internalLinkCandidates,
            onOpenInternalLink: { link in
                linkedEditorTarget = LinkedRecordEditorTarget(collection: link.collection, recordID: link.recordID)
            }
        )
    }

    private var internalLinkCandidates: [RichTextInternalLink] {
        // Error and word editors do not expose the internal-link workflow. Avoid
        // sorting and mapping the complete library during their first render.
        guard kind == .notes else { return [] }
        return records
            .filter { ($0.collection == "errors" || $0.collection == "notes") && $0.recordID != recordID }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
            .map { RichTextInternalLink(collection: $0.collection, recordID: $0.recordID, title: $0.title) }
    }

    private var canSave: Bool {
        switch kind {
        case .errors:
            !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && draft.reviewSource != .pending
        case .notes, .words: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stickies: !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var draftSnapshot: LibraryDraftSnapshot { LibraryDraftSnapshot(draft) }

    private func requestBackFromNewRecord() {
        guard draftSnapshot.hasUserContent else {
            dismiss()
            return
        }
        showDiscardDraftConfirmation = true
    }

    private func discardDraftAndExit() {
        Task { @MainActor in
            await LibraryDraftStore.clearAndWait(kind: kind, scope: scope, category: draft.type)
            draftPersistenceCleared = true
            dismiss()
        }
    }

    private var noteTypes: [NoteTypeDefinition] {
        NoteTypeRepository.types(subject: draft.subject, module: draft.module, records: records)
    }

    private var stickyTags: [StickyTagDefinition] {
        StickyTagRepository.tags(
            subject: draft.subject,
            module: draft.module,
            records: records
        )
    }

    private func save() {
        guard !isSaving else { return }
        guard kind != .errors || draft.reviewSource != .pending else {
            saveErrorMessage = "请选择真题复盘或模拟题复盘后再保存。"
            return
        }
        isSaving = true
        saveErrorMessage = nil
        Task { @MainActor in
            await Task.yield()
            do {
                if recordID == nil {
                    commitPendingQuestionImageWidths()
                    await LibraryDraftStore.flush(draftSnapshot, kind: kind, scope: scope)
                }
                if kind == .errors || (kind == .notes && isQuantityRelations) {
                    try TagLibraryRepository.add(
                        splitTags(draft.knowledgePoint),
                        kind: .knowledgePoint,
                        module: draft.module,
                        records: records,
                        context: modelContext,
                        persist: false
                    )
                    if kind == .errors && !isDataAnalysis && !isAnalogyReasoning && !isQuantityRelations {
                        try TagLibraryRepository.add(
                            [draft.errorCause],
                            kind: .errorCause,
                            module: draft.module,
                            records: records,
                            context: modelContext,
                            persist: false
                        )
                    }
                }
                // 思维误区是普通文字，不写入标签库。
                let savedID = try LibraryRecordRepository.save(kind: kind, draft: draft, records: records, context: modelContext)
                if recordID == nil {
                    await LibraryDraftStore.clearAndWait(kind: kind, scope: scope, category: draft.type)
                    draftPersistenceCleared = true
                }
                isSaving = false
                onSaved?(savedID)
                if dismissAfterSave { dismiss() }
            } catch {
                isSaving = false
                saveErrorMessage = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    private func remove() {
        guard let recordID else { return }
        try? LibraryRecordRepository.remove(kind: kind, id: recordID, records: records, context: modelContext)
        dismiss()
    }

    private func openSmartSplit() {
        smartSplitDraft = ""
        splitMessage = nil
        showSmartSplit = true
    }

    private func applySmartSplit(_ rawText: String) {
        let separatesLogicFillTerms = draft.subject == "言语理解" && draft.module == "逻辑填空"
        switch ErrorQuestionParser.parse(rawText, separateOptionLines: separatesLogicFillTerms) {
        case .success(let result):
            draft.title = result.question
            draft.options = result.options + Array(repeating: "", count: max(0, 4 - result.options.count))
            if let correct = result.correctOption { draft.correctOption = correct }
            if let selected = result.userOption { draft.userOption = selected }
            splitMessage = "已拆分题干和 \(result.options.count) 个选项，请核对后保存"
            showSmartSplit = false
        case .failure(let error):
            splitMessage = error.localizedDescription
        }
    }

    @MainActor
    private func appendImages(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
            draft.appendQuestionImage("data:image/jpeg;base64,\(data.base64EncodedString())")
        }
        selectedPhotos = []
    }

    private func questionImageWidthBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { questionImageWidth(for: id) },
            set: { questionImageWidthPreview[id] = LibraryImageDisplaySetting.normalizedWidthFraction($0) }
        )
    }

    private func questionImageWidth(for id: String) -> Double {
        questionImageWidthPreview[id]
            ?? draft.imageDisplaySettings.first(where: { $0.id == id })?.widthFraction
            ?? LibraryImageDisplaySetting.maximumWidthFraction
    }

    private func commitQuestionImageWidth(for id: String) {
        guard let fraction = questionImageWidthPreview.removeValue(forKey: id) else { return }
        draft.setQuestionImageWidth(id: id, fraction: fraction)
    }

    private func commitPendingQuestionImageWidths() {
        let pending = questionImageWidthPreview
        questionImageWidthPreview.removeAll()
        for (id, fraction) in pending {
            draft.setQuestionImageWidth(id: id, fraction: fraction)
        }
    }
}

struct ErrorFormTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12.5, weight: .regular))
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
    }
}

struct DataAnalysisOptionImagePicker: View {
    let hasImage: Bool
    let onPicked: (String) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Image(systemName: hasImage ? "photo.fill" : "photo.badge.plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasImage ? "更换选项图片" : "添加选项图片")
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self), !data.isEmpty else { return }
                await MainActor.run {
                    onPicked("data:image/jpeg;base64,\(data.base64EncodedString())")
                    item = nil
                }
            }
        }
    }
}

private struct ErrorSmartSplitDialog: View {
    @State private var text: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onApply: (String) -> Void

    init(
        initialText: String,
        errorMessage: String?,
        onCancel: @escaping () -> Void,
        onApply: @escaping (String) -> Void
    ) {
        _text = State(initialValue: initialText)
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onApply = onApply
    }

    private var canApply: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("智能拆分题目")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $text)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(height: 148)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.13), lineWidth: 0.8))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppTheme.warning)
                }

                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .buttonStyle(NativeSecondaryButtonStyle())
                    Button("识别并填入") { onApply(text) }
                        .buttonStyle(NativePrimaryButtonStyle())
                        .disabled(!canApply)
                }
            }
            .padding(18)
            .frame(maxWidth: 560)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.17), radius: 24, y: 10)
            .padding(24)
        }
        .transition(.opacity)
    }
}

private struct ParsedErrorQuestion {
    let question: String
    let options: [String]
    let correctOption: String?
    let userOption: String?
}

private enum ErrorQuestionParser {
    private struct OptionMarker {
        let code: Int
        let range: NSRange
    }

    private struct ParseFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ rawValue: String, separateOptionLines: Bool = false) -> Result<ParsedErrorQuestion, Error> {
        let source = normalized(rawValue)
        guard !source.isEmpty else {
            return .failure(ParseFailure(message: "请先粘贴完整题目。"))
        }
        guard let expression = try? NSRegularExpression(
            pattern: "(?m)^[\\t \\u3000]*(?:[（(【\\[][\\t \\u3000]*)?([A-H])(?:(?:[\\t \\u3000]*[）)】\\]]|[\\t \\u3000]*[\\.、。:：)）])[\\t \\u3000]*|[\\t \\u3000]+|(?=[\\p{Han}])|[\\t \\u3000]*(?=\\n))",
            options: .caseInsensitive
        ) else {
            return .failure(ParseFailure(message: "拆分规则初始化失败。"))
        }

        let sourceNSString = source as NSString
        let answerStart = firstAnswerRange(in: source)?.location ?? sourceNSString.length
        let optionRange = NSRange(location: 0, length: answerStart)
        let markers = expression.matches(in: source, range: optionRange).compactMap { match -> OptionMarker? in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            let letter = sourceNSString.substring(with: match.range(at: 1)).uppercased()
            guard let scalar = letter.unicodeScalars.first else { return nil }
            return OptionMarker(code: Int(scalar.value), range: match.range)
        }
        var best: [OptionMarker] = []
        for start in markers.indices where markers[start].code == 65 {
            var chain = [markers[start]]
            var expected = 66
            for marker in markers[(start + 1)...] where marker.range.location >= chain.last!.range.location + chain.last!.range.length {
                if marker.code == expected {
                    chain.append(marker)
                    expected += 1
                }
            }
            if chain.count >= 2,
               chain.count > best.count || (chain.count == best.count && chain[0].range.location > (best.first?.range.location ?? -1)) {
                best = chain
            }
        }
        guard let first = best.first else {
            return .failure(ParseFailure(message: "没有识别到连续选项。请将 A、B、C、D 分行放在各选项开头。"))
        }

        let question = cleanedQuestion(
            sourceNSString.substring(with: NSRange(location: 0, length: first.range.location))
        )
        var options: [String] = []
        for (index, marker) in best.enumerated() {
            let start = marker.range.location + marker.range.length
            let end = index + 1 < best.count ? best[index + 1].range.location : answerStart
            let value = cleanedOption(
                sourceNSString.substring(with: NSRange(location: start, length: max(0, end - start))),
                separateOptionLines: separateOptionLines
            )
            if !value.isEmpty { options.append(value) }
        }
        guard !question.isEmpty, options.count >= 2 else {
            return .failure(ParseFailure(message: "题干或选项内容不完整，当前表单没有被修改。"))
        }

        return .success(
            ParsedErrorQuestion(
                question: question,
                options: options,
                correctOption: answerLetter(in: source, labels: ["正确答案", "参考答案", "答案"]),
                userOption: answerLetter(in: source, labels: ["我的答案", "你的答案", "用户答案"])
            )
        )
    }

    private static func normalized(_ value: String) -> String {
        let halfwidth = String(value.unicodeScalars.map { scalar -> Character in
            if (0xFF21...0xFF28).contains(scalar.value) || (0xFF41...0xFF48).contains(scalar.value),
               let converted = UnicodeScalar(scalar.value - 0xFEE0) {
                return Character(converted)
            }
            return Character(scalar)
        })
        return halfwidth
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[．﹒]", with: ".", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedOption(_ value: String, separateOptionLines: Bool) -> String {
        value.components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: separateOptionLines ? " " : "")
    }

    /// Removes copy/paste wrapping while preserving one intentional break
    /// before the final question sentence.
    private static func cleanedQuestion(_ value: String) -> String {
        let lines = value
            .components(separatedBy: .newlines)
            .map(compactLine)
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        if lines.count > 1, let last = lines.last {
            let body = lines.dropLast().joined()
            return body.isEmpty ? last : "\(body)\n\(last)"
        }

        let merged = lines.joined()
        let nsMerged = merged as NSString
        let pattern = "(?<=[。；;])(?:以下|下列|根据上述|由此|据此|请问|上述)"
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(
               in: merged,
               range: NSRange(location: 0, length: nsMerged.length)
           ), match.range.location > 0 {
            let body = nsMerged.substring(to: match.range.location)
            let prompt = nsMerged.substring(from: match.range.location)
            return "\(body)\n\(prompt)"
        }
        return merged
    }

    private static func compactLine(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "[\\t\\u00A0 ]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cjkAndPunctuation = "\\p{Han}，。！？；：、‘’“”（）《》"
        result = result.replacingOccurrences(
            of: "([\(cjkAndPunctuation)])\\s+",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s+([\(cjkAndPunctuation)])",
            with: "$1",
            options: .regularExpression
        )
        return result
    }

    private static func isQuestionLead(_ value: String) -> Bool {
        ["以下", "下列", "根据上述", "由此", "据此", "请问", "上述"]
            .contains { value.hasPrefix($0) }
    }

    private static func firstAnswerRange(in source: String) -> NSRange? {
        let patterns = ["(?:正确答案|参考答案|我的答案|你的答案|用户答案|答案)\\s*[：:]", "(?m)^\\s*解析\\s*[：:]"]
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        var ranges: [NSRange] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: source, range: fullRange)
            else { continue }
            ranges.append(match.range)
        }
        return ranges.min { $0.location < $1.location }
    }

    private static func answerLetter(in source: String, labels: [String]) -> String? {
        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        let specificLabels = labels.filter { $0 != "答案" }
        if !specificLabels.isEmpty {
            let labelPattern = specificLabels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            let pattern = "(?:\(labelPattern))\\s*[：:]?\\s*([A-D])"
            if let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = expression.firstMatch(in: source, range: range), match.numberOfRanges > 1 {
                return nsSource.substring(with: match.range(at: 1)).uppercased()
            }
        }
        guard labels.contains("答案"),
              let expression = try? NSRegularExpression(pattern: "(?m)^\\s*答案\\s*[：:]?\\s*([A-D])", options: .caseInsensitive),
              let match = expression.firstMatch(in: source, range: range), match.numberOfRanges > 1
        else { return nil }
        return nsSource.substring(with: match.range(at: 1)).uppercased()
    }
}
