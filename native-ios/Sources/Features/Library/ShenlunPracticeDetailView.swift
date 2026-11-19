import PDFKit
import PencilKit
import SwiftData
import SwiftUI
import UIKit

private enum ShenlunReviewSection: String, CaseIterable, Identifiable {
    case answer
    case doubts
    case score
    var id: String { rawValue }
    var title: String {
        switch self {
        case .answer: "对照答案"
        case .doubts: "逐条答疑"
        case .score: "评分与分析"
        }
    }
}

private struct ShenlunQuestionReadingLocation: Codable {
    var materialID: String?
    var pageIndex: Int
}

struct ShenlunPracticeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pencilController = PencilDrawingController()

    let practice: ShenlunWorkspacePractice
    let onEditQuestion: (String) -> Void
    let onAddQuestion: () -> Void
    let onPracticeChanged: () -> Void

    @State private var questions: [ShenlunWorkspaceQuestion] = []
    @State private var materials: [ShenlunWorkspaceMaterial] = []
    @State private var answers: [String: ShenlunWorkspaceAnswer] = [:]
    @State private var questionID: String?
    @State private var selectedMaterialID: String?
    @State private var pageIndex = 0
    @State private var zoom: CGFloat = 0.55
    @State private var answerText = ""
    @State private var referenceAnswerDraft = ""
    @State private var isAnswerEditing = false
    @State private var isEditingCompletedAnswer = false
    @State private var isEditingReferenceAnswer = false
    @State private var selectedReviewSection: ShenlunReviewSection = .answer
    @State private var isDoodling = false
    @State private var drawingData = ""
    @State private var drawingPreviews: [String: UIImage] = [:]
    @State private var assetImage: UIImage?
    @State private var pageAspect: CGFloat = 612 / 866
    @State private var textPaperLayout: ShenlunWorkspacePaperLayout?
    @State private var requirementsPaperLayout: ShenlunWorkspacePaperLayout?
    @State private var readingLocations: [String: ShenlunQuestionReadingLocation] = [:]
    @State private var errorMessage: String?
    @State private var isShowingLayerMenu = false
    @State private var isShowingNewLayer = false
    @State private var layerName = ""
    @State private var isShowingDoubtEditor = false
    @State private var doubtText = ""
    @State private var showsDoubts = false
    @State private var answerPaperIndex = 0
    @State private var didLoad = false

    init(
        practice: ShenlunWorkspacePractice,
        selectedQuestionID: String?,
        onEditQuestion: @escaping (String) -> Void,
        onAddQuestion: @escaping () -> Void,
        onPracticeChanged: @escaping () -> Void
    ) {
        self.practice = practice
        self.onEditQuestion = onEditQuestion
        self.onAddQuestion = onAddQuestion
        self.onPracticeChanged = onPracticeChanged
        _questionID = State(initialValue: selectedQuestionID ?? practice.questionIDs.first)
    }

    private var currentQuestion: ShenlunWorkspaceQuestion? {
        questions.first { $0.id == questionID }
    }

    private var currentQuestionIndex: Int? {
        guard let questionID else { return nil }
        return questions.firstIndex { $0.id == questionID }
    }

    private var currentAnswer: ShenlunWorkspaceAnswer? {
        questionID.flatMap { answers[$0] }
    }

    private var currentMaterial: ShenlunWorkspaceMaterial? {
        selectedMaterialID.flatMap { id in materials.first { $0.id == id } }
    }

    private var currentQuestionMaterials: [ShenlunWorkspaceMaterial] {
        let linkedIDs = Set(currentQuestion?.materialIDs ?? [])
        return materials.filter { linkedIDs.contains($0.id) }.sorted { $0.order < $1.order }
    }

    private var didDecideCurrentQuestionMaterials: Bool {
        currentQuestion?.materialDecisionMade ?? practice.materialDecisionMade
    }

    private var activeLayer: ShenlunWorkspaceLayer? {
        guard let currentMaterial, let activeLayerID = currentMaterial.activeLayerID else { return nil }
        return currentMaterial.layers.first { $0.id == activeLayerID }
    }

    private var isRequirementsPage: Bool { selectedMaterialID == nil }

    private var leftPageCount: Int {
        if isRequirementsPage { return max(1, requirementsPaperLayout?.pages.count ?? 1) }
        guard let currentMaterial else { return 1 }
        switch currentMaterial.kind {
        case .text: return max(1, textPaperLayout?.pages.count ?? 1)
        case .pdf: return max(1, currentMaterial.selectedPDFPageIndices.count)
        case .image: return 1
        }
    }

    private var drawingPageID: String {
        if isRequirementsPage { return "requirements-page-\(pageIndex)" }
        return "\(currentMaterial?.id ?? "missing")|\(currentMaterial?.versionID ?? "missing")|\(sourcePageIndex)"
    }

    private var drawingLoadKey: String { "\(didLoad)|\(drawingPageID)|\(activeLayer?.id ?? "none")" }
    private var answerDraftTaskKey: String { "\(didLoad)|\(questionID ?? "")|\(answerText)" }
    private var readingLocationDefaultsKey: String { "native.shenlun.reader.\(practice.id)" }

    private var sourcePageIndex: Int {
        guard let currentMaterial, currentMaterial.kind == .pdf,
              currentMaterial.selectedPDFPageIndices.indices.contains(pageIndex) else { return pageIndex }
        return currentMaterial.selectedPDFPageIndices[pageIndex]
    }

    private var paperSize: CGSize {
        guard currentMaterial?.kind != .text, !isRequirementsPage else { return CGSize(width: 612, height: 866) }
        let aspect = pageAspect.isFinite && pageAspect > 0 ? pageAspect : 612 / 866
        return CGSize(width: 612, height: 612 / aspect)
    }

    private var answerProjection: ShenlunAnswerGridProjection {
        ShenlunAnswerGridLayout.project(answerText: answerText, maximumWordCount: currentQuestion?.maximumWordCount)
    }

    var body: some View {
        GeometryReader { proxy in
            let dualPane = proxy.size.width >= 680
            let available = max(0, proxy.size.width - 1)
            let leftWidth = min(max(280, available * 0.55), max(280, available - 280))
            VStack(spacing: 0) {
                topBar
                if dualPane {
                    HStack(spacing: 0) {
                        leftPane.frame(width: leftWidth)
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                        rightPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            leftPane
                                .frame(minHeight: 390)
                            rightPane
                                .frame(minHeight: 540)
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(Color.white)
            .overlay(alignment: .bottom) {
                if pencilController.showSettings && isDoodling {
                    NativePencilDrawingSettingsPanel(controller: pencilController)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.white)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingDoubtEditor) { doubtEditorSheet }
        .alert("申论工作区", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("新建图层", isPresented: $isShowingNewLayer) {
            TextField("图层名称", text: $layerName)
            Button("保存") { createLayer() }
            Button("取消", role: .cancel) { layerName = "" }
        } message: {
            Text("图层名称不能为空。")
        }
        .popover(isPresented: $isShowingLayerMenu, arrowEdge: .top) { layerPopover }
        .task { loadInitialData() }
        .task(id: drawingLoadKey) { loadPageAssetsAndDrawings() }
        .task(id: drawingData) {
            guard isDoodling, !drawingData.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            _ = persistDrawingNow()
        }
        .task(id: answerDraftTaskKey) {
            guard didLoad, questionID != nil, !isEditingCompletedAnswer else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled else { return }
            persistAnswerDraft()
        }
        .onChange(of: currentMaterial?.versionID) { _, _ in refreshTextPaperLayout() }
    }

    private var topBar: some View {
        HStack(spacing: 9) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 42)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("返回申论列表")

            Text(practice.name)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(practice.name)

            Menu {
                if let currentQuestion {
                    Button { onEditQuestion(currentQuestion.id) } label: { Label("编辑题目", systemImage: "pencil") }
                }
                if practice.kind == .paper {
                    Button(action: onAddQuestion) { Label("添加题目", systemImage: "plus") }
                }
                Button {
                    selectMaterial(nil)
                } label: { Label("查看作答要求", systemImage: "doc.text") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 42)
            }
            .accessibilityLabel("更多操作")

            if !isRequirementsPage, currentMaterial != nil {
                Button { isShowingLayerMenu.toggle() } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 42)
                }
                .accessibilityLabel("批注图层")
            }

            if !isRequirementsPage, currentMaterial != nil {
                NativeDoodleToolbarCapsule {
                    Button {
                        pencilController.selectPenTool()
                        toggleDoodling()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isDoodling ? "xmark" : "pencil.tip.crop.circle")
                            Text(isDoodling ? "收起" : "涂鸦")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isDoodling ? AppTheme.accent : .primary)
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                    }
                    .disabled(activeLayer?.isVisible != true || currentMaterial?.showAllLayers != true)
                    Button {
                        pencilController.showSettings.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 36)
                    }
                    .accessibilityLabel("画笔设置")
                    .disabled(!isDoodling || currentMaterial?.showAllLayers != true)
                    Button { pencilController.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 36)
                    }
                    .accessibilityLabel("撤销当前页笔迹")
                    .disabled(!isDoodling || activeLayer?.isVisible != true)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 54)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.7) }
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            materialSelector
            if currentQuestionMaterials.isEmpty && !didDecideCurrentQuestionMaterials {
                Label("尚未设置给定材料", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else if currentQuestionMaterials.isEmpty && didDecideCurrentQuestionMaterials {
                Text("此题已明确设置为无需材料")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            ScrollView([.horizontal, .vertical]) {
                paperViewport
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.97))
            leftPaperControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.95, green: 0.96, blue: 0.97))
    }

    private var materialSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(currentQuestionMaterials) { material in
                    materialTab(material)
                }
                Button {
                    selectMaterial(nil)
                } label: {
                    tabLabel("作答要求", isSelected: isRequirementsPage)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 50)
        .background(Color.white)
    }

    private func materialTab(_ material: ShenlunWorkspaceMaterial) -> some View {
        Button { selectMaterial(material.id) } label: {
            tabLabel(material.title.isEmpty ? "材料 \(material.order + 1)" : material.title,
                     isSelected: selectedMaterialID == material.id)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shenlun-material-tab-\(material.id)")
    }

    private func tabLabel(_ text: String, isSelected: Bool) -> some View {
        VStack(spacing: 7) {
            Text(text).font(.system(size: 13, weight: isSelected ? .semibold : .regular)).lineLimit(1)
            Capsule().fill(isSelected ? AppTheme.accent : .clear).frame(height: 2)
        }
        .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
        .frame(height: 50)
    }

    private var paperViewport: some View {
        let size = paperSize
        return ZStack(alignment: .topLeading) {
            pageSurface
                .frame(width: size.width, height: size.height)

            ForEach(visibleDrawingLayerIDs, id: \.self) { layerID in
                if let preview = drawingPreviews[layerID], !(isDoodling && activeLayer?.id == layerID) {
                    Image(uiImage: preview)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            if isDoodling, activeLayer?.isVisible == true, let currentMaterial, currentMaterial.showAllLayers {
                NativePencilDrawingEditor(
                    encodedData: $drawingData,
                    transparentBackground: true,
                    isActive: true,
                    minimumCanvasHeight: size.height,
                    settingsPanelPresentedExternally: true,
                    controller: pencilController
                )
                .frame(width: size.width, height: size.height)
                .accessibilityIdentifier("shenlun-page-drawing-\(currentMaterial.id)-\(activeLayer!.id)")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(zoom, anchor: .topLeading)
        .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
        .shadow(color: .black.opacity(0.10), radius: 7, y: 3)
    }

    @ViewBuilder private var pageSurface: some View {
        if isRequirementsPage {
            let pages = requirementsPaperLayout?.pages ?? []
            paperPage(pages.indices.contains(pageIndex) ? pages[pageIndex] : (pages.first ?? NSAttributedString(string: "")))
        } else if let currentMaterial {
            switch currentMaterial.kind {
            case .text:
                let pages = textPaperLayout?.pages ?? []
                paperPage(pages.indices.contains(pageIndex) ? pages[pageIndex] : (pages.first ?? NSAttributedString(string: "")))
            case .pdf, .image:
                ZStack {
                    Color.white
                    if let assetImage {
                        Image(uiImage: assetImage).resizable().scaledToFit()
                    } else if let errorMessage {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                    } else {
                        ProgressView()
                    }
                }
            }
        } else {
            paperPage(NSAttributedString(string: "尚未选择材料。"))
        }
    }

    private func paperPage(_ attributedText: NSAttributedString) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            ShenlunWorkspaceTextPaperPage(text: attributedText)
                .frame(width: 472, height: 741)
                .padding(.leading, 70)
                .padding(.top, 68)
        }
        .frame(width: 612, height: 866)
        .overlay { Rectangle().stroke(Color.primary.opacity(0.07), lineWidth: 0.6) }
    }

    private var leftPaperControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("缩放").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $zoom, in: 0.45...1.2, step: 0.05)
                    .accessibilityLabel("纸面缩放")
                Text("\(Int(zoom * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Button { changePage(to: pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(pageIndex <= 0)
                Text("\(min(pageIndex + 1, leftPageCount))/\(leftPageCount) 页")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                Button { changePage(to: pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(pageIndex + 1 >= leftPageCount)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white)
    }

    private var rightPane: some View {
        VStack(spacing: 0) {
            rightHeader
            Divider()
            if let currentQuestion {
                if currentAnswer?.isCompleted == true {
                    completedReview(for: currentQuestion)
                } else {
                    answerInput(for: currentQuestion)
                }
            } else {
                ContentUnavailableView("尚无题目", systemImage: "doc.text", description: Text("请先录入题干和作答要求。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rightHeader: some View {
        HStack(spacing: 10) {
            Text("答题纸").font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 6)
            if questions.count > 1, let index = currentQuestionIndex {
                Button {
                    if index > 0 { selectQuestion(questions[index - 1].id) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(index == 0)
                .accessibilityLabel("上一题")
                Menu {
                    ForEach(questions) { question in
                        Button {
                            selectQuestion(question.id)
                        } label: {
                            Text("\(question.order + 1) · \(question.type.title) · \(question.title.prefix(28))")
                        }
                    }
                } label: {
                    Text("\(index + 1)/\(questions.count)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(Rectangle())
                    .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .accessibilityLabel("选择题目序号")
                Button {
                    if index + 1 < questions.count { selectQuestion(questions[index + 1].id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(index + 1 >= questions.count)
                .accessibilityLabel("下一题")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color.white)
    }

    private func answerInput(for question: ShenlunWorkspaceQuestion) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(isAnswerEditing ? "收起" : "键入") { isAnswerEditing.toggle() }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.accent)
                Spacer()
                if let maximum = question.maximumWordCount {
                    Text("\(answerProjection.occupiedCount)/\(maximum) 格")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(answerProjection.overflowCount > 0 ? AppTheme.danger : .secondary)
                } else {
                    Text("未设字数上限 · \(answerText.count) 字")
                        .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if question.maximumWordCount == nil {
                        Text("未设字数上限").font(.system(size: 13)).foregroundStyle(.secondary)
                        if isAnswerEditing || answerText.isEmpty {
                            ShenlunCommittedTextEditor(text: $answerText, accessibilityIdentifier: "shenlun-answer-text")
                                .frame(minHeight: 220)
                        } else {
                            Text(answerText).font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        answerGridPaper(for: question)
                            .onTapGesture { isAnswerEditing = true }
                        if answerProjection.overflowCount > 0 {
                            Text("超出 \(answerProjection.overflowCount) 格，原文未截断。")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.danger)
                        }
                        if isAnswerEditing {
                            ShenlunCommittedTextEditor(text: $answerText, accessibilityIdentifier: "shenlun-answer-text")
                                .frame(minHeight: 180)
                        }
                    }
                }
                .padding(12)
            }
            Spacer(minLength: 0)
            doubtDisclosure
            HStack(spacing: 12) {
                Button("记疑惑") { openDoubtEditor() }
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("完成作答", action: completeAnswer)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.45) : AppTheme.accent, in: Capsule())
                    .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }

    private func answerGridPaper(for question: ShenlunWorkspaceQuestion) -> some View {
        let sheetCount = answerProjection.sheetCount
        let sheet = min(answerPaperIndex, max(0, sheetCount - 1))
        let maxCount = question.maximumWordCount ?? 0
        let gridCells = answerProjection.gridCellCount(on: sheet)
        return VStack(spacing: 8) {
            if sheetCount > 1 {
                HStack {
                    Text("\(sheet + 1)/\(sheetCount) 张").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { answerPaperIndex = max(0, answerPaperIndex - 1) } label: { Image(systemName: "chevron.left") }.disabled(sheet <= 0)
                    Button { answerPaperIndex = min(sheetCount - 1, answerPaperIndex + 1) } label: { Image(systemName: "chevron.right") }.disabled(sheet + 1 >= sheetCount)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geometry in
                let cell = max(5, geometry.size.width / 25)
                let rows = answerProjection.rowCount(on: sheet)
                Canvas { context, size in
                    let spacing = cell * 0.42
                    let pageStart = sheet * 600
                    let cellsOnLastRow = gridCells % 25 == 0 ? 25 : gridCells % 25
                    for row in 0..<rows {
                        let rowCount = row == rows - 1 ? cellsOnLastRow : 25
                        for column in 0..<rowCount {
                            let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * (cell + spacing), width: cell - 1, height: cell - 1)
                            context.stroke(Path(rect), with: .color(Color(red: 0.71, green: 0.50, blue: 0.51).opacity(0.68)), lineWidth: column == 24 ? 1.1 : 0.65)
                        }
                    }
                    for item in answerProjection.visibleCells(on: sheet) {
                        guard item.index <= maxCount, item.character != " " && item.character != "\t" else { continue }
                        let point = CGPoint(x: CGFloat(item.column) * cell + cell * 0.1, y: CGFloat(item.row) * (cell + spacing) + cell * 0.02)
                        context.draw(Text(item.character).font(.system(size: cell * 0.72, weight: .regular, design: .serif)).foregroundColor(.primary), at: point, anchor: .topLeading)
                    }
                    for mark in answerProjection.markers(on: sheet, minimumWordCount: question.minimumWordCount) {
                        let row = ((mark - 1) % 600) / 25
                        let column = (mark - 1) % 25
                        let label = Text(String(mark)).font(.system(size: max(6, cell * 0.28), weight: .medium).monospacedDigit()).foregroundColor(Color(red: 0.58, green: 0.26, blue: 0.29))
                        context.draw(label, at: CGPoint(x: CGFloat(column + 1) * cell - 2, y: CGFloat(row) * (cell + spacing) + cell), anchor: .topTrailing)
                    }
                    _ = pageStart
                    _ = size
                }
                .frame(height: CGFloat(rows) * (cell * 1.42) + 14)
            }
            .aspectRatio(25 / (CGFloat(max(1, answerProjection.rowCount(on: sheet))) * 1.42 + 1.25), contentMode: .fit)
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 0.7) }
        }
    }

    private var doubtDisclosure: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                showsDoubts.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("已有疑惑")
                    Text("\(currentAnswer?.doubts.count ?? 0)").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showsDoubts ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            if showsDoubts {
                ForEach(currentAnswer?.doubts ?? []) { doubt in
                    Text(doubt.body).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    private func completedReview(for question: ShenlunWorkspaceQuestion) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(ShenlunReviewSection.allCases) { section in
                    Button(section.title) { selectedReviewSection = section }
                        .font(.system(size: 11, weight: selectedReviewSection == section ? .semibold : .regular))
                        .foregroundStyle(selectedReviewSection == section ? AppTheme.accent : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selectedReviewSection == section ? AppTheme.accent : .clear).frame(height: 2)
                        }
                }
            }
            .padding(.horizontal, 9)
            .background(Color.white)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if currentAnswer?.reviewState == .needsReview {
                        Label("题目或参考内容已修改，原评分需复核。", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.warning)
                    }
                    switch selectedReviewSection {
                    case .answer:
                        Text("我的作答").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        if isEditingCompletedAnswer {
                            ShenlunCommittedTextEditor(text: $answerText, accessibilityIdentifier: "shenlun-answer-edit")
                                .frame(minHeight: 220)
                            Button("保存作答修改") { _ = saveRevisedAnswer() }
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.accent)
                        } else {
                            Text(answerText).font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                            Button("修改作答") { isEditingCompletedAnswer = true }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.accent)
                        }
                        Divider()
                        Text("参考答案").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        if isEditingReferenceAnswer {
                            TextEditor(text: $referenceAnswerDraft)
                                .font(.system(size: 15))
                                .frame(minHeight: 180)
                                .padding(8)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            HStack {
                                Button("取消") {
                                    referenceAnswerDraft = question.referenceAnswer
                                    isEditingReferenceAnswer = false
                                }
                                Spacer()
                                Button("保存参考答案") { _ = saveReferenceAnswer() }
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        } else {
                            Text(question.referenceAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "尚未录入参考答案。" : question.referenceAnswer)
                                .font(.system(size: 15)).foregroundStyle(question.referenceAnswer.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("修改参考答案") {
                                referenceAnswerDraft = question.referenceAnswer
                                isEditingReferenceAnswer = true
                            }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.accent)
                        }
                    case .doubts:
                        HStack {
                            Text("逐条答疑").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Button("记疑惑") { openDoubtEditor() }.font(.system(size: 12, weight: .medium))
                        }
                        if currentAnswer?.doubts.isEmpty != false {
                            Text("此题尚未记录疑惑。可以在对照答案后逐条补充。")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        if currentAnswer?.reviewState == .pendingVerification {
                            Label("已标记为待核验", systemImage: "checkmark.circle")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.warning)
                        } else {
                            Button("标记为待核验") { markPendingVerification() }
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.accent)
                        }
                        ForEach(Array((currentAnswer?.doubts ?? []).enumerated()), id: \.element.id) { index, doubt in
                            VStack(alignment: .leading, spacing: 7) {
                                Text("疑惑 \(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.accent)
                                Text(doubt.body).font(.system(size: 14))
                                if let materialID = doubt.materialID {
                                    Text("锚点：\(materials.first(where: { $0.id == materialID })?.title ?? "材料") · 第 \((doubt.pageIndex ?? 0) + 1) 页")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                } else if let page = doubt.pageIndex {
                                    Text("锚点：作答要求 · 第 \(page + 1) 页")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                    case .score:
                        scoreUnavailableState
                    }
                }
                .padding(15)
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
        }
    }

    private var scoreUnavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            if currentAnswer?.reviewState == .confirmed, let score = currentAnswer?.confirmedScore {
                Text("已确认评分").font(.system(size: 14, weight: .semibold))
                Text("\(score.formatted(.number.precision(.fractionLength(0...2)))) 分")
                    .font(.system(size: 25, weight: .bold)).foregroundStyle(AppTheme.accent)
                if let analysis = currentAnswer?.confirmedAnalysis, !analysis.isEmpty { Text(analysis).font(.system(size: 14)) }
            } else {
                if currentAnswer?.reviewState == .pendingVerification {
                    Label("已标记为待核验", systemImage: "checkmark.circle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.warning)
                }
                Label("评分与分析服务尚未接入", systemImage: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                Text("本版本没有申论评分或分析接口。这里不会生成分数、答疑结论或知识点报告。作答和疑惑仍会保存在本机。")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("发起评分与分析") {}
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .disabled(true)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var doubtEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("记录当前题目中的一个具体疑惑。可在复盘时继续补充或逐条核对。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                TextEditor(text: $doubtText)
                    .font(.system(size: 15))
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                if let currentMaterial {
                    let anchorPage = currentMaterial.kind == .pdf ? sourcePageIndex : pageIndex
                    Text("锚点：\(currentMaterial.title) · 第 \(anchorPage + 1) 页")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else if isRequirementsPage {
                    Text("锚点：作答要求 · 第 \(pageIndex + 1) 页")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .navigationTitle("记疑惑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { isShowingDoubtEditor = false } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { saveDoubt() }.disabled(doubtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var layerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批注图层").font(.system(size: 14, weight: .semibold))
            if let currentMaterial {
                ForEach(currentMaterial.layers) { layer in
                    HStack(spacing: 8) {
                        Image(uiImage: drawingPreviews[layer.id] ?? UIImage())
                            .resizable().scaledToFit().frame(width: 34, height: 31)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                        Button(layer.name) { activateLayer(layer.id) }
                            .font(.system(size: 13, weight: layer.id == currentMaterial.activeLayerID ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(layer.id == currentMaterial.activeLayerID ? AppTheme.accent : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { toggleLayer(layer.id) } label: {
                            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                                .frame(width: 38, height: 44)
                        }
                        .accessibilityLabel("\(layer.name)，\(layer.isVisible ? "显示" : "隐藏")")
                        Menu {
                            Button("重命名") {
                                layerName = layer.name
                                layerToRenameID = layer.id
                                isShowingRenameLayer = true
                            }
                            .labelStyle(.titleAndIcon)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 34, height: 44)
                        }
                        .accessibilityLabel("管理图层 \(layer.name)")
                    }
                    .frame(minHeight: 44)
                }
                Button("＋ 新建图层") { layerName = ""; isShowingNewLayer = true }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Divider()
                Button {
                    var updated = currentMaterial
                    updated.showAllLayers.toggle()
                    let shouldHide = !updated.showAllLayers
                    commitDrawingBeforeTransition {
                        self.saveMaterial(updated)
                        if shouldHide {
                            self.isDoodling = false
                            self.pencilController.showSettings = false
                        }
                    }
                } label: {
                    Label(currentMaterial.showAllLayers ? "隐藏全部图层预览" : "显示全部图层", systemImage: currentMaterial.showAllLayers ? "eye.slash" : "eye")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(width: 258)
        .frame(maxHeight: 390)
        .background(Color.white)
        .alert("重命名图层", isPresented: $isShowingRenameLayer) {
            TextField("图层名称", text: $layerName)
            Button("保存") { renameLayer() }
            Button("取消", role: .cancel) { layerToRenameID = nil }
        }
    }

    @State private var layerToRenameID: String?
    @State private var isShowingRenameLayer = false

    private var visibleDrawingLayerIDs: [String] {
        guard let currentMaterial, currentMaterial.showAllLayers else { return [] }
        return currentMaterial.layers.filter(\.isVisible).map(\.id)
    }

    private func loadInitialData() {
        guard !didLoad else { return }
        do {
            questions = try ShenlunWorkspaceRepository.questions(practiceID: practice.id, in: modelContext)
            materials = try ShenlunWorkspaceRepository.materials(practiceID: practice.id, in: modelContext)
            answers = try ShenlunWorkspaceRepository.answers(practiceID: practice.id, in: modelContext)
            if let data = UserDefaults.standard.data(forKey: readingLocationDefaultsKey),
               let saved = try? JSONDecoder().decode([String: ShenlunQuestionReadingLocation].self, from: data) {
                readingLocations = saved
            }
            if !questions.contains(where: { $0.id == questionID }) { questionID = questions.first?.id }
            requirementsPaperLayout = ShenlunWorkspacePaperLayout.requirements(questions: questions)
            if let questionID {
                let location = readingLocation(for: questionID)
                selectedMaterialID = location.materialID
                pageIndex = location.pageIndex
            }
            if let questionID {
                answerText = answers[questionID]?.answerText ?? ""
                referenceAnswerDraft = questions.first(where: { $0.id == questionID })?.referenceAnswer ?? ""
            }
            refreshTextPaperLayout(for: materials.first(where: { $0.id == selectedMaterialID }))
            didLoad = true
        } catch {
            errorMessage = "无法载入练习：\(error.localizedDescription)"
        }
    }

    private func refreshTextPaperLayout() {
        refreshTextPaperLayout(for: currentMaterial)
    }

    private func refreshTextPaperLayout(for material: ShenlunWorkspaceMaterial?) {
        guard let material, material.kind == .text else {
            textPaperLayout = nil
            return
        }
        textPaperLayout = ShenlunWorkspacePaperLayout.material(title: material.title, text: material.text)
        pageIndex = min(pageIndex, max(0, (textPaperLayout?.pages.count ?? 1) - 1))
    }

    private func rememberReadingLocation(for id: String?) {
        guard let id else { return }
        readingLocations[id] = ShenlunQuestionReadingLocation(materialID: selectedMaterialID, pageIndex: pageIndex)
        if let data = try? JSONEncoder().encode(readingLocations) {
            UserDefaults.standard.set(data, forKey: readingLocationDefaultsKey)
        }
    }

    private func selectMaterial(_ materialID: String?) {
        guard selectedMaterialID != materialID else { return }
        let currentQuestionID = questionID
        let change = {
            self.rememberReadingLocation(for: currentQuestionID)
            self.selectedMaterialID = materialID
            self.pageIndex = 0
            self.refreshTextPaperLayout(for: self.materials.first(where: { $0.id == materialID }))
            self.rememberReadingLocation(for: currentQuestionID)
        }
        commitDrawingBeforeTransition(change)
    }

    private func readingLocation(for targetQuestionID: String) -> ShenlunQuestionReadingLocation {
        let linkedIDs = Set(questions.first(where: { $0.id == targetQuestionID })?.materialIDs ?? [])
        if let saved = readingLocations[targetQuestionID],
           saved.materialID == nil || (linkedIDs.contains(saved.materialID ?? "") && materials.contains(where: { $0.id == saved.materialID })) {
            let pageCount: Int
            if let materialID = saved.materialID, let material = materials.first(where: { $0.id == materialID }) {
                switch material.kind {
                case .text: pageCount = ShenlunWorkspacePaperLayout.material(title: material.title, text: material.text).pages.count
                case .pdf: pageCount = material.selectedPDFPageIndices.count
                case .image: pageCount = 1
                }
            } else {
                pageCount = requirementsPaperLayout?.pages.count ?? 1
            }
            return ShenlunQuestionReadingLocation(
                materialID: saved.materialID,
                pageIndex: min(max(0, saved.pageIndex), max(0, pageCount - 1))
            )
        }
        let firstMaterial = materials
            .filter { linkedIDs.contains($0.id) }
            .sorted { $0.order < $1.order }
            .first
        return ShenlunQuestionReadingLocation(materialID: firstMaterial?.id, pageIndex: 0)
    }

    private func loadPageAssetsAndDrawings() {
        loadCurrentAssetPage()
        drawingPreviews = [:]
        if let currentMaterial {
            var layers = currentMaterial.layers
            if layers.isEmpty {
                layers = [.init(name: "批注")]
                var repaired = currentMaterial
                repaired.layers = layers
                repaired.activeLayerID = layers.first?.id
                saveMaterial(repaired)
            }
            do {
                let drawings = try ShenlunWorkspaceRepository.drawings(
                    practiceID: practice.id,
                    materialID: currentMaterial.id,
                    materialVersionID: currentMaterial.versionID,
                    pageID: drawingPageID,
                    in: modelContext
                )
                let rect = CGRect(origin: .zero, size: paperSize)
                for drawing in drawings {
                    if let decoded = try? PKDrawing(data: drawing.drawingData), !decoded.strokes.isEmpty {
                        drawingPreviews[drawing.layerID] = decoded.image(from: rect, scale: 1)
                    }
                }
                let activeID = currentMaterial.activeLayerID ?? layers.first?.id
                drawingData = drawings.first(where: { $0.layerID == activeID })?.drawingData.base64EncodedString() ?? ""
            } catch {
                errorMessage = "笔迹读取失败：\(error.localizedDescription)"
            }
        } else {
            drawingData = ""
            drawingPreviews = [:]
        }
    }

    private func loadCurrentAssetPage() {
        assetImage = nil
        guard let currentMaterial, currentMaterial.kind != .text, let assetID = currentMaterial.assetID else { return }
        do {
            guard let asset = try ShenlunWorkspaceRepository.asset(id: assetID, in: modelContext) else {
                errorMessage = "材料附件已丢失，原始记录仍保留。"
                return
            }
            if currentMaterial.kind == .image {
                guard let image = UIImage(data: asset.data) else { errorMessage = "图片无法解码。"; return }
                pageAspect = image.size.width / max(1, image.size.height)
                assetImage = image
            } else {
                guard let document = PDFDocument(data: asset.data),
                      currentMaterial.selectedPDFPageIndices.indices.contains(pageIndex),
                      let page = document.page(at: sourcePageIndex) else {
                    errorMessage = "PDF 页面无法读取。"
                    return
                }
                let bounds = page.bounds(for: .cropBox)
                pageAspect = bounds.width / max(1, bounds.height)
                assetImage = page.thumbnail(of: CGSize(width: 1224, height: 1732), for: .cropBox)
            }
        } catch {
            errorMessage = "材料附件读取失败：\(error.localizedDescription)"
        }
    }

    private func selectQuestion(_ id: String) {
        guard id != questionID else { return }
        if isEditingReferenceAnswer {
            guard saveReferenceAnswer() else { return }
        }
        if isEditingCompletedAnswer {
            guard saveRevisedAnswer() else { return }
        } else {
            persistAnswerDraft()
        }
        let location = readingLocation(for: id)
        let previousQuestionID = questionID
        let change = {
            self.rememberReadingLocation(for: previousQuestionID)
            self.questionID = id
            self.answerText = self.answers[id]?.answerText ?? ""
            self.referenceAnswerDraft = self.questions.first(where: { $0.id == id })?.referenceAnswer ?? ""
            self.isAnswerEditing = false
            self.isEditingCompletedAnswer = false
            self.isEditingReferenceAnswer = false
            self.selectedReviewSection = .answer
            self.answerPaperIndex = 0
            self.selectedMaterialID = location.materialID
            self.pageIndex = location.pageIndex
            self.refreshTextPaperLayout(for: self.materials.first(where: { $0.id == location.materialID }))
            self.rememberReadingLocation(for: id)
        }
        commitDrawingBeforeTransition(change)
    }

    private func completeAnswer() {
        guard !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let questionID else {
            errorMessage = "空白答案不能完成作答。"
            return
        }
        var updated = answers[questionID] ?? ShenlunWorkspaceAnswer(practiceID: practice.id, questionID: questionID)
        updated.answerText = answerText
        updated.isCompleted = true
        updated.completedAt = .now
        updated.revision += 1
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            answers[questionID] = updated
            isAnswerEditing = false
            selectedReviewSection = .answer
            answerPaperIndex = 0
            onPracticeChanged()
        } catch {
            errorMessage = "作答保存失败：\(error.localizedDescription)"
        }
    }

    private func persistAnswerDraft() {
        guard let questionID else { return }
        let current = answers[questionID]
        guard current?.answerText != answerText || current == nil else { return }
        var updated = current ?? ShenlunWorkspaceAnswer(practiceID: practice.id, questionID: questionID)
        updated.answerText = answerText
        updated.revision += 1
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            answers[questionID] = updated
            onPracticeChanged()
        } catch {
            errorMessage = "草稿保存失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func saveRevisedAnswer() -> Bool {
        guard let questionID else { return false }
        var updated = answers[questionID] ?? ShenlunWorkspaceAnswer(practiceID: practice.id, questionID: questionID)
        updated.answerText = answerText
        updated.isCompleted = true
        updated.revision += 1
        if updated.confirmedScore != nil { updated.reviewState = .needsReview }
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            answers[questionID] = updated
            isEditingCompletedAnswer = false
            onPracticeChanged()
            return true
        } catch {
            errorMessage = "作答修改保存失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func saveReferenceAnswer() -> Bool {
        guard let questionID,
              let index = questions.firstIndex(where: { $0.id == questionID }) else { return false }
        var updatedQuestion = questions[index]
        guard updatedQuestion.referenceAnswer != referenceAnswerDraft else {
            isEditingReferenceAnswer = false
            return true
        }
        updatedQuestion.referenceAnswer = referenceAnswerDraft
        updatedQuestion.revision += 1
        var updatedPractice = practice
        updatedPractice.updatedAt = .now
        var answerUpdate = answers[questionID]
        if var answer = answerUpdate, answer.confirmedScore != nil {
            answer.reviewState = .needsReview
            answer.revision += 1
            answerUpdate = answer
        }
        do {
            try ShenlunWorkspaceRepository.savePracticeAndQuestion(
                updatedPractice,
                updatedQuestion,
                createdAt: practice.createdAt,
                answerUpdate: answerUpdate,
                in: modelContext
            )
            questions[index] = updatedQuestion
            if let answerUpdate { answers[questionID] = answerUpdate }
            isEditingReferenceAnswer = false
            onPracticeChanged()
            return true
        } catch {
            errorMessage = "参考答案保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func openDoubtEditor() {
        doubtText = ""
        isShowingDoubtEditor = true
    }

    private func saveDoubt() {
        guard let questionID else { return }
        let text = doubtText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var updated = answers[questionID] ?? ShenlunWorkspaceAnswer(practiceID: practice.id, questionID: questionID)
        updated.doubts.append(ShenlunWorkspaceDoubt(
            questionID: questionID,
            body: text,
            materialID: selectedMaterialID,
            pageIndex: currentMaterial?.kind == .pdf ? sourcePageIndex : pageIndex
        ))
        updated.revision += 1
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            answers[questionID] = updated
            doubtText = ""
            isShowingDoubtEditor = false
            onPracticeChanged()
        } catch {
            errorMessage = "疑惑保存失败：\(error.localizedDescription)"
        }
    }

    private func markPendingVerification() {
        guard let questionID else { return }
        var updated = answers[questionID] ?? ShenlunWorkspaceAnswer(practiceID: practice.id, questionID: questionID)
        updated.reviewState = .pendingVerification
        updated.revision += 1
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            answers[questionID] = updated
            onPracticeChanged()
        } catch {
            errorMessage = "状态保存失败：\(error.localizedDescription)"
        }
    }

    private func toggleDoodling() {
        guard activeLayer?.isVisible == true else { return }
        if isDoodling {
            commitDrawingBeforeTransition { isDoodling = false; pencilController.showSettings = false }
        } else {
            pencilController.prepareForPresentation(preservingLoadedDrawing: true)
            isDoodling = true
        }
    }

    private func commitDrawingBeforeTransition(_ transition: @escaping () -> Void) {
        guard isDoodling else { transition(); return }
        pencilController.commit {
            guard self.persistDrawingNow() else { return }
            self.isDoodling = false
            transition()
        }
    }

    @discardableResult
    private func persistDrawingNow() -> Bool {
        guard let currentMaterial, let activeLayer else { return false }
        let id = ShenlunWorkspaceRepository.drawingRecordID(
            practiceID: practice.id,
            materialID: currentMaterial.id,
            materialVersionID: currentMaterial.versionID,
            pageID: drawingPageID,
            layerID: activeLayer.id
        )
        do {
            if let data = Data(base64Encoded: drawingData), !data.isEmpty {
                try ShenlunWorkspaceRepository.save(ShenlunWorkspaceDrawing(
                    id: id,
                    practiceID: practice.id,
                    materialID: currentMaterial.id,
                    materialVersionID: currentMaterial.versionID,
                    pageID: drawingPageID,
                    layerID: activeLayer.id,
                    drawingData: data,
                    updatedAt: .now
                ), in: modelContext)
            } else {
                try ShenlunWorkspaceRepository.deleteDrawing(id: id, in: modelContext)
            }
            return true
        } catch {
            errorMessage = "笔迹保存失败；当前页笔迹仍留在画布中，可稍后重试。\(error.localizedDescription)"
            return false
        }
    }

    private func activateLayer(_ id: String) {
        guard let currentMaterial, let layerIndex = currentMaterial.layers.firstIndex(where: { $0.id == id }) else { return }
        let update = {
            var material = currentMaterial
            material.layers[layerIndex].isVisible = true
            material.activeLayerID = id
            self.saveMaterial(material)
            self.isShowingLayerMenu = false
        }
        commitDrawingBeforeTransition(update)
    }

    private func toggleLayer(_ id: String) {
        guard let currentMaterial, let index = currentMaterial.layers.firstIndex(where: { $0.id == id }) else { return }
        var material = currentMaterial
        material.layers[index].isVisible.toggle()
        if material.activeLayerID == id && !material.layers[index].isVisible {
            material.activeLayerID = material.layers.first(where: \.isVisible)?.id
        }
        let update = {
            self.saveMaterial(material)
            if material.activeLayerID == nil {
                self.isDoodling = false
                self.pencilController.showSettings = false
            }
        }
        commitDrawingBeforeTransition(update)
    }

    private func createLayer() {
        guard let currentMaterial else { return }
        let name = layerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "图层名称不能为空。"; return }
        guard !currentMaterial.layers.contains(where: { $0.name == name }) else { errorMessage = "此材料中已有同名图层。"; return }
        var material = currentMaterial
        let layer = ShenlunWorkspaceLayer(name: name)
        material.layers.insert(layer, at: 0)
        material.activeLayerID = layer.id
        let update = {
            self.saveMaterial(material)
            self.layerName = ""
            self.isShowingNewLayer = false
            self.isShowingLayerMenu = false
        }
        commitDrawingBeforeTransition(update)
    }

    private func renameLayer() {
        guard let currentMaterial, let layerToRenameID,
              let index = currentMaterial.layers.firstIndex(where: { $0.id == layerToRenameID }) else { return }
        let name = layerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "图层名称不能为空。"; return }
        guard !currentMaterial.layers.enumerated().contains(where: { $0.offset != index && $0.element.name == name }) else {
            errorMessage = "此材料中已有同名图层。"
            return
        }
        var material = currentMaterial
        material.layers[index].name = name
        saveMaterial(material)
        self.layerToRenameID = nil
        layerName = ""
    }

    private func saveMaterial(_ updated: ShenlunWorkspaceMaterial) {
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            if let index = materials.firstIndex(where: { $0.id == updated.id }) { materials[index] = updated }
        } catch {
            errorMessage = "材料或图层保存失败：\(error.localizedDescription)"
        }
    }

    private func changePage(to newIndex: Int) {
        let next = min(max(0, newIndex), leftPageCount - 1)
        guard next != pageIndex else { return }
        let currentQuestionID = questionID
        let update = {
            self.pageIndex = next
            self.rememberReadingLocation(for: currentQuestionID)
        }
        commitDrawingBeforeTransition(update)
    }
}

private struct ShenlunCommittedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 15)
        view.textColor = .label
        view.backgroundColor = .white
        view.accessibilityIdentifier = accessibilityIdentifier
        view.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.text = text
        view.isScrollEnabled = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityIdentifier = accessibilityIdentifier
        guard view.text != text, view.markedTextRange == nil else { return }
        view.text = text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ShenlunCommittedTextEditor
        init(parent: ShenlunCommittedTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text ?? ""
        }
    }
}
