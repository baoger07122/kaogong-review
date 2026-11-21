import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ShenlunWorkspaceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let practiceID: String?
    let questionID: String?
    let kind: ShenlunWorkspaceKind
    let onSaved: (String, String) -> Void

    @State private var practice: ShenlunWorkspacePractice?
    @State private var question: ShenlunWorkspaceQuestion
    @State private var materials: [ShenlunWorkspaceMaterial] = []
    @State private var newAssets: [ShenlunWorkspaceAsset] = []
    @State private var deletingAssetIDs = Set<String>()
    @State private var selectedMaterialIDs = Set<String>()
    @State private var originalQuestion: ShenlunWorkspaceQuestion?
    @State private var originalMaterials: [ShenlunWorkspaceMaterial] = []
    @State private var pageRangeText: [String: String] = [:]
    @State private var pageCounts: [String: Int] = [:]
    @State private var draftPracticeName = ""
    @State private var isImportingFiles = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var didDecideMaterials = false
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
        _question = State(initialValue: ShenlunWorkspaceQuestion(practiceID: practiceID ?? "", order: 0, type: initialType))
    }

    private var isEditingQuestion: Bool { questionID != nil }
    private var navigationTitle: String {
        if isEditingQuestion { return "编辑题目" }
        if practiceID != nil { return "录入套卷题目" }
        return kind == .single ? "录入单题" : "新建套卷"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                Group {
                    if proxy.size.width >= 900 {
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : kind == .paper && practiceID == nil ? "保存套卷" : "保存题目", action: save)
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
        .task { loadExistingDraftIfNeeded() }
        .alert("无法保存申论题目", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请检查表单后重试。")
        }
    }

    private var questionInformationSection: some View {
        editorCard("题目信息") {
            if kind == .paper {
                editorFieldTitle("套卷名称")
                TextField("必填，例如：2026 年国考申论", text: $draftPracticeName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
            }
            editorFieldTitle("题型")
            Picker("题型", selection: $question.type) {
                ForEach(ShenlunWorkspaceQuestionType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            editorFieldTitle("题目来源")
            TextField("可选，例如：2025 年国考", text: $question.source)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))
            editorFieldTitle("原题号")
            TextField("可选", text: $question.originalNumber)
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
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(materials) { material in
                        Toggle(material.title, isOn: materialSelectionBinding(material))
                            .font(.system(size: 14))
                            .tint(AppTheme.accent)
                    }
                }
            } else {
                Button("明确无需材料") {
                    selectedMaterialIDs.removeAll()
                    didDecideMaterials = true
                    practice?.materialDecisionMade = true
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var questionContentSection: some View {
        editorCard("题干与作答要求") {
            editorFieldTitle("题干（必填）")
            ShenlunAdaptiveTextEditor(
                text: $question.title,
                minimumHeight: 160,
                growsWithContent: true,
                fontSize: 15,
                accessibilityIdentifier: "shenlun-question-stem"
            )
            editorFieldTitle("作答要求")
            ShenlunAdaptiveTextEditor(
                text: $question.instructions,
                minimumHeight: 90,
                growsWithContent: true,
                fontSize: 15,
                accessibilityIdentifier: "shenlun-question-instructions"
            )
        }
    }

    private var materialsSection: some View {
        editorCard("给定材料") {
            if materials.isEmpty {
                Text("可以粘贴材料文字、导入 PDF 页或添加图片。尚未决定时，练习详情会保留“尚未设置”的状态。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(materials.indices, id: \.self) { index in
                materialEditorRow(at: index)
            }
            HStack(spacing: 9) {
                Button {
                    let material = ShenlunWorkspaceMaterial(
                        practiceID: practiceID ?? practice?.id ?? "",
                        title: "材料 \(materials.count + 1)",
                        order: materials.count,
                        kind: .text
                    )
                    materials.append(material)
                    selectedMaterialIDs.insert(material.id)
                    didDecideMaterials = true
                    practice?.materialDecisionMade = true
                } label: {
                    Label("粘贴文字", systemImage: "text.alignleft")
                }
                Button { isImportingFiles = true } label: {
                    Label("导入 PDF / 图片", systemImage: "paperclip")
                }
            }
            if !materials.isEmpty {
                Button("本题无需材料") {
                    selectedMaterialIDs.removeAll()
                    didDecideMaterials = true
                    practice?.materialDecisionMade = true
                }
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
                TextEditor(text: materialTextBinding(id: material.id))
                    .font(.system(size: 15))
                    .frame(minHeight: 140)
                    .padding(4)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1), lineWidth: 0.7) }
                    .accessibilityIdentifier("shenlun-material-text-\(index)")
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

    private var referenceAnswerSection: some View {
        editorCard("预录参考答案") {
            Text("参考答案会在该题完成独立作答后才显示。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            ShenlunAdaptiveTextEditor(
                text: $question.referenceAnswer,
                minimumHeight: 180,
                growsWithContent: true,
                fontSize: 15,
                accessibilityIdentifier: "shenlun-reference-answer"
            )
        }
    }

    private func editorCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 0.7) }
    }

    private func editorFieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
    }

    private var fullScoreBinding: Binding<String> {
        Binding(get: { question.fullScore.map { String($0) } ?? "" }, set: { question.fullScore = Double($0) })
    }

    private var minimumWordCountBinding: Binding<String> {
        Binding(get: { question.minimumWordCount.map(String.init) ?? "" }, set: { question.minimumWordCount = Int($0) })
    }

    private var maximumWordCountBinding: Binding<String> {
        Binding(get: { question.maximumWordCount.map(String.init) ?? "" }, set: { value in
            question.maximumWordCount = Int(value)
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                question.minimumWordCount = nil
            }
        })
    }

    private func materialSelectionBinding(_ material: ShenlunWorkspaceMaterial) -> Binding<Bool> {
        Binding(get: { selectedMaterialIDs.contains(material.id) }, set: { isSelected in
            if isSelected { selectedMaterialIDs.insert(material.id) } else { selectedMaterialIDs.remove(material.id) }
            didDecideMaterials = true
            practice?.materialDecisionMade = true
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
            guard let index = materials.firstIndex(where: { $0.id == id }) else { return }
            materials[index].text = value
            materials[index].versionID = UUID().uuidString
        })
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
        if let practiceID,
           let otherQuestions = try? ShenlunWorkspaceRepository.questions(practiceID: practiceID, in: modelContext),
           otherQuestions.contains(where: { $0.id != questionID && $0.materialIDs.contains(id) }) {
            errorMessage = "这份材料还关联着套卷中的其他题目。请先在对应题目取消关联，再删除材料。"
            return
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
        selectedMaterialIDs.remove(id)
        for index in materials.indices { materials[index].order = index }
    }

    private func loadExistingDraftIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let practiceID else {
            if kind == .single {
                question.practiceID = UUID().uuidString
            }
            return
        }
        do {
            practice = try ShenlunWorkspaceRepository.practice(id: practiceID, in: modelContext)
            guard let practice else { throw CocoaError(.fileNoSuchFile) }
            draftPracticeName = practice.name
            question.practiceID = practiceID
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
            selectedMaterialIDs = Set((try ShenlunWorkspaceRepository.questions(practiceID: practiceID, in: modelContext)
                .first(where: { $0.id == questionID })?.materialIDs) ?? [])
            if let questionID {
                guard let loaded = try ShenlunWorkspaceRepository.question(id: questionID, in: modelContext) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                question = loaded
                originalQuestion = loaded
                didDecideMaterials = loaded.materialDecisionMade ?? practice.materialDecisionMade
            } else {
                question = ShenlunWorkspaceQuestion(
                    practiceID: practiceID,
                    order: practice.questionIDs.count,
                    type: .single
                )
                selectedMaterialIDs = []
                didDecideMaterials = false
            }
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
                    let asset = ShenlunWorkspaceAsset(id: UUID().uuidString, practiceID: practiceID ?? practice?.id ?? "", fileName: url.lastPathComponent, mimeType: "application/pdf", data: data)
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
                    selectedMaterialIDs.insert(material.id)
                    didDecideMaterials = true
                    pageCounts[material.id] = document.pageCount
                    pageRangeText[material.id] = ""
                    practice?.materialDecisionMade = true
                } else {
                    guard UIImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
                    let asset = ShenlunWorkspaceAsset(id: UUID().uuidString, practiceID: practiceID ?? practice?.id ?? "", fileName: url.lastPathComponent, mimeType: "image/\(extensionName.isEmpty ? "jpeg" : extensionName)", data: data)
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
                    selectedMaterialIDs.insert(material.id)
                    didDecideMaterials = true
                    practice?.materialDecisionMade = true
                }
            } catch {
                errorMessage = "无法读取 \(url.lastPathComponent)：\(error.localizedDescription)"
                return
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedTitle = question.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { errorMessage = "题干不能为空。"; return }
        let name = draftPracticeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .paper && name.isEmpty { errorMessage = "套卷名称不能为空。"; return }
        if !fullScoreBinding.wrappedValue.isEmpty,
           question.fullScore == nil || question.fullScore.map({ !$0.isFinite || $0 <= 0 }) == true {
            errorMessage = "满分请填写大于 0 的数字。"; return
        }
        let lower = minimumWordCountBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = maximumWordCountBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lower.isEmpty && question.minimumWordCount == nil { errorMessage = "字数下限必须是正整数。"; return }
        if !upper.isEmpty && question.maximumWordCount == nil { errorMessage = "字数上限必须是正整数。"; return }
        if let minCount = question.minimumWordCount, minCount <= 0 { errorMessage = "字数下限必须是正整数。"; return }
        if let maxCount = question.maximumWordCount, maxCount <= 0 { errorMessage = "字数上限必须是正整数。"; return }
        if question.minimumWordCount != nil && question.maximumWordCount == nil { errorMessage = "填写字数下限时，必须同时填写字数上限。"; return }
        if let minCount = question.minimumWordCount, let maxCount = question.maximumWordCount, minCount > maxCount {
            errorMessage = "字数下限不能大于字数上限。"; return
        }

        for index in materials.indices where materials[index].kind == .pdf {
            guard let pageCount = pageCounts[materials[index].id],
                  let selected = Self.parsePDFSelection(pageRangeText[materials[index].id] ?? "", pageCount: pageCount),
                  !selected.isEmpty else {
                errorMessage = "请为每份 PDF 选择有效页码范围，例如 1-3,5。"
                return
            }
            materials[index].selectedPDFPageIndices = selected
        }

        isSaving = true
        errorMessage = nil
        let now = Date.now
        let newPracticeID = practiceID ?? UUID().uuidString
        question.practiceID = newPracticeID
        question.title = trimmedTitle
        question.materialIDs = materials.map(\.id).filter { selectedMaterialIDs.contains($0) }
        question.materialDecisionMade = didDecideMaterials || !selectedMaterialIDs.isEmpty
        question.revision += 1
        var savedPractice = practice ?? ShenlunWorkspacePractice(
            id: newPracticeID,
            name: kind == .single ? trimmedTitle : name,
            kind: kind
        )
        if kind == .paper { savedPractice.name = name }
        if let questionID {
            question.id = questionID
        } else {
            question.order = savedPractice.questionIDs.count
            savedPractice.questionIDs.append(question.id)
        }
        savedPractice.materialIDs = materials.map(\.id)
        savedPractice.materialDecisionMade = didDecideMaterials || savedPractice.materialDecisionMade || !materials.isEmpty || !selectedMaterialIDs.isEmpty
        savedPractice.updatedAt = now
        for index in materials.indices { materials[index].practiceID = newPracticeID }
        for index in newAssets.indices { newAssets[index].practiceID = newPracticeID }

        do {
            let existingAnswer = try ShenlunWorkspaceRepository.answer(questionID: question.id, in: modelContext)
            var answerUpdate: ShenlunWorkspaceAnswer?
            if let existingAnswer, existingAnswer.confirmedScore != nil, scoringInputsChanged(practice: savedPractice) {
                var answer = existingAnswer
                answer.reviewState = .needsReview
                answer.revision += 1
                answerUpdate = answer
            }
            try ShenlunWorkspaceRepository.savePracticeAndQuestion(
                savedPractice,
                question,
                createdAt: savedPractice.createdAt,
                materials: materials,
                assets: newAssets,
                answerUpdate: answerUpdate,
                deletingMaterialIDs: Array(deletingMaterialIDs),
                deletingAssetIDs: Array(deletingAssetIDs),
                in: modelContext
            )
            isSaving = false
            onSaved(savedPractice.id, question.id)
        } catch {
            isSaving = false
            errorMessage = "保存失败，内容仍保留在当前表单：\(error.localizedDescription)"
        }
    }

    private func scoringInputsChanged(practice savedPractice: ShenlunWorkspacePractice) -> Bool {
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

    private static func parsePDFSelection(_ text: String, pageCount: Int) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, pageCount > 0 else { return nil }
        var selected = Set<Int>()
        for component in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            let token = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            if bounds.count == 1 {
                guard let page = Int(bounds[0]), (1...pageCount).contains(page) else { return nil }
                selected.insert(page - 1)
            } else if bounds.count == 2,
                      let first = Int(bounds[0]), let last = Int(bounds[1]),
                      first > 0, first <= last, last <= pageCount {
                selected.formUnion((first...last).map { $0 - 1 })
            } else {
                return nil
            }
        }
        return selected.sorted()
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
