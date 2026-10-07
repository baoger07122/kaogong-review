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
            type: question.type.isEmpty ? question.subject : question.type,
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
    @State private var continuousAnchorQuestionID: String?
    @State private var pendingOverviewQuestionID: String?
    @State private var continuousScrollRequest: QuestionBankScrollRequest?
    @State private var splitScrollRequest: QuestionBankScrollRequest?
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
            questionDoodleToolbarItems
            readerOptionsMenu
            questionOverviewButton
        }
    }

    private var readerOptionsMenu: some View {
        Menu {
            Section("展示方式 · 当前：\(presentationMode.title)") {
                ForEach(QuestionBankPresentationMode.allCases) { mode in
                    Button {
                        selectPresentationMode(mode)
                    } label: {
                        if presentationMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }
            Section("答题方式 · 当前：\(readingMode.title)") {
                ForEach(QuestionBankReadingMode.allCases) { mode in
                    Button {
                        guard !doodleSession.isPresented else { return }
                        readingMode = mode
                    } label: {
                        if readingMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }
            if readingMode == .practice {
                Toggle("选择后确认答案", isOn: $requiresAnswerConfirmation)
                    .accessibilityIdentifier("question-bank-confirm-answer-toggle")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(presentationMode.shortTitle) · \(readingMode.title)")
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .foregroundStyle(AppTheme.accent)
        }
        .accessibilityLabel("阅读设置，\(presentationMode.title)，\(readingMode.title)")
        .accessibilityValue("展示方式：\(presentationMode.title)，答题方式：\(readingMode.title)")
        .accessibilityHint("打开菜单调整展示方式、答题方式和确认选项")
        .accessibilityIdentifier("question-bank-reader-options")
        .disabled(doodleSession.isPresented)
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
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent.opacity(0.58))
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
                        questionSection(item, showsDetailButton: presentationMode == .continuous)
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
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(target, anchor: .top)
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
        showsDetailButton: Bool = false
    ) -> some View {
        let selectedOptionID = selectedOptionsByQuestionID[item.id]
        let revealsAnswer = readingMode.revealsAnswer(
            afterSelecting: selectedOptionID,
            wasConfirmed: revealedAnswerQuestionIDs.contains(item.id),
            requiresConfirmation: requiresAnswerConfirmation
        )
        return VStack(alignment: .leading, spacing: 0) {
            let subject = item.question.type.isEmpty ? item.question.subject : item.question.type
            if !subject.isEmpty {
                HStack(spacing: 8) {
                    Text(subject)
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
                        Text(item.question.stem)
                            .font(AppTheme.questionTextFont)
                            .lineSpacing(AppTheme.questionLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 10)
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
        .accessibilityIdentifier("question-bank-question-\(item.id)")
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
            }
            questionSection(item)
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
                        materialContent(material)
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
        applyReaderPosition(position)
        continuousAnchorQuestionID = targetID

        if hadSplitMaterial, splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: targetID, token: UUID())
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
        guard !doodleSession.isPresented else { return }
        selectedOptionsByQuestionID[questionID] = optionID
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
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(questionID, anchor: .top)
            }
        }
    }

    private func updateVisibleQuestion(_ frames: [String: QuestionBankReaderViewportFrame]) {
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
                doodleDrawingCache[recordID] = drawingData
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
                        Text(overview.stem)
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
            .accessibilityLabel("第\(String(overview.number))题，\(overview.type)")
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

private struct QuestionBankOptionRow: View {
    let questionID: String
    let option: QuestionBankOption
    let answer: String
    let readingMode: QuestionBankReadingMode
    let selectedOptionID: String?
    let revealsAnswer: Bool
    let isInteractionBlocked: Bool
    let onSelect: () -> Void
    let assetLookup: (String) -> QuestionBankRecord?

    var body: some View {
        Group {
            if readingMode == .practice {
                Button {
                    guard !isInteractionBlocked else { return }
                    onSelect()
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
        .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
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
