import PDFKit
import PencilKit
import SwiftData
import SwiftUI
import UIKit

private enum ShenlunReviewSection: String, CaseIterable, Identifiable {
    case answer
    case review
    case history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .answer: "对照答案"
        case .review: "本次复盘"
        case .history: "作答历史"
        }
    }
}

private struct ShenlunQuestionReadingLocation: Codable {
    var materialID: String?
    var pageIndex: Int
}

private enum ShenlunLayerNameTarget: Equatable {
    case new
    case existing(String)

    var title: String { self == .new ? "新建图层" : "重命名图层" }
}

struct ShenlunPracticeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("native.shenlun.completed-answer.grid") private var showsCompletedAnswerGrid = true
    @StateObject private var pencilController = PencilDrawingController()

    let practice: ShenlunWorkspacePractice
    let onEditQuestion: (String) -> Void
    let onAddQuestion: () -> Void
    let onPracticeChanged: () -> Void

    @State private var questions: [ShenlunWorkspaceQuestion] = []
    @State private var materials: [ShenlunWorkspaceMaterial] = []
    @State private var histories: [String: ShenlunWorkspaceAttemptHistory] = [:]
    @State private var questionID: String?
    @State private var reviewAttemptID: String?
    @State private var previousReviewAttemptID: String?
    @State private var reviewDraft = ShenlunWorkspaceReviewDraft()
    @State private var reviewSaved = false
    @State private var scoreSaved = false
    @State private var showsHistoryFromAnswer = false
    @State private var showsBackfill = false
    @State private var backfillDate = Date.now
    @State private var backfillAnswer = ""
    @State private var selectedMaterialID: String?
    @State private var pageIndex = 0
    @State private var zoomFraction: CGFloat = 1
    @State private var zoomRequest: ShenlunReaderZoomRequest?
    @State private var zoomActivity = 0
    @State private var showsZoomControl = ProcessInfo.processInfo.arguments.contains("--shenlun-reader-zoom-ui-test")
    @State private var showsZoomMenu = false
    @State private var answerText = ""
    @State private var referenceAnswerDraft = ""
    @State private var answerFocusRequest: UUID?
    @State private var readingFocusRequest: UUID?
    @State private var workFocusRequest: UUID?
    @State private var isEditingReferenceAnswer = false
    @State private var selectedReviewSection: ShenlunReviewSection = .answer
    @State private var isDoodling = false
    @State private var isClosingDoodle = false
    @State private var drawingData = ""
    @State private var drawingPreviews: [String: UIImage] = [:]
    @State private var assetImage: UIImage?
    @State private var pageAspect: CGFloat = 612 / 866
    @State private var textPaperLayout: ShenlunWorkspacePaperLayout?
    @State private var requirementsPaperLayout: ShenlunWorkspacePaperLayout?
    @State private var readingLocations: [String: ShenlunQuestionReadingLocation] = [:]
    @State private var errorMessage: String?
    @State private var isShowingLayerMenu = false
    @State private var layerNameTarget: ShenlunLayerNameTarget?
    @State private var layerName = ""
    @State private var layerNameError: String?
    @State private var isSavingLayerName = false
    @State private var isShowingDoubtEditor = false
    @State private var doubtText = ""
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

    private var currentHistory: ShenlunWorkspaceAttemptHistory? {
        questionID.flatMap { histories[$0] }
    }

    private var reviewAnswer: ShenlunWorkspaceAnswer? {
        currentHistory?.completed.first { $0.id == reviewAttemptID }
    }

    private var currentAttemptNumber: Int {
        reviewAnswer?.attemptNumber ?? currentHistory?.nextNumber ?? 1
    }

    private var completedCount: Int { currentHistory?.completed.count ?? 0 }

    private var canReturnToReview: Bool { completedCount > 0 }

    private var hasAnswerDraft: Bool {
        guard let draft = currentHistory?.draft else { return false }
        return !draft.answerText.isEmpty || !draft.doubts.isEmpty
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
    private var answerDraftTaskKey: String { "\(didLoad)|\(questionID ?? "")|\(reviewAttemptID ?? "")|\(answerText)" }
    private var readingLocationDefaultsKey: String { "native.shenlun.reader.\(practice.id)" }

    private var sourcePageIndex: Int {
        guard let currentMaterial, currentMaterial.kind == .pdf,
              currentMaterial.selectedPDFPageIndices.indices.contains(pageIndex) else { return pageIndex }
        return currentMaterial.selectedPDFPageIndices[pageIndex]
    }

    private var paperSize: CGSize {
        let textPaper = ShenlunWorkspacePaperLayout.paperSize
        guard !isRequirementsPage, let currentMaterial, currentMaterial.kind != .text else { return textPaper }
        let aspect = pageAspect.isFinite && pageAspect > 0 ? pageAspect : textPaper.width / textPaper.height
        return CGSize(width: textPaper.width, height: textPaper.width / aspect)
    }

    private var answerProjection: ShenlunAnswerGridProjection {
        ShenlunAnswerGridLayout.project(answerText: answerText, maximumWordCount: currentQuestion?.maximumWordCount)
    }

    var body: some View {
        GeometryReader { proxy in
            let dualPane = proxy.size.width >= 680
            let available = max(0, proxy.size.width - 1)
            let paneWidth = available / 2
            let movesDrawingToolsBelowBar = proxy.size.width < 580
            VStack(spacing: 0) {
                if isDoodling && showsMaterialTools && movesDrawingToolsBelowBar {
                    drawingToolbar
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if dualPane {
                    HStack(spacing: 0) {
                        leftPane.frame(width: paneWidth)
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                        rightPane.frame(width: paneWidth).frame(maxHeight: .infinity)
                    }
                } else {
                    ScrollViewReader { scroll in
                        VStack(spacing: 0) {
                            HStack(spacing: 20) {
                                Button("材料与要求") { scroll.scrollTo("shenlun-reading-pane", anchor: .top) }
                                Button(reviewAnswer == nil ? "答题纸" : "答案与复盘") { scroll.scrollTo("shenlun-answer-pane", anchor: .top) }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            ScrollView {
                                VStack(spacing: 12) {
                                    leftPane
                                        .frame(height: 390)
                                        .id("shenlun-reading-pane")
                                    rightPane
                                        .frame(minHeight: 540)
                                        .id("shenlun-answer-pane")
                                }
                                .padding(.bottom, 16)
                            }
                        }
                        .onChange(of: answerFocusRequest, initial: true) { _, request in
                            if request != nil { scroll.scrollTo("shenlun-answer-pane", anchor: .top) }
                        }
                        .onChange(of: readingFocusRequest) { _, _ in
                            scroll.scrollTo("shenlun-reading-pane", anchor: .top)
                        }
                        .onChange(of: workFocusRequest) { _, _ in
                            scroll.scrollTo("shenlun-answer-pane", anchor: .top)
                        }
                    }
                }
            }
            .background(Color.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    practiceToolbar(showsInlineDrawingTools: !movesDrawingToolsBelowBar)
                }
                .documentToolbarBackground()
            }
            .overlay(alignment: .bottom) {
                if pencilController.showSettings && isDoodling {
                    NativePencilDrawingSettingsPanel(controller: pencilController)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.white)
        .navigationTitle(practice.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $isShowingDoubtEditor) { doubtEditorSheet }
        .sheet(isPresented: $showsBackfill) { backfillSheet }
        .alert("申论工作区", isPresented: Binding(
            get: { errorMessage != nil && !showsBackfill && !isShowingDoubtEditor },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: isShowingLayerMenu) { _, shown in
            if !shown { cancelLayerNameEntry() }
        }
        .onChange(of: selectedMaterialID) { _, _ in
            isShowingLayerMenu = false
            cancelLayerNameEntry()
        }
        .task { loadInitialData() }
        .task(id: drawingLoadKey) { loadPageAssetsAndDrawings() }
        .task(id: drawingData) {
            guard isDoodling, !drawingData.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            _ = persistDrawingNow()
        }
        .task(id: answerDraftTaskKey) {
            guard didLoad, questionID != nil, reviewAttemptID == nil else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled else { return }
            persistAnswerDraft()
        }
        .task(id: reviewDraft) {
            guard didLoad, reviewAttemptID != nil else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled else { return }
            persistReviewDraft()
        }
        .onDisappear { persistWorkInProgress() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistWorkInProgress() }
        }
        .onChange(of: currentMaterial?.versionID) { _, _ in refreshTextPaperLayout() }
    }

    private var showsMaterialTools: Bool { !isRequirementsPage && currentMaterial != nil }

    private func practiceToolbar(showsInlineDrawingTools: Bool) -> some View {
        HStack(spacing: 8) {
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
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("更多操作")

            if showsMaterialTools {
                Button { isShowingLayerMenu.toggle() } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("批注图层")
                .popover(isPresented: $isShowingLayerMenu, arrowEdge: .top) { layerPopover }

                if !isDoodling {
                    Button(action: openDoodling) {
                        Label("涂鸦", systemImage: "pencil.tip.crop.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 44)
                    }
                    .buttonStyle(NativeToolbarPressStyle(highlightDiameter: 30))
                    .disabled(activeLayer?.isVisible != true || currentMaterial?.showAllLayers != true)
                    .accessibilityIdentifier("shenlun-doodle-open")
                } else if showsInlineDrawingTools {
                    drawingToolbar
                }
            }
        }
    }

    private var drawingToolbar: some View {
        NativePencilDrawingToolbar(
            controller: pencilController,
            toolsEnabled: pencilController.canvasReady && activeLayer?.isVisible == true && currentMaterial?.showAllLayers == true,
            isClosing: isClosingDoodle,
            closeIdentifier: "shenlun-doodle-close",
            onClose: closeDoodling
        ) {
            EmptyView()
        }
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
            materialZoomViewport
            .background(Color(red: 0.95, green: 0.96, blue: 0.97))
            leftPaperControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.95, green: 0.96, blue: 0.97))
    }

    private var materialZoomViewport: some View {
        ShenlunMaterialZoomReader(
            paper: paperViewport,
            paperSize: paperSize,
            pageID: drawingPageID,
            isDrawing: isDoodling,
            initialFraction: zoomFraction,
            request: zoomRequest,
            onInteraction: showReaderZoom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAction(named: Text("纸面缩放")) {
            showsZoomControl = true
            showsZoomMenu = true
        }
        .overlay(alignment: .topLeading) {
            if showsZoomControl || showsZoomMenu {
                readerZoomButton.padding(8)
            }
        }
        .task(id: zoomActivity) {
            guard showsZoomControl, !showsZoomMenu,
                  !ProcessInfo.processInfo.arguments.contains("--shenlun-reader-zoom-ui-test") else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if !showsZoomMenu { showsZoomControl = false }
        }
        .onChange(of: showsZoomMenu) { _, isOpen in
            if !isOpen { zoomActivity += 1 }
        }
    }

    private var readerZoomButton: some View {
        Button {
            showsZoomMenu = true
        } label: {
            Text("\(Int((zoomFraction * 100).rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("纸面缩放")
        .accessibilityValue("\(Int((zoomFraction * 100).rounded()))%")
        .accessibilityIdentifier("shenlun-reader-zoom")
        .popover(isPresented: $showsZoomMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Button("适应宽度") { selectReaderZoom(100) }
                    .frame(minHeight: 44, alignment: .leading)
                Divider()
                ForEach([50, 75, 100, 125, 150, 200, 250, 300], id: \.self) { percentage in
                    Button("\(percentage)%") { selectReaderZoom(percentage) }
                        .frame(minHeight: 36, alignment: .leading)
                }
            }
            .font(.system(size: 14))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func showReaderZoom(_ fraction: CGFloat) {
        guard fraction.isFinite else { return }
        zoomRequest = nil
        zoomFraction = min(3, max(0.5, fraction))
        showsZoomControl = true
        zoomActivity += 1
    }

    private func selectReaderZoom(_ percentage: Int) {
        let fraction = CGFloat(percentage) / 100
        showReaderZoom(fraction)
        zoomRequest = ShenlunReaderZoomRequest(fraction: fraction)
        showsZoomMenu = false
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shenlun-material-paper")
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
        let paperSize = ShenlunWorkspacePaperLayout.paperSize
        let textSize = ShenlunWorkspacePaperLayout.textSize
        let origin = ShenlunWorkspacePaperLayout.textOrigin
        return ZStack(alignment: .topLeading) {
            Color.white
            ShenlunWorkspaceTextPaperPage(text: attributedText)
                .frame(width: textSize.width, height: textSize.height)
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
        }
        .frame(width: paperSize.width, height: paperSize.height)
        .overlay { Rectangle().stroke(Color.primary.opacity(0.07), lineWidth: 0.6) }
    }

    private var leftPaperControls: some View {
        VStack(spacing: 6) {
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
                if showsHistoryFromAnswer {
                    ScrollView {
                        historySection
                            .padding(12)
                    }
                } else if let reviewAnswer {
                    completedReview(for: currentQuestion, answer: reviewAnswer)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(showsHistoryFromAnswer ? "作答历史" : "第 \(currentAttemptNumber) 次作答")
                    .font(.system(size: 15, weight: .semibold))
                Text("已完成 \(completedCount) 次")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
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
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        answerPaperSection(for: question)
                            .id("shenlun-answer-paper-start")
                        doubtsSection
                    }
                    .padding(12)
                }
                .onChange(of: answerFocusRequest, initial: true) { _, request in
                    if request != nil { scroll.scrollTo("shenlun-answer-paper-start", anchor: .top) }
                }
                .onChange(of: question.id) { _, _ in
                    scroll.scrollTo("shenlun-answer-paper-start", anchor: .top)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    answerNavigation
                    Spacer(minLength: 8)
                    completeAnswerButton
                }
                VStack(alignment: .trailing, spacing: 0) {
                    answerNavigation
                    completeAnswerButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }

    private var answerNavigation: some View {
        HStack(spacing: 12) {
            if canReturnToReview {
                Button("返回上次复盘", action: returnToPreviousReview)
            }
            Button("作答历史") {
                finishKeyboardInput()
                guard persistAnswerDraft() else { return }
                answerFocusRequest = nil
                showsHistoryFromAnswer = true
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .frame(minHeight: 44)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var completeAnswerButton: some View {
        Button("完成作答", action: completeAnswer)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(AppTheme.accent, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("shenlun-complete-answer")
    }

    private func answerPaperSection(for question: ShenlunWorkspaceQuestion) -> some View {
        let projection = answerProjection
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("答题纸").font(.system(size: 13, weight: .medium))
                Button(answerFocusRequest == nil ? "键入" : "收起") {
                    if answerFocusRequest == nil {
                        beginAnswerEditing()
                    } else {
                        answerFocusRequest = nil
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
                Spacer(minLength: 4)
                if projection.isGridEnabled {
                    gridCount(projection)
                } else {
                    Text("未设字数上限 · \(answerText.count) 字")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let answerFocusRequest {
                ShenlunCommittedTextEditor(
                    text: $answerText,
                    accessibilityIdentifier: "shenlun-answer-text",
                    focusRequest: answerFocusRequest
                )
                .frame(minHeight: question.maximumWordCount == nil ? 220 : 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if projection.isGridEnabled {
                answerGridPaper(projection, minimumWordCount: question.minimumWordCount, onEdit: beginAnswerEditing)
                gridOverflow(projection)
            } else if answerFocusRequest == nil {
                Button(action: beginAnswerEditing) {
                    Text(answerText.isEmpty ? "点此键入答案" : answerText)
                        .font(.system(size: 15))
                        .foregroundStyle(answerText.isEmpty ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func beginAnswerEditing() {
        answerFocusRequest = UUID()
    }

    private func gridCount(_ projection: ShenlunAnswerGridProjection) -> some View {
        Text("\(projection.occupiedCount)/\(projection.visibleCellCount) 格")
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(projection.overflowCount > 0 ? AppTheme.danger : .secondary)
    }

    @ViewBuilder
    private func gridOverflow(_ projection: ShenlunAnswerGridProjection) -> some View {
        if projection.overflowCount > 0 {
            Text("超出答题纸 \(projection.overflowCount) 格，原文完整保留。")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.danger)
        }
    }

    private func answerGridPaper(
        _ projection: ShenlunAnswerGridProjection,
        minimumWordCount: Int?,
        onEdit: (() -> Void)? = nil
    ) -> some View {
        let sheetCount = projection.sheetCount
        let sheet = min(answerPaperIndex, max(0, sheetCount - 1))
        let gridCells = projection.gridCellCount(on: sheet)
        return VStack(spacing: 8) {
            if let maximum = projection.maximumCount {
                Text(projection.isReview ? "题目上限 \(maximum) 字" : "题目上限 \(maximum) 字 · 备用 \(projection.visibleCellCount - maximum) 格")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if sheetCount > 1 {
                HStack {
                    Text("\(sheet + 1)/\(sheetCount) 张").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { answerPaperIndex = max(0, answerPaperIndex - 1) } label: { Image(systemName: "chevron.left") }.disabled(sheet <= 0)
                    Button { answerPaperIndex = min(sheetCount - 1, answerPaperIndex + 1) } label: { Image(systemName: "chevron.right") }.disabled(sheet + 1 >= sheetCount)
                }
                .buttonStyle(.plain)
            }
            let grid = GeometryReader { geometry in
                let cell = max(5, geometry.size.width / 25)
                let rows = projection.rowCount(on: sheet)
                Canvas { context, _ in
                    let spacing = cell * 0.42
                    let cellsOnLastRow = gridCells % 25 == 0 ? 25 : gridCells % 25
                    for row in 0..<rows {
                        let rowCount = row == rows - 1 ? cellsOnLastRow : 25
                        for column in 0..<rowCount {
                            let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * (cell + spacing), width: cell - 1, height: cell - 1)
                            context.stroke(Path(rect), with: .color(Color(red: 0.71, green: 0.50, blue: 0.51).opacity(0.68)), lineWidth: column == 24 ? 1.1 : 0.65)
                        }
                    }
                    for item in projection.visibleCells(on: sheet) {
                        guard !item.character.allSatisfy(\.isWhitespace) else { continue }
                        let x = CGFloat(item.column) * cell
                        let y = CGFloat(item.row) * (cell + spacing)
                        let value = item.sharesCellWithFullStop ? item.character + "。" : item.character
                        let text = Text(value).font(.system(size: cell * 0.72, weight: .regular, design: .serif)).foregroundColor(.primary)
                        let center = CGPoint(x: x + (cell - 1) / 2, y: y + (cell - 1) / 2)
                        if value.count == 1 {
                            context.draw(text, at: center)
                        } else {
                            let resolved = context.resolve(text)
                            let width = resolved.measure(in: CGSize(
                                width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude
                            )).width
                            var fitted = context
                            fitted.translateBy(x: center.x, y: center.y)
                            fitted.scaleBy(x: min(1, (cell - 2) / max(width, 1)), y: 1)
                            fitted.draw(resolved, at: .zero)
                        }
                    }
                    for mark in projection.markers(on: sheet, minimumWordCount: minimumWordCount) {
                        let row = ((mark - 1) % 600) / 25
                        let column = (mark - 1) % 25
                        let label = Text(String(mark)).font(.system(size: max(6, cell * 0.28), weight: .medium).monospacedDigit()).foregroundColor(Color(red: 0.58, green: 0.26, blue: 0.29))
                        context.draw(label, at: CGPoint(x: CGFloat(column + 1) * cell - 2, y: CGFloat(row) * (cell + spacing) + cell), anchor: .topTrailing)
                    }
                }
                .frame(height: CGFloat(rows) * (cell * 1.42) + 14)
            }
            .aspectRatio(25 / (CGFloat(max(1, projection.rowCount(on: sheet))) * 1.42 + 1.25), contentMode: .fit)
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 0.7) }
            .contentShape(Rectangle())
            if let onEdit {
                grid.onTapGesture(perform: onEdit)
                    .accessibilityLabel("红格答题纸")
                    .accessibilityIdentifier("shenlun-answer-grid")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onEdit() }
            } else {
                grid.accessibilityLabel("作答格子纸")
            }
        }
    }

    private var doubtsSection: some View {
        let doubts = currentHistory?.draft?.doubts ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("疑惑", systemImage: "questionmark.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button(action: openDoubtEditor) {
                    Label("记疑惑", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
            }
            if doubts.isEmpty {
                Text("还没有记录疑惑")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            ForEach(doubts) { doubt in
                VStack(alignment: .leading, spacing: 5) {
                    Text(doubt.body)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let anchor = doubtAnchor(doubt) {
                        Button(anchor) { goToDoubtAnchor(doubt) }
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("shenlun-active-doubts")
    }

    private func doubtAnchor(_ doubt: ShenlunWorkspaceDoubt) -> String? {
        guard let page = doubt.pageIndex else { return nil }
        let title = doubt.materialTitle ?? doubt.materialID.map { id in
            materials.first { $0.id == id }?.title ?? "材料"
        } ?? "作答要求"
        return "\(title) · 第 \(page + 1) 页"
    }

    private func completedReview(for question: ShenlunWorkspaceQuestion, answer: ShenlunWorkspaceAnswer) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let date = answer.completedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(hasAnswerDraft ? "继续第 \(currentHistory?.nextNumber ?? 1) 次作答" : "再做一次", action: resumeAnswer)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("shenlun-retry-answer")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.white)

            HStack(spacing: 5) {
                ForEach(ShenlunReviewSection.allCases) { section in
                    Button(section.title) {
                        if section != .answer && isEditingReferenceAnswer {
                            guard saveReferenceAnswer() else { return }
                        }
                        selectedReviewSection = section
                    }
                    .font(.system(size: 13, weight: selectedReviewSection == section ? .semibold : .regular))
                    .foregroundStyle(selectedReviewSection == section ? AppTheme.accent : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selectedReviewSection == section ? AppTheme.accent : .clear).frame(height: 2)
                    }
                    .accessibilityAddTraits(selectedReviewSection == section ? .isSelected : [])
                    .accessibilityIdentifier("shenlun-review-section-\(section.rawValue)")
                }
            }
            .padding(.horizontal, 9)
            .background(Color.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedReviewSection {
                    case .review:
                        localReviewSection(answer: answer)
                    case .answer:
                        comparisonSection(for: question, answer: answer)
                    case .history:
                        historySection
                    }
                }
                .padding(12)
            }
            .id("\(answer.id)|\(selectedReviewSection.rawValue)")
        }
    }

    private func comparisonSection(for question: ShenlunWorkspaceQuestion, answer: ShenlunWorkspaceAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            scoreSection(for: question, answer: answer)
            reviewCard("我的作答") {
                if answer.answerText.isEmpty {
                    Text("这次补录没有作答原文。").font(.system(size: 15)).foregroundStyle(.secondary)
                } else {
                    Picker("作答显示方式", selection: $showsCompletedAnswerGrid) {
                        Text("格子纸").tag(true)
                        Text("普通").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if showsCompletedAnswerGrid {
                        let projection = ShenlunAnswerGridLayout.project(
                            answerText: answer.answerText,
                            maximumWordCount: question.maximumWordCount,
                            isReview: true
                        )
                        gridCount(projection)
                        answerGridPaper(projection, minimumWordCount: question.minimumWordCount)
                        gridOverflow(projection)
                    } else {
                        Text(answer.answerText).font(.system(size: 15)).textSelection(.enabled)
                    }
                }
            }
            reviewCard("参考答案") {
                if isEditingReferenceAnswer {
                    ShenlunCommittedTextEditor(text: $referenceAnswerDraft, accessibilityIdentifier: "shenlun-reference-answer")
                        .frame(minHeight: 160)
                    HStack {
                        Button("取消") {
                            referenceAnswerDraft = question.referenceAnswer
                            isEditingReferenceAnswer = false
                        }
                        Spacer()
                        Button("保存参考答案") { _ = saveReferenceAnswer() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                } else {
                    Text(question.referenceAnswer.isEmpty ? "尚未录入参考答案。" : question.referenceAnswer)
                        .font(.system(size: 15))
                        .foregroundStyle(question.referenceAnswer.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                    Button("修改参考答案") {
                        referenceAnswerDraft = question.referenceAnswer
                        isEditingReferenceAnswer = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                }
                if let original = answer.referenceAnswerAtCompletion,
                   !original.isEmpty, original != question.referenceAnswer {
                    DisclosureGroup("作答时的参考答案") {
                        Text(original).font(.system(size: 14)).textSelection(.enabled)
                    }
                    .font(.system(size: 13))
                }
            }
        }
    }

    private func localReviewSection(answer: ShenlunWorkspaceAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewCard("疑惑") {
                Button(action: openDoubtEditor) {
                    Label("记疑惑", systemImage: "plus").frame(minHeight: 44)
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.accent)
                if reviewDraft.doubts.isEmpty {
                    Text("还没有记录疑惑").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                if answer.reviewState == .pendingVerification {
                    Text("此题曾标记为待核验").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach($reviewDraft.doubts) { $doubt in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(doubt.body).font(.system(size: 14))
                        if let anchor = doubtAnchor(doubt) {
                            Button(anchor) { goToDoubtAnchor(doubt) }
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.accent)
                                .frame(minHeight: 30)
                        }
                        TextField("记录这条疑惑的结论", text: Binding(
                            get: { doubt.conclusion ?? "" },
                            set: { doubt.conclusion = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .lineLimit(1...5)
                        Toggle("已核验", isOn: Binding(
                            get: { doubt.isVerified == true },
                            set: { doubt.isVerified = $0 }
                        ))
                        .font(.system(size: 12))
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            reviewCard("复盘心得") {
                TextField("这次漏了什么？下次准备怎么改？", text: $reviewDraft.note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .lineLimit(3...10)
                    .accessibilityLabel("复盘心得")
                .accessibilityIdentifier("shenlun-review-note")
            }
            HStack {
                if reviewSaved, answer.doubts == reviewDraft.doubts, (answer.reviewNote ?? "") == reviewDraft.note {
                    Label("已保存", systemImage: "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.success)
                }
                Spacer()
                Button("保存本次复盘") { saveReview() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(AppTheme.accent, in: Capsule())
            }
        }
    }

    private func scoreSection(for question: ShenlunWorkspaceQuestion, answer: ShenlunWorkspaceAnswer) -> some View {
        reviewCard("本次得分") {
            if answer.reviewState == .needsReview {
                Label("题目或参考内容已修改，原评分需复核。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.warning)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    scoreField(for: question, answer: answer)
                    scoreSourcePicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    scoreField(for: question, answer: answer)
                    scoreSourcePicker
                }
            }
            HStack {
                if scoreSaved,
                   answer.savedReview.scoreText == reviewDraft.scoreText,
                   answer.savedReview.scoreSource == reviewDraft.scoreSource {
                    Label("已保存", systemImage: "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.success)
                }
                Spacer()
                Button(answer.reviewState == .needsReview ? "确认本次评分" : "保存成绩") { saveScore() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
            }
            if let analysis = answer.confirmedAnalysis, !analysis.isEmpty {
                Text(analysis).font(.system(size: 13)).textSelection(.enabled)
            }
        }
    }

    private func scoreField(for question: ShenlunWorkspaceQuestion, answer: ShenlunWorkspaceAnswer) -> some View {
        HStack(spacing: 6) {
            TextField("未评分", text: $reviewDraft.scoreText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 90)
                .accessibilityLabel("本次得分")
                .accessibilityIdentifier("shenlun-review-score")
            if let maximum = answer.fullScore(for: question) {
                Text("/ \(maximum.formatted(.number.precision(.fractionLength(0...2)))) 分")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                Text("分").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14))
    }

    private var scoreSourcePicker: some View {
        Picker("评分来源", selection: $reviewDraft.scoreSource) {
            if reviewDraft.scoreSource == nil {
                Text("未注明来源").tag(nil as ShenlunWorkspaceScoreSource?)
            }
            ForEach(ShenlunWorkspaceScoreSource.allCases, id: \.self) { source in
                Text(source.rawValue).tag(Optional(source))
            }
        }
        .pickerStyle(.menu)
        .font(.system(size: 13))
        .fixedSize()
    }

    private var historySection: some View {
        reviewCard("作答历史") {
            HStack {
                if showsHistoryFromAnswer {
                    Button("返回答题纸") { showsHistoryFromAnswer = false }
                }
                Spacer()
                Button {
                    guard persistWorkInProgress() else { return }
                    backfillDate = .now
                    backfillAnswer = ""
                    showsBackfill = true
                } label: {
                    Label("补录一次", systemImage: "plus")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(minHeight: 44)

            let records = currentHistory?.completed ?? []
            if records.isEmpty {
                Text("还没有完成的作答").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(records) { answer in
                Button { openReview(answer.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第 \(answer.attemptNumber ?? 1) 次作答")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            if let date = answer.completedAt {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if let currentQuestion {
                            Text(scoreDescription(answer, question: currentQuestion))
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.accent)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scoreDescription(_ answer: ShenlunWorkspaceAnswer, question: ShenlunWorkspaceQuestion) -> String {
        guard let score = answer.confirmedScore else { return "未评分" }
        let number = score.formatted(.number.precision(.fractionLength(0...2)))
        if let fullScore = answer.fullScore(for: question) {
            return "\(number) / \(fullScore.formatted(.number.precision(.fractionLength(0...2)))) 分"
        }
        return "\(number) 分"
    }

    private func reviewCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var backfillSheet: some View {
        NavigationStack {
            Form {
                DatePicker("作答日期", selection: $backfillDate, in: ...Date.now, displayedComponents: .date)
                Section("作答原文（可选）") {
                    ShenlunCommittedTextEditor(text: $backfillAnswer, accessibilityIdentifier: "shenlun-backfill-answer")
                        .frame(minHeight: 140)
                }
                sheetError
            }
            .navigationTitle("补录作答记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        errorMessage = nil
                        showsBackfill = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存记录", action: saveBackfill) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var sheetError: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.danger)
        }
    }

    private var doubtEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("记录当前题目中的一个具体疑惑。可在复盘时继续补充或逐条核对。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                ShenlunCommittedTextEditor(text: $doubtText, accessibilityIdentifier: "shenlun-doubt-text")
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
                sheetError
            }
            .padding(16)
            .navigationTitle("记疑惑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        errorMessage = nil
                        isShowingDoubtEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { saveDoubt() }.disabled(doubtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var layerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("批注图层").font(.system(size: 14, weight: .semibold))
                    Text(activeLayer.map { "当前图层 · \($0.name)" } ?? "暂无活动图层")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("关闭") { isShowingLayerMenu = false }
                    .frame(minHeight: 44)
                    .disabled(isSavingLayerName)
            }
            if let currentMaterial {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(currentMaterial.layers) { layer in
                            layerMenuRow(layer, isActive: layer.id == currentMaterial.activeLayerID)
                        }
                    }
                }
                .frame(height: CGFloat(max(1, min(currentMaterial.layers.count, 4))) * 44)
                .disabled(isSavingLayerName)
                if let target = layerNameTarget { layerNameForm(target) }
                Divider()
                HStack(spacing: 8) {
                    Button {
                        beginLayerNameEntry(.new)
                    } label: {
                        Label("新建图层", systemImage: "plus")
                            .frame(minHeight: 44)
                    }
                    Spacer(minLength: 0)
                    Button {
                        var updated = currentMaterial
                        updated.showAllLayers.toggle()
                        commitDrawingBeforeTransition {
                            guard self.saveMaterial(updated) else { return }
                            if !updated.showAllLayers {
                                self.isDoodling = false
                                self.pencilController.showSettings = false
                            }
                        }
                    } label: {
                        Label(currentMaterial.showAllLayers ? "隐藏笔迹" : "显示笔迹",
                              systemImage: currentMaterial.showAllLayers ? "eye.slash" : "eye")
                            .frame(minHeight: 44)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .disabled(isSavingLayerName)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color.white)
    }

    private func layerMenuRow(_ layer: ShenlunWorkspaceLayer, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: drawingPreviews[layer.id] ?? UIImage())
                .resizable().scaledToFit().frame(width: 34, height: 31)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            Button { activateLayer(layer.id) } label: {
                Text(layer.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? AppTheme.accent : .primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityAddTraits(isActive ? .isSelected : [])
            Button { toggleLayer(layer.id) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .frame(width: 38, height: 44)
            }
            .accessibilityLabel("\(layer.isVisible ? "隐藏" : "显示")图层 \(layer.name)")
            Menu {
                Button("重命名") { beginLayerNameEntry(.existing(layer.id), name: layer.name) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 34, height: 44)
            }
            .accessibilityLabel("管理图层 \(layer.name)")
        }
    }

    private func layerNameForm(_ target: ShenlunLayerNameTarget) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(target.title).font(.system(size: 13, weight: .medium))
            TextField("图层名称", text: $layerName)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { submitLayerName() }
                .accessibilityIdentifier("shenlun-layer-name")
            if let layerNameError {
                Text(layerNameError)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.warning)
            }
            HStack {
                Spacer()
                Button("取消") { cancelLayerNameEntry() }
                    .frame(minHeight: 44)
                Button("保存") { submitLayerName() }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
            }
            .font(.system(size: 13))
        }
        .disabled(isSavingLayerName)
    }

    private var visibleDrawingLayerIDs: [String] {
        guard let currentMaterial, currentMaterial.showAllLayers else { return [] }
        return currentMaterial.layers.filter(\.isVisible).map(\.id)
    }

    private func loadInitialData() {
        guard !didLoad else { return }
        do {
            questions = try ShenlunWorkspaceRepository.questions(practiceID: practice.id, in: modelContext)
            materials = try ShenlunWorkspaceRepository.materials(practiceID: practice.id, in: modelContext)
            histories = try ShenlunWorkspaceRepository.attemptHistories(practiceID: practice.id, in: modelContext)
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
                loadQuestionWork(questionID)
            }
            refreshTextPaperLayout(for: materials.first(where: { $0.id == selectedMaterialID }))
            didLoad = true
            if questionID != nil { workFocusRequest = UUID() }
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
        finishKeyboardInput()
        guard persistWorkInProgress() else { return }
        if isEditingReferenceAnswer, !saveReferenceAnswer() { return }
        let location = readingLocation(for: id)
        let previousQuestionID = questionID
        commitDrawingBeforeTransition {
            self.rememberReadingLocation(for: previousQuestionID)
            self.questionID = id
            self.loadQuestionWork(id)
            self.selectedMaterialID = location.materialID
            self.pageIndex = location.pageIndex
            self.refreshTextPaperLayout(for: self.materials.first(where: { $0.id == location.materialID }))
            self.rememberReadingLocation(for: id)
        }
    }

    private func loadQuestionWork(_ id: String) {
        referenceAnswerDraft = questions.first { $0.id == id }?.referenceAnswer ?? ""
        isEditingReferenceAnswer = false
        answerText = histories[id]?.draft?.answerText ?? ""
        answerFocusRequest = nil
        answerPaperIndex = 0
        previousReviewAttemptID = histories[id]?.completed.first?.id
        showsHistoryFromAnswer = false
        if histories[id]?.draft == nil, let latest = histories[id]?.completed.first {
            displayReview(latest)
        } else {
            reviewAttemptID = nil
            reviewDraft = .init()
            reviewSaved = false
            scoreSaved = false
            selectedReviewSection = .answer
        }
    }

    private func displayReview(_ answer: ShenlunWorkspaceAnswer) {
        answerFocusRequest = nil
        answerPaperIndex = 0
        reviewAttemptID = answer.id
        reviewDraft = answer.reviewDraft ?? answer.savedReview
        reviewSaved = false
        scoreSaved = false
        showsHistoryFromAnswer = false
        selectedReviewSection = .answer
    }

    private func openReview(_ id: String) {
        finishKeyboardInput()
        guard persistWorkInProgress(), let answer = currentHistory?.completed.first(where: { $0.id == id }) else { return }
        displayReview(answer)
        workFocusRequest = UUID()
    }

    private func returnToPreviousReview() {
        guard let id = previousReviewAttemptID ?? currentHistory?.completed.first?.id else { return }
        openReview(id)
    }

    private func resumeAnswer() {
        finishKeyboardInput()
        if isEditingReferenceAnswer, !saveReferenceAnswer() { return }
        guard persistReviewDraft() else { return }
        previousReviewAttemptID = reviewAttemptID
        reviewAttemptID = nil
        reviewDraft = .init()
        reviewSaved = false
        scoreSaved = false
        answerText = currentHistory?.draft?.answerText ?? ""
        answerFocusRequest = nil
        answerPaperIndex = 0
        showsHistoryFromAnswer = false
        workFocusRequest = UUID()
    }

    private func newAttempt(for questionID: String) -> ShenlunWorkspaceAnswer {
        var answer = ShenlunWorkspaceAnswer(practiceID: practice.id, questionID: questionID)
        answer.attemptID = UUID().uuidString
        return answer
    }

    private func completeAnswer() {
        guard reviewAttemptID == nil, !showsHistoryFromAnswer, let question = currentQuestion else { return }
        finishKeyboardInput()
        guard !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            beginAnswerEditing()
            return
        }
        guard persistAnswerDraft(), let existing = currentHistory?.draft else { return }
        var attempt = existing
        attempt.complete(on: .now, for: question)
        guard writeAttempt(attempt, replacing: existing, failure: "作答保存失败"),
              let saved = currentHistory?.completed.first(where: { $0.id == attempt.id }) else { return }
        answerText = ""
        displayReview(saved)
        workFocusRequest = UUID()
        onPracticeChanged()
    }

    private func saveBackfill() {
        guard showsBackfill, let question = currentQuestion else { return }
        finishKeyboardInput()
        var attempt = newAttempt(for: question.id)
        attempt.answerText = backfillAnswer
        attempt.complete(on: backfillDate, for: question)
        guard writeAttempt(attempt, replacing: nil, failure: "补录保存失败"),
              let saved = currentHistory?.completed.first(where: { $0.id == attempt.id }) else { return }
        showsBackfill = false
        errorMessage = nil
        displayReview(saved)
        workFocusRequest = UUID()
        onPracticeChanged()
    }

    private func finishKeyboardInput() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @discardableResult
    private func persistWorkInProgress() -> Bool {
        guard didLoad else { return true }
        return reviewAttemptID == nil ? persistAnswerDraft() : persistReviewDraft()
    }

    @discardableResult
    private func persistAnswerDraft() -> Bool {
        guard didLoad, reviewAttemptID == nil, let questionID else { return true }
        let existing = currentHistory?.draft
        guard answerText != (existing?.answerText ?? "") else { return true }
        var updated = existing ?? newAttempt(for: questionID)
        updated.answerText = answerText
        return writeAttempt(updated, replacing: existing, failure: "作答草稿保存失败")
    }

    @discardableResult
    private func persistReviewDraft() -> Bool {
        guard let answer = reviewAnswer else { return true }
        return persistReviewDraft(reviewDraft, for: answer)
    }

    private func persistReviewDraft(_ draft: ShenlunWorkspaceReviewDraft, for answer: ShenlunWorkspaceAnswer) -> Bool {
        let changes = draft == answer.savedReview ? nil : draft
        guard changes != answer.reviewDraft else { return true }
        var updated = answer
        updated.reviewDraft = changes
        return writeAttempt(updated, replacing: answer, failure: "复盘草稿保存失败")
    }

    private func saveScore() {
        guard let answer = reviewAnswer, let question = currentQuestion else { return }
        finishKeyboardInput()
        let score: Double?
        do {
            score = try reviewDraft.validatedScore(maximum: answer.fullScore(for: question))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        var updated = answer
        if updated.questionRevisionAtCompletion == nil {
            updated.questionRevisionAtCompletion = question.revision
            updated.fullScoreAtCompletion = question.fullScore
            updated.referenceAnswerAtCompletion = question.referenceAnswer
        }
        updated.confirmedScore = score
        updated.scoreSource = score == nil ? nil : reviewDraft.scoreSource
        if score != nil {
            updated.reviewState = .confirmed
        } else if score == nil && (answer.reviewState == .confirmed || answer.reviewState == .needsReview) {
            updated.reviewState = .notReviewed
        }
        var draft = reviewDraft
        draft.scoreText = updated.savedReview.scoreText
        draft.scoreSource = updated.savedReview.scoreSource
        updated.reviewDraft = draft == updated.savedReview ? nil : draft
        guard writeAttempt(updated, replacing: answer, failure: "成绩保存失败") else { return }
        reviewDraft = draft
        scoreSaved = true
        onPracticeChanged()
    }

    private func saveReview() {
        guard let answer = reviewAnswer else { return }
        finishKeyboardInput()
        var updated = answer
        updated.reviewNote = reviewDraft.note
        updated.doubts = reviewDraft.doubts
        updated.reviewDraft = reviewDraft == updated.savedReview ? nil : reviewDraft
        guard writeAttempt(updated, replacing: answer, failure: "复盘保存失败") else { return }
        reviewSaved = true
        onPracticeChanged()
    }

    private func writeAttempt(_ value: ShenlunWorkspaceAnswer, replacing existing: ShenlunWorkspaceAnswer?, failure: String) -> Bool {
        do {
            histories[value.questionID] = try ShenlunWorkspaceRepository.saveAttempt(
                value, replacingRevision: existing?.revision, in: modelContext
            )
            return true
        } catch {
            errorMessage = "\(failure)：\(error.localizedDescription)"
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
        guard persistReviewDraft() else { return false }
        updatedQuestion.referenceAnswer = referenceAnswerDraft
        updatedQuestion.revision += 1
        var updatedPractice = practice
        updatedPractice.updatedAt = .now
        do {
            try ShenlunWorkspaceRepository.savePracticeAndQuestion(
                updatedPractice,
                updatedQuestion,
                createdAt: practice.createdAt,
                markScoresForReview: true,
                in: modelContext
            )
            questions[index] = updatedQuestion
            isEditingReferenceAnswer = false
            histories = try ShenlunWorkspaceRepository.attemptHistories(practiceID: practice.id, in: modelContext)
            reviewSaved = false
            scoreSaved = false
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
        let text = doubtText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var doubt = ShenlunWorkspaceDoubt(
            questionID: questionID,
            body: text,
            materialID: selectedMaterialID,
            pageIndex: currentMaterial?.kind == .pdf ? sourcePageIndex : pageIndex
        )
        doubt.materialTitle = currentMaterial?.title
        doubt.materialVersionID = currentMaterial?.versionID
        if let answer = reviewAnswer {
            var draft = reviewDraft
            draft.doubts.append(doubt)
            guard persistReviewDraft(draft, for: answer) else { return }
            reviewDraft = draft
        } else {
            let existing = currentHistory?.draft
            var updated = existing ?? newAttempt(for: questionID)
            updated.answerText = answerText
            updated.doubts.append(doubt)
            guard writeAttempt(updated, replacing: existing, failure: "疑惑保存失败") else { return }
        }
        doubtText = ""
        isShowingDoubtEditor = false
        errorMessage = nil
    }

    private func goToDoubtAnchor(_ doubt: ShenlunWorkspaceDoubt) {
        guard let page = doubt.pageIndex else { return }
        let material = materials.first { $0.id == doubt.materialID }
        if doubt.materialID != nil && material == nil {
            errorMessage = "这条疑惑引用的材料已移除。"
            return
        }
        let versionChanged = doubt.materialVersionID != nil && doubt.materialVersionID != material?.versionID
        let targetPage: Int
        if versionChanged {
            targetPage = 0
        } else if let material, material.kind == .pdf, !material.selectedPDFPageIndices.isEmpty {
            guard let index = material.selectedPDFPageIndices.firstIndex(of: page) else {
                errorMessage = "这条疑惑引用的页已不在当前材料中。"
                return
            }
            targetPage = index
        } else {
            targetPage = page
        }
        commitDrawingBeforeTransition {
            self.selectedMaterialID = material?.id
            self.refreshTextPaperLayout(for: material)
            self.pageIndex = min(max(0, targetPage), self.leftPageCount - 1)
            self.rememberReadingLocation(for: self.questionID)
            self.readingFocusRequest = UUID()
            if versionChanged {
                self.errorMessage = "原材料版本已更新，已打开当前材料的第一页。"
            }
        }
    }

    private func openDoodling() {
        guard !isDoodling, !isClosingDoodle,
              activeLayer?.isVisible == true, currentMaterial?.showAllLayers == true else { return }
        pencilController.prepareForPresentation(preservingLoadedDrawing: true)
        isDoodling = true
    }

    private func closeDoodling() {
        guard isDoodling, !isClosingDoodle else { return }
        isClosingDoodle = true
        pencilController.commit {
            isClosingDoodle = false
            guard isDoodling, persistDrawingNow() else { return }
            isDoodling = false
            pencilController.showSettings = false
        }
    }

    private func commitDrawingBeforeTransition(onFailure: (() -> Void)? = nil, _ transition: @escaping () -> Void) {
        guard isDoodling else { transition(); return }
        pencilController.commit {
            guard self.persistDrawingNow() else {
                onFailure?()
                return
            }
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
            guard self.saveMaterial(material) else { return }
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
            guard self.saveMaterial(material) else { return }
            if material.activeLayerID == nil {
                self.isDoodling = false
                self.pencilController.showSettings = false
            }
        }
        commitDrawingBeforeTransition(update)
    }

    private func beginLayerNameEntry(_ target: ShenlunLayerNameTarget, name: String = "") {
        layerNameTarget = target
        layerName = name
        layerNameError = nil
    }

    private func cancelLayerNameEntry() {
        layerNameTarget = nil
        layerName = ""
        layerNameError = nil
    }

    private func submitLayerName() {
        guard !isSavingLayerName, let target = layerNameTarget, var material = currentMaterial else { return }
        let name = layerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            layerNameError = "图层名称不能为空。"
            return
        }
        guard !material.layers.contains(where: { $0.name == name && target != .existing($0.id) }) else {
            layerNameError = "此材料中已有同名图层。"
            return
        }
        switch target {
        case .new:
            let newLayer = ShenlunWorkspaceLayer(name: name)
            material.layers.insert(newLayer, at: 0)
            material.activeLayerID = newLayer.id
            material.showAllLayers = true
        case let .existing(id):
            guard let index = material.layers.firstIndex(where: { $0.id == id }) else { return }
            material.layers[index].name = name
        }

        let updated = material
        let finish = {
            defer { self.isSavingLayerName = false }
            guard self.currentMaterial?.id == updated.id else { return }
            if self.saveMaterial(updated) {
                self.cancelLayerNameEntry()
            } else {
                self.layerNameError = self.errorMessage
                self.errorMessage = nil
            }
        }
        isSavingLayerName = true
        if target == .new {
            commitDrawingBeforeTransition(onFailure: {
                self.isSavingLayerName = false
                self.layerNameError = self.errorMessage
                self.errorMessage = nil
            }, finish)
        } else {
            finish()
        }
    }

    @discardableResult
    private func saveMaterial(_ updated: ShenlunWorkspaceMaterial) -> Bool {
        do {
            try ShenlunWorkspaceRepository.save(updated, in: modelContext)
            if let index = materials.firstIndex(where: { $0.id == updated.id }) { materials[index] = updated }
            return true
        } catch {
            errorMessage = "材料或图层保存失败：\(error.localizedDescription)"
            return false
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
    var focusRequest: UUID? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> FocusableTextView {
        let view = FocusableTextView()
        view.delegate = context.coordinator
        view.pasteDelegate = context.coordinator
        view.font = .systemFont(ofSize: 15)
        view.textColor = .label
        view.backgroundColor = .white
        view.accessibilityIdentifier = accessibilityIdentifier
        view.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.text = text
        if focusRequest != nil {
            view.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }
        view.focusRequest = focusRequest
        view.isScrollEnabled = true
        return view
    }

    func updateUIView(_ view: FocusableTextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityIdentifier = accessibilityIdentifier
        if view.text != text, view.markedTextRange == nil {
            view.text = text
        }
        view.focusRequest = focusRequest
    }

    final class FocusableTextView: UITextView {
        var focusRequest: UUID? {
            didSet {
                if focusRequest != oldValue { applyFocusRequest() }
            }
        }
        private var appliedFocusRequest: UUID?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyFocusRequest()
        }

        private func applyFocusRequest() {
            guard window != nil, let request = focusRequest, request != appliedFocusRequest else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.focusRequest == request,
                      self.appliedFocusRequest != request else { return }
                if self.becomeFirstResponder() { self.appliedFocusRequest = request }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: ShenlunCommittedTextEditor
        init(parent: ShenlunCommittedTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text ?? ""
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard textView.markedTextRange == nil, let text = textView.text, text != parent.text else { return }
            parent.text = text
        }

        func textPasteConfigurationSupporting(
            _ supporting: any UITextPasteConfigurationSupporting,
            performPasteOf attributedString: NSAttributedString,
            to textRange: UITextRange
        ) -> UITextRange {
            guard let view = supporting as? UITextView else { return textRange }
            let start = view.offset(from: view.beginningOfDocument, to: textRange.start)
            let length = view.offset(from: textRange.start, to: textRange.end)
            let insertion = ShenlunMaterialTextFormatter.unindentedPaste(
                attributedString.string, in: view.text ?? "", replacing: NSRange(location: start, length: length)
            )
            view.replace(textRange, withText: insertion)
            textViewDidChange(view)
            guard let beginning = view.position(from: view.beginningOfDocument, offset: start),
                  let end = view.position(from: beginning, offset: insertion.utf16.count),
                  let insertedRange = view.textRange(from: beginning, to: end) else { return textRange }
            view.selectedTextRange = view.textRange(from: end, to: end)
            return insertedRange
        }
    }
}
