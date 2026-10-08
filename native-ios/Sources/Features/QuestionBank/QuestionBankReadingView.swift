import SwiftUI
import SwiftData
import UIKit
import ImageIO

struct QuestionBankReadingStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case material(String)
        case question(String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .material(let id): "material:\(id)"
        case .question(let id): "question:\(id)"
        }
    }
}

enum QuestionBankReadingSequence {
    static func steps(for questions: [QuestionBankQuestion]) -> [QuestionBankReadingStep] {
        let orderedQuestions = questions.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.id < $1.id
        }
        var emittedMaterialIDs = Set<String>()
        var result: [QuestionBankReadingStep] = []
        result.reserveCapacity(orderedQuestions.count * 2)

        for question in orderedQuestions {
            if !question.materialID.isEmpty, emittedMaterialIDs.insert(question.materialID).inserted {
                result.append(QuestionBankReadingStep(kind: .material(question.materialID)))
            }
            result.append(QuestionBankReadingStep(kind: .question(question.id)))
        }
        return result
    }
}

struct QuestionBankQuestionRouteTarget: Equatable {
    let moduleID: String
    let questionNumber: Int
}

enum QuestionBankQuestionRoute {
    static func target(
        questionNumber: Int?,
        paperID: String,
        selectedModuleTitle: String,
        records: [QuestionBankRecord]
    ) -> QuestionBankQuestionRouteTarget? {
        guard let questionNumber, questionNumber > 0 else { return nil }
        let candidates = records
            .filter {
                $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind
                    && $0.questionNumber == questionNumber
            }
            .sorted { $0.stableID < $1.stableID }
        for question in candidates {
            guard let moduleID = question.moduleID, !moduleID.isEmpty else { continue }
            if !selectedModuleTitle.isEmpty {
                let moduleMatchesFilter = records.contains {
                    $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind
                        && $0.stableID == moduleID && $0.title == selectedModuleTitle
                }
                guard moduleMatchesFilter else { continue }
            }
            return QuestionBankQuestionRouteTarget(moduleID: moduleID, questionNumber: questionNumber)
        }
        return nil
    }
}

struct QuestionBankOverviewItem: Identifiable, Equatable {
    let id: String
    let number: Int
    let materialID: String
    let type: String
    let stem: String
    let stemImageAssetID: String

    var materialGroupLabel: String? {
        materialID.isEmpty ? nil : "共用材料组"
    }
}

private struct QuestionBankReadingItem: Identifiable {
    let record: QuestionBankRecord
    let question: QuestionBankQuestion

    var id: String { record.stableID }
    var overviewItem: QuestionBankOverviewItem {
        QuestionBankOverviewItem(
            id: id,
            number: question.number,
            materialID: question.materialID,
            type: QuestionBankQuestionHeading.displayLabel(
                type: question.type,
                subject: question.subject
            ) ?? "",
            stem: question.stem,
            stemImageAssetID: question.stemImageAssetID
        )
    }
}

private struct QuestionBankReaderSheet: Identifiable {
    enum Content {
        case overview
        case material(String)
        case questionDetail(String)
    }

    let content: Content

    var id: String {
        switch content {
        case .overview: "question-overview"
        case .material(let id): "material-panel:\(id)"
        case .questionDetail(let id): "question-detail:\(id)"
        }
    }
}

private struct QuestionBankScrollRequest: Equatable {
    let questionID: String
    let token: UUID
}

private struct QuestionBankReaderViewportFrame: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

private struct QuestionBankReaderViewportPreference: PreferenceKey {
    static var defaultValue: [String: QuestionBankReaderViewportFrame] = [:]

