import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ShenlunWorkspaceEditorView: View {
    private enum MaterialFormattingState {
        case unchanged
        case undo(text: String, versionID: String)
    }

    @Environment(\.modelContext) private var modelContext

    let practiceID: String?
    let questionID: String?
    let kind: ShenlunWorkspaceKind
    let onSaved: (String, String) -> Void

    @State private var practice: ShenlunWorkspacePractice?
    @State private var questionDrafts: [ShenlunWorkspaceQuestion]
    @State private var selectedQuestionID: String
    @State private var draftPracticeID: String
    @State private var compactPaperSection: ShenlunPaperPasteKind = .materials
    @State private var batchPasteKind: ShenlunPaperPasteKind?
    @State private var materials: [ShenlunWorkspaceMaterial] = []
    @State private var materialFormatting: [String: MaterialFormattingState] = [:]
    @State private var newAssets: [ShenlunWorkspaceAsset] = []
    @State private var deletingAssetIDs = Set<String>()
    @State private var originalQuestion: ShenlunWorkspaceQuestion?
    @State private var originalMaterials: [ShenlunWorkspaceMaterial] = []
    @State private var pageRangeText: [String: String] = [:]
    @State private var pageCounts: [String: Int] = [:]
    @State private var draftPracticeName = ""
    @State private var isImportingFiles = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var deletingMaterialIDs = Set<String>()

    init(
        practiceID: String?,
        questionID: String?,
        kind: ShenlunWorkspaceKind,
        preferredQuestionType: ShenlunWorkspaceQuestionType = .single,
        onSaved: @escaping (String, String) -> Void
    ) {
        self.practiceID = practiceID
        self.questionID = questionID
        self.kind = kind
        self.onSaved = onSaved
        let initialType = practiceID == nil && questionID == nil && kind == .single ? preferredQuestionType : .single
        let draftID = practiceID ?? UUID().uuidString
        let initial = ShenlunWorkspaceQuestion(practiceID: draftID, order: 0, type: initialType)
        _draftPracticeID = State(initialValue: draftID)
        _selectedQuestionID = State(initialValue: initial.id)
        _questionDrafts = State(initialValue: [initial])
    }

    private var isEditingQuestion: Bool { questionID != nil }
    private var isCreatingPaper: Bool { kind == .paper && practiceID == nil }

    private var question: ShenlunWorkspaceQuestion {
        questionDrafts.first { $0.id == selectedQuestionID } ?? questionDrafts[0]
    }

    private var questionBinding: Binding<ShenlunWorkspaceQuestion> {
        let initial = question
        return Binding(
            get: { questionDrafts.first { $0.id == initial.id } ?? initial },
            set: { value in
                guard let index = questionDrafts.firstIndex(where: { $0.id == initial.id }) else { return }
                questionDrafts[index] = value
            }
        )
    }

    private var navigationTitle: String {
        if isEditingQuestion { return "编辑题目" }
        if practiceID != nil { return "录入套卷题目" }
        return kind == .single ? "录入单题" : "新建套卷"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                Group {
                    if isCreatingPaper {
                        paperEditor(twoColumns: proxy.size.width >= 900)
                    } else if proxy.size.width >= 900 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 14) {
                                questionContentSection
                                if !isEditingQuestion { referenceAnswerSection }
                            }
                            VStack(spacing: 14) {
                                questionInformationSection
                                materialsSection
                            }
                        }
                    } else {
                        VStack(spacing: 14) {
                            questionInformationSection
                            questionContentSection
                            materialsSection
                            if !isEditingQuestion { referenceAnswerSection }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: 1320)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.groupedBackground)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : (isCreatingPaper ? "保存套卷" : "保存题目"), action: save)
                    .fontWeight(.semibold)
                    .disabled(isSaving)
            }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true,
            onCompletion: handleFileSelection
        )
        .sheet(item: $batchPasteKind) { kind in
            ShenlunPaperPasteSheet(kind: kind) { entries in
                appendPasted(entries, kind: kind)
            }
        }
        .task { loadExistingDraftIfNeeded() }
        .alert(isCreatingPaper ? "无法保存套卷" : "无法保存申论题目", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请检查表单后重试。")
        }
    }

    private func paperEditor(twoColumns: Bool) -> some View {
        VStack(spacing: 14) {
            editorCard("套卷信息", icon: "doc.on.doc") {
                TextField("套卷名称（必填）", text: $draftPracticeName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .accessibilityIdentifier("shenlun-paper-name")
            }
            if twoColumns {
                HStack(alignment: .top, spacing: 16) {
                    materialsSection
                    paperQuestions
                }
            } else {
                Picker("套卷内容", selection: $compactPaperSection) {
                    Text("给定材料").tag(ShenlunPaperPasteKind.materials)
                    Text("题目（\(questionDrafts.count)）").tag(ShenlunPaperPasteKind.questions)
                }
                .pickerStyle(.segmented)
                if compactPaperSection == .materials {
                    materialsSection
                } else {
                    paperQuestions
                }
            }
        }
    }

    private var paperQuestions: some View {
        VStack(spacing: 14) {
            editorCard("题目", icon: "list.number") {
                NativeTagFlow(spacing: 7) {
                    ForEach(Array(questionDrafts.enumerated()), id: \.element.id) { index, draft in
                        let selected = draft.id == selectedQuestionID
                        Button("第 \(index + 1) 题") { selectedQuestionID = draft.id }
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(selected ? AppTheme.accent : Color.primary)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(selected ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                NativeTagFlow(spacing: 10) {
                    Button { appendQuestion() } label: { Label("新增题目", systemImage: "plus") }
                    Button { batchPasteKind = .questions } label: {
                        Label("批量粘贴题目", systemImage: "doc.on.clipboard")
                    }
                    if questionDrafts.count > 1 {
                        Button("移除本题", role: .destructive, action: removeSelectedQuestion)
                    }
                }
            }
            VStack(spacing: 14) {
                questionInformationSection
                questionContentSection
                referenceAnswerSection
            }
            .id(question.id)
        }
    }

    private func appendQuestion() {
        let draft = ShenlunWorkspaceQuestion(practiceID: draftPracticeID, order: questionDrafts.count)
        questionDrafts.append(draft)
        selectedQuestionID = draft.id
    }

    private func removeSelectedQuestion() {
        guard questionDrafts.count > 1,
              let index = questionDrafts.firstIndex(where: { $0.id == selectedQuestionID }) else { return }
        questionDrafts.remove(at: index)
        selectedQuestionID = questionDrafts[min(index, questionDrafts.count - 1)].id
    }

    private func appendTextMaterial(title: String? = nil, text: String = "") {
        let material = ShenlunWorkspaceMaterial(
            practiceID: draftPracticeID,
            title: title ?? "材料 \(materials.count + 1)",
            order: materials.count,
            kind: .text,
            text: text
        )
        materials.append(material)
        attachNewMaterialIfEditingOneQuestion(material.id)
        if !text.isEmpty { formatMaterial(id: material.id, reportsUnchanged: false) }
    }

    private func attachNewMaterialIfEditingOneQuestion(_ id: String) {
        guard !isCreatingPaper else { return }
        let draft = questionBinding
        setQuestionMaterials(draft.wrappedValue.materialIDs + [id], for: draft)
    }

    private func appendPasted(_ entries: [ShenlunPaperPasteEntry], kind: ShenlunPaperPasteKind) {
        if kind == .materials {
            for entry in entries { appendTextMaterial(title: entry.heading, text: entry.text) }
            return
        }
        let current = question
        let initial = ShenlunWorkspaceQuestion(id: current.id, practiceID: draftPracticeID, order: 0)
        let replacesBlankQuestion = questionDrafts.count == 1 && current == initial
        let firstOrder = replacesBlankQuestion ? 0 : questionDrafts.count
        let drafts = entries.enumerated().map { index, entry in
            ShenlunWorkspaceQuestion(
                practiceID: draftPracticeID,
                order: firstOrder + index,
                originalNumber: entry.heading ?? "",
                title: entry.text,
                instructions: entry.instructions
            )
        }
        guard let first = drafts.first else { return }
        if replacesBlankQuestion {
            questionDrafts = drafts
        } else {
            questionDrafts.append(contentsOf: drafts)
        }
        compactPaperSection = .questions
        selectedQuestionID = first.id
    }

    private var questionInformationSection: some View {
        let draft = questionBinding
        return editorCard("题目信息", icon: "info.circle") {
            if kind == .paper, !isCreatingPaper {
                editorFieldTitle("套卷名称")
                TextField("必填，例如：2026 年国考申论", text: $draftPracticeName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
            }
            editorFieldTitle("题型")
            Picker("题型", selection: draft.type) {
                ForEach(ShenlunWorkspaceQuestionType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            editorFieldTitle("题目来源")
            TextField("可选，例如：2025 年国考", text: draft.source)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))
            editorFieldTitle("原题号")
            TextField("可选", text: draft.originalNumber)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))
            editorFieldTitle("分值与字数范围")
            HStack(spacing: 8) {
                TextField("满分", text: fullScoreBinding)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("满分")
                TextField("字数下限", text: minimumWordCountBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("字数下限")
                TextField("字数上限", text: maximumWordCountBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("字数上限")
            }
            .font(.system(size: 15))
            if !materials.isEmpty {
                editorFieldTitle("关联材料")
                if isCreatingPaper {
                    HStack(spacing: 12) {
                        Button("关联全部") { setQuestionMaterials(materials.map(\.id), for: draft) }
                        Button("本题无需材料") { setQuestionMaterials([], for: draft) }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(materials) { material in
                        Toggle(material.title, isOn: materialSelectionBinding(material, question: draft))
                            .font(.system(size: 14))
                            .tint(AppTheme.accent)
                    }
                }
            } else {
                Button(draft.wrappedValue.materialDecisionMade == true ? "已设为无需材料" : "明确无需材料") {
                    setQuestionMaterials([], for: draft)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var questionContentSection: some View {
        editorCard("题干与作答要求", icon: "list.bullet.rectangle") {
            editorFieldTitle("题干（必填）")
            ShenlunAdaptiveTextEditor(
                text: questionBinding.title,
                minimumHeight: 160,
                growsWithContent: true,
                fontSize: 15,
                accessibilityIdentifier: "shenlun-question-stem"
            )
            editorFieldTitle("作答要求")
            ShenlunAdaptiveTextEditor(
                text: questionBinding.instructions,
                minimumHeight: 90,
                growsWithContent: true,
                fontSize: 15,
                accessibilityIdentifier: "shenlun-question-instructions"
            )
        }
    }

    private var materialsSection: some View {
        editorCard("给定材料", icon: "doc.text") {
            if materials.isEmpty {
                Text(isCreatingPaper
                     ? "整卷共享材料库。每道题可在「关联材料」里选择所需材料。"
                     : "可以粘贴材料文字、导入 PDF 页或添加图片。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NativeTagFlow(spacing: 10) {
                Button { appendTextMaterial() } label: {
                    Label(isCreatingPaper ? "新增文字材料" : "粘贴文字", systemImage: "text.alignleft")
                }
                if isCreatingPaper {
                    Button { batchPasteKind = .materials } label: {
                        Label("批量粘贴材料", systemImage: "doc.on.clipboard")
                    }
                }
                Button { isImportingFiles = true } label: {
                    Label("导入 PDF / 图片", systemImage: "paperclip")
                }
            }
            ForEach(Array(materials.enumerated()), id: \.element.id) { index, _ in
                materialEditorRow(at: index)
            }
            if !isCreatingPaper, !materials.isEmpty {
                let draft = questionBinding
                Button("本题无需材料") { setQuestionMaterials([], for: draft) }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func materialEditorRow(at index: Int) -> some View {
        let material = materials[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("材料名称", text: materialTitleBinding(id: material.id))
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 2)
                if index > 0 {
                    Button { moveMaterial(index, by: -1) } label: {
                        Image(systemName: "arrow.up").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("材料上移")
                }
                if index + 1 < materials.count {
                    Button { moveMaterial(index, by: 1) } label: {
                        Image(systemName: "arrow.down").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("材料下移")
                }
                Button(role: .destructive) { removeMaterial(id: material.id) } label: {
                    Image(systemName: "trash").frame(width: 32, height: 32)
                }
                .accessibilityLabel("删除材料")
            }
            if material.kind == .text {
                ShenlunAdaptiveTextEditor(
                    text: materialTextBinding(id: material.id),
                    minimumHeight: 148,
                    growsWithContent: false,
                    fontSize: 15,
                    accessibilityIdentifier: "shenlun-material-text-\(index)",
                    onFormattedMaterialPaste: { edit in
                        applyMaterialFormatting(id: material.id, formatted: edit.formattedText, restore: edit.restoredText)
                    }
                )
                materialFormattingControls(for: material)
            } else if material.kind == .pdf {
                Text("PDF：\(material.sourceName ?? "已选择文件") · \(pageCounts[material.id].map(String.init) ?? "? 页")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("所选页码，例如 1-3,5（必填）", text: pageRangeBinding(id: material.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                Text("只导入明确选择的原页，不会把整卷默认并入材料。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            } else {
                Text("图片：\(material.sourceName ?? "已选择图片")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    private func materialFormattingControls(for material: ShenlunWorkspaceMaterial) -> some View {
        HStack(spacing: 10) {
            if case .undo? = materialFormatting[material.id] {
                Button { undoMaterialFormatting(id: material.id) } label: {
                    Text("撤销整理").frame(minHeight: 44).contentShape(Rectangle())
                }
            } else {
                Button { formatMaterial(id: material.id) } label: {
                    Text("整理排版").frame(minHeight: 44).contentShape(Rectangle())
                }
                .disabled(material.text.allSatisfy(\.isWhitespace))
                if case .unchanged? = materialFormatting[material.id] {
                    Text("排版无需整理")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .tint(AppTheme.accent)
    }

    private var referenceAnswerSection: some View {
        editorCard("预录参考答案", icon: "doc.plaintext") {
            Text("参考答案会在该题完成独立作答后才显示。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            ShenlunAdaptiveTextEditor(
                text: questionBinding.referenceAnswer,
                minimumHeight: 180,
                growsWithContent: true,
                fontSize: 15,
                accessibilityIdentifier: "shenlun-reference-answer"
            )
        }
    }

    private func editorCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private func editorFieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
    }

    private var fullScoreBinding: Binding<String> {
        let draft = questionBinding
        return Binding(get: { draft.wrappedValue.fullScore.map { String($0) } ?? "" }, set: { draft.wrappedValue.fullScore = Double($0) })
    }

    private var minimumWordCountBinding: Binding<String> {
        let draft = questionBinding
        return Binding(get: { draft.wrappedValue.minimumWordCount.map(String.init) ?? "" }, set: { draft.wrappedValue.minimumWordCount = Int($0) })
    }

    private var maximumWordCountBinding: Binding<String> {
        let draft = questionBinding
        return Binding(get: { draft.wrappedValue.maximumWordCount.map(String.init) ?? "" }, set: { value in
            draft.wrappedValue.maximumWordCount = Int(value)
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.wrappedValue.minimumWordCount = nil
            }
        })
    }

    private func setQuestionMaterials(_ ids: [String], for draft: Binding<ShenlunWorkspaceQuestion>) {
        var updated = draft.wrappedValue
        updated.materialIDs = ids
        updated.materialDecisionMade = true
        draft.wrappedValue = updated
    }

    private func materialSelectionBinding(_ material: ShenlunWorkspaceMaterial, question draft: Binding<ShenlunWorkspaceQuestion>) -> Binding<Bool> {
        Binding(get: { draft.wrappedValue.materialIDs.contains(material.id) }, set: { isSelected in
            var ids = draft.wrappedValue.materialIDs.filter { $0 != material.id }
            if isSelected { ids.append(material.id) }
            setQuestionMaterials(ids, for: draft)
        })
    }

    private func materialTitleBinding(id: String) -> Binding<String> {
        Binding(get: { materials.first(where: { $0.id == id })?.title ?? "" }, set: { value in
            guard let index = materials.firstIndex(where: { $0.id == id }) else { return }
            materials[index].title = value
        })
    }

    private func materialTextBinding(id: String) -> Binding<String> {
        Binding(get: { materials.first(where: { $0.id == id })?.text ?? "" }, set: { value in
            guard let index = materials.firstIndex(where: { $0.id == id }),
                  materials[index].text != value else { return }
            materials[index].text = value
            materials[index].versionID = UUID().uuidString
            materialFormatting.removeValue(forKey: id)
        })
    }

    private func formatMaterial(id: String, reportsUnchanged: Bool = true) {
        guard let material = materials.first(where: { $0.id == id }), material.kind == .text else { return }
        let formatted = ShenlunMaterialTextFormatter.format(material.text)
        guard formatted != material.text else {
            if reportsUnchanged { materialFormatting[id] = .unchanged }
            return
        }
        applyMaterialFormatting(id: id, formatted: formatted, restore: material.text)
    }

    private func applyMaterialFormatting(id: String, formatted: String, restore: String) {
        guard let index = materials.firstIndex(where: { $0.id == id }), materials[index].kind == .text else { return }
        let material = materials[index]
        let restoredVersionID = material.text == restore ? material.versionID : UUID().uuidString
        materialFormatting[id] = .undo(text: restore, versionID: restoredVersionID)
        if material.text != formatted {
            materials[index].text = formatted
            materials[index].versionID = UUID().uuidString
        }
    }

    private func undoMaterialFormatting(id: String) {
        guard let index = materials.firstIndex(where: { $0.id == id }),
              case let .undo(text, versionID)? = materialFormatting[id] else { return }
        materials[index].text = text
        materials[index].versionID = versionID
        materialFormatting.removeValue(forKey: id)
    }

    private func pageRangeBinding(id: String) -> Binding<String> {
        Binding(get: { pageRangeText[id] ?? "" }, set: { pageRangeText[id] = $0 })
    }

    private func moveMaterial(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard materials.indices.contains(index), materials.indices.contains(destination) else { return }
        materials.swapAt(index, destination)
        for position in materials.indices { materials[position].order = position }
    }

    private func removeMaterial(id: String) {
        guard let removed = materials.first(where: { $0.id == id }) else { return }
        if let practiceID {
            do {
                let storedQuestions = try ShenlunWorkspaceRepository.questions(practiceID: practiceID, in: modelContext)
                if storedQuestions.contains(where: { $0.id != questionID && $0.materialIDs.contains(id) }) {
                    errorMessage = "这份材料还关联着套卷中的其他题目。请先在对应题目取消关联，再删除材料。"
                    return
                }
            } catch {
                errorMessage = "无法核对这份材料的关联题目，请重试：\(error.localizedDescription)"
                return
            }
        }
        if practiceID != nil { deletingMaterialIDs.insert(id) }
        if let assetID = removed.assetID {
            if newAssets.contains(where: { $0.id == assetID }) {
                newAssets.removeAll { $0.id == assetID }
            } else {
                deletingAssetIDs.insert(assetID)
            }
        }
        materials.removeAll { $0.id == id }
        materialFormatting.removeValue(forKey: id)
        for index in questionDrafts.indices {
            questionDrafts[index].materialIDs.removeAll { $0 == id }
        }
        for index in materials.indices { materials[index].order = index }
    }

    private func loadExistingDraftIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let practiceID else { return }
        do {
            practice = try ShenlunWorkspaceRepository.practice(id: practiceID, in: modelContext)
            guard let practice else { throw CocoaError(.fileNoSuchFile) }
            draftPracticeName = practice.name
            materials = try ShenlunWorkspaceRepository.materials(practiceID: practiceID, in: modelContext)
            originalMaterials = materials
            for material in materials {
                if material.kind == .pdf, let assetID = material.assetID,
                   let asset = try ShenlunWorkspaceRepository.asset(id: assetID, in: modelContext),
                   let document = PDFDocument(data: asset.data) {
                    pageCounts[material.id] = document.pageCount
                    pageRangeText[material.id] = Self.formatPDFSelection(material.selectedPDFPageIndices)
                }
            }
            let loadedDraft: ShenlunWorkspaceQuestion
            if let questionID {
                guard var loaded = try ShenlunWorkspaceRepository.question(id: questionID, in: modelContext),
                      loaded.practiceID == practiceID else {
                    throw CocoaError(.fileNoSuchFile)
                }
                originalQuestion = loaded
                loaded.materialDecisionMade = loaded.materialDecisionMade ?? practice.materialDecisionMade
                loadedDraft = loaded
            } else {
                loadedDraft = ShenlunWorkspaceQuestion(
                    id: question.id,
                    practiceID: practiceID,
                    order: practice.questionIDs.count,
                    type: .single
                )
            }
            questionDrafts = [loadedDraft]
            selectedQuestionID = loadedDraft.id
        } catch {
            errorMessage = "無法載入原有草稿：\(error.localizedDescription)"
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error): errorMessage = "附件选择失败：\(error.localizedDescription)"
        case .success(let urls):
            Task { await importFiles(urls) }
        }
    }

    @MainActor
    private func importFiles(_ urls: [URL]) async {
        isSaving = true
        defer { isSaving = false }
        for url in urls {
            let hasScope = url.startAccessingSecurityScopedResource()
            defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                let extensionName = url.pathExtension.lowercased()
                let isPDF = extensionName == "pdf"
                if isPDF {
                    guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let asset = ShenlunWorkspaceAsset(id: UUID().uuidString, practiceID: draftPracticeID, fileName: url.lastPathComponent, mimeType: "application/pdf", data: data)
                    let material = ShenlunWorkspaceMaterial(
                        practiceID: asset.practiceID,
                        title: url.deletingPathExtension().lastPathComponent,
                        order: materials.count,
                        kind: .pdf,
                        assetID: asset.id,
                        sourceName: url.lastPathComponent
                    )
                    newAssets.append(asset)
                    materials.append(material)
                    attachNewMaterialIfEditingOneQuestion(material.id)
                    pageCounts[material.id] = document.pageCount
                } else {
                    guard UIImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
                    let asset = ShenlunWorkspaceAsset(id: UUID().uuidString, practiceID: draftPracticeID, fileName: url.lastPathComponent, mimeType: "image/\(extensionName.isEmpty ? "jpeg" : extensionName)", data: data)
                    let material = ShenlunWorkspaceMaterial(
                        practiceID: asset.practiceID,
                        title: url.deletingPathExtension().lastPathComponent,
                        order: materials.count,
                        kind: .image,
                        assetID: asset.id,
                        sourceName: url.lastPathComponent
                    )
                    newAssets.append(asset)
                    materials.append(material)
                    attachNewMaterialIfEditingOneQuestion(material.id)
                }
            } catch {
                errorMessage = "无法读取 \(url.lastPathComponent)：\(error.localizedDescription)"
                return
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        if practiceID != nil, practice == nil || (isEditingQuestion && originalQuestion == nil) {
            errorMessage = "原有练习未载入，请返回后重试。"
            return
        }
        let name = draftPracticeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .paper && name.isEmpty {
            errorMessage = "套卷名称不能为空。"
            return
        }
        for (index, draft) in questionDrafts.enumerated() {
            if let message = validationMessage(for: draft) {
                selectedQuestionID = draft.id
                compactPaperSection = .questions
                errorMessage = isCreatingPaper ? "第 \(index + 1) 题：\(message)" : message
                return
            }
        }

        var savedMaterials = materials
        for index in savedMaterials.indices {
            let material = savedMaterials[index]
            if isCreatingPaper, material.kind == .text, material.text.allSatisfy(\.isWhitespace) {
                compactPaperSection = .materials
                errorMessage = "\(material.title)的正文为空，请补录或移除这份材料。"
                return
            }
            if material.kind == .pdf {
                guard let pageCount = pageCounts[material.id],
                      let selected = ShenlunPDFPageSelectionPolicy.parse(pageRangeText[material.id] ?? "", pageCount: pageCount) else {
                    compactPaperSection = .materials
                    errorMessage = "请为「\(material.title)」选择有效的 PDF 页码范围，例如 1-3,5。"
                    return
                }
                savedMaterials[index].selectedPDFPageIndices = selected
            }
        }

        let materialIDs = savedMaterials.map(\.id)
        var savedPractice = practice ?? ShenlunWorkspacePractice(
            id: draftPracticeID,
            name: kind == .single ? question.title.trimmingCharacters(in: .whitespacesAndNewlines) : name,
            kind: kind
        )
        let savedQuestions = questionDrafts.enumerated().map { index, draft in
            var saved = draft
            saved.title = draft.title
            saved.materialIDs = materialIDs.filter { draft.materialIDs.contains($0) }
            saved.materialDecisionMade = draft.materialDecisionMade == true || !saved.materialIDs.isEmpty
            saved.revision += 1
            if questionID == nil { saved.order = savedPractice.questionIDs.count + index }
            return saved
        }
        guard let firstQuestion = savedQuestions.first else { return }
        if kind == .paper { savedPractice.name = name }
        if questionID == nil { savedPractice.questionIDs.append(contentsOf: savedQuestions.map(\.id)) }
        savedPractice.materialIDs = materialIDs
        savedPractice.materialDecisionMade = savedPractice.materialDecisionMade || !materialIDs.isEmpty
            || savedQuestions.contains { $0.materialDecisionMade == true }
        savedPractice.updatedAt = .now

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            if isCreatingPaper {
                try ShenlunWorkspaceRepository.saveNewPractice(
                    savedPractice, questions: savedQuestions, materials: savedMaterials, assets: newAssets, in: modelContext
                )
            } else {
                try ShenlunWorkspaceRepository.savePracticeAndQuestion(
                    savedPractice,
                    firstQuestion,
                    createdAt: savedPractice.createdAt,
                    materials: savedMaterials,
                    assets: newAssets,
                    markScoresForReview: scoringInputsChanged(question: firstQuestion, practice: savedPractice, materials: savedMaterials),
                    deletingMaterialIDs: Array(deletingMaterialIDs),
                    deletingAssetIDs: Array(deletingAssetIDs),
                    in: modelContext
                )
            }
            onSaved(savedPractice.id, firstQuestion.id)
        } catch {
            errorMessage = "保存失败，内容仍保留在当前表单：\(error.localizedDescription)"
        }
    }

    private func validationMessage(for question: ShenlunWorkspaceQuestion) -> String? {
        if question.title.allSatisfy(\.isWhitespace) { return "题干不能为空。" }
        if let score = question.fullScore, !score.isFinite || score <= 0 { return "满分请填写大于 0 的数字。" }
        if let maximum = question.maximumWordCount, maximum <= 0 { return "字数上限必须是正整数。" }
        if let minimum = question.minimumWordCount {
            if minimum <= 0 { return "字数下限必须是正整数。" }
            guard let maximum = question.maximumWordCount else { return "填写字数下限时，必须同时填写字数上限。" }
            if minimum > maximum { return "字数下限不能大于字数上限。" }
        }
        return nil
    }

    private func scoringInputsChanged(
        question: ShenlunWorkspaceQuestion,
        practice savedPractice: ShenlunWorkspacePractice,
        materials: [ShenlunWorkspaceMaterial]
    ) -> Bool {
        guard let originalQuestion else { return false }
        let questionChanged = originalQuestion.title != question.title
            || originalQuestion.instructions != question.instructions
            || originalQuestion.type != question.type
            || originalQuestion.fullScore != question.fullScore
            || originalQuestion.minimumWordCount != question.minimumWordCount
            || originalQuestion.maximumWordCount != question.maximumWordCount
            || originalQuestion.referenceAnswer != question.referenceAnswer
            || originalQuestion.materialIDs != question.materialIDs
        return questionChanged
            || savedPractice.materialIDs != (practice?.materialIDs ?? [])
            || originalMaterials != materials
    }

    private static func formatPDFSelection(_ pages: [Int]) -> String {
        guard !pages.isEmpty else { return "" }
        let oneBased = pages.map { $0 + 1 }
        var groups: [String] = []
        var start = oneBased[0]
        var previous = start
        for value in oneBased.dropFirst() {
            if value == previous + 1 {
                previous = value
            } else {
                groups.append(start == previous ? "\(start)" : "\(start)-\(previous)")
                start = value
                previous = value
            }
        }
        groups.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return groups.joined(separator: ",")
    }
}
