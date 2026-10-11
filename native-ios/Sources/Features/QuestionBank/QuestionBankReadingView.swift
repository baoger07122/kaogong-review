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
    let moduleTitle: String?
    let moduleSequence: Int

    var id: String { record.stableID }
    var overviewItem: QuestionBankOverviewItem {
        QuestionBankOverviewItem(
            id: id,
            number: question.number,
            materialID: question.materialID,
            type: QuestionBankQuestionHeading.displayLabel(
                type: question.type,
                subject: question.subject,
                moduleTitle: moduleTitle
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
    @State private var snapshotRevision = 0
    @State private var doodleDrawingCache = QuestionBankDoodleMemoryCache()
    @State private var continuousQuestionDoodleRecordID: String?
    @State private var didApplyInitialFocus = false
    @State private var didApplyAutomaticDataAnalysisSplit = false
    @State private var missingAnswerEditError: String?
    @State private var missingAnswerEditConfirmation: String?
    @State private var showsRedoConfirmation = false
    @SceneStorage private var storedSplitMaterialID: String
    @SceneStorage private var storedQuestionID: String
    @SceneStorage private var storedReadingMode: String
    @AppStorage(QuestionBankReaderPreferences.presentationModeKey)
    private var storedPresentationMode = QuestionBankPresentationMode.continuous.rawValue
    @SceneStorage private var storedSelectedOptionsJSON: String
    @SceneStorage private var storedRevealedAnswersJSON: String
    @AppStorage(QuestionBankAnswerStateStorage.appStorageKey)
    private var storedAnswerStateJSON = QuestionBankAnswerStateStorage.emptyValue
    @AppStorage("question-bank.answer-state-migrated.default")
    private var didMigrateLegacyAnswerState = false
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
            wrappedValue: QuestionBankReadingMode.practice.rawValue,
            "question-bank.mode.v2.\(paperID).\(moduleID)"
        )
        _storedSelectedOptionsJSON = SceneStorage(
            wrappedValue: "{}",
            "question-bank.selected-options.\(paperID).\(moduleID)"
        )
        _storedRevealedAnswersJSON = SceneStorage(
            wrappedValue: "[]",
            "question-bank.revealed-answers.\(paperID).\(moduleID)"
        )
        _didMigrateLegacyAnswerState = AppStorage(
            wrappedValue: false,
            "question-bank.answer-state-migrated.\(paperID).\(moduleID)"
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
        get { QuestionBankReadingMode(rawValue: storedReadingMode) ?? .practice }
        nonmutating set { storedReadingMode = newValue.rawValue }
    }

    private var presentationMode: QuestionBankPresentationMode {
        get { QuestionBankPresentationMode(rawValue: storedPresentationMode) ?? .continuous }
        nonmutating set { storedPresentationMode = newValue.rawValue }
    }

    private var selectedOptionsByQuestionID: [String: String] {
        get { QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON).selectedOptions }
        nonmutating set {
            var state = QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON)
            state.selectedOptions = newValue
            storedAnswerStateJSON = QuestionBankAnswerStateStorage.encode(state)
        }
    }

    private var revealedAnswerQuestionIDs: Set<String> {
        get { QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON).revealedQuestionIDs }
        nonmutating set {
            var state = QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON)
            state.revealedQuestionIDs = newValue
            storedAnswerStateJSON = QuestionBankAnswerStateStorage.encode(state)
        }
    }

    private var readerPosition: QuestionBankReaderPosition {
        QuestionBankReaderPosition(
            presentationMode: presentationMode,
            currentQuestionID: currentVisibleQuestionID,
            splitMaterialID: splitMaterialID
        )
    }

    private var currentSingleItem: QuestionBankReadingItem? {
        let questionID = QuestionBankReaderTransition.displayedQuestionIDs(
            for: .single, currentID: currentVisibleQuestionID, orderedIDs: orderedQuestionIDs
        ).first
        return questionID.flatMap { readingItem(for: $0) } ?? readingItems.first
    }

    private var orderedQuestionIDs: [String] { readingItems.map(\.id) }

    private var singlePositionText: String {
        let ordinal = QuestionBankReaderTransition.ordinal(of: currentVisibleQuestionID, in: orderedQuestionIDs) ?? 1
        return "\(ordinal)/\(orderedQuestionIDs.count)"
    }

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
        .overlay(alignment: .topTrailing) {
            if showsReaderOptions {
                readerOptionsOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsReaderOptions)
        .background(Color.white)
        .navigationTitle(presentationMode == .single ? "" : (module?.title ?? "真题阅读"))
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .secondaryPageTabBarHidden()
        .toolbar {
            if presentationMode == .single {
                ToolbarItem(placement: .principal) {
                    Button {
                        guard let currentSingleItem, !doodleSession.isPresented else { return }
                        activeSheet = QuestionBankReaderSheet(content: .questionDetail(currentSingleItem.id))
                    } label: {
                        Text(singlePositionText)
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(currentSingleItem.map {
                        "打开第\($0.question.number)题详情，当前进度\(singlePositionText)"
                    } ?? "当前题进度")
                    .accessibilityHint("打开当前题目详情")
                    .accessibilityIdentifier("question-bank-single-position")
                    .disabled(currentSingleItem == nil || doodleSession.isPresented)
                }
            }
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
                    onSelect: { handleOverviewSelection($0.overviewItem) }
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
            migrateLegacyAnswerStateIfNeeded()
            refreshReaderSnapshot()
            restoreReaderState()
        }
        .onChange(of: readerRecordRevision) { _, _ in
            invalidateDoodleCache()
            refreshReaderSnapshot()
            restoreReaderState()
        }
        .onChange(of: snapshotRevision) { _, _ in applyInitialFocusIfNeeded() }
        .onChange(of: presentationMode) { _, mode in
            if mode != .continuous { continuousQuestionDoodleRecordID = nil }
        }
        .onChange(of: doodleSession.isPresented) { _, isPresented in
            if !isPresented { continuousQuestionDoodleRecordID = nil }
        }
        .alert("答案更新", isPresented: Binding(
            get: { missingAnswerEditError != nil || missingAnswerEditConfirmation != nil },
            set: {
                if !$0 {
                    missingAnswerEditError = nil
                    missingAnswerEditConfirmation = nil
                }
            }
        )) {
            Button("好", role: .cancel) {
                missingAnswerEditError = nil
                missingAnswerEditConfirmation = nil
            }
        } message: {
            Text(missingAnswerEditError ?? missingAnswerEditConfirmation ?? "")
        }
        .confirmationDialog("重新作答？", isPresented: $showsRedoConfirmation, titleVisibility: .visible) {
            Button("清除整卷作答记录", role: .destructive, action: redoPaperAnswers)
            Button("取消", role: .cancel) { }
        } message: {
            Text("将清除本试卷所有模块的选项和答案揭示状态。涂鸦、题干与选项的手动修改及考试数据会保留。")
        }
    }

    private func readerContent(width: CGFloat, height: CGFloat) -> some View {
        let canOpenSplit = horizontalSizeClass == .regular && width >= 700
        let splitOrientation = QuestionBankSplitLayout.orientation(width: width, height: height)
        return Group {
            if let splitMaterialID, presentationMode == .continuous {
                splitReader(
                    materialID: splitMaterialID,
                    width: width,
                    height: height,
                    orientation: splitOrientation
                )
            } else if presentationMode == .single {
                singleQuestionReader(height: height)
            } else {
                continuousReader(canOpenSplit: canOpenSplit)
            }
        }
        .frame(width: width, height: height)
        .onChange(of: splitOrientation) { _, _ in
            guard presentationMode == .continuous, splitMaterialID != nil,
                  let questionID = currentVisibleQuestionID else { return }
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
        .task(id: "\(snapshotRevision)-\(canOpenSplit)-\(presentationMode.rawValue)") {
            guard canOpenSplit, presentationMode == .continuous,
                  !didApplyAutomaticDataAnalysisSplit, splitMaterialID == nil,
                  QuestionBankCoarseModule.classify(explicitModuleTitle: module?.title) == .dataAnalysis else { return }
            let focusedID = currentVisibleQuestionID ?? initialFocusQuestionID
            guard let item = focusedID.flatMap(readingItem(for:)) ?? readingItems.first,
                  !item.question.materialID.isEmpty,
                  materialsByID[item.question.materialID] != nil else { return }
            didApplyAutomaticDataAnalysisSplit = true
            currentVisibleQuestionID = item.id
            splitMaterialID = item.question.materialID
        }
        .overlay {
            QuestionBankDoodleAutosaveObserver(session: doodleSession, context: modelContext) {
                recordID, drawingData, error in
                guard error == nil else { return }
                cacheDoodleDrawing(drawingData, for: recordID)
            }
        }
        .overlay {
            if presentationMode == .continuous,
               doodleSession.isPresented,
               let recordID = continuousQuestionDoodleRecordID,
               doodleSession.targetRecordID == recordID {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: recordID,
                    minimumCanvasHeight: height
                )
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
                if presentationMode == .single, doodleToolbarTarget != nil {
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
                if presentationMode == .single { questionDoodleToolbarItems }
                redoPaperButton
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
            showsReaderOptions.toggle()
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
    }

    private var redoPaperButton: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            showsRedoConfirmation = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent.opacity(0.86))
        }
        .accessibilityLabel("整卷重新作答")
        .accessibilityHint("清除本试卷所有题目的选择和答案揭示状态")
        .accessibilityIdentifier("question-bank-redo-paper")
        .disabled(doodleSession.isPresented || readingItems.isEmpty)
    }

    private var readerOptionsOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showsReaderOptions = false }
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
                ),
                onDismiss: { showsReaderOptions = false }
            )
            .padding(.top, 6)
            .padding(.trailing, 8)
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
                                        questionSection(
                                            item,
                                            showsDoodleCanvas: false,
                                            showsDoodleButton: true,
                                            showsQuestionType: false
                                        )
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
                .accessibilityIdentifier("question-bank-continuous-scroll")
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
    private func singleQuestionReader(height: CGFloat) -> some View {
        if readingItems.isEmpty {
            emptyModuleState
        } else if let item = currentSingleItem {
            QuestionBankInteractivePageDeck(
                currentID: item.id,
                previousID: QuestionBankReaderTransition.adjacentQuestionID(
                    currentID: item.id, orderedIDs: orderedQuestionIDs, direction: -1
                ),
                nextID: QuestionBankReaderTransition.adjacentQuestionID(
                    currentID: item.id, orderedIDs: orderedQuestionIDs, direction: 1
                ),
                isEnabled: !doodleSession.isPresented,
                onCommit: navigateSingleQuestion(to:)
            ) { pageID, isHorizontalPagingDrag in
                if let pageItem = readingItem(for: pageID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !pageItem.question.materialID.isEmpty,
                               let material = materialsByID[pageItem.question.materialID] {
                                singleMaterialContent(material)
                            }
                            questionSection(
                                pageItem,
                                showsQuestionNumber: false,
                                showsDoodleCanvas: false,
                                showsQuestionType: false
                            )
                        }
                        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .overlay {
                            LibraryDoodleContentLayer(
                                session: doodleSession,
                                targetRecordID: doodleRecordID(for: .question(pageItem.id)),
                                minimumCanvasHeight: height
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented || isHorizontalPagingDrag)
                    .scrollBounceBehavior(.basedOnSize)
                    .coordinateSpace(name: "question-bank-continuous-scroll")
                    .accessibilityIdentifier("question-bank-single-page-scroll")
                } else {
                    Color.clear
                }
            }
        } else {
            emptyModuleState
        }
    }

    private func singleMaterialContent(_ material: QuestionBankMaterial) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(material.type.isEmpty ? "共用材料" : "共用材料 · \(material.type)")
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(AppTheme.accent)
            if !material.text.isEmpty {
                Text(verbatim: material.text)
                    .font(QuestionBankTypography.contentFont)
                    .lineSpacing(QuestionBankTypography.contentLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !material.imageAssetID.isEmpty,
               let asset = assetRecord(for: material.imageAssetID) {
                QuestionBankLocalImage(asset: asset, sizing: .material)
            }
            QuestionBankProvenanceDisclosure(
                title: "材料来源", entries: material.provenance ?? [],
                sourcePapers: paperData?.sourcePapers ?? []
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.35)).frame(height: 1)
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
            .accessibilityIdentifier("question-bank-material-panel-scroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-bank-split-material-pane-\(material.id)")
    }

    private func questionPane(_ groupedQuestions: [QuestionBankReadingItem]) -> some View {
        Group {
            if presentationMode == .single,
               let item = currentVisibleQuestionID.flatMap({ readingItem(for: $0) }) ?? groupedQuestions.first {
                QuestionBankInteractivePageDeck(
                    currentID: item.id,
                    previousID: QuestionBankReaderTransition.adjacentQuestionID(
                        currentID: item.id, orderedIDs: orderedQuestionIDs, direction: -1
                    ),
                    nextID: QuestionBankReaderTransition.adjacentQuestionID(
                        currentID: item.id, orderedIDs: orderedQuestionIDs, direction: 1
                    ),
                    isEnabled: !doodleSession.isPresented,
                    onCommit: navigateSingleQuestion(to:)
                ) { pageID, isHorizontalPagingDrag in
                    if let pageItem = readingItem(for: pageID) {
                        ScrollView {
                            questionSection(
                                pageItem,
                                showsQuestionNumber: false,
                                showsDoodleCanvas: false,
                                showsQuestionType: false
                            )
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.white)
                        .scrollDisabled(doodleSession.isPresented || isHorizontalPagingDrag)
                        .scrollBounceBehavior(.basedOnSize)
                        .coordinateSpace(name: "question-bank-continuous-scroll")
                    } else {
                        Color.clear
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groupedQuestions) { item in
                                questionSection(
                                    item,
                                    showsDoodleCanvas: false,
                                    showsDoodleButton: true,
                                    showsQuestionType: false
                                )
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented)
                    .coordinateSpace(name: "question-bank-continuous-scroll")
                    .accessibilityIdentifier("question-bank-continuous-scroll")
                    .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                    .onChange(of: splitScrollRequest) { _, request in
                        guard let request else { return }
                        let target = groupedQuestions.first(where: { $0.id == request.questionID })?.id
                            ?? groupedQuestions.first?.id
                        guard let target else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                    .onAppear {
                        let preferred = currentVisibleQuestionID
                        let target = groupedQuestions.first(where: { $0.id == preferred })?.id
                            ?? groupedQuestions.first(where: { $0.id == splitScrollRequest?.questionID })?.id
                            ?? groupedQuestions.first?.id
                        guard let target else { return }
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-bank-split-question-pane")
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
        showsQuestionNumber: Bool = true,
        showsDoodleCanvas: Bool = true,
        showsDoodleButton: Bool = false,
        showsQuestionType: Bool = true
    ) -> some View {
        let answerStateID = item.record.compoundID
        let selectedOptionID = selectedOptionsByQuestionID[answerStateID]
        let hasAnswer = !item.question.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let revealsAnswer = readingMode.revealsAnswer(
            afterSelecting: selectedOptionID,
            wasConfirmed: revealedAnswerQuestionIDs.contains(answerStateID),
            requiresConfirmation: requiresAnswerConfirmation
        )
        let heading = showsQuestionType ? QuestionBankQuestionHeading.displayLabel(
            type: item.question.type,
            subject: item.question.subject,
            moduleTitle: item.moduleTitle
        ) : nil
        return VStack(alignment: .leading, spacing: 0) {
            if showsQuestionNumber || heading != nil {
                HStack(spacing: 8) {
                    if showsQuestionNumber { questionNumberButton(for: item) }
                    if let heading {
                        Text(heading)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if showsDoodleButton {
                        Button { openQuestionDoodle(item) } label: {
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 16, weight: .regular))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("标注第\(item.question.number)题")
                        .accessibilityHint("仅标注这道题")
                        .accessibilityIdentifier("question-bank-doodle-question-\(item.id)")
                        .disabled(doodleSession.isPresented)
                    }
                }
                .padding(.bottom, 7)
            }

            VStack(alignment: .leading, spacing: 0) {
                QuestionBankQuestionAnnotationBadges(question: item.question)
                if !item.question.stem.isEmpty {
                    Text(verbatim: item.question.stem)
                        .font(QuestionBankTypography.contentFont)
                        .lineSpacing(QuestionBankTypography.contentLineSpacing)
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
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    questionID: item.id,
                    option: option,
                    answer: item.question.answer,
                    readingMode: readingMode,
                    selectedOptionID: selectedOptionID,
                    revealsAnswer: revealsAnswer,
                    isSelectionLocked: readingMode == .practice && selectedOptionID != nil,
                    isInteractionBlocked: doodleSession.isPresented,
                    onSelect: { selectOption(option.id, for: answerStateID) },
                    assetLookup: assetRecord(for:)
                )
            }

            if readingMode == .reading, hasAnswer {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                    Text("正确答案")
                        .foregroundStyle(.secondary)
                    Text(item.question.answer.isEmpty ? "未提供" : item.question.answer)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.success)
                }
                .font(QuestionBankTypography.contentFont)
                .padding(.top, 12)
            } else if readingMode == .practice {
                if revealsAnswer, let selectedOptionID, hasAnswer {
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
                            confirmAnswer(for: answerStateID)
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
            if !hasAnswer {
                QuestionBankMissingAnswerMenu(questionID: item.id, options: item.question.options) { answer in
                    setMissingAnswer(answer, for: item)
                }
                .padding(.top, 10)
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
            if showsDoodleCanvas {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: doodleRecordID(for: .question(item.id)),
                    minimumCanvasHeight: 0
                )
            }
        }
        .id(item.id)
    }

    private func questionNumberButton(for item: QuestionBankReadingItem) -> some View {
        Button {
            guard !doodleSession.isPresented else { return }
            activeSheet = QuestionBankReaderSheet(content: .questionDetail(item.id))
        } label: {
            Text("\(item.question.number).")
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开第\(item.question.number)题详情")
        .accessibilityHint("查看题干、选项和解析")
        .accessibilityIdentifier("question-bank-question-detail-\(item.id)")
        .disabled(doodleSession.isPresented)
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
            questionSection(item, showsQuestionNumber: false)
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
        QuestionBankQuestionDetailPanel(
            question: item.question,
            title: "第\(item.question.number)题详情",
            isDoodlePresented: doodleSession.isPresented,
            onDone: { activeSheet = nil },
            onClearAnswer: { clearAnswer(for: item.record.compoundID) },
            onSave: { stem, optionTexts, annotations in
                try QuestionBankRepository.updateQuestionText(
                    paperID: paperID,
                    questionID: item.question.id,
                    stem: stem,
                    optionTexts: optionTexts,
                    annotations: annotations,
                    records: records,
                    context: modelContext
                )
            }
        ) {
            ScrollView {
                questionDetailContent(item)
            }
            .coordinateSpace(name: "question-bank-continuous-scroll")
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .scrollDisabled(doodleSession.isPresented)
        }
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
                    .accessibilityIdentifier("question-bank-material-panel-scroll")
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
        guard mode != presentationMode else {
            showsReaderOptions = false
            return
        }
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
        showsReaderOptions = false
    }

    private func migrateLegacyAnswerStateIfNeeded() {
        guard !didMigrateLegacyAnswerState else { return }
        let questionStateIDs = Dictionary(
            records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind }
                .map { ($0.stableID, $0.compoundID) },
            uniquingKeysWith: { first, _ in first }
        )
        let oldSelections = QuestionBankSelectedOptionsStorage.decode(storedSelectedOptionsJSON)
        let migratedSelections = Dictionary(oldSelections.map { key, value in
            (questionStateIDs[key] ?? key, value)
        }, uniquingKeysWith: { first, _ in first })
        let oldRevealed = QuestionBankRevealedAnswersStorage.decode(storedRevealedAnswersJSON)
        let migratedRevealed = QuestionBankRevealedAnswersStorage.encode(Set(
            oldRevealed.map { questionStateIDs[$0] ?? $0 }
        ))
        storedAnswerStateJSON = QuestionBankAnswerStateStorage.migratingLegacyState(
            selectedOptionsJSON: QuestionBankSelectedOptionsStorage.encode(migratedSelections),
            revealedAnswersJSON: migratedRevealed,
            into: storedAnswerStateJSON
        )
        storedSelectedOptionsJSON = "{}"
        storedRevealedAnswersJSON = "[]"
        didMigrateLegacyAnswerState = true
    }

    private func redoPaperAnswers() {
        storedAnswerStateJSON = QuestionBankAnswerStateStorage.clearing(
            QuestionBankRedoScope.questionIDs(inPaper: paperID, records: records),
            from: storedAnswerStateJSON
        )
    }

    private func clearAnswer(for questionID: String) {
        storedAnswerStateJSON = QuestionBankAnswerStateStorage.clearing(
            [questionID], from: storedAnswerStateJSON
        )
    }

    private func navigateSingleQuestion(to targetID: String) {
        guard presentationMode == .single, !doodleSession.isPresented else { return }
        guard let target = readingItem(for: targetID) else { return }

        let hadSplitMaterial = splitMaterialID != nil
        let position = QuestionBankReaderTransition.movingToQuestion(
            targetID,
            materialID: target.question.materialID.isEmpty ? nil : target.question.materialID,
            availableMaterialIDs: Set(materialsByID.keys),
            from: readerPosition
        )
        applyReaderPosition(position)
        continuousAnchorQuestionID = targetID

        if hadSplitMaterial, position.splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: targetID, token: UUID())
        }
    }

    private func selectOption(_ optionID: String, for questionID: String) {
        guard !doodleSession.isPresented,
              readingMode == .practice,
              !revealedAnswerQuestionIDs.contains(questionID) else { return }
        guard selectedOptionsByQuestionID[questionID] == nil else { return }
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

    private func setMissingAnswer(_ answer: String, for item: QuestionBankReadingItem) {
        do {
            try QuestionBankRepository.setMissingAnswer(
                paperID: paperID,
                questionID: item.question.id,
                answer: answer,
                records: records,
                context: modelContext
            )
            missingAnswerEditConfirmation = "答案已补录为 \(answer)。"
        } catch {
            missingAnswerEditError = error.localizedDescription
            missingAnswerEditConfirmation = nil
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
        continuousQuestionDoodleRecordID = nil
        presentDoodle(for: .material(materialID))
    }

    private func openQuestionDoodle(_ item: QuestionBankReadingItem) {
        guard !doodleSession.isPresented else { return }
        continuousQuestionDoodleRecordID = presentationMode == .continuous
            ? doodleRecordID(for: .question(item.id))
            : nil
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
                return QuestionBankReadingItem(
                    record: record,
                    question: question,
                    moduleTitle: module?.title,
                    moduleSequence: module?.sequence ?? Int.max
                )
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

private struct QuestionBankCrossPaperDetailRoute: Identifiable {
    let questionID: String
    var id: String { questionID }
}

struct QuestionBankCrossPaperReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @Query private var records: [QuestionBankRecord]

    let filter: QuestionBankHomeFilter
    let paperID: String?

    @AppStorage(QuestionBankReaderPreferences.presentationModeKey)
    private var storedPresentationMode = QuestionBankPresentationMode.continuous.rawValue
    @State private var readingMode: QuestionBankReadingMode = .practice
    @State private var currentQuestionID: String?
    @State private var activeQuestionDetail: QuestionBankCrossPaperDetailRoute?
    @State private var groups: [QuestionBankCrossPaperGroup] = []
    @State private var showsReaderOptions = false
    @State private var showsOverview = false
    @State private var continuousQuestionDoodleRecordID: String?
    @State private var missingAnswerEditError: String?
    @State private var missingAnswerEditConfirmation: String?
    @State private var showsRedoConfirmation = false
    @SceneStorage private var selectedOptionsJSON: String
    @SceneStorage private var revealedAnswersJSON: String
    @AppStorage(QuestionBankAnswerStateStorage.appStorageKey)
    private var storedAnswerStateJSON = QuestionBankAnswerStateStorage.emptyValue
    @AppStorage("question-bank.scope.answer-state-migrated.default")
    private var didMigrateLegacyAnswerState = false
    @AppStorage(QuestionBankReaderPreferences.confirmAnswerAfterSelectionKey)
    private var requiresAnswerConfirmation = false

    init(filter: QuestionBankHomeFilter, paperID: String? = nil) {
        self.filter = filter
        self.paperID = paperID
        let scope = [
            filter.module?.rawValue ?? "", filter.questionType, filter.year, filter.examType,
            filter.province, filter.search, filter.questionNumber,
            String(filter.difficultOnly), String(filter.needsReviewOnly),
            filter.knowledgePoint, filter.weaknessTag, paperID ?? "all"
        ].joined(separator: "|")
        let key = Data(scope.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        _selectedOptionsJSON = SceneStorage(wrappedValue: "{}", "question-bank.scope.selected-options.\(key)")
        _revealedAnswersJSON = SceneStorage(wrappedValue: "[]", "question-bank.scope.revealed-answers.\(key)")
        _didMigrateLegacyAnswerState = AppStorage(
            wrappedValue: false,
            "question-bank.scope.answer-state-migrated.\(key)"
        )
    }

    private var index: QuestionBankHomeIndex { QuestionBankHomeIndex(records: records) }

    private var presentationMode: QuestionBankPresentationMode {
        get { QuestionBankPresentationMode(rawValue: storedPresentationMode) ?? .continuous }
        nonmutating set { storedPresentationMode = newValue.rawValue }
    }

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

    private var overviewGroups: [QuestionBankOverviewGroup] {
        let paperTitles = Dictionary(
            index.papers.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        return QuestionBankOverviewGrouping.groups(from: orderedItems.map { item in
            QuestionBankOverviewCandidate(
                id: item.id,
                paperID: item.record.paperID,
                paperTitle: paperTitles[item.record.paperID] ?? "未命名试卷",
                questionNumber: item.question.number,
                moduleID: item.moduleID ?? item.question.moduleID,
                moduleTitle: item.moduleTitle ?? "",
                moduleSequence: item.moduleSequence,
                type: item.question.type,
                subject: item.question.subject
            )
        })
    }

    private var currentItem: QuestionBankHomeQuestion? {
        orderedItems.first { $0.id == currentQuestionID } ?? orderedItems.first
    }

    private var singlePositionText: String {
        let ids = orderedItems.map(\.id)
        let ordinal = QuestionBankReaderTransition.ordinal(of: currentQuestionID, in: ids) ?? 1
        return "\(ordinal)/\(ids.count)"
    }

    private var selectedOptionsByQuestionID: [String: String] {
        get { QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON).selectedOptions }
        nonmutating set {
            var state = QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON)
            state.selectedOptions = newValue
            storedAnswerStateJSON = QuestionBankAnswerStateStorage.encode(state)
        }
    }

    private var revealedAnswerQuestionIDs: Set<String> {
        get { QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON).revealedQuestionIDs }
        nonmutating set {
            var state = QuestionBankAnswerStateStorage.decode(storedAnswerStateJSON)
            state.revealedQuestionIDs = newValue
            storedAnswerStateJSON = QuestionBankAnswerStateStorage.encode(state)
        }
    }

    var body: some View {
        readerScreen
            .onAppear {
                migrateLegacyAnswerStateIfNeeded()
                refreshGroups()
                if currentQuestionID == nil { currentQuestionID = orderedItems.first?.id }
            }
            .onChange(of: readerRecordRevision) { _, _ in refreshGroups() }
            .onChange(of: presentationMode) { _, mode in
                if mode != .continuous { continuousQuestionDoodleRecordID = nil }
            }
            .onChange(of: doodleSession.isPresented) { _, isPresented in
                if !isPresented { continuousQuestionDoodleRecordID = nil }
            }
            .alert("答案更新", isPresented: Binding(
                get: { missingAnswerEditError != nil || missingAnswerEditConfirmation != nil },
                set: {
                    if !$0 {
                        missingAnswerEditError = nil
                        missingAnswerEditConfirmation = nil
                    }
                }
            )) {
                Button("好", role: .cancel) {
                    missingAnswerEditError = nil
                    missingAnswerEditConfirmation = nil
                }
            } message: {
                Text(missingAnswerEditError ?? missingAnswerEditConfirmation ?? "")
            }
            .confirmationDialog("重新作答？", isPresented: $showsRedoConfirmation, titleVisibility: .visible) {
                Button("清除当前题组作答记录", role: .destructive, action: redoCurrentGroupAnswers)
                Button("取消", role: .cancel) { }
            } message: {
                Text("将清除当前筛选题组的选项和答案揭示状态。涂鸦、题干与选项的手动修改及考试数据会保留。")
            }
    }

    private var readerScreen: some View {
        GeometryReader { geometry in
            readerPage(width: geometry.size.width, height: geometry.size.height)
        }
        .overlay(alignment: .topTrailing) {
            if showsReaderOptions {
                readerOptionsOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsReaderOptions)
        .background(Color.white)
        .navigationTitle(presentationMode == .single ? "" : (paperTitle ?? filter.module?.rawValue ?? "多卷题目"))
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .secondaryPageTabBarHidden()
        .toolbar { readerToolbar }
        .sheet(isPresented: $showsOverview) { questionOverviewSheet }
        .sheet(item: $activeQuestionDetail) { questionDetailSheet(for: $0) }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
            if presentationMode == .single {
                ToolbarItem(placement: .principal) {
                    Button {
                        guard let currentItem, !doodleSession.isPresented else { return }
                        activeQuestionDetail = QuestionBankCrossPaperDetailRoute(questionID: currentItem.id)
                    } label: {
                        Text(singlePositionText)
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(currentItem.map {
                        "打开第\($0.question.number)题详情，当前进度\(singlePositionText)"
                    } ?? "当前题进度")
                    .accessibilityHint("打开当前题目详情")
                    .accessibilityIdentifier("question-bank-single-position")
                    .disabled(currentItem == nil || doodleSession.isPresented)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if presentationMode == .single { doodleButton }
                    redoCurrentGroupButton
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

    private var questionOverviewSheet: some View {
            NavigationStack {
                List {
                    ForEach(overviewGroups) { group in
                        Section {
                            ForEach(group.questions) { candidate in
                                Button {
                                    presentationMode = .single
                                    currentQuestionID = candidate.id
                                    showsOverview = false
                                } label: {
                                    HStack {
                                        Text("第\(candidate.questionNumber)题")
                                        Spacer()
                                        if let item = orderedItems.first(where: { $0.id == candidate.id }),
                                           let heading = QuestionBankQuestionHeading.displayLabel(
                                            type: item.question.type,
                                            subject: item.question.subject,
                                            moduleTitle: item.moduleTitle
                                        ) {
                                            Text(heading).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityLabel("\(group.moduleTitle)，第\(candidate.questionNumber)题")
                                .accessibilityIdentifier("question-bank-cross-paper-overview-\(candidate.id)")
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 3) {
                                if paperID == nil {
                                    Text(group.paperTitle)
                                        .font(AppTheme.auxiliaryFont)
                                }
                                HStack(spacing: 6) {
                                    Text(group.moduleTitle)
                                    if let type = group.coarseQuestionType {
                                        Text(type)
                                    }
                                }
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
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

    @ViewBuilder
    private func questionDetailSheet(for route: QuestionBankCrossPaperDetailRoute) -> some View {
        if let item = orderedItems.first(where: { $0.id == route.questionID }),
           let group = groups.first(where: { $0.paperID == item.record.paperID }) {
            QuestionBankQuestionDetailPanel(
                question: item.question,
                title: "第\(item.question.number)题详情",
                isDoodlePresented: doodleSession.isPresented,
                onDone: { activeQuestionDetail = nil },
                onClearAnswer: { clearAnswer(for: item.record.compoundID) },
                onSave: { stem, optionTexts, annotations in
                    try QuestionBankRepository.updateQuestionText(
                        paperID: item.record.paperID,
                        questionID: item.question.id,
                        stem: stem,
                        optionTexts: optionTexts,
                        annotations: annotations,
                        records: records,
                        context: modelContext
                    )
                }
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let material = group.materialsByID[item.question.materialID] {
                            materialSection(
                                material,
                                paperID: group.paperID,
                                sourcePapers: group.sourcePapers
                            )
                        }
                        questionSection(
                            item,
                            group: group,
                            showsPaperHeading: false,
                            showsQuestionNumber: false,
                            showsDoodleCanvas: false
                        )
                        QuestionBankProvenanceDisclosure(
                            title: "题目来源",
                            entries: item.question.provenance ?? [],
                            sourcePapers: group.sourcePapers
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented)
                .coordinateSpace(name: "question-bank-cross-paper-scroll")
            }
        } else {
            ContentUnavailableView("题目不存在", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func readerPage(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if presentationMode == .single, let item = currentItem {
                singleReader(item, pageHeight: height)
            } else {
                continuousReader
            }
        }
        .frame(width: width, height: height)
        .overlay { continuousQuestionDoodleLayer(height: height) }
    }

    @ViewBuilder
    private func continuousQuestionDoodleLayer(height: CGFloat) -> some View {
        if presentationMode == .continuous,
           doodleSession.isPresented,
           let recordID = continuousQuestionDoodleRecordID,
           doodleSession.targetRecordID == recordID {
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: recordID,
                minimumCanvasHeight: height
            )
        }
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
            showsReaderOptions.toggle()
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
    }

    private var redoCurrentGroupButton: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            showsRedoConfirmation = true
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent.opacity(0.86))
        }
        .accessibilityLabel("当前题组重新作答")
        .accessibilityHint("清除当前筛选题组所有题目的选择和答案揭示状态")
        .accessibilityIdentifier("question-bank-redo-filtered-group")
        .disabled(doodleSession.isPresented || orderedItems.isEmpty)
    }

    private var readerOptionsOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showsReaderOptions = false }
            QuestionBankReaderOptionsPopover(
                presentationMode: Binding(
                    get: { presentationMode },
                    set: {
                        presentationMode = $0
                        showsReaderOptions = false
                    }
                ),
                readingMode: Binding(
                    get: { readingMode },
                    set: {
                        readingMode = $0
                        showsReaderOptions = false
                    }
                ),
                requiresAnswerConfirmation: Binding(
                    get: { requiresAnswerConfirmation },
                    set: { setAnswerConfirmationEnabled($0) }
                ),
                onDismiss: { showsReaderOptions = false }
            )
            .padding(.top, 6)
            .padding(.trailing, 8)
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
                                questionSection(
                                    item,
                                    group: group,
                                    showsPaperHeading: false,
                                    showsDoodleCanvas: false,
                                    showsDoodleButton: true,
                                    showsQuestionType: false
                                )
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
        .onPreferenceChange(QuestionBankReaderViewportPreference.self) { frames in
            let visible = frames.filter { $0.value.bottom > 0 }
                .min { abs($0.value.top) < abs($1.value.top) }
            if let visible { currentQuestionID = visible.key }
        }
    }

    private func singleReader(_ item: QuestionBankHomeQuestion, pageHeight: CGFloat) -> some View {
        let ids = orderedItems.map(\.id)
        return QuestionBankInteractivePageDeck(
            currentID: item.id,
            previousID: QuestionBankReaderTransition.adjacentQuestionID(
                currentID: item.id, orderedIDs: ids, direction: -1
            ),
            nextID: QuestionBankReaderTransition.adjacentQuestionID(
                currentID: item.id, orderedIDs: ids, direction: 1
            ),
            isEnabled: !doodleSession.isPresented,
            onCommit: moveQuestion(to:)
        ) { pageID, isHorizontalPagingDrag in
            if let pageItem = orderedItems.first(where: { $0.id == pageID }),
               let group = groups.first(where: { $0.paperID == pageItem.record.paperID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if group.questions.first?.id == pageItem.id {
                            paperDivider(group.title, count: group.questions.count)
                        }
                        if !pageItem.question.materialID.isEmpty,
                           let material = group.materialsByID[pageItem.question.materialID] {
                            materialSection(material, paperID: group.paperID, sourcePapers: group.sourcePapers)
                        }
                        questionSection(
                            pageItem,
                            group: group,
                            showsPaperHeading: false,
                            showsQuestionNumber: false,
                            showsDoodleCanvas: false,
                            showsQuestionType: false
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: pageHeight, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .overlay {
                        LibraryDoodleContentLayer(
                            session: doodleSession,
                            targetRecordID: QuestionBankDoodleRepository.recordID(
                                paperID: pageItem.record.paperID,
                                scope: .question(pageItem.question.id)
                            ),
                            minimumCanvasHeight: pageHeight
                        )
                    }
                }
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented || isHorizontalPagingDrag)
                .scrollBounceBehavior(.basedOnSize)
                .coordinateSpace(name: "question-bank-cross-paper-scroll")
                .accessibilityIdentifier("question-bank-single-page-scroll")
            } else {
                Color.clear
            }
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
                    .font(QuestionBankTypography.contentFont)
                    .lineSpacing(QuestionBankTypography.contentLineSpacing)
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
        showsPaperHeading: Bool,
        showsQuestionNumber: Bool = true,
        showsDoodleCanvas: Bool = true,
        showsDoodleButton: Bool = false,
        showsQuestionType: Bool = true
    ) -> some View {
        let answerStateID = item.record.compoundID
        let selected = selectedOptionsByQuestionID[answerStateID]
        let hasAnswer = !item.question.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let reveals = readingMode.revealsAnswer(
            afterSelecting: selected,
            wasConfirmed: revealedAnswerQuestionIDs.contains(answerStateID),
            requiresConfirmation: requiresAnswerConfirmation
        )
        let heading = showsQuestionType ? QuestionBankQuestionHeading.displayLabel(
            type: item.question.type,
            subject: item.question.subject,
            moduleTitle: item.moduleTitle
        ) : nil
        return VStack(alignment: .leading, spacing: 8) {
            if showsPaperHeading, group.questions.first?.id == item.id {
                paperDivider(group.title, count: group.questions.count)
            }
            if showsQuestionNumber || heading != nil {
                HStack(spacing: 8) {
                    if showsQuestionNumber { questionNumberButton(for: item) }
                    if let heading {
                        Text(heading)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if showsDoodleButton {
                        Button { presentDoodle(for: item) } label: {
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 16, weight: .regular))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("标注第\(item.question.number)题")
                        .accessibilityHint("仅标注这道题")
                        .accessibilityIdentifier("question-bank-doodle-question-\(item.id)")
                        .disabled(doodleSession.isPresented)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                QuestionBankQuestionAnnotationBadges(question: item.question)
                if !item.question.stem.isEmpty {
                    Text(verbatim: item.question.stem)
                        .font(QuestionBankTypography.contentFont)
                        .lineSpacing(QuestionBankTypography.contentLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.question.stemImageAssetID.isEmpty,
                   let asset = assetRecord(for: item.question.stemImageAssetID, paperID: item.record.paperID) {
                    QuestionBankLocalImage(asset: asset, sizing: .stem)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    questionID: item.question.id,
                    option: option,
                    answer: item.question.answer,
                    readingMode: readingMode,
                    selectedOptionID: selected,
                    revealsAnswer: reveals,
                    isSelectionLocked: readingMode == .practice && selected != nil,
                    isInteractionBlocked: doodleSession.isPresented,
                    onSelect: { selectOption(option.id, item: item) },
                    assetLookup: { assetRecord(for: $0, paperID: item.record.paperID) }
                )
            }
            if readingMode == .reading, hasAnswer {
                Label("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)", systemImage: "checkmark.circle.fill")
                    .font(QuestionBankTypography.contentFont)
                    .foregroundStyle(AppTheme.success)
                    .padding(.top, 6)
            } else if reveals, let selected, hasAnswer {
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
                    Button("确认答案") { confirmAnswer(for: answerStateID) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected == nil || doodleSession.isPresented)
                        .accessibilityLabel("确认答案并查看正确选项")
                        .accessibilityIdentifier("question-bank-confirm-answer-\(item.id)")
                }
                .padding(.top, 6)
            }
            if !hasAnswer {
                QuestionBankMissingAnswerMenu(questionID: item.id, options: item.question.options) { answer in
                    setMissingAnswer(answer, for: item)
                }
                .padding(.top, 4)
            }
            if let material = group.materialsByID[item.question.materialID] {
                QuestionBankProvenanceDisclosure(
                    title: "材料来源", entries: material.provenance ?? [], sourcePapers: group.sourcePapers
                )
            }
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
            if showsDoodleCanvas {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: QuestionBankDoodleRepository.recordID(
                        paperID: item.record.paperID, scope: .question(item.question.id)
                    ),
                    minimumCanvasHeight: 0
                )
            }
        }
        .id(item.id)
    }

    private func questionNumberButton(for item: QuestionBankHomeQuestion) -> some View {
        Button {
            guard !doodleSession.isPresented else { return }
            activeQuestionDetail = QuestionBankCrossPaperDetailRoute(questionID: item.id)
        } label: {
            Text("\(item.question.number).")
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开第\(item.question.number)题详情")
        .accessibilityHint("查看题干、选项和解析")
        .accessibilityIdentifier("question-bank-question-detail-\(item.id)")
        .disabled(doodleSession.isPresented)
    }

    private func moveQuestion(to target: String) {
        guard !doodleSession.isPresented,
              orderedItems.contains(where: { $0.id == target }) else { return }
        currentQuestionID = target
    }

    private func migrateLegacyAnswerStateIfNeeded() {
        guard !didMigrateLegacyAnswerState else { return }
        let legacyQuestionIDs = Dictionary(records
            .filter { $0.kind == QuestionBankRepository.questionKind }
            .map { ($0.compoundID, $0.compoundID) },
            uniquingKeysWith: { first, _ in first }
        )
        let oldSelections = QuestionBankSelectedOptionsStorage.decode(selectedOptionsJSON)
        let migratedSelections = Dictionary(oldSelections.map { key, value in
            (legacyQuestionIDs[key] ?? key, value)
        }, uniquingKeysWith: { first, _ in first })
        let oldRevealed = QuestionBankRevealedAnswersStorage.decode(revealedAnswersJSON)
        let migratedRevealed = QuestionBankRevealedAnswersStorage.encode(Set(
            oldRevealed.map { legacyQuestionIDs[$0] ?? $0 }
        ))
        storedAnswerStateJSON = QuestionBankAnswerStateStorage.migratingLegacyState(
            selectedOptionsJSON: QuestionBankSelectedOptionsStorage.encode(migratedSelections),
            revealedAnswersJSON: migratedRevealed,
            into: storedAnswerStateJSON
        )
        selectedOptionsJSON = "{}"
        revealedAnswersJSON = "[]"
        didMigrateLegacyAnswerState = true
    }

    private func redoCurrentGroupAnswers() {
        storedAnswerStateJSON = QuestionBankAnswerStateStorage.clearing(
            QuestionBankRedoScope.questionIDs(inCurrentGroup: orderedItems),
            from: storedAnswerStateJSON
        )
    }

    private func clearAnswer(for questionID: String) {
        storedAnswerStateJSON = QuestionBankAnswerStateStorage.clearing(
            [questionID], from: storedAnswerStateJSON
        )
    }

    private func selectOption(_ optionID: String, item: QuestionBankHomeQuestion) {
        let answerStateID = item.record.compoundID
        guard !doodleSession.isPresented, readingMode == .practice,
              !revealedAnswerQuestionIDs.contains(answerStateID) else { return }
        guard selectedOptionsByQuestionID[answerStateID] == nil else { return }
        var selected = selectedOptionsByQuestionID
        selected[answerStateID] = optionID
        selectedOptionsByQuestionID = selected
        if !requiresAnswerConfirmation {
            var revealed = revealedAnswerQuestionIDs
            revealed.insert(answerStateID)
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
        guard !doodleSession.isPresented, selectedOptionsByQuestionID[questionID] != nil else { return }
        var revealed = revealedAnswerQuestionIDs
        revealed.insert(questionID)
        revealedAnswerQuestionIDs = revealed
    }

    private func setMissingAnswer(_ answer: String, for item: QuestionBankHomeQuestion) {
        do {
            try QuestionBankRepository.setMissingAnswer(
                paperID: item.record.paperID,
                questionID: item.question.id,
                answer: answer,
                records: records,
                context: modelContext
            )
            missingAnswerEditConfirmation = "答案已补录为 \(answer)。"
        } catch {
            missingAnswerEditError = error.localizedDescription
            missingAnswerEditConfirmation = nil
        }
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
        guard !doodleSession.isPresented else { return }
        continuousQuestionDoodleRecordID = presentationMode == .continuous ? recordID : nil
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
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(overviewGroups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    groupHeading(group)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 7)], spacing: 7) {
                                        ForEach(group.questions) { candidate in
                                            if let item = itemsByID[candidate.id] { numberButton(item) }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(overviewGroups) { group in
                                groupHeading(group)
                                ForEach(group.questions) { candidate in
                                    if let item = itemsByID[candidate.id] { cardButton(item) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .navigationTitle("题目总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var itemsByID: [String: QuestionBankReadingItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var overviewGroups: [QuestionBankOverviewGroup] {
        QuestionBankOverviewGrouping.groups(from: items.map { item in
            QuestionBankOverviewCandidate(
                id: item.id,
                paperID: item.record.paperID,
                paperTitle: item.record.title ?? "",
                questionNumber: item.question.number,
                moduleID: item.question.moduleID,
                moduleTitle: item.moduleTitle ?? "",
                moduleSequence: item.moduleSequence,
                type: item.question.type,
                subject: item.question.subject
            )
        })
    }

    private func groupHeading(_ group: QuestionBankOverviewGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.moduleTitle)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(.primary)
            if let type = group.coarseQuestionType {
                Text(type)
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("question-bank-overview-group-\(group.id)")
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
        return Button {
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
        .buttonStyle(.plain)
        .accessibilityLabel("第\(String(overview.number))题\(headingDescription)")
        .accessibilityIdentifier("question-bank-overview-item-\(item.id)")
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
                    .font(QuestionBankTypography.contentFont)
                    .lineSpacing(QuestionBankTypography.contentLineSpacing)
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

private struct QuestionBankQuestionDetailPanel<Content: View>: View {
    let question: QuestionBankQuestion
    let title: String
    let isDoodlePresented: Bool
    let onDone: () -> Void
    let onClearAnswer: () -> Void
    let onSave: (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void
    private let content: Content
    @State private var showsTextEditor = false
    @State private var showsClearAnswerConfirmation = false

    init(
        question: QuestionBankQuestion,
        title: String,
        isDoodlePresented: Bool,
        onDone: @escaping () -> Void,
        onClearAnswer: @escaping () -> Void,
        onSave: @escaping (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.question = question
        self.title = title
        self.isDoodlePresented = isDoodlePresented
        self.onDone = onDone
        self.onClearAnswer = onClearAnswer
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("编辑题目") { showsTextEditor = true }
                            .accessibilityIdentifier("question-bank-edit-question")
                            .disabled(isDoodlePresented)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button("清除本题作答记录", role: .destructive) {
                                showsClearAnswerConfirmation = true
                            }
                            .accessibilityIdentifier("question-bank-clear-question-answer")
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("题目操作")
                        .accessibilityIdentifier("question-bank-question-actions")
                        .disabled(isDoodlePresented)
                        Button("完成", action: onDone)
                    }
                }
                .sheet(isPresented: $showsTextEditor) {
                    QuestionBankQuestionTextEditor(question: question, onSave: onSave)
                }
                .confirmationDialog(
                    "清除本题作答记录？",
                    isPresented: $showsClearAnswerConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("清除本题作答记录", role: .destructive, action: onClearAnswer)
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("将清除本题已选选项和答案揭示状态，涂鸦及题目文字修改会保留。")
                }
        }
        .presentationDetents([.large])
    }
}

private struct QuestionBankQuestionTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    let question: QuestionBankQuestion
    let onSave: (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void
    @State private var stem: String
    @State private var optionTexts: [String: String]
    @State private var isDifficult: Bool
    @State private var needsReview: Bool
    @State private var knowledgePointsText: String
    @State private var weaknessTagsText: String
    @State private var saveError: String?

    init(
        question: QuestionBankQuestion,
        onSave: @escaping (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void
    ) {
        self.question = question
        self.onSave = onSave
        _stem = State(initialValue: question.stem)
        let annotations = QuestionBankQuestionAnnotations(question: question)
        _isDifficult = State(initialValue: annotations.isDifficult)
        _needsReview = State(initialValue: annotations.needsReview)
        _knowledgePointsText = State(initialValue: annotations.knowledgePoints.joined(separator: "、"))
        _weaknessTagsText = State(initialValue: annotations.weaknessTags.joined(separator: "、"))
        _optionTexts = State(initialValue: Dictionary(
            question.options.map { ($0.id, $0.text) },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("题干") {
                    TextEditor(text: $stem)
                        .frame(minHeight: 150)
                        .accessibilityIdentifier("question-bank-edit-stem")
                }
                Section {
                    ForEach(question.options) { option in
                        HStack(alignment: .top, spacing: 10) {
                            Text(option.id)
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 34, height: 30)
                                .background(AppTheme.accent.opacity(0.10), in: Capsule())
                            TextField("", text: optionBinding(for: option.id), axis: .vertical)
                                .lineLimit(1...6)
                                .font(QuestionBankTypography.contentFont)
                                .padding(.vertical, 5)
                                .accessibilityLabel("选项 \(option.id)")
                                .accessibilityIdentifier("question-bank-edit-option-\(option.id)")
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .accessibilityElement(children: .contain)
                    }
                }
                Section("标记与知识点") {
                    Toggle("难题", isOn: $isDifficult)
                        .accessibilityIdentifier("question-bank-edit-difficult")
                    Toggle("待复习", isOn: $needsReview)
                        .accessibilityIdentifier("question-bank-edit-needs-review")
                    TextField("知识点，用顿号分隔", text: $knowledgePointsText)
                        .accessibilityIdentifier("question-bank-edit-knowledge-points")
                    TextField("弱项标签，用顿号分隔", text: $weaknessTagsText)
                        .accessibilityIdentifier("question-bank-edit-weakness-tags")
                }
            }
            .navigationTitle("编辑题目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier("question-bank-save-question-text")
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func optionBinding(for optionID: String) -> Binding<String> {
        Binding(
            get: { optionTexts[optionID] ?? "" },
            set: { optionTexts[optionID] = $0 }
        )
    }

    private func save() {
        do {
            let originalOptionTexts = Dictionary(
                question.options.map { ($0.id, $0.text) },
                uniquingKeysWith: { first, _ in first }
            )
            let editedOptionTexts = optionTexts.filter { originalOptionTexts[$0.key] != $0.value }
            try onSave(
                stem,
                editedOptionTexts,
                QuestionBankQuestionAnnotations(
                    isDifficult: isDifficult,
                    needsReview: needsReview,
                    knowledgePoints: QuestionBankQuestionAnnotations.tags(from: knowledgePointsText),
                    weaknessTags: QuestionBankQuestionAnnotations.tags(from: weaknessTagsText)
                )
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct QuestionBankReaderOptionsPopover: View {
    private struct Choice: Identifiable {
        let title: String
        let accessibilityLabel: String
        var id: String { title }
    }

    @Binding var presentationMode: QuestionBankPresentationMode
    @Binding var readingMode: QuestionBankReadingMode
    @Binding var requiresAnswerConfirmation: Bool
    let onDismiss: () -> Void

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
            Text("设置会立即应用到当前题目。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        onDismiss()
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
                capsule("关闭", isSelected: !configuration.isOn,
                        accessibilityIdentifier: "question-bank-confirm-answer-off") {
                    configuration.isOn = false
                }
                capsule("开启", isSelected: configuration.isOn,
                        accessibilityIdentifier: "question-bank-confirm-answer-on") {
                    configuration.isOn = true
                }
            }
            .padding(3)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .frame(maxWidth: .infinity)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
    }

    private func capsule(
        _ title: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(isSelected ? AppTheme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选" : "")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct QuestionBankMissingAnswerMenu: View {
    let questionID: String
    let options: [QuestionBankOption]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("正确答案尚未录入")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                ForEach(options) { option in
                    Button("设为 \(option.id)") { onSelect(option.id) }
                }
            } label: {
                Label("补录答案", systemImage: "pencil")
                    .font(.system(size: 15, weight: .medium))
            }
            .accessibilityIdentifier("question-bank-missing-answer-\(questionID)")
        }
        .font(QuestionBankTypography.contentFont)
        .accessibilityElement(children: .contain)
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
            .buttonStyle(QuestionBankOptionButtonStyle())
            // The first choice remains locked semantically, while the custom
            // style keeps that state from dimming the option text and marker.
            .accessibilityHint(isSelectionLocked ? "答案已提交，不能更改选择" : "选择此选项")
            .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
            .disabled(isSelectionLocked)
        } else {
            row
                .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(option.id)
                .font(QuestionBankTypography.contentFont.weight(.semibold))
                .foregroundStyle(letterColor)
                .frame(width: 32, height: 32)
                .background(selectionRingColor.opacity(isSelected ? 0.10 : 0), in: Circle())
                .overlay {
                    Circle()
                        .stroke(selectionRingColor, lineWidth: isSelected ? 1.5 : 0)
                }
            VStack(alignment: .leading, spacing: 8) {
                if let displayText = QuestionBankOptionDisplay.text(for: option) {
                    Text(displayText)
                        .font(QuestionBankTypography.contentFont)
                        .foregroundStyle(Color.primary)
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
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? selectionRingColor.opacity(0.045) : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(height: 0.7)
        }
    }

    private var letterColor: Color {
        if revealsAnswer, answer == option.id { return AppTheme.success }
        if revealsAnswer, isSelected { return AppTheme.danger }
        if isSelected { return AppTheme.accent }
        return .primary
    }

    private var isSelected: Bool {
        readingMode == .practice && selectedOptionID == option.id
    }

    private var selectionRingColor: Color {
        guard isSelected else { return .clear }
        guard revealsAnswer else { return AppTheme.accent }
        return answer == option.id ? AppTheme.success : AppTheme.danger
    }
}

private struct QuestionBankOptionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

private struct QuestionBankQuestionAnnotationBadges: View {
    let question: QuestionBankQuestion

    private var labels: [String] {
        (question.isDifficult == true ? ["难题"] : [])
            + (question.needsReview == true ? ["待复习"] : [])
            + (question.knowledgePoints ?? [])
            + (question.weaknessTags ?? [])
    }

    private var hasAnnotations: Bool {
        question.isDifficult == true || question.needsReview == true
            || !(question.knowledgePoints ?? []).isEmpty || !(question.weaknessTags ?? []).isEmpty
    }

    var body: some View {
        if hasAnnotations {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if question.isDifficult == true { badge("难题", color: AppTheme.danger) }
                    if question.needsReview == true { badge("待复习", color: AppTheme.accent) }
                    ForEach(question.knowledgePoints ?? [], id: \.self) { value in
                        badge(value, color: AppTheme.success)
                    }
                    ForEach(question.weaknessTags ?? [], id: \.self) { value in
                        badge(value, color: AppTheme.accent)
                    }
                }
                .padding(.bottom, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("题目标记：\(labels.joined(separator: "、"))")
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.09), in: Capsule())
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