    static func reduce(
        value: inout [String: QuestionBankReaderViewportFrame],
        nextValue: () -> [String: QuestionBankReaderViewportFrame]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct QuestionBankModuleView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @Query private var records: [QuestionBankRecord]

    let paperID: String
    let moduleID: String
    let initialQuestionNumber: String

    @State private var readingItems: [QuestionBankReadingItem] = []
    @State private var readingSteps: [QuestionBankReadingStep] = []
    @State private var materialsByID: [String: QuestionBankMaterial] = [:]
    @State private var assetsByID: [String: QuestionBankRecord] = [:]
    @State private var activeSheet: QuestionBankReaderSheet?
    @State private var showsReaderOptions = false
    @State private var continuousAnchorQuestionID: String?
    @State private var pendingOverviewQuestionID: String?
    @State private var continuousScrollRequest: QuestionBankScrollRequest?
    @State private var splitScrollRequest: QuestionBankScrollRequest?
    @State private var singleQuestionTransitionDirection = 1
    @State private var snapshotRevision = 0
    @State private var doodleDrawingCache = QuestionBankDoodleMemoryCache()
    @State private var didApplyInitialFocus = false
    @SceneStorage private var storedSplitMaterialID: String
    @SceneStorage private var storedQuestionID: String
    @SceneStorage private var storedReadingMode: String
    @SceneStorage private var storedPresentationMode: String
    @SceneStorage private var storedSelectedOptionsJSON: String
    @SceneStorage private var storedRevealedAnswersJSON: String
    @AppStorage(QuestionBankReaderPreferences.confirmAnswerAfterSelectionKey)
    private var requiresAnswerConfirmation = false

    init(paperID: String, moduleID: String, initialQuestionNumber: String) {
        self.paperID = paperID
        self.moduleID = moduleID
        self.initialQuestionNumber = initialQuestionNumber
        _storedSplitMaterialID = SceneStorage(
            wrappedValue: "",
            "question-bank.split.\(paperID).\(moduleID)"
        )
        _storedQuestionID = SceneStorage(
            wrappedValue: "",
            "question-bank.question.\(paperID).\(moduleID)"
        )
        _storedReadingMode = SceneStorage(
            wrappedValue: QuestionBankReadingMode.reading.rawValue,
            "question-bank.mode.\(paperID).\(moduleID)"
        )
        _storedPresentationMode = SceneStorage(
            wrappedValue: QuestionBankPresentationMode.continuous.rawValue,
            "question-bank.presentation.\(paperID).\(moduleID)"
        )
        _storedSelectedOptionsJSON = SceneStorage(
            wrappedValue: "{}",
            "question-bank.selected-options.\(paperID).\(moduleID)"
        )
        _storedRevealedAnswersJSON = SceneStorage(
            wrappedValue: "[]",
            "question-bank.revealed-answers.\(paperID).\(moduleID)"
        )
    }

    private var module: QuestionBankModule? {
        records.first {
            $0.paperID == paperID && $0.stableID == moduleID && $0.kind == QuestionBankRepository.moduleKind
        }?.decoded(QuestionBankModule.self)
    }

    private var initialFocusQuestionID: String? {
        guard let number = Int(initialQuestionNumber), number > 0 else { return nil }
        return readingItems.first { $0.question.number == number }?.id
    }

    private var paperData: QuestionBankPaper? {
        records.first { $0.paperID == paperID && $0.kind == QuestionBankRepository.paperKind }?.decoded(QuestionBankPaper.self)
    }

    private var splitMaterialID: String? {
        get { storedSplitMaterialID.isEmpty ? nil : storedSplitMaterialID }
        nonmutating set { storedSplitMaterialID = newValue ?? "" }
    }

    private var currentVisibleQuestionID: String? {
        get { storedQuestionID.isEmpty ? nil : storedQuestionID }
        nonmutating set { storedQuestionID = newValue ?? "" }
    }

    private var readingMode: QuestionBankReadingMode {
        get { QuestionBankReadingMode(rawValue: storedReadingMode) ?? .reading }
        nonmutating set { storedReadingMode = newValue.rawValue }
    }

    private var presentationMode: QuestionBankPresentationMode {
        get { QuestionBankPresentationMode(rawValue: storedPresentationMode) ?? .continuous }
        nonmutating set { storedPresentationMode = newValue.rawValue }
    }

    private var selectedOptionsByQuestionID: [String: String] {
        get { QuestionBankSelectedOptionsStorage.decode(storedSelectedOptionsJSON) }
        nonmutating set { storedSelectedOptionsJSON = QuestionBankSelectedOptionsStorage.encode(newValue) }
    }

    private var revealedAnswerQuestionIDs: Set<String> {
        get { QuestionBankRevealedAnswersStorage.decode(storedRevealedAnswersJSON) }
        nonmutating set { storedRevealedAnswersJSON = QuestionBankRevealedAnswersStorage.encode(newValue) }
    }

    private var readerPosition: QuestionBankReaderPosition {
        QuestionBankReaderPosition(
            presentationMode: presentationMode,
            currentQuestionID: currentVisibleQuestionID,
            splitMaterialID: splitMaterialID
        )
    }

    private var singleQuestionPageTransition: AnyTransition {
        let motion = QuestionBankPageTransition.motion(for: singleQuestionTransitionDirection)
        let insertionEdge: Edge = motion.insertion == .leading ? .leading : .trailing
        let removalEdge: Edge = motion.removal == .leading ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge),
            removal: .move(edge: removalEdge)
        )
    }

    private var currentSingleItem: QuestionBankReadingItem? {
        let questionID = QuestionBankReaderTransition.displayedQuestionIDs(
            for: .single, currentID: currentVisibleQuestionID, orderedIDs: orderedQuestionIDs
        ).first
        return questionID.flatMap { readingItem(for: $0) } ?? readingItems.first
    }

    private var orderedQuestionIDs: [String] { readingItems.map(\.id) }

    private var readerRecordRevision: Int {
        var hasher = Hasher()
        for record in records.filter({ $0.paperID == paperID }).sorted(by: { $0.compoundID < $1.compoundID }) {
            hasher.combine(record.compoundID)
            hasher.combine(record.payload)
            hasher.combine(record.assetRelativePath)
        }
        return hasher.finalize()
    }

    private var doodleToolbarTarget: QuestionBankDoodleToolbarTarget? {
        QuestionBankDoodleToolbarTarget.resolve(
            visibleQuestionID: currentVisibleQuestionID,
            questions: readingItems.map(\.question),
            materialIDs: Set(materialsByID.keys)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            readerContent(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.white)
        .navigationTitle(module?.title ?? "真题阅读")
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .secondaryPageTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                questionBankToolbar
            }
            .documentToolbarBackground()
        }
        .sheet(item: $activeSheet, onDismiss: handleReaderSheetDismissal) { sheet in
            switch sheet.content {
            case .overview:
                QuestionBankQuestionOverviewSheet(
                    items: readingItems,
                    currentQuestionID: currentVisibleQuestionID,
                    assetLookup: assetRecord(for:),
                    onSelect: { handleOverviewSelection($0.overviewItem) },
                    detailContent: { AnyView(questionDetailContent($0)) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .material(let materialID):
                materialPanel(for: materialID)
            case .questionDetail(let questionID):
                if let item = readingItem(for: questionID) {
                    questionDetailPanel(for: item)
                } else {
                    ContentUnavailableView("题目不存在", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .onAppear {
            refreshReaderSnapshot()
            restoreReaderState()
        }
        .onChange(of: readerRecordRevision) { _, _ in
            invalidateDoodleCache()
            refreshReaderSnapshot()
            restoreReaderState()
        }
        .onChange(of: snapshotRevision) { _, _ in applyInitialFocusIfNeeded() }
    }

    private func readerContent(width: CGFloat, height: CGFloat) -> some View {
        let canOpenSplit = horizontalSizeClass == .regular && width >= 700
        let splitOrientation = QuestionBankSplitLayout.orientation(width: width, height: height)
        return Group {
            if let splitMaterialID {
                splitReader(
                    materialID: splitMaterialID,
                    width: width,
                    height: height,
                    orientation: splitOrientation
                )
            } else if presentationMode == .single {
                singleQuestionReader(canOpenSplit: canOpenSplit)
            } else {
                continuousReader(canOpenSplit: canOpenSplit)
            }
        }
        .onChange(of: splitOrientation) { _, _ in
            guard splitMaterialID != nil, let questionID = currentVisibleQuestionID else { return }
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
        .overlay {
            QuestionBankDoodleAutosaveObserver(session: doodleSession, context: modelContext) {
                recordID, drawingData, error in
                guard error == nil else { return }
                cacheDoodleDrawing(drawingData, for: recordID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive, .background:
                invalidateDoodleCache()
                doodleSession.canvas.controller.invalidateDecodedDrawing()
                if let currentVisibleQuestionID { storedQuestionID = currentVisibleQuestionID }
                storedSplitMaterialID = splitMaterialID ?? ""
            case .active:
                invalidateDoodleCache()
                doodleSession.canvas.controller.invalidateDecodedDrawing()
                restoreReaderPosition()
            @unknown default:
                break
            }
        }
    }

    private var questionBankToolbar: some View {
        HStack(spacing: 0) {
            if doodleSession.isPresented {
                if doodleToolbarTarget != nil {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                questionDoodleToolbarItems
                questionOverviewButton
                readerOptionsMenu
            }
        }
        .frame(minHeight: 44)
        .id(doodleSession.isPresented ? "question-bank-toolbar-doodle" : "question-bank-toolbar-reader")
    }

    private var readerOptionsMenu: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            showsReaderOptions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent)
        }
        .accessibilityLabel("阅读设置")
        .accessibilityValue("浏览方式：\(presentationMode.title)，答题方式：\(readingMode.title)，选择后确认答案：\(requiresAnswerConfirmation ? "开启" : "关闭")")
        .accessibilityHint("打开设置，调整浏览方式、答题方式和答案确认")
        .accessibilityIdentifier("question-bank-reader-options")
        .disabled(doodleSession.isPresented)
        .popover(isPresented: $showsReaderOptions, arrowEdge: .top) {
            QuestionBankReaderOptionsPopover(
                presentationMode: Binding(
                    get: { presentationMode },
                    set: { selectPresentationMode($0) }
                ),
                readingMode: Binding(
                    get: { readingMode },
                    set: { guard !doodleSession.isPresented else { return }; readingMode = $0 }
                ),
                requiresAnswerConfirmation: Binding(
                    get: { requiresAnswerConfirmation },
                    set: { setAnswerConfirmationEnabled($0) }
                )
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var questionDoodleToolbarItems: some View {
        if let target = doodleToolbarTarget {
            currentQuestionDoodleButton(target)
        }
    }

    @ViewBuilder
    private func currentQuestionDoodleButton(_ target: QuestionBankDoodleToolbarTarget) -> some View {
        let button = Button {
            guard let item = readingItem(for: target.questionID) else { return }
            openQuestionDoodle(item)
        } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("标注当前题（第\(target.questionNumber)题）")
        .accessibilityHint(target.materialID == nil ? "打开当前题涂鸦" : "轻点标注当前题，长按可选择标注共用材料")
        .accessibilityIdentifier("question-bank-doodle-current-question")
        .disabled(doodleSession.isPresented)

        if let materialID = target.materialID {
            button
                .contextMenu {
                    Button {
                        openMaterialDoodle(materialID)
                    } label: {
                        Label("标注共用材料", systemImage: "pencil.and.scribble")
                    }
                }
                .accessibilityAction(named: Text("标注共用材料")) {
                    guard !doodleSession.isPresented else { return }
                    openMaterialDoodle(materialID)
                }
        } else {
            button
        }
    }

    private var questionOverviewButton: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            activeSheet = QuestionBankReaderSheet(content: .overview)
        } label: {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent.opacity(0.86))
        }
        .accessibilityLabel("题号总览")
        .disabled(readingItems.isEmpty || doodleSession.isPresented)
        .accessibilityIdentifier("question-bank-number-overview")
    }

    @ViewBuilder
    private func continuousReader(canOpenSplit: Bool) -> some View {
        if readingItems.isEmpty {
            emptyModuleState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(readingSteps) { step in
                                switch step.kind {
                                case .material(let materialID):
                                    if let material = materialsByID[materialID] {
                                        materialSection(material, canOpenSplit: canOpenSplit)
                                            .id(step.id)
                                    }
                                case .question(let questionID):
                                    if let item = readingItem(for: questionID) {
                                        questionSection(item, showsDetailButton: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented)
                .coordinateSpace(name: "question-bank-continuous-scroll")
                .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                .onChange(of: continuousScrollRequest) { _, request in
                    guard request != nil else { return }
                    consumeContinuousScrollRequest(using: proxy)
                }
                .onAppear { consumeContinuousScrollRequest(using: proxy) }
            }
        }
    }

    @ViewBuilder
    private func singleQuestionReader(canOpenSplit: Bool) -> some View {
        if readingItems.isEmpty {
            emptyModuleState
        } else if let item = currentSingleItem {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        singleMaterialEntry(for: item, canOpenSplit: canOpenSplit)
                        questionSection(item)
                    }
                    .id("single-question-page-\(item.id)")
                    .transition(singleQuestionPageTransition)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented)
                .simultaneousGesture(questionNavigationSwipeGesture())
                .coordinateSpace(name: "question-bank-continuous-scroll")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    singleQuestionNavigation(for: item)
                }
                .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                .onChange(of: currentVisibleQuestionID) { _, questionID in
                    guard presentationMode == .single, let questionID else { return }
                    scrollSingleQuestion(questionID, using: proxy)
                }
                .onAppear {
                    if currentVisibleQuestionID != item.id { currentVisibleQuestionID = item.id }
                    scrollSingleQuestion(item.id, using: proxy)
                }
            }
        } else {
            emptyModuleState
        }
    }

    @ViewBuilder
    private func splitReader(
        materialID: String,
        width: CGFloat,
        height: CGFloat,
        orientation: QuestionBankSplitOrientation
    ) -> some View {
        if let material = materialsByID[materialID] {
            let groupedQuestions = readingItems.filter { $0.question.materialID == materialID }
            Group {
                if orientation == .landscape {
                    HStack(spacing: 0) {
                        materialPane(material)
                            .frame(width: QuestionBankSplitLayout.materialWidth(totalWidth: width))
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.65))
                            .frame(width: 1)
                        questionPane(groupedQuestions)
                            .frame(minWidth: QuestionBankSplitLayout.minimumQuestionPaneWidth)
                    }
                } else {
                    VStack(spacing: 0) {
                        materialPane(material)
                            .frame(height: QuestionBankSplitLayout.materialHeight(totalHeight: height))
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.65))
                            .frame(height: 1)
                        questionPane(groupedQuestions)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        } else {
            emptyModuleState
        }
    }

    private func materialPane(_ material: QuestionBankMaterial) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("共用材料").font(AppTheme.sectionTitleFont)
                Spacer(minLength: 4)
                Button(action: closeSplitReader) {
                    Image(systemName: "rectangle.split.2x1")
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭分屏")
                .accessibilityIdentifier("question-bank-close-material-split")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
            ScrollView {
                materialContent(material)
                    .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .scrollDisabled(doodleSession.isPresented)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private func questionPane(_ groupedQuestions: [QuestionBankReadingItem]) -> some View {
        let visibleQuestions: [QuestionBankReadingItem]
        if presentationMode == .single {
            let questionID = QuestionBankReaderTransition.displayedQuestionIDs(
                for: .single,
                currentID: currentVisibleQuestionID,
                orderedIDs: groupedQuestions.map(\.id)
            ).first
            visibleQuestions = groupedQuestions.filter { $0.id == questionID }
        } else {
            visibleQuestions = groupedQuestions
        }
        return ScrollViewReader { proxy in
            ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleQuestions) { item in
                        questionSection(
                            item,
                            showsDetailButton: presentationMode == .continuous,
                            appliesSingleQuestionTransition: presentationMode == .single
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .scrollDisabled(doodleSession.isPresented)
            .simultaneousGesture(questionNavigationSwipeGesture())
            .coordinateSpace(name: "question-bank-continuous-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if presentationMode == .single, let item = visibleQuestions.first {
                    singleQuestionNavigation(for: item)
                }
            }
            .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
            .onChange(of: currentVisibleQuestionID) { _, questionID in
                guard presentationMode == .single, let questionID else { return }
                scrollSingleQuestion(questionID, using: proxy)
            }
            .onChange(of: splitScrollRequest) { _, request in
                guard let request else { return }
                let target = visibleQuestions.first(where: { $0.id == request.questionID })?.id
                    ?? visibleQuestions.first?.id
                guard let target else { return }
                if presentationMode == .single {
                    proxy.scrollTo(target, anchor: .top)
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            .onAppear {
                let preferred = currentVisibleQuestionID
                let target = visibleQuestions.first(where: { $0.id == preferred })?.id
                    ?? visibleQuestions.first(where: { $0.id == splitScrollRequest?.questionID })?.id
                    ?? visibleQuestions.first?.id
                guard let target else { return }
                if presentationMode == .single, currentVisibleQuestionID != target {
                    currentVisibleQuestionID = target
                }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func singleMaterialEntry(
        for item: QuestionBankReadingItem,
        canOpenSplit: Bool
    ) -> some View {
        if !item.question.materialID.isEmpty,
           let material = materialsByID[item.question.materialID] {
            let materialID = item.question.materialID
            Button {
                openMaterial(materialID, canOpenSplit: canOpenSplit)
            } label: {
                Label(
                    material.type.isEmpty ? "查看共用材料" : "查看\(material.type)共用材料",
                    systemImage: canOpenSplit ? "rectangle.split.2x1" : "doc.text"
                )
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .lineLimit(1)
                .frame(minHeight: 40)
            }
            .buttonStyle(.bordered)
            .disabled(doodleSession.isPresented)
            .accessibilityIdentifier("question-bank-single-material-\(materialID)")
            .padding(.bottom, 10)
        }
    }

    private func singleQuestionNavigation(for item: QuestionBankReadingItem) -> some View {
        let ordinal = QuestionBankReaderTransition.ordinal(of: item.id, in: orderedQuestionIDs) ?? 1
        let previousID = QuestionBankReaderTransition.adjacentQuestionID(
            currentID: item.id, orderedIDs: orderedQuestionIDs, direction: -1
        )
        let nextID = QuestionBankReaderTransition.adjacentQuestionID(
            currentID: item.id, orderedIDs: orderedQuestionIDs, direction: 1
        )
        return HStack(spacing: 8) {
            Button { navigateSingleQuestion(by: -1) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    Text("上一题")
                }
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .frame(minWidth: 78, minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(previousID == nil || doodleSession.isPresented)
            .accessibilityLabel("上一题")
            .accessibilityIdentifier("question-bank-single-previous")

            Spacer(minLength: 0)
            Text("\(item.question.number) · \(ordinal)/\(readingItems.count)")
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel("第\(item.question.number)题，共\(readingItems.count)题，第\(ordinal)题")
                .accessibilityIdentifier("question-bank-single-position")
            Spacer(minLength: 0)

            Button { navigateSingleQuestion(by: 1) } label: {
                HStack(spacing: 5) {
                    Text("下一题")
                    Image(systemName: "chevron.right")
                }
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .frame(minWidth: 78, minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(nextID == nil || doodleSession.isPresented)
            .accessibilityLabel("下一题")
            .accessibilityIdentifier("question-bank-single-next")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.55))
                .frame(height: 0.7)
        }
    }

    private func materialContent(_ material: QuestionBankMaterial, showsHeading: Bool = false) -> some View {
        QuestionBankMaterialBody(
            material: material,
            imageAsset: assetRecord(for: material.imageAssetID),
            showsHeading: showsHeading
        )
        .overlay {
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: doodleRecordID(for: .material(material.id)),
                minimumCanvasHeight: 0
            )
        }
    }

    private var emptyModuleState: some View {
        Group {
            if module == nil {
                NativeStatusCard(
                    title: "模块不存在",
                    detail: "此模块可能已被试卷替换。",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
            } else {
                NativeStatusCard(
                    title: "本次样本未收录题目",
                    detail: "该模块已保留在试卷结构中，当前导入样本没有可阅读的题目。",
                    systemImage: "doc.text.magnifyingglass",
                    color: AppTheme.accent
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func materialSection(_ material: QuestionBankMaterial, canOpenSplit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("共用材料")
                    .font(AppTheme.sectionTitleFont)
                if !material.type.isEmpty {
                    Text(material.type)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    openMaterial(material.id, canOpenSplit: canOpenSplit)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(canOpenSplit ? "分屏看材料" : "查看材料")
                .accessibilityIdentifier("question-bank-split-material-\(material.id)")
            }
            materialContent(material)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func questionSection(
        _ item: QuestionBankReadingItem,
        showsDetailButton: Bool = false,
        appliesSingleQuestionTransition: Bool = false
    ) -> some View {
        let selectedOptionID = selectedOptionsByQuestionID[item.id]
        let revealsAnswer = readingMode.revealsAnswer(
            afterSelecting: selectedOptionID,
            wasConfirmed: revealedAnswerQuestionIDs.contains(item.id),
            requiresConfirmation: requiresAnswerConfirmation
        )
        return VStack(alignment: .leading, spacing: 0) {
            if let heading = QuestionBankQuestionHeading.displayLabel(
                type: item.question.type,
                subject: item.question.subject
            ) {
                HStack(spacing: 8) {
                    Text(heading)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if showsDetailButton { questionDetailButton(for: item) }
                }
                .padding(.bottom, 7)
            } else if showsDetailButton {
                HStack {
                    Spacer(minLength: 0)
                    questionDetailButton(for: item)
                }
                .padding(.bottom, 4)
            }

            HStack(alignment: .top, spacing: 10) {
                Text("\(String(item.question.number)).")
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    if !item.question.stem.isEmpty {
                        Text(verbatim: item.question.stem)
                            .font(AppTheme.questionTextFont)
                            .lineSpacing(AppTheme.questionLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 10)
                            .accessibilityIdentifier("question-bank-question-stem-\(item.id)")
                    }
                    if !item.question.stemImageAssetID.isEmpty,
                       let asset = assetRecord(for: item.question.stemImageAssetID) {
                        QuestionBankLocalImage(asset: asset, sizing: .stem)
                            .padding(.bottom, 10)
                    }
                }
            }

            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    questionID: item.id,
                    option: option,
                    answer: item.question.answer,
                    readingMode: readingMode,
                    selectedOptionID: selectedOptionID,
                    revealsAnswer: revealsAnswer,
                    isSelectionLocked: readingMode == .practice && revealsAnswer,
                    isInteractionBlocked: doodleSession.isPresented,
                    onSelect: { selectOption(option.id, for: item.id) },
                    assetLookup: assetRecord(for:)
                )
            }

            if readingMode == .reading {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                    Text("正确答案")
                        .foregroundStyle(.secondary)
                    Text(item.question.answer.isEmpty ? "未提供" : item.question.answer)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.success)
                }
                .font(AppTheme.bodyFont)
                .padding(.top, 12)
            } else if readingMode == .practice {
                if revealsAnswer, let selectedOptionID {
                    HStack(spacing: 8) {
                        Text("你的选择：\(selectedOptionID)")
                            .foregroundStyle(selectedOptionID == item.question.answer ? AppTheme.success : AppTheme.danger)
                        Spacer(minLength: 8)
                        Text("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.success)
                    }
                    .font(AppTheme.auxiliaryFont)
                    .padding(.top, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("question-bank-answer-feedback-\(item.id)")
                } else if requiresAnswerConfirmation {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            confirmAnswer(for: item.id)
                        } label: {
                            Text("确认答案")
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                                .frame(minWidth: 96, minHeight: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedOptionID == nil || doodleSession.isPresented)
                        .accessibilityLabel("确认答案并查看正确选项")
                        .accessibilityIdentifier("question-bank-confirm-answer-\(item.id)")
                    }
                    .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("question-bank-continuous-scroll"))
                Color.clear.preference(
                    key: QuestionBankReaderViewportPreference.self,
                    value: [item.id: QuestionBankReaderViewportFrame(top: frame.minY, bottom: frame.maxY)]
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
        }
        .overlay {
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: doodleRecordID(for: .question(item.id)),
                minimumCanvasHeight: 0
            )
        }
        .id(item.id)
        .transition(appliesSingleQuestionTransition ? singleQuestionPageTransition : .identity)
    }

    private func questionDetailButton(for item: QuestionBankReadingItem) -> some View {
        Button {
            guard !doodleSession.isPresented else { return }
            activeSheet = QuestionBankReaderSheet(content: .questionDetail(item.id))
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.accent.opacity(0.78))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看第\(item.question.number)题详情")
        .accessibilityIdentifier("question-bank-question-detail-\(item.id)")
    }

    private func questionDetailContent(_ item: QuestionBankReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !item.question.materialID.isEmpty,
               let material = materialsByID[item.question.materialID] {
                materialContent(material, showsHeading: true)
                    .padding(.bottom, 12)
                QuestionBankProvenanceDisclosure(
                    title: "材料来源", entries: material.provenance ?? [],
                    sourcePapers: paperData?.sourcePapers ?? []
                )
                    .padding(.bottom, 12)
            }
            questionSection(item)
            QuestionBankProvenanceDisclosure(
                title: "题目来源", entries: item.question.provenance ?? [],
                sourcePapers: paperData?.sourcePapers ?? []
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func questionDetailPanel(for item: QuestionBankReadingItem) -> some View {
        NavigationStack {
            ScrollView {
                questionDetailContent(item)
            }
            .coordinateSpace(name: "question-bank-continuous-scroll")
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .scrollDisabled(doodleSession.isPresented)
            .navigationTitle("第\(item.question.number)题详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func openMaterial(_ materialID: String, canOpenSplit: Bool) {
        guard !doodleSession.isPresented else { return }
        guard canOpenSplit else {
            activeSheet = QuestionBankReaderSheet(content: .material(materialID))
            return
        }
        continuousAnchorQuestionID = currentVisibleQuestionID ?? continuousAnchorQuestionID
        splitMaterialID = materialID
        storedSplitMaterialID = materialID
        let preferredQuestion = readingItems.first {
            $0.id == currentVisibleQuestionID && $0.question.materialID == materialID
        }
        let target = preferredQuestion?.id ?? readingItems.first { $0.question.materialID == materialID }?.id
        if let target {
            currentVisibleQuestionID = target
            splitScrollRequest = QuestionBankScrollRequest(questionID: target, token: UUID())
        }
    }

    private func closeSplitReader() {
        guard !doodleSession.isPresented else { return }
        let returnTarget = currentVisibleQuestionID ?? continuousAnchorQuestionID
        splitMaterialID = nil
        storedSplitMaterialID = ""
        guard presentationMode == .continuous, let returnTarget else { return }
        continuousScrollRequest = QuestionBankScrollRequest(questionID: returnTarget, token: UUID())
    }

    private func materialPanel(for materialID: String) -> some View {
        Group {
            if let material = materialsByID[materialID] {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            materialContent(material)
                            QuestionBankProvenanceDisclosure(
                                title: "材料来源", entries: material.provenance ?? [],
                                sourcePapers: paperData?.sourcePapers ?? []
                            )
                        }
                        .padding(20)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented)
                    .navigationTitle("共用材料")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { activeSheet = nil }
                        }
                    }
                }
            } else {
                NativeStatusCard(
                    title: "材料不存在",
                    detail: "该材料可能已被试卷替换。",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
            }
        }
    }

    private func handleOverviewSelection(_ item: QuestionBankOverviewItem) {
        guard !doodleSession.isPresented else { return }
        pendingOverviewQuestionID = item.id
        continuousAnchorQuestionID = item.id
        let position = QuestionBankReaderTransition.selectingOverviewQuestion(
            item.id,
            materialID: item.materialID.isEmpty ? nil : item.materialID,
            availableMaterialIDs: Set(materialsByID.keys),
            from: readerPosition
        )
        applyReaderPosition(position)
    }

    private func handleReaderSheetDismissal() {
        guard let questionID = pendingOverviewQuestionID else { return }
        pendingOverviewQuestionID = nil
        let request = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        if splitMaterialID != nil {
            splitScrollRequest = request
        } else if presentationMode == .continuous {
            continuousScrollRequest = request
        }
    }

    private func applyReaderPosition(_ position: QuestionBankReaderPosition) {
        presentationMode = position.presentationMode
        currentVisibleQuestionID = position.currentQuestionID
        splitMaterialID = position.splitMaterialID
    }

    private func selectPresentationMode(_ mode: QuestionBankPresentationMode) {
        guard !doodleSession.isPresented else { return }
        guard mode != presentationMode else { return }
        var source = readerPosition
        if source.currentQuestionID == nil {
            source.currentQuestionID = currentSingleItem?.id ?? initialFocusQuestionID
        }
        let position = QuestionBankReaderTransition.switchingPresentation(to: mode, from: source)
        applyReaderPosition(position)
        guard let questionID = position.currentQuestionID else { return }
        continuousAnchorQuestionID = questionID
        if position.splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        } else if mode == .continuous {
            continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
    }

    private func navigateSingleQuestion(by direction: Int) {
        guard presentationMode == .single, !doodleSession.isPresented else { return }
        guard let targetID = QuestionBankReaderTransition.adjacentQuestionID(
            currentID: currentVisibleQuestionID ?? currentSingleItem?.id,
            orderedIDs: orderedQuestionIDs,
            direction: direction
        ), let target = readingItem(for: targetID) else { return }

        let hadSplitMaterial = splitMaterialID != nil
        let position = QuestionBankReaderTransition.movingToQuestion(
            targetID,
            materialID: target.question.materialID.isEmpty ? nil : target.question.materialID,
            availableMaterialIDs: Set(materialsByID.keys),
            from: readerPosition
        )
        withAnimation(.easeInOut(duration: 0.32)) {
            singleQuestionTransitionDirection = direction < 0 ? -1 : 1
            applyReaderPosition(position)
            continuousAnchorQuestionID = targetID

            if hadSplitMaterial, position.splitMaterialID != nil {
                splitScrollRequest = QuestionBankScrollRequest(questionID: targetID, token: UUID())
            }
        }
    }

    private func questionNavigationSwipeGesture() -> some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onEnded { value in
                guard presentationMode == .single, !doodleSession.isPresented,
                      let direction = QuestionBankHorizontalSwipe.direction(
                        horizontal: value.translation.width,
                        vertical: value.translation.height
                      ) else { return }
                navigateSingleQuestion(by: direction)
            }
    }

    private func selectOption(_ optionID: String, for questionID: String) {
        guard !doodleSession.isPresented,
              readingMode == .practice,
              !revealedAnswerQuestionIDs.contains(questionID) else { return }
        if !requiresAnswerConfirmation, selectedOptionsByQuestionID[questionID] != nil { return }
        selectedOptionsByQuestionID[questionID] = optionID
        if !requiresAnswerConfirmation {
            var revealed = revealedAnswerQuestionIDs
            revealed.insert(questionID)
            revealedAnswerQuestionIDs = revealed
        }
    }

    private func setAnswerConfirmationEnabled(_ enabled: Bool) {
        guard !doodleSession.isPresented else { return }
        requiresAnswerConfirmation = enabled
        if !enabled {
            var revealed = revealedAnswerQuestionIDs
            revealed.formUnion(selectedOptionsByQuestionID.keys)
            revealedAnswerQuestionIDs = revealed
        }
    }

    private func confirmAnswer(for questionID: String) {
        guard !doodleSession.isPresented,
              selectedOptionsByQuestionID[questionID] != nil else { return }
        var revealed = revealedAnswerQuestionIDs
        revealed.insert(questionID)
        revealedAnswerQuestionIDs = revealed
    }

    private func scrollSingleQuestion(_ questionID: String, using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(questionID, anchor: .top)
        }
    }

    private func updateVisibleQuestion(_ frames: [String: QuestionBankReaderViewportFrame]) {
        guard presentationMode == .continuous else { return }
        guard let visible = frames
            .filter({ $0.value.bottom > 1 })
            .min(by: { $0.value.top < $1.value.top })?.key else { return }
        guard currentVisibleQuestionID != visible else { return }
        currentVisibleQuestionID = visible
        if splitMaterialID == nil { continuousAnchorQuestionID = visible }
    }

    private func applyInitialFocusIfNeeded() {
        guard !didApplyInitialFocus else { return }
        let restoredID = readingItems.first(where: { $0.id == currentVisibleQuestionID })?.id
        guard let questionID = initialFocusQuestionID ?? restoredID else { return }
        didApplyInitialFocus = true
        currentVisibleQuestionID = questionID
        continuousAnchorQuestionID = questionID
        if let item = readingItem(for: questionID), splitMaterialID != nil {
            reconcileSplitMaterial(for: item)
        }
        if splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        } else if presentationMode == .continuous {
            continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
    }

    private func restoreReaderState() {
        if let splitMaterialID, materialsByID[splitMaterialID] == nil {
            self.splitMaterialID = nil
        }
        applyInitialFocusIfNeeded()
        if splitMaterialID != nil,
           let questionID = currentVisibleQuestionID,
           let item = readingItem(for: questionID) {
            reconcileSplitMaterial(for: item)
            if self.splitMaterialID != nil {
                splitScrollRequest = QuestionBankScrollRequest(questionID: item.id, token: UUID())
            } else if presentationMode == .continuous {
                continuousScrollRequest = QuestionBankScrollRequest(questionID: item.id, token: UUID())
            }
        }
    }

    private func restoreReaderPosition() {
        guard let item = readingItems.first(where: { $0.id == currentVisibleQuestionID }) else { return }
        let questionID = item.id
        currentVisibleQuestionID = questionID
        if splitMaterialID != nil {
            reconcileSplitMaterial(for: item)
        }
        if splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        } else if presentationMode == .continuous {
            continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
    }

    private func reconcileSplitMaterial(for item: QuestionBankReadingItem) {
        guard splitMaterialID != nil else { return }
        let materialID = item.question.materialID
        splitMaterialID = !materialID.isEmpty && materialsByID[materialID] != nil ? materialID : nil
    }

    private func doodleRecordID(for scope: QuestionBankDoodleScope) -> String {
        QuestionBankDoodleRepository.recordID(paperID: paperID, scope: scope)
    }

    private func openMaterialDoodle(_ materialID: String) {
        presentDoodle(for: .material(materialID))
    }

    private func openQuestionDoodle(_ item: QuestionBankReadingItem) {
        presentDoodle(for: .question(item.id))
    }

    private func presentDoodle(for scope: QuestionBankDoodleScope) {
        let recordID = doodleRecordID(for: scope)
        do {
            let readStart = ProcessInfo.processInfo.systemUptime
            let drawingData: String
            if let cached = cachedDoodleDrawing(for: recordID) {
                drawingData = cached
                LibraryPerformanceLog.mark("doodle.read.cache-hit", since: readStart)
            } else {
                drawingData = try QuestionBankDoodleRepository.drawingData(
                    recordID: recordID,
                    context: modelContext
                )
                cacheDoodleDrawing(drawingData, for: recordID)
            }
            doodleSession.present(
                targetRecordID: recordID,
                drawingData: drawingData,
                legacyPreviewDataURL: "",
                onSave: { drawingData, _ in
                    let error = QuestionBankDoodleRepository.save(
                        recordID: recordID,
                        drawingData: drawingData,
                        context: modelContext
                    )
                    if error == nil { cacheDoodleDrawing(drawingData, for: recordID) }
                    return error
                }
            )
        } catch {
            doodleSession.saveError = "涂鸦读取失败：\(error.localizedDescription)"
        }
    }

    private func cachedDoodleDrawing(for recordID: String) -> String? {
        doodleDrawingCache.drawingData(for: recordID)
    }

    private func cacheDoodleDrawing(_ drawingData: String, for recordID: String) {
        doodleDrawingCache.store(drawingData, for: recordID)
    }

    private func invalidateDoodleCache() {
        doodleDrawingCache.invalidate()
    }

    private func consumeContinuousScrollRequest(using proxy: ScrollViewProxy) {
        guard let request = continuousScrollRequest else { return }
        continuousScrollRequest = nil
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(request.questionID, anchor: .top)
            }
        }
    }

    private func refreshReaderSnapshot() {
        let questions = records
            .filter {
                $0.paperID == paperID && $0.moduleID == moduleID
                    && $0.kind == QuestionBankRepository.questionKind
            }
            .compactMap { record -> QuestionBankReadingItem? in
                guard let question = record.decoded(QuestionBankQuestion.self) else { return nil }
                return QuestionBankReadingItem(record: record, question: question)
            }
            .sorted {
                if $0.question.number != $1.question.number { return $0.question.number < $1.question.number }
                return $0.id < $1.id
            }
        readingItems = questions
        readingSteps = QuestionBankReadingSequence.steps(for: questions.map(\.question))
        materialsByID = Dictionary(
            records
                .filter {
                    $0.paperID == paperID && $0.moduleID == moduleID
                        && $0.kind == QuestionBankRepository.materialKind
                }
                .compactMap { record -> (String, QuestionBankMaterial)? in
                    guard let material = record.decoded(QuestionBankMaterial.self) else { return nil }
                    return (record.stableID, material)
                },
            uniquingKeysWith: { first, _ in first }
        )
        assetsByID = Dictionary(
            records
                .filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.assetKind }
                .map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        snapshotRevision += 1
    }

    private func readingItem(for id: String) -> QuestionBankReadingItem? {
        readingItems.first { $0.id == id }
    }

    private func assetRecord(for id: String) -> QuestionBankRecord? {
        guard !id.isEmpty else { return nil }
        return assetsByID[id]
    }
}

private struct QuestionBankCrossPaperStep: Identifiable {
    let id: String
    let material: QuestionBankMaterial?
    let question: QuestionBankHomeQuestion?
}

private struct QuestionBankCrossPaperGroup: Identifiable {
    let paperID: String
    let title: String
    let steps: [QuestionBankCrossPaperStep]
    let questions: [QuestionBankHomeQuestion]
    let materialsByID: [String: QuestionBankMaterial]
    let sourcePapers: [QuestionBankSourcePaper]

    var id: String { paperID }
}

struct QuestionBankCrossPaperReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @Query private var records: [QuestionBankRecord]

    let filter: QuestionBankHomeFilter
    let paperID: String?

    @State private var presentationMode: QuestionBankPresentationMode = .continuous
    @State private var readingMode: QuestionBankReadingMode = .reading
    @State private var currentQuestionID: String?
    @State private var groups: [QuestionBankCrossPaperGroup] = []
    @State private var showsReaderOptions = false
    @State private var showsOverview = false
    @State private var transitionDirection = 1
    @SceneStorage private var selectedOptionsJSON: String
    @SceneStorage private var revealedAnswersJSON: String
    @AppStorage(QuestionBankReaderPreferences.confirmAnswerAfterSelectionKey)
    private var requiresAnswerConfirmation = false

    init(filter: QuestionBankHomeFilter, paperID: String? = nil) {
        self.filter = filter
        self.paperID = paperID
        let scope = [
            filter.module?.rawValue ?? "", filter.questionType, filter.year, filter.examType,
            filter.province, filter.search, filter.questionNumber, paperID ?? "all"
        ].joined(separator: "|")
        let key = Data(scope.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        _selectedOptionsJSON = SceneStorage(wrappedValue: "{}", "question-bank.scope.selected-options.\(key)")
        _revealedAnswersJSON = SceneStorage(wrappedValue: "[]", "question-bank.scope.revealed-answers.\(key)")
    }

    private var index: QuestionBankHomeIndex { QuestionBankHomeIndex(records: records) }

    private var readerRecordRevision: Int {
        var hasher = Hasher()
        for record in records.sorted(by: { $0.compoundID < $1.compoundID }) {
            hasher.combine(record.compoundID)
            hasher.combine(record.payload)
            hasher.combine(record.assetRelativePath)
        }
        return hasher.finalize()
    }

    private func makeGroups() -> [QuestionBankCrossPaperGroup] {
        let homeIndex = index
        let scoped = homeIndex.filteredQuestions(matching: filter, paperID: paperID)
        let grouped = Dictionary(grouping: scoped, by: { $0.record.paperID })
        return homeIndex.papers.compactMap { paper in
            guard let questions = grouped[paper.id], !questions.isEmpty else { return nil }
            let materials = Dictionary(
                records
                    .filter { $0.paperID == paper.id && $0.kind == QuestionBankRepository.materialKind }
                    .compactMap { $0.decoded(QuestionBankMaterial.self) }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var emittedMaterials = Set<String>()
            var steps: [QuestionBankCrossPaperStep] = []
            for item in questions {
                let materialID = item.question.materialID
                if !materialID.isEmpty, let material = materials[materialID],
                   emittedMaterials.insert(materialID).inserted {
                    steps.append(QuestionBankCrossPaperStep(
                        id: "\(paper.id)::material::\(materialID)", material: material, question: nil
                    ))
                }
                steps.append(QuestionBankCrossPaperStep(
                    id: item.id, material: nil, question: item
                ))
            }
            return QuestionBankCrossPaperGroup(
                paperID: paper.id, title: paper.title, steps: steps,
                questions: questions, materialsByID: materials,
                sourcePapers: paper.paper.sourcePapers ?? []
            )
        }
    }

    private func refreshGroups() {
        groups = makeGroups()
        if !groups.flatMap(\.questions).contains(where: { $0.id == currentQuestionID }) {
            currentQuestionID = groups.first?.questions.first?.id
        }
    }

    private var orderedItems: [QuestionBankHomeQuestion] { groups.flatMap(\.questions) }

    private var currentItem: QuestionBankHomeQuestion? {
        orderedItems.first { $0.id == currentQuestionID } ?? orderedItems.first
    }

    private var selectedOptionsByQuestionID: [String: String] {
        get { QuestionBankSelectedOptionsStorage.decode(selectedOptionsJSON) }
        nonmutating set { selectedOptionsJSON = QuestionBankSelectedOptionsStorage.encode(newValue) }
    }

    private var revealedAnswerQuestionIDs: Set<String> {
        get { QuestionBankRevealedAnswersStorage.decode(revealedAnswersJSON) }
        nonmutating set { revealedAnswersJSON = QuestionBankRevealedAnswersStorage.encode(newValue) }
    }

    private var singleQuestionPageTransition: AnyTransition {
        let motion = QuestionBankPageTransition.motion(for: transitionDirection)
        let insertion: Edge = motion.insertion == .leading ? .leading : .trailing
        let removal: Edge = motion.removal == .leading ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: insertion), removal: .move(edge: removal))
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if presentationMode == .single, let item = currentItem {
                    singleReader(item)
                } else {
                    continuousReader
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.white)
        .navigationTitle(paperTitle ?? filter.module?.rawValue ?? "多卷题目")
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .secondaryPageTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    doodleButton
                    Button {
                        guard !doodleSession.isPresented else { return }
                        showsOverview = true
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(AppTheme.accent.opacity(0.86))
                    }
                    .accessibilityLabel("题号总览")
                    .accessibilityIdentifier("question-bank-number-overview")
                    .disabled(orderedItems.isEmpty || doodleSession.isPresented)
                    readerOptionsButton
                }
                .id(doodleSession.isPresented ? "cross-paper-toolbar-doodle" : "cross-paper-toolbar-reader")
            }
            .documentToolbarBackground()
        }
        .sheet(isPresented: $showsOverview) {
            NavigationStack {
                List {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.questions) { item in
                                Button {
                                    presentationMode = .single
                                    currentQuestionID = item.id
                                    showsOverview = false
                                } label: {
                                    HStack {
                                        Text("第\(item.question.number)题")
                                        Spacer()
                                        if let heading = QuestionBankQuestionHeading.displayLabel(
                                            type: item.question.type, subject: item.question.subject
                                        ) {
                                            Text(heading).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityLabel("\(group.title)，第\(item.question.number)题")
                                .accessibilityIdentifier("question-bank-cross-paper-overview-\(item.id)")
                            }
                        }
                    }
                }
                .navigationTitle("题号总览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsOverview = false }
                    }
                }
            }
        }
        .onAppear {
            refreshGroups()
            if currentQuestionID == nil { currentQuestionID = orderedItems.first?.id }
        }
        .onChange(of: readerRecordRevision) { _, _ in refreshGroups() }
    }

    private var paperTitle: String? {
        guard let paperID else { return nil }
        return index.papers.first(where: { $0.id == paperID })?.title
    }

    private var doodleButton: some View {
        Button {
            guard let item = currentItem, !doodleSession.isPresented else { return }
            presentDoodle(for: item)
        } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(currentItem.map { "标注当前题（第\($0.question.number)题）" } ?? "标注当前题")
        .accessibilityIdentifier("question-bank-doodle-current-question")
        .disabled(currentItem == nil || doodleSession.isPresented)
    }

    private var readerOptionsButton: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            showsReaderOptions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(AppTheme.accent)
        }
        .accessibilityLabel("阅读设置")
        .accessibilityValue("浏览方式：\(presentationMode.title)，答题方式：\(readingMode.title)，选择后确认答案：\(requiresAnswerConfirmation ? "开启" : "关闭")")
        .accessibilityIdentifier("question-bank-reader-options")
        .disabled(doodleSession.isPresented)
        .popover(isPresented: $showsReaderOptions, arrowEdge: .top) {
            QuestionBankReaderOptionsPopover(
                presentationMode: $presentationMode,
                readingMode: $readingMode,
                requiresAnswerConfirmation: Binding(
                    get: { requiresAnswerConfirmation },
                    set: { setAnswerConfirmationEnabled($0) }
                )
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var continuousReader: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if groups.isEmpty {
                    ContentUnavailableView("没有符合条件的题目", systemImage: "text.book.closed")
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        paperDivider(group.title, count: group.questions.count)
                        ForEach(group.steps) { step in
                            if let material = step.material {
                                materialSection(material, paperID: group.paperID, sourcePapers: group.sourcePapers)
                            } else if let item = step.question {
                                questionSection(item, group: group, showsPaperHeading: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .scrollDisabled(doodleSession.isPresented)
        .coordinateSpace(name: "question-bank-cross-paper-scroll")
        .simultaneousGesture(horizontalSwipeGesture)
        .onPreferenceChange(QuestionBankReaderViewportPreference.self) { frames in
            let visible = frames.filter { $0.value.bottom > 0 }
                .min { abs($0.value.top) < abs($1.value.top) }
            if let visible { currentQuestionID = visible.key }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presentationMode == .single, let item = currentItem {
                singleQuestionNavigation(for: item)
            }
        }
    }

    @ViewBuilder
    private func singleReader(_ item: QuestionBankHomeQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let group = groups.first(where: { $0.paperID == item.record.paperID }) {
                    if group.questions.first?.id == item.id {
                        paperDivider(group.title, count: group.questions.count)
                    }
                    if !item.question.materialID.isEmpty,
                       let material = group.materialsByID[item.question.materialID] {
                        materialSection(material, paperID: group.paperID, sourcePapers: group.sourcePapers)
                    }
                    questionSection(item, group: group, showsPaperHeading: false)
                }
            }
            .id("cross-paper-single-\(item.id)")
            .transition(singleQuestionPageTransition)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .scrollDisabled(doodleSession.isPresented)
        .coordinateSpace(name: "question-bank-cross-paper-scroll")
        .simultaneousGesture(horizontalSwipeGesture)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            singleQuestionNavigation(for: item)
        }
        .id("cross-paper-single-scroll-\(item.id)")
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onEnded { value in
                guard presentationMode == .single, !doodleSession.isPresented,
                      let direction = QuestionBankHorizontalSwipe.direction(
                        horizontal: value.translation.width,
                        vertical: value.translation.height
                      ) else { return }
                moveQuestion(by: direction)
            }
    }

    private func paperDivider(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)题")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.55)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("question-bank-paper-divider-\(title)")
    }

    private func materialSection(
        _ material: QuestionBankMaterial,
        paperID: String,
        sourcePapers: [QuestionBankSourcePaper]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(material.type.isEmpty ? "共用材料" : material.type)
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            if !material.text.isEmpty {
                Text(verbatim: material.text)
                    .font(AppTheme.bodyFont)
                    .lineSpacing(AppTheme.questionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !material.imageAssetID.isEmpty,
               let asset = assetRecord(for: material.imageAssetID, paperID: paperID) {
                QuestionBankLocalImage(asset: asset, sizing: .material)
            }
            QuestionBankProvenanceDisclosure(
                title: "材料来源", entries: material.provenance ?? [], sourcePapers: sourcePapers
            )
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: QuestionBankDoodleRepository.recordID(
                    paperID: paperID, scope: .material(material.id)
                ),
                minimumCanvasHeight: 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.35)).frame(height: 1)
        }
    }

    private func questionSection(
        _ item: QuestionBankHomeQuestion,
        group: QuestionBankCrossPaperGroup,
        showsPaperHeading: Bool
    ) -> some View {
        let selected = selectedOptionsByQuestionID[item.id]
        let reveals = readingMode.revealsAnswer(
            afterSelecting: selected,
            wasConfirmed: revealedAnswerQuestionIDs.contains(item.id),
            requiresConfirmation: requiresAnswerConfirmation
        )
        return VStack(alignment: .leading, spacing: 8) {
            if showsPaperHeading, group.questions.first?.id == item.id {
                paperDivider(group.title, count: group.questions.count)
            }
            if let heading = QuestionBankQuestionHeading.displayLabel(
                type: item.question.type, subject: item.question.subject
            ) {
                Text(heading)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                Text("\(item.question.number).")
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 9) {
                    if !item.question.stem.isEmpty {
                        Text(verbatim: item.question.stem)
                            .font(AppTheme.questionTextFont)
                            .lineSpacing(AppTheme.questionLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !item.question.stemImageAssetID.isEmpty,
                       let asset = assetRecord(for: item.question.stemImageAssetID, paperID: item.record.paperID) {
                        QuestionBankLocalImage(asset: asset, sizing: .stem)
                    }
                }
            }
            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    questionID: item.id,
                    option: option,
                    answer: item.question.answer,
                    readingMode: readingMode,
                    selectedOptionID: selected,
                    revealsAnswer: reveals,
                    isSelectionLocked: readingMode == .practice && reveals,
                    isInteractionBlocked: doodleSession.isPresented,
                    onSelect: { selectOption(option.id, item: item) },
                    assetLookup: { assetRecord(for: $0, paperID: item.record.paperID) }
                )
            }
            if readingMode == .reading {
                Label("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.success)
                    .padding(.top, 6)
            } else if reveals, let selected {
                HStack(spacing: 8) {
                    Text("你的选择：\(selected)")
                        .foregroundStyle(selected == item.question.answer ? AppTheme.success : AppTheme.danger)
                    Spacer(minLength: 8)
                    Text("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.success)
                }
                .font(AppTheme.auxiliaryFont)
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("question-bank-answer-feedback-\(item.id)")
            } else if readingMode == .practice && requiresAnswerConfirmation {
                HStack {
                    Spacer()
                    Button("确认答案") { confirmAnswer(for: item.id) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected == nil || doodleSession.isPresented)
                        .accessibilityLabel("确认答案并查看正确选项")
                        .accessibilityIdentifier("question-bank-confirm-answer-\(item.id)")
                }
                .padding(.top, 6)
            }
            if let material = group.materialsByID[item.question.materialID] {
                QuestionBankProvenanceDisclosure(
                    title: "材料来源", entries: material.provenance ?? [], sourcePapers: group.sourcePapers
                )
            }
            QuestionBankProvenanceDisclosure(
                title: "题目来源", entries: item.question.provenance ?? [], sourcePapers: group.sourcePapers
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("question-bank-cross-paper-scroll"))
                Color.clear.preference(
                    key: QuestionBankReaderViewportPreference.self,
                    value: [item.id: QuestionBankReaderViewportFrame(top: frame.minY, bottom: frame.maxY)]
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.4)).frame(height: 1)
        }
        .overlay {
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: QuestionBankDoodleRepository.recordID(
                    paperID: item.record.paperID, scope: .question(item.question.id)
                ),
                minimumCanvasHeight: 0
            )
        }
        .id(item.id)
    }

    private func singleQuestionNavigation(for item: QuestionBankHomeQuestion) -> some View {
        let ids = orderedItems.map(\.id)
        let ordinal = QuestionBankReaderTransition.ordinal(of: item.id, in: ids) ?? 1
        let previousID = QuestionBankReaderTransition.adjacentQuestionID(currentID: item.id, orderedIDs: ids, direction: -1)
        let nextID = QuestionBankReaderTransition.adjacentQuestionID(currentID: item.id, orderedIDs: ids, direction: 1)
        return HStack(spacing: 8) {
            Button { moveQuestion(by: -1) } label: {
                Label("上一题", systemImage: "chevron.left")
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .frame(minWidth: 78, minHeight: 44)
            }
            .disabled(previousID == nil || doodleSession.isPresented)
            .accessibilityIdentifier("question-bank-single-previous")
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text("范围 \(ordinal) / \(ids.count)")
                    .font(AppTheme.auxiliaryFont)
                Text("第\(item.question.number)题")
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("question-bank-single-position")
            Spacer(minLength: 4)
            Button { moveQuestion(by: 1) } label: {
                Label("下一题", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .frame(minWidth: 78, minHeight: 44)
            }
            .disabled(nextID == nil || doodleSession.isPresented)
            .accessibilityIdentifier("question-bank-single-next")
        }
        .padding(.horizontal, 14)
        .background(.regularMaterial)
    }

    private func moveQuestion(by direction: Int) {
        guard !doodleSession.isPresented,
              let target = QuestionBankReaderTransition.adjacentQuestionID(
                currentID: currentItem?.id, orderedIDs: orderedItems.map(\.id), direction: direction
              ) else { return }
        transitionDirection = direction
        withAnimation(.easeInOut(duration: 0.22)) { currentQuestionID = target }
    }

    private func selectOption(_ optionID: String, item: QuestionBankHomeQuestion) {
        guard !doodleSession.isPresented, readingMode == .practice,
              !revealedAnswerQuestionIDs.contains(item.id) else { return }
        if !requiresAnswerConfirmation, selectedOptionsByQuestionID[item.id] != nil { return }
        var selected = selectedOptionsByQuestionID
        selected[item.id] = optionID
        selectedOptionsByQuestionID = selected
        if !requiresAnswerConfirmation {
            var revealed = revealedAnswerQuestionIDs
            revealed.insert(item.id)
            revealedAnswerQuestionIDs = revealed
        }
        currentQuestionID = item.id
    }

    private func setAnswerConfirmationEnabled(_ enabled: Bool) {
        guard !doodleSession.isPresented else { return }
        requiresAnswerConfirmation = enabled
        if !enabled {
            var revealed = revealedAnswerQuestionIDs
            revealed.formUnion(selectedOptionsByQuestionID.keys)
            revealedAnswerQuestionIDs = revealed
        }
    }

    private func confirmAnswer(for questionID: String) {
        guard !doodleSession.isPresented, selectedOptionsByQuestionID[questionID] != nil else { return }
        var revealed = revealedAnswerQuestionIDs
        revealed.insert(questionID)
        revealedAnswerQuestionIDs = revealed
    }

    private func assetRecord(for id: String, paperID: String) -> QuestionBankRecord? {
        guard !id.isEmpty else { return nil }
        return records.first {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.assetKind && $0.stableID == id
        }
    }

    private func presentDoodle(for item: QuestionBankHomeQuestion) {
        let recordID = QuestionBankDoodleRepository.recordID(
            paperID: item.record.paperID, scope: .question(item.question.id)
        )
        do {
            let drawing = try QuestionBankDoodleRepository.drawingData(recordID: recordID, context: modelContext)
            doodleSession.present(
                targetRecordID: recordID,
                drawingData: drawing,
                legacyPreviewDataURL: "",
                onSave: { drawingData, _ in
                    QuestionBankDoodleRepository.save(
                        recordID: recordID, drawingData: drawingData, context: modelContext
                    )
                }
            )
        } catch {
            doodleSession.saveError = "涂鸦读取失败：\(error.localizedDescription)"
        }
    }
}

private struct QuestionBankQuestionOverviewSheet: View {
    private enum Presentation: String, CaseIterable, Identifiable, Hashable {
        case numbers
        case cards
        var id: String { rawValue }
        var title: String { self == .numbers ? "题号" : "卡片" }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var presentation = Presentation.numbers

    let items: [QuestionBankReadingItem]
    let currentQuestionID: String?
    let assetLookup: (String) -> QuestionBankRecord?
    let onSelect: (QuestionBankReadingItem) -> Void
    let detailContent: (QuestionBankReadingItem) -> AnyView

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("总览方式", selection: $presentation) {
                    ForEach(Presentation.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .accessibilityIdentifier("question-bank-overview-presentation")

                if presentation == .numbers {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 7)], spacing: 7) {
                            ForEach(items) { item in numberButton(item) }
                        }
                        .padding(16)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in cardButton(item) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .navigationDestination(for: String.self) { questionID in
                if let item = items.first(where: { $0.id == questionID }) {
                    detailContent(item)
                        .navigationTitle("第\(item.question.number)题详情")
                        .navigationBarTitleDisplayMode(.inline)
                        .accessibilityIdentifier("question-bank-overview-detail-screen-\(item.id)")
                } else {
                    ContentUnavailableView("题目不存在", systemImage: "doc.text.magnifyingglass")
                }
            }
            .navigationTitle("题目总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func numberButton(_ item: QuestionBankReadingItem) -> some View {
        let isCurrent = item.id == currentQuestionID
        return Button {
            onSelect(item)
            dismiss()
        } label: {
            Text(String(item.question.number))
                .font(AppTheme.bodyFont.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isCurrent ? AppTheme.accent.opacity(0.10) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isCurrent ? AppTheme.accent : Color(uiColor: .separator).opacity(0.35))
                        .frame(height: isCurrent ? 1.5 : 0.7)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第\(String(item.question.number))题")
        .accessibilityIdentifier("question-bank-number-card-\(item.question.number)")
    }

    private func cardButton(_ item: QuestionBankReadingItem) -> some View {
        let overview = item.overviewItem
        let isCurrent = item.id == currentQuestionID
        let headingDescription = overview.type.isEmpty ? "" : "，\(overview.type)"
        return HStack(spacing: 4) {
            Button {
                onSelect(item)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(String(overview.number)).")
                            .font(AppTheme.bodyFont.weight(.semibold))
                            .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
                        if !overview.type.isEmpty {
                            Text(overview.type)
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if isCurrent {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    if let materialGroupLabel = overview.materialGroupLabel {
                        Text(materialGroupLabel)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                    }
                    if !overview.stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: overview.stem)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    } else if let asset = assetLookup(overview.stemImageAssetID) {
                        QuestionBankLocalImage(asset: asset, sizing: .overview)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("第\(String(overview.number))题\(headingDescription)")
            .accessibilityIdentifier("question-bank-overview-item-\(item.id)")

            NavigationLink(value: item.id) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.accent.opacity(0.78))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看第\(String(overview.number))题详情")
            .accessibilityIdentifier("question-bank-overview-detail-\(item.id)")
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isCurrent ? AppTheme.accent.opacity(0.75) : Color(uiColor: .separator).opacity(0.4))
                .frame(height: isCurrent ? 1.5 : 0.7)
        }
    }
}

private struct QuestionBankMaterialBody: View {
    let material: QuestionBankMaterial
    let imageAsset: QuestionBankRecord?
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeading {
                HStack(spacing: 8) {
                    Text("共用材料").font(AppTheme.sectionTitleFont)
                    if !material.type.isEmpty {
                        Text(material.type).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
            }
            if !material.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(material.text)
                    .font(AppTheme.bodyFont)
                    .lineSpacing(AppTheme.inputLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let imageAsset {
                QuestionBankLocalImage(asset: imageAsset, sizing: .material)
            }
            if material.text.isEmpty && material.imageAssetID.isEmpty {
                Text("本材料暂无可显示内容")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuestionBankReaderOptionsPopover: View {
    @Environment(\.dismiss) private var dismiss

    private struct Choice: Identifiable {
        let title: String
        let accessibilityLabel: String
        var id: String { title }
    }

    @Binding var presentationMode: QuestionBankPresentationMode
    @Binding var readingMode: QuestionBankReadingMode
    @Binding var requiresAnswerConfirmation: Bool

    var body: some View {
        VStack(spacing: 10) {
            choiceRow(
                label: "浏览",
                selected: presentationMode.shortTitle,
                options: [
                    Choice(title: "连续", accessibilityLabel: "连续阅读"),
                    Choice(title: "单题", accessibilityLabel: "单题模式")
                ],
                identifierPrefix: "question-bank-presentation"
            ) { value in
                presentationMode = value == "连续" ? .continuous : .single
            }
            choiceRow(
                label: "答题",
                selected: readingMode.title,
                options: [
                    Choice(title: "刷题", accessibilityLabel: "刷题"),
                    Choice(title: "看题", accessibilityLabel: "看题")
                ],
                identifierPrefix: "question-bank-reading-mode"
            ) { value in
                readingMode = value == "刷题" ? .practice : .reading
            }
            Toggle(isOn: $requiresAnswerConfirmation) {
                Text("确认")
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .frame(width: 44, alignment: .leading)
            }
            .toggleStyle(QuestionBankConfirmationCapsuleToggleStyle())
            .accessibilityLabel("选择后确认答案")
            .accessibilityValue(requiresAnswerConfirmation ? "开启" : "关闭")
            .accessibilityIdentifier("question-bank-confirm-answer-toggle")
        }
        .padding(12)
        .frame(width: 248)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func choiceRow(
        label: String,
        selected: String,
        options: [Choice],
        identifierPrefix: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.title)
                        dismiss()
                    } label: {
                        Text(option.title)
                            .font(AppTheme.auxiliaryFont.weight(.medium))
                            .foregroundStyle(selected == option.title ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(selected == option.title ? AppTheme.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                    .accessibilityValue(selected == option.title ? "已选" : "")
                    .accessibilityAddTraits(selected == option.title ? .isSelected : [])
                    .accessibilityIdentifier("\(identifierPrefix)-\(option.title)")
                }
            }
            .padding(3)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
        }
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label)方式")
    }
}

private struct QuestionBankProvenanceDisclosure: View {
    let title: String
    let entries: [QuestionBankProvenance]
    var sourcePapers: [QuestionBankSourcePaper] = []

    var body: some View {
        if !entries.isEmpty {
            DisclosureGroup(title) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("来源 \(index + 1)")
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                            Text(detail(for: entry))
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let evidence = entry.evidence, !evidence.isEmpty {
                                Text(evidence)
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let source = sourcePapers.first(where: { $0.id == entry.sourcePaperID }) {
                                if let fileName = source.originalFileName, !fileName.isEmpty {
                                    Text("原始文件：\(fileName)")
                                        .font(AppTheme.auxiliaryFont)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let sha256 = source.originalFileSHA256, !sha256.isEmpty {
                                    Text("SHA-256：\(sha256)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 7)
            }
            .font(AppTheme.auxiliaryFont.weight(.medium))
            .accessibilityIdentifier("question-bank-provenance-disclosure-\(title)")
        }
    }

    private func detail(for entry: QuestionBankProvenance) -> String {
        var parts = ["来源卷 \(entry.sourcePaperID)"]
        if let province = entry.provinceName ?? entry.provinceCode, !province.isEmpty {
            parts.append(province)
        }
        if let number = entry.sourceQuestionNumber { parts.append("原第\(number)题") }
        if let numbers = entry.sourceQuestionNumbers, !numbers.isEmpty {
            parts.append("原题号 \(numbers.map(String.init).joined(separator: "、"))")
        }
        if let page = entry.originalPage, !page.isEmpty { parts.append("第\(page)页") }
        return parts.joined(separator: " · ")
    }
}

private struct QuestionBankConfirmationCapsuleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            HStack(spacing: 3) {
                capsule("关闭", isSelected: !configuration.isOn) { configuration.isOn = false }
                capsule("开启", isSelected: configuration.isOn) { configuration.isOn = true }
            }
            .padding(3)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .frame(maxWidth: .infinity)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
    }

    private func capsule(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(isSelected ? AppTheme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

private struct QuestionBankOptionRow: View {
    let questionID: String
    let option: QuestionBankOption
    let answer: String
    let readingMode: QuestionBankReadingMode
    let selectedOptionID: String?
    let revealsAnswer: Bool
    let isSelectionLocked: Bool
    let isInteractionBlocked: Bool
    let onSelect: () -> Void
    let assetLookup: (String) -> QuestionBankRecord?

    var body: some View {
        if readingMode == .practice {
            Button {
                guard !isInteractionBlocked else { return }
                onSelect()
            } label: {
                row
            }
            .buttonStyle(.plain)
            // Keep the underlying option enabled while a doodle canvas is open.
            // The canvas interaction shield blocks the tap; leaving this button
            // enabled keeps its accessibility state truthful and lets the
            // shield own the interaction boundary.
            .disabled(isSelectionLocked)
            .accessibilityHint(isSelectionLocked ? "答案已提交，不能更改选择" : "选择此选项")
            .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
        } else {
            row
                .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(option.id)
                .font(AppTheme.bodyFont.weight(.semibold))
                .foregroundStyle(letterColor)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if let displayText = QuestionBankOptionDisplay.text(for: option) {
                    Text(displayText)
                        .font(AppTheme.bodyFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !option.imageAssetID.isEmpty, let asset = assetLookup(option.imageAssetID) {
                    QuestionBankLocalImage(asset: asset, sizing: .option)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if revealsAnswer && answer == option.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                    .accessibilityLabel("正确选项")
            } else if selectedOptionID == option.id && readingMode == .practice {
                Image(systemName: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(letterColor)
                    .accessibilityLabel("你的选择")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedOptionID == option.id && readingMode == .practice
            ? AppTheme.accent.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(height: 0.7)
        }
    }

    private var letterColor: Color {
        guard revealsAnswer else { return AppTheme.accent }
        if answer == option.id { return AppTheme.success }
        if selectedOptionID == option.id { return AppTheme.danger }
        return AppTheme.accent
    }
}

private struct QuestionBankLocalImage: View {
    enum Sizing: String {
        case material
        case stem
        case option
        case overview
    }

    let asset: QuestionBankRecord
    var sizing: Sizing = .material

    @State private var image: UIImage?
    @State private var failedToLoad = false

    var body: some View {
        Group {
            if let image {
                imageView(image)
            } else if failedToLoad {
                Label("图片无法读取", systemImage: "exclamationmark.triangle")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                    .fill(AppTheme.secondaryBackground)
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: 72)
            }
        }
        .task(id: "\(asset.assetRelativePath ?? "")|\(sizing.rawValue)") {
            image = nil
            failedToLoad = false
            guard let url = QuestionBankAssetStore.url(for: asset.assetRelativePath) else {
                failedToLoad = true
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            guard let data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                failedToLoad = true
                return
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                failedToLoad = true
                return
            }
            image = UIImage(cgImage: thumbnail)
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
        case .overview:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 150, maxHeight: 86, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var maximumPixelDimension: Int {
        switch sizing {
        case .material, .stem: 2400
        case .option: 900
        case .overview: 420
        }
    }
}

extension QuestionBankRecord {
    func decoded<Value: Decodable>(_ type: Value.Type) -> Value? {
        try? JSONDecoder().decode(type, from: payload)
    }
}
