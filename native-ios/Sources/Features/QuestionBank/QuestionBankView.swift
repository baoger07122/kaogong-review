import SwiftUI
import SwiftData
import OSLog

private enum QuestionBankImportSheet: Identifiable {
    case picker(UUID)
    case preparing(UUID)
    case preview(QuestionBankImportPlan)

    var id: String {
        // Keep one sheet owner across picker → preparation → preview. Replacing
        // the item ID while a document picker is dismissing can drop the preview.
        "question-bank-import-flow"
    }
}

@MainActor
private final class QuestionBankImportProgressModel: ObservableObject {
    @Published private(set) var message: String?
    private var activeRunID: UUID?
    private var fileName = ""

    func setMessage(_ value: String?) {
        message = value
    }

    func begin(runID: UUID, fileName: String) {
        activeRunID = runID
        self.fileName = fileName
        message = "\(fileName)／准备读取"
    }

    func update(runID: UUID, phase: QuestionBankImportPhase) {
        guard activeRunID == runID else { return }
        message = "\(fileName)／\(phase.rawValue)"
    }

    func finish(runID: UUID, message: String? = nil) {
        guard activeRunID == runID else { return }
        activeRunID = nil
        fileName = ""
        self.message = message
    }
}

struct QuestionBankView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootTabSelection) private var rootTabSelection
    @EnvironmentObject private var importRouter: QuestionBankImportRouter
    @Query private var records: [QuestionBankRecord]
    @Query private var batchIndexes: [QuestionBankBatchRecord]
    @Query private var batchSources: [QuestionBankBatchSourceRecord]
    @Query private var batchMaterialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var batchQuestionLinks: [QuestionBankBatchQuestionLinkRecord]
    @StateObject private var importProgress = QuestionBankImportProgressModel()
    @StateObject private var importSelection = QuestionBankImportSelectionCoordinator()
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var isFiltersExpanded = false
    @State private var selectedYear = ""
    @State private var selectedExamType = ""
    @State private var selectedProvince = ""
    @State private var selectedCoarseModule: QuestionBankCoarseModule?
    @State private var selectedQuestionType = ""
    @State private var paperPendingDeletion: QuestionBankRecord?
    @State private var showsPaperDeletionConfirmation = false
    @State private var activeImportSheet: QuestionBankImportSheet?
    @State private var isPreparingImport = false
    @State private var isCancellingImport = false
    @State private var isCommittingImport = false
    @State private var importStagingDirectory: URL?
    @State private var inlineImportFailure: String?
    @State private var showImportAlert = false
    @State private var importAlertTitle = "导入未完成"
    @State private var importAlertMessage = ""
    @State private var activeImportID: UUID?
    @State private var importWorkerID: UUID?
    @State private var importWorker: Task<QuestionBankImportPlan, Error>?

    private let importLogger = Logger(subsystem: "com.baoger07122.kaogongreview", category: "QuestionBankImportUI")

    private var sortedBatches: [QuestionBankBatchRecord] {
        batchIndexes.sorted { ($0.year, $0.displayName) > ($1.year, $1.displayName) }
    }

    private var homeFilter: QuestionBankHomeFilter {
        QuestionBankHomeFilter(
            module: selectedCoarseModule,
            questionType: selectedQuestionType,
            year: selectedYear,
            examType: selectedExamType,
            province: selectedProvince,
            search: searchIndexQuery,
            questionNumber: searchedQuestionNumber.map { String($0) } ?? ""
        )
    }

    private var searchedQuestionNumber: Int? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(query), value > 0 {
            let isKnownPaperYear = records.contains {
                $0.kind == QuestionBankRepository.paperKind && $0.year == value
            }
            return isKnownPaperYear ? nil : value
        }
        guard query.hasPrefix("第"), query.hasSuffix("题"), query.count > 2 else { return nil }
        let digits = query.dropFirst().dropLast()
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private var searchIndexQuery: String {
        searchedQuestionNumber.map { String($0) } ?? searchText
    }

    private var hasActiveFilters: Bool {
        selectedYear.isEmpty == false || selectedExamType.isEmpty == false
            || selectedProvince.isEmpty == false || selectedCoarseModule != nil
            || selectedQuestionType.isEmpty == false
    }

    private var activeFilterSummary: String {
        var values: [String] = []
        if !selectedYear.isEmpty { values.append(selectedYear) }
        if !selectedExamType.isEmpty { values.append(selectedExamType) }
        if !selectedProvince.isEmpty { values.append(selectedProvince) }
        if let selectedCoarseModule { values.append(selectedCoarseModule.rawValue) }
        if !selectedQuestionType.isEmpty { values.append(selectedQuestionType) }
        return values.joined(separator: " · ")
    }

    private func clearFilters() {
        selectedYear = ""
        selectedExamType = ""
        selectedProvince = ""
        selectedCoarseModule = nil
        selectedQuestionType = ""
    }

    var body: some View {
        let index = QuestionBankHomeIndex(records: records)
        let filter = homeFilter
        let visiblePapers = index.visiblePapers(matching: filter)
        return ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let importStatusMessage = importProgress.message {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if isPreparingImport {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            Text(importStatusMessage)
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if isPreparingImport && !isCancellingImport {
                                Button("取消", action: cancelPreparingImport)
                                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !sortedBatches.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("批次来源索引（非合卷）").font(AppTheme.sectionTitleFont)
                            ForEach(sortedBatches, id: \.identityKey) { batch in
                                NavigationLink {
                                    QuestionBankBatchDetailView(batchID: batch.identityKey)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "rectangle.stack.fill")
                                            .foregroundStyle(AppTheme.accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(batch.displayName).font(AppTheme.cardTitleFont).foregroundStyle(.primary)
                                            Text("\(batch.sourceCount) 个来源 · \(batch.uniqueQuestionCount) 道唯一题 · \(batch.pendingCount) 条待核")
                                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .nativeCard(padding: 13)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("question-bank-batch-\(batch.identityKey)")
                            }
                        }
                    }
                    if isSearchExpanded {
                        searchField
                    } else if !searchText.isEmpty {
                        activeSearchSummary
                    }

                    if isFiltersExpanded {
                        filterControls(index: index)
                    } else if hasActiveFilters {
                        activeFilterSummaryRow
                    }

                    if selectedCoarseModule != nil {
                        NavigationLink {
                            QuestionBankCrossPaperReaderView(filter: filter)
                        } label: {
                            Label("查看本范围全部题目（\(index.filteredQuestions(matching: filter).count) 题）", systemImage: "rectangle.stack")
                                .font(AppTheme.bodyFont.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("question-bank-scope-all-questions")
                    }

                    if visiblePapers.isEmpty {
                        NativeStatusCard(
                            title: index.papers.isEmpty ? "还没有导入真题" : "没有符合条件的试卷",
                            detail: index.papers.isEmpty
                                ? "优先导入单文件 JSON 真题包；旧版 ZIP 套卷也可继续使用。"
                                : "调整年份、考试类型、省份、模块、题型或搜索关键词后重试。",
                            systemImage: "books.vertical",
                            color: AppTheme.accent
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visiblePapers) { paper in
                                QuestionBankPaperSwipeRow(onDelete: {
                                    paperPendingDeletion = paper.record
                                    showsPaperDeletionConfirmation = true
                                }) {
                                    if selectedCoarseModule != nil {
                                        NavigationLink {
                                            QuestionBankCrossPaperReaderView(filter: filter, paperID: paper.id)
                                        } label: {
                                            paperCard(paper, questionCount: index.filteredQuestionCount(for: paper.id, matching: filter))
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink {
                                            paperDestination(for: paper.record)
                                        } label: {
                                            paperCard(paper, questionCount: index.filteredQuestionCount(for: paper.id, matching: filter))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .accessibilityIdentifier("question-bank-paper-\(paper.id)")
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            importButton
        }
        .background(Color.white)
        .navigationTitle("真题库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSearchExpanded.toggle()
                    }
                    isSearchFocused = isSearchExpanded
                } label: {
                    Image(systemName: isSearchExpanded ? "magnifyingglass.circle.fill" : "magnifyingglass")
                }
                .accessibilityLabel(isSearchExpanded ? "收起搜索" : "搜索真题")
                .accessibilityIdentifier("question-bank-search")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isFiltersExpanded.toggle() }
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
                .accessibilityLabel(isFiltersExpanded ? "收起筛选" : "筛选真题")
                .accessibilityIdentifier("question-bank-filter-toggle")

                Menu {
                    Button {
                        presentDocumentPicker()
                    } label: {
                        Label("导入真题包", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        clearFilters()
                        searchText = ""
                    } label: {
                        Label("清除筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    if !sortedBatches.isEmpty {
                        Section("批次来源索引（非合卷）") {
                            ForEach(sortedBatches, id: \.identityKey) { batch in
                                NavigationLink(batch.displayName) {
                                    QuestionBankBatchDetailView(batchID: batch.identityKey)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("纸卷管理与导入")
                .accessibilityIdentifier("question-bank-management-menu")
            }
        }
        .rootTabBarContentInset()
        .sheet(item: $activeImportSheet, onDismiss: handleImportSheetDismissal) { sheet in
            switch sheet {
            case .picker(let requestID):
                QuestionBankDocumentPicker(
                    requestID: requestID,
                    onPick: handlePickedDocuments,
                    onCancel: handleDocumentPickerCancellation
                )
                .ignoresSafeArea()
            case .preparing:
                QuestionBankImportPreparingView(
                    message: importProgress.message ?? "正在准备读取…",
                    onCancel: cancelPreparingImport
                )
            case .preview(let plan):
                QuestionBankImportPreview(
                    plan: plan,
                    records: records,
                    batchSources: batchSources,
                    isImporting: isCommittingImport,
                    importFailure: $inlineImportFailure,
                    onImport: { decision, batchMetadata in commitImport(plan, decision: decision, batchMetadata: batchMetadata) },
                    onCancel: { activeImportSheet = nil }
                )
            }
        }
        .alert(importAlertTitle, isPresented: $showImportAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importAlertMessage)
        }
        .confirmationDialog(
            "删除试卷？",
            isPresented: $showsPaperDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除试卷及关联题目与图片", role: .destructive) {
                deletePendingPaper()
            }
            Button("取消", role: .cancel) { paperPendingDeletion = nil }
        } message: {
            Text("将删除《\(paperPendingDeletion?.title ?? paperPendingDeletion?.decoded(QuestionBankPaper.self)?.title ?? "未命名试卷")》及其题目和纸卷图片。学习库笔记与涂鸦会保留；仍被批次来源索引引用的试卷不能删除。")
        }
        .onAppear { NativePerformanceLog.event("question bank onAppear") }
        .onAppear(perform: processPendingExternalFileIfPossible)
        .onDisappear {
            if isPreparingImport { cancelPreparingImport() }
        }
        .onChange(of: importRouter.pendingRequestIDs) { _, _ in
            processPendingExternalFileIfPossible()
        }
        .onChange(of: rootTabSelection.wrappedValue) { _, selectedTab in
            if selectedTab == .questionBank { processPendingExternalFileIfPossible() }
        }
        .onChange(of: isPreparingImport) { _, isPreparing in
            if !isPreparing { processPendingExternalFileIfPossible() }
        }
        .onChange(of: isCommittingImport) { _, isCommitting in
            if !isCommitting { processPendingExternalFileIfPossible() }
        }
        .onChange(of: showImportAlert) { _, isShowing in
            if !isShowing { processPendingExternalFileIfPossible() }
        }
    }

    private var importButton: some View {
        Button {
            presentDocumentPicker()
        } label: {
            Group {
                if isPreparingImport || isCommittingImport {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            .background(AppTheme.accent, in: Circle())
            .shadow(color: AppTheme.accent.opacity(0.28), radius: 12, y: 5)
        }
        .buttonStyle(NativePressButtonStyle())
        .disabled(isPreparingImport || isCommittingImport)
        .accessibilityLabel("导入真题包")
        .accessibilityIdentifier("question-bank-import")
        .padding(.trailing, 18)
        .padding(.bottom, 72)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("试卷、题干、选项或题号", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("question-bank-search-field")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
                .accessibilityIdentifier("question-bank-search-clear")
            }
            Button {
                isSearchExpanded = false
                isSearchFocused = false
            } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起搜索")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private var activeSearchSummary: some View {
        HStack(spacing: 8) {
            Text("搜索：\(searchText)")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("修改") {
                isSearchExpanded = true
                isSearchFocused = true
            }
            .font(AppTheme.auxiliaryFont.weight(.semibold))
            Button {
                searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除搜索")
        }
        .frame(minHeight: 28)
    }

    private var activeFilterSummaryRow: some View {
        HStack(spacing: 8) {
            Text("筛选：\(activeFilterSummary)")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("修改") { isFiltersExpanded = true }
                .font(AppTheme.auxiliaryFont.weight(.semibold))
            Button {
                clearFilters()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除筛选")
        }
        .frame(minHeight: 28)
    }

    private func filterControls(index: QuestionBankHomeIndex) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Button {
                        selectedCoarseModule = nil
                        selectedQuestionType = ""
                    } label: {
                        Text("全部")
                            .font(AppTheme.auxiliaryFont.weight(.medium))
                            .foregroundStyle(selectedCoarseModule == nil ? .white : Color.primary)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(selectedCoarseModule == nil ? AppTheme.accent : AppTheme.secondaryBackground,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("question-bank-module-filter-all")
                    ForEach(QuestionBankCoarseModule.homeOrder) { module in
                        Button {
                            selectedCoarseModule = selectedCoarseModule == module ? nil : module
                            selectedQuestionType = ""
                        } label: {
                            Text(module.rawValue)
                                .font(AppTheme.auxiliaryFont.weight(.medium))
                                .foregroundStyle(selectedCoarseModule == module ? .white : Color.primary)
                                .padding(.horizontal, 13)
                                .frame(height: 34)
                                .background(selectedCoarseModule == module ? AppTheme.accent : AppTheme.secondaryBackground,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("模块：\(module.rawValue)")
                        .accessibilityAddTraits(selectedCoarseModule == module ? .isSelected : [])
                        .accessibilityIdentifier("question-bank-module-filter-\(module.id)")
                    }
                }
            }
            if let module = selectedCoarseModule, !index.questionTypeOptions(for: module).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        typeFilterChip("全部", value: "")
                        ForEach(index.questionTypeOptions(for: module), id: \.self) { type in
                            typeFilterChip(type, value: type)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                filterMenu(title: "年份", selection: $selectedYear, options: index.years)
                filterMenu(title: "考试类别", selection: $selectedExamType, options: index.examTypes)
                filterMenu(title: "省份", selection: $selectedProvince, options: index.provinces)
                Spacer(minLength: 0)
            }
        }
    }

    private func typeFilterChip(_ title: String, value: String) -> some View {
        Button { selectedQuestionType = value } label: {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(selectedQuestionType == value ? .white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selectedQuestionType == value ? AppTheme.accent.opacity(0.88) : AppTheme.secondaryBackground,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedQuestionType == value ? .isSelected : [])
        .accessibilityIdentifier("question-bank-type-filter-\(value.isEmpty ? "all" : value)")
    }

    private func filterMenu(title: String, selection: Binding<String>, options: [String]) -> some View {
        Menu {
            Button("全部") { selection.wrappedValue = "" }
            ForEach(options, id: \.self) { value in
                Button(value) { selection.wrappedValue = value }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection.wrappedValue.isEmpty ? title : selection.wrappedValue)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(AppTheme.auxiliaryFont.weight(.medium))
            .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : AppTheme.accent)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(AppTheme.secondaryBackground, in: Capsule())
        }
    }

    private func paperCard(_ paper: QuestionBankHomePaper, questionCount: Int) -> some View {
        HStack(spacing: 12) {
            Text(paper.title)
                .font(AppTheme.cardTitleFont)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(questionCount)题")
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .nativeCard(padding: 15)
    }

    @ViewBuilder
    private func paperDestination(for record: QuestionBankRecord) -> some View {
        if let target = questionTarget(for: record.paperID) {
            QuestionBankModuleView(
                paperID: record.paperID,
                moduleID: target.moduleID,
                initialQuestionNumber: String(target.questionNumber)
            )
        } else {
            QuestionBankPaperView(
                paperID: record.paperID,
                initialModuleTitle: "",
                initialQuestionNumber: searchedQuestionNumber.map { String($0) } ?? ""
            )
        }
    }

    private func questionTarget(for paperID: String) -> QuestionBankQuestionRouteTarget? {
        QuestionBankQuestionRoute.target(
            questionNumber: searchedQuestionNumber,
            paperID: paperID,
            selectedModuleTitle: "",
            records: records
        )
    }

    private func deletePendingPaper() {
        guard let paper = paperPendingDeletion else { return }
        do {
            let result = try QuestionBankRepository.deletePaper(
                paperID: paper.paperID,
                records: records,
                context: modelContext,
                assetRoot: nil,
                batchSources: batchSources,
                batchMaterialLinks: batchMaterialLinks,
                batchQuestionLinks: batchQuestionLinks
            )
            importAlertTitle = "删除完成"
            importAlertMessage = result.assetCleanupPending
                ? "试卷与题目已删除；少量已失去引用的图片文件暂未清理，不影响其他数据。学习库笔记和涂鸦已保留。"
                : "试卷、题目及关联纸卷图片已删除。学习库笔记和涂鸦已保留。"
        } catch {
            importAlertTitle = "删除未完成"
            importAlertMessage = error.localizedDescription
        }
        paperPendingDeletion = nil
        showImportAlert = true
    }

    private func presentDocumentPicker() {
        guard !isPreparingImport, !isCommittingImport, activeImportSheet == nil else { return }
        let requestID = importSelection.beginPicker()
        importProgress.setMessage("文件选择器已打开")
        importLogger.info("native document picker opened")
        activeImportSheet = .picker(requestID)
    }

    private func handlePickedDocuments(_ requestID: UUID, _ urls: [URL]) {
        switch importSelection.receivePickedURLs(requestID: requestID, urls: urls) {
        case .selected(let selection):
            importLogger.info("native document picker returned a valid selection for request \(requestID.uuidString, privacy: .public)")
            showImportAlert = false
            importProgress.setMessage("\(selection.url.lastPathComponent)／准备读取")
            activeImportSheet = .preparing(requestID)
            // Selection starts preparation directly. The dismissal callback is
            // never required and cannot invalidate this request.
            Task { @MainActor in
                await Task.yield()
                startPendingPickedImportIfPossible(requestID: requestID)
            }
        case .emptySelection:
            reportPickerFailure(requestID: requestID, message: "文件选择器没有返回所选文件。请重新选择 JSON 或 ZIP 文件。")
        case .emptyURL:
            reportPickerFailure(requestID: requestID, message: "所选文件路径为空。请重新选择文件。")
        case .nonFileURL:
            reportPickerFailure(requestID: requestID, message: "选择器返回的不是本地文件，无法导入。")
        case .duplicate:
            importLogger.info("duplicate picker callback ignored for request \(requestID.uuidString, privacy: .public)")
        case .staleRequest:
            importLogger.info("stale picker callback ignored for request \(requestID.uuidString, privacy: .public)")
        }
    }

    private func handleDocumentPickerCancellation(_ requestID: UUID) {
        guard importSelection.cancelPickerRequest(requestID: requestID) else {
            importLogger.info("picker cancellation ignored after a selection was accepted")
            return
        }
        importProgress.setMessage("已取消选择")
        importLogger.info("native document picker reported cancellation")
        if case .picker(let activeID) = activeImportSheet, activeID == requestID {
            activeImportSheet = nil
        }
    }

    private func handleImportSheetDismissal() {
        if let requestID = importSelection.activePickerRequestID {
            switch importSelection.pickerWasDismissed(requestID: requestID) {
            case .awaitingCallback:
                importLogger.info("picker dismissed before callback; waiting for a late result")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard importSelection.noteDismissalWithoutCallback(requestID: requestID) else { return }
                    importProgress.setMessage(nil)
                    showImportError("文件选择器关闭后没有返回文件。请重新选择。")
                }
                return
            case .selectionAlreadyReceived:
                // A selected URL remains valid even when the picker dismisses
                // before the flow view is ready to retain its new sheet item.
                if activeImportSheet == nil {
                    activeImportSheet = .preparing(requestID)
                }
                return
            case .alreadyAwaitingCallback:
                return
            case .previewAlreadyPresented:
                importSelection.finishPickerRequest(requestID: requestID)
            case .staleRequest:
                break
            }
        }

        guard activeImportSheet == nil else { return }
        if let importStagingDirectory {
            try? FileManager.default.removeItem(at: importStagingDirectory)
        }
        importStagingDirectory = nil
        processPendingExternalFileIfPossible()
    }

    private func startPendingPickedImportIfPossible(requestID: UUID) {
        guard case .preparing(let activeID) = activeImportSheet,
              activeID == requestID,
              !isPreparingImport,
              importWorker == nil,
              !isCommittingImport,
              let selection = importSelection.takePendingSelection(requestID: requestID)
        else { return }
        prepareImport(from: selection.url, source: .pickerCopy, pickerRequestID: requestID)
    }

    private func reportPickerFailure(requestID: UUID, message: String) {
        importSelection.failPickerRequest(requestID: requestID)
        importLogger.error("document picker returned an unusable selection for request \(requestID.uuidString, privacy: .public)")
        importProgress.setMessage(nil)
        activeImportSheet = nil
        showImportError(message)
    }

    private func processPendingExternalFileIfPossible() {
        guard rootTabSelection.wrappedValue == .questionBank,
              !isPreparingImport,
              importWorker == nil,
              !isCommittingImport,
              !showImportAlert,
              activeImportSheet == nil,
              let request = importRouter.takeNextRequest()
        else { return }

        importLogger.info("Files document-open request received")
        prepareImport(
            from: request.url,
            source: .filesOpenIn
        )
    }

    private func prepareImport(
        from url: URL,
        source: QuestionBankImportSource = .trustedLocalFile,
        pickerRequestID: UUID? = nil
    ) {
        guard !isPreparingImport, importWorker == nil, !isCommittingImport else { return }
        let runID = UUID()
        activeImportID = runID
        importWorkerID = runID
        isPreparingImport = true
        isCancellingImport = false
        importProgress.begin(runID: runID, fileName: url.lastPathComponent)
        let progress = importProgress
        let worker = Task.detached(priority: .utility) {
            try QuestionBankPackageImporter.prepare(from: url, source: source) { phase in
                Task { @MainActor in progress.update(runID: runID, phase: phase) }
            }
        }
        importWorker = worker
        Task { @MainActor in
            defer {
                if importWorkerID == runID {
                    importWorker = nil
                    importWorkerID = nil
                    if activeImportID == runID { activeImportID = nil }
                    isPreparingImport = false
                    if isCancellingImport {
                        isCancellingImport = false
                        importProgress.setMessage("已取消读取")
                    }
                    processPendingExternalFileIfPossible()
                }
            }
            do {
                let plan = try await worker.value
                guard activeImportID == runID else {
                    QuestionBankPackageImporter.cleanup(plan)
                    return
                }
                if let pickerRequestID,
                   !importSelection.markPreviewReady(requestID: pickerRequestID) {
                    QuestionBankPackageImporter.cleanup(plan)
                    return
                }
                importLogger.info("package validation finished: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count), errors=\(plan.errors.count)")
                importStagingDirectory = plan.stagingDirectory
                activeImportSheet = .preview(plan)
                importProgress.finish(runID: runID)
            } catch is CancellationError {
                if activeImportID == runID {
                    importProgress.finish(runID: runID, message: "已取消读取")
                }
            } catch {
                guard activeImportID == runID else { return }
                let errorType = String(reflecting: type(of: error))
                importLogger.error("package preparation failed (\(errorType, privacy: .public))")
                if let pickerRequestID {
                    importSelection.failPickerRequest(requestID: pickerRequestID)
                }
                importProgress.finish(runID: runID)
                activeImportSheet = nil
                showImportError(error.localizedDescription)
            }
        }
    }

    private func cancelPreparingImport() {
        guard isPreparingImport, let runID = activeImportID else { return }
        activeImportID = nil
        importWorker?.cancel()
        if let requestID = importSelection.activePickerRequestID {
            importSelection.failPickerRequest(requestID: requestID)
        }
        isCancellingImport = true
        importProgress.finish(runID: runID, message: "正在停止读取…")
        activeImportSheet = nil
        importLogger.info("question bank import cancelled by user")
    }

    private func commitImport(_ plan: QuestionBankImportPlan, decision: QuestionBankImportDecision,
                              batchMetadata: QuestionBankBatchMetadata?) {
        guard !isCommittingImport else { return }
        isCommittingImport = true
        inlineImportFailure = nil
        do {
            let duplicate = plan.paper.flatMap { QuestionBankRepository.duplicatePaper(for: $0, in: records) }
            let batchPreparation: QuestionBankBatchPreparation?
            if let batchMetadata {
                batchPreparation = try QuestionBankBatchRepository.prepare(
                    metadata: batchMetadata, plan: plan, records: records,
                    sourceRecords: batchSources, replacingPaperID: duplicate?.paperID
                )
            } else {
                batchPreparation = nil
            }
            try QuestionBankRepository.commit(
                plan, decision: decision, records: records, context: modelContext,
                batchPreparation: batchPreparation, batches: batchIndexes, sources: batchSources,
                batchMaterialLinks: batchMaterialLinks, batchQuestionLinks: batchQuestionLinks
            )
            isCommittingImport = false
            activeImportSheet = nil
            importLogger.info("atomic import committed: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count)")
            importAlertTitle = "导入完成"
            let batchSuffix = batchPreparation.map {
                "；批次新增唯一题 \($0.currentSourcePreview.uniqueQuestions)，精确重复 \($0.currentSourcePreview.duplicateQuestions)，待核 \($0.currentSourcePreview.suspectedQuestions + $0.currentSourcePreview.conflictingQuestions)"
            } ?? ""
            importAlertMessage = "已导入“\(plan.paper?.title ?? "试卷")”：\(plan.modules.count) 个模块、\(plan.questions.count) 道题目\(batchSuffix)。套卷成绩记录和学习库数据未更改。"
            showImportAlert = true
        } catch {
            isCommittingImport = false
            let errorType = String(reflecting: type(of: error))
            importLogger.error("atomic import failed and was rolled back (\(errorType, privacy: .public))")
            inlineImportFailure = error.localizedDescription
        }
    }

    private func showImportError(_ message: String) {
        importProgress.setMessage(nil)
        importAlertTitle = "导入未完成"
        importAlertMessage = message
        showImportAlert = true
    }

}

private struct QuestionBankPaperSwipeRow<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    @State private var revealOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { revealOffset = 0 }
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 82)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.danger, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("question-bank-paper-delete-action")
            .opacity(revealOffset > 0 ? 1 : 0)
            .allowsHitTesting(revealOffset > 0)

            content
                .offset(x: revealOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18, coordinateSpace: .local)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                            if dragStartOffset == nil { dragStartOffset = revealOffset }
                            let proposed = (dragStartOffset ?? revealOffset) + value.translation.width
                            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
                                revealOffset = min(82, max(0, proposed))
                            }
                        }
                        .onEnded { value in
                            defer { dragStartOffset = nil }
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                            let finalOffset = (dragStartOffset ?? revealOffset) + value.translation.width
                            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
                                if finalOffset > 41 {
                                    revealOffset = 82
                                } else {
                                    revealOffset = 0
                                }
                            }
                        }
                )
                .accessibilityHint("向右滑动以显示删除按钮")
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct QuestionBankImportPreparingView: View {
    let message: String
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("取消读取", action: onCancel)
                    .buttonStyle(NativeSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("导入真题")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct QuestionBankImportPreview: View {
    let plan: QuestionBankImportPlan
    let isImporting: Bool
    let records: [QuestionBankRecord]
    let batchSources: [QuestionBankBatchSourceRecord]
    @Binding var importFailure: String?
    let onImport: (QuestionBankImportDecision, QuestionBankBatchMetadata?) -> Void
    let onCancel: () -> Void
    @State private var asksToReplace = false
    @State private var includesBatch: Bool
    @State private var family: QuestionBankBatchFamily?
    @State private var sourceID: String
    @State private var revision: String
    @State private var batchYear: String
    @State private var volumeID: String
    @State private var volumeName: String
    @State private var sessionID: String
    @State private var sessionName: String
    @State private var sourceProvinces: String
    @State private var provinceCode: String
    @State private var provinceName: String
    @State private var batchID: String
    @State private var batchName: String

    init(plan: QuestionBankImportPlan, records: [QuestionBankRecord],
         batchSources: [QuestionBankBatchSourceRecord], isImporting: Bool,
         importFailure: Binding<String?>,
         onImport: @escaping (QuestionBankImportDecision, QuestionBankBatchMetadata?) -> Void,
         onCancel: @escaping () -> Void) {
        self.plan = plan
        self.records = records
        self.batchSources = batchSources
        self.isImporting = isImporting
        self._importFailure = importFailure
        self.onImport = onImport
        self.onCancel = onCancel
        let metadata = plan.batchMetadata
        _includesBatch = State(initialValue: metadata != nil)
        _family = State(initialValue: metadata?.family)
        _sourceID = State(initialValue: metadata?.sourceID ?? "")
        _revision = State(initialValue: metadata?.revision ?? "")
        _batchYear = State(initialValue: metadata.map { String($0.year) } ?? "")
        _volumeID = State(initialValue: metadata?.volumeID ?? "")
        _volumeName = State(initialValue: metadata?.volumeName ?? "")
        _sessionID = State(initialValue: metadata?.sessionID ?? "")
        _sessionName = State(initialValue: metadata?.sessionName ?? "")
        _sourceProvinces = State(initialValue: (metadata?.sourceProvinces ?? [])
            .map { "\($0.code)|\($0.name)" }.joined(separator: "\n"))
        _provinceCode = State(initialValue: metadata?.provinceCode ?? "")
        _provinceName = State(initialValue: metadata?.provinceName ?? "")
        _batchID = State(initialValue: metadata?.batchID ?? "")
        _batchName = State(initialValue: metadata?.batchName ?? "")
    }

    private var currentBatchMetadata: QuestionBankBatchMetadata? {
        guard includesBatch, let family else { return nil }
        let year = Int(batchYear.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let passthrough = plan.batchMetadata?.family == family ? plan.batchMetadata : nil
        switch family {
        case .national:
            return QuestionBankBatchMetadata(family: family, sourceID: sourceID, revision: revision, year: year,
                volumeID: volumeID, volumeName: volumeName, sessionID: passthrough?.sessionID,
                sessionName: passthrough?.sessionName, sourceProvinces: passthrough?.sourceProvinces,
                provinceCode: passthrough?.provinceCode, provinceName: passthrough?.provinceName,
                batchID: passthrough?.batchID, batchName: passthrough?.batchName)
        case .joint:
            return QuestionBankBatchMetadata(family: family, sourceID: sourceID, revision: revision, year: year,
                volumeID: passthrough?.volumeID, volumeName: passthrough?.volumeName,
                sessionID: sessionID, sessionName: sessionName,
                sourceProvinces: parseSourceProvinces(), provinceCode: passthrough?.provinceCode,
                provinceName: passthrough?.provinceName, batchID: passthrough?.batchID,
                batchName: passthrough?.batchName)
        case .provincial:
            return QuestionBankBatchMetadata(family: family, sourceID: sourceID, revision: revision, year: year,
                volumeID: passthrough?.volumeID, volumeName: passthrough?.volumeName,
                sessionID: passthrough?.sessionID, sessionName: passthrough?.sessionName,
                sourceProvinces: passthrough?.sourceProvinces,
                provinceCode: provinceCode, provinceName: provinceName,
                batchID: batchID, batchName: batchName)
        }
    }

    private var batchPreparationResult: Result<QuestionBankBatchPreparation, Error>? {
        guard plan.canImport, let metadata = currentBatchMetadata, metadata.validationError == nil else { return nil }
        let duplicate = replacementPaperRecord
        return Result {
            try QuestionBankBatchRepository.prepare(metadata: metadata, plan: plan, records: records,
                sourceRecords: batchSources, replacingPaperID: duplicate?.paperID)
        }
    }

    private var duplicatePaperRecord: QuestionBankRecord? {
        plan.paper.flatMap { QuestionBankRepository.duplicatePaper(for: $0, in: records) }
    }

    private var existingSourcePaperRecord: QuestionBankRecord? {
        guard includesBatch, let metadata = currentBatchMetadata else { return nil }
        let stableSourceID = metadata.sourceID.trimmedNonempty
        guard let source = batchSources.first(where: { $0.sourceID == stableSourceID }) else { return nil }
        return records.first {
            $0.paperID == source.paperID && $0.kind == QuestionBankRepository.paperKind
        }
    }

    private var replacementPaperRecord: QuestionBankRecord? {
        existingSourcePaperRecord ?? duplicatePaperRecord
    }

    private var replacementTitle: String? {
        replacementPaperRecord.map { row in
            row.decoded(QuestionBankPaper.self)?.title ?? row.title ?? "未命名试卷"
        }
    }

    private var replacementContinuityWarning: String? {
        guard let oldPaper = replacementPaperRecord,
              let incomingPaper = plan.paper else { return nil }
        let oldRows = records.filter { $0.paperID == oldPaper.paperID }
        let idSets: [(String, Set<String>, Set<String>)] = [
            ("模块", Set(oldRows.filter { $0.kind == QuestionBankRepository.moduleKind }.map(\.stableID)), Set(plan.modules.map(\.id))),
            ("题目", Set(oldRows.filter { $0.kind == QuestionBankRepository.questionKind }.map(\.stableID)), Set(plan.questions.map(\.id))),
            ("材料", Set(oldRows.filter { $0.kind == QuestionBankRepository.materialKind }.map(\.stableID)), Set(plan.materials.map(\.id))),
            ("图片", Set(oldRows.filter { $0.kind == QuestionBankRepository.assetKind }.map(\.stableID)), Set(plan.assets.map(\.id)))
        ]
        let changed = idSets.filter { $0.1 != $0.2 }.map(\.0)
        let existingPaper = oldPaper.decoded(QuestionBankPaper.self)
        let sourceMetadataChanged = (existingPaper?.sourcePapers ?? []) != plan.sourcePapers
        guard incomingPaper.id != oldPaper.paperID || !changed.isEmpty || sourceMetadataChanged else { return nil }
        let changedDescription = changed.isEmpty ? "无" : changed.joined(separator: "、")
        let paperIDContinuity = incomingPaper.id == oldPaper.paperID ? "一致" : "不同"
        let sourceContinuity = sourceMetadataChanged ? "来源卷元数据将更新或移除" : "来源卷元数据一致"
        let inkWarning = incomingPaper.id != oldPaper.paperID || !changed.isEmpty
            ? "应用不会迁移或删除旧涂鸦；题目/材料 ID 改变会让旧笔迹无法自动挂到新题，作答状态也不会迁移。"
            : "稳定 ID 连续，旧涂鸦仍按原题目 ID 关联。"
        return "替换包与现有记录有差异（纸卷ID：\(paperIDContinuity)，稳定ID变化：\(changedDescription)；\(sourceContinuity)）。\(inkWarning) 请先核对预览。"
    }

    private func parseSourceProvinces() -> [QuestionBankSourceProvince] {
        return sourceProvinceLines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return QuestionBankSourceProvince(code: String(parts[0]).trimmedNonempty,
                name: String(parts[1]).trimmedNonempty)
        }
    }

    private var sourceProvinceLines: [String] {
        var lines = sourceProvinces
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.trimmedNonempty.isEmpty == true { lines.removeLast() }
        return lines
    }

    private var hasMalformedSourceProvinceLine: Bool {
        sourceProvinceLines.contains { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count != 2 || parts.contains { String($0).trimmedNonempty.isEmpty }
        }
    }

    private func submit(_ decision: QuestionBankImportDecision) {
        onImport(decision, currentBatchMetadata)
    }

    var body: some View {
        let batchResult = batchPreparationResult
        let metadataError: String? = {
            guard includesBatch else { return nil }
            guard let family else { return "请选择批次类别。" }
            guard let metadata = currentBatchMetadata else { return "请填写完整批次信息。" }
            if let existingSourcePaperRecord, let duplicatePaperRecord,
               existingSourcePaperRecord.paperID != duplicatePaperRecord.paperID {
                return QuestionBankBatchFailure.conflictingReplacementTargets(metadata.sourceID)
                    .localizedDescription
            }
            if family == .joint && hasMalformedSourceProvinceLine {
                return "来源省份每行必须按“代码|名称”填写；无效行不会被忽略。"
            }
            if let message = metadata.validationError { return message }
            if let batchResult, case .failure(let error) = batchResult { return error.localizedDescription }
            return nil
        }()
        let preparedBatch: QuestionBankBatchPreparation? = {
            guard let batchResult, case .success(let preparation) = batchResult else { return nil }
            return preparation
        }()
        return NavigationStack {
            Form {
                if let importFailure {
                    Section("导入失败，原有试卷未更改") {
                        Label(importFailure, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTheme.bodyFont).foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("试卷预览") {
                    LabeledContent("名称", value: plan.paper?.title ?? "无法识别")
                    LabeledContent("年份 / 类型", value: plan.paper.map { "\($0.year) · \($0.examType)" } ?? "—")
                    LabeledContent("模块", value: "\(plan.modules.count) 个")
                    LabeledContent("共用材料", value: "\(plan.materials.count) 份")
                    LabeledContent("题目", value: "\(plan.questions.count) 道")
                    LabeledContent("图片", value: "\(plan.assets.count) 张")
                    LabeledContent("来源卷", value: "\(plan.sourcePapers.count) 个")
                    LabeledContent(
                        plan.sourceFileFormat == "json" ? "JSON 大小" : "ZIP 大小",
                        value: plan.sourceFileFormat == "json"
                            ? "\(mib(plan.sourceFileByteCount)) / 64 MiB"
                            : mib(plan.sourceFileByteCount)
                    )
                    LabeledContent("解码图片", value: "\(mib(plan.decodedImageByteCount)) / 48 MiB；单张最大 \(mib(plan.largestDecodedImageByteCount)) / 16 MiB")
                    LabeledContent("题目来源映射", value: "\(plan.questions.reduce(0) { $0 + ($1.provenance?.count ?? 0) }) 条")
                    LabeledContent("材料来源映射", value: "\(plan.materials.reduce(0) { $0 + ($1.provenance?.count ?? 0) }) 条")
                    if !plan.sourcePapers.isEmpty {
                        Text("单一规范纸卷；来源卷和题目/材料溯源只作为元数据保存，不在应用内拼接或去重正文。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    if let replacementContinuityWarning {
                        Label(replacementContinuityWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !plan.sourcePapers.isEmpty {
                    Section("来源 PDF") {
                        ForEach(plan.sourcePapers) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sourceDisplayLabel(source))
                                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                                Text("文件名：\(source.originalFileName ?? "缺失")")
                                    .font(AppTheme.auxiliaryFont)
                                Text("SHA-256：\(source.originalFileSHA256 ?? "缺失")")
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section("跨卷批次") {
                    Toggle("加入跨卷批次", isOn: $includesBatch)
                    if includesBatch {
                        Picker("批次类别", selection: $family) {
                            Text("请选择类别").tag(QuestionBankBatchFamily?.none)
                            ForEach(QuestionBankBatchFamily.allCases, id: \.self) { value in
                                Text(value.title).tag(Optional(value))
                            }
                        }
                        TextField("来源标识 sourceID", text: $sourceID).textInputAutocapitalization(.never)
                        TextField("来源修订 revision", text: $revision).textInputAutocapitalization(.never)
                        TextField("批次年份 year", text: $batchYear).keyboardType(.numberPad)
                        if let family {
                            switch family {
                            case .national:
                                TextField("明确卷别 ID volumeID", text: $volumeID)
                                TextField("明确卷别名称 volumeName", text: $volumeName)
                            case .joint:
                                TextField("明确场次 ID sessionID", text: $sessionID)
                                TextField("明确场次名称 sessionName", text: $sessionName)
                                TextField("来源省份：每行代码|名称", text: $sourceProvinces, axis: .vertical)
                                    .lineLimit(1...4)
                            case .provincial:
                                TextField("省份代码 provinceCode", text: $provinceCode)
                                TextField("省份名称 provinceName", text: $provinceName)
                                TextField("批次 ID batchID", text: $batchID)
                                TextField("批次名称 batchName", text: $batchName)
                            }
                        }
                        if let metadataError {
                            Label(metadataError, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let preview = preparedBatch?.currentSourcePreview {
                            LabeledContent("题目", value: "新增唯一 \(preview.uniqueQuestions) · 精确重复 \(preview.duplicateQuestions) · 疑似 \(preview.suspectedQuestions) · 冲突 \(preview.conflictingQuestions)")
                            LabeledContent("材料", value: "新增唯一 \(preview.uniqueMaterials) · 精确重复 \(preview.duplicateMaterials) · 待核 \(preview.pendingMaterials)")
                        }
                        Text("批次只新增索引与来源关联，不复制正文或图片；整卷替换仍按上方确认执行。卷别、省份、场次和批次必须由来源明确提供，不从标题或文件名猜测。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    } else if plan.batchMetadata == nil {
                        Text("旧版 v1 文件可继续作为单卷导入；需要归入批次时再填写明确元数据。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
                if !plan.errors.isEmpty {
                    Section("校验错误（修复后再导入）") {
                        ForEach(Array(plan.errors.enumerated()), id: \.offset) { _, error in
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Section("校验结果") {
                        Label("结构、题号、答案、图片文件及关联均已通过检查", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text("图片将以文件保存；列表不会加载图片字节。导入只新增真题库内容，不生成解析或作答记录。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("确认导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel).disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "正在导入…" : "导入试卷") {
                        if replacementTitle != nil { asksToReplace = true }
                        else { submit(.add) }
                    }
                    .disabled(!plan.canImport || isImporting
                        || (includesBatch && (metadataError != nil || preparedBatch == nil)))
                }
            }
            .confirmationDialog(
                "检测到重复试卷",
                isPresented: $asksToReplace,
                titleVisibility: .visible
            ) {
                Button("替换已有的“\(replacementTitle ?? "同名试卷")”", role: .destructive) {
                    submit(.replaceExisting)
                }
                Button("取消导入", role: .cancel) { }
            } message: {
                Text("按来源标识的修订关系、试卷 ID，或年份、考试类型、卷别和名称识别替换目标。替换失败时仍保留原数据。\(replacementContinuityWarning ?? "替换包的稳定 ID 与现有数据一致，原涂鸦仍按原题目 ID 关联。")")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func mib(_ bytes: Int64) -> String {
        String(format: "%.1f MiB", Double(bytes) / 1_048_576)
    }

    private func sourceDisplayLabel(_ source: QuestionBankSourcePaper) -> String {
        ([source.provinceName, source.batchName].compactMap { $0?.trimmedNonempty }
            + [source.id.trimmedNonempty].filter { !$0.isEmpty })
            .joined(separator: " · ")
    }
}

private struct QuestionBankPaperView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [QuestionBankRecord]
    @Query private var batchSources: [QuestionBankBatchSourceRecord]
    @Query private var batchMaterialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var batchQuestionLinks: [QuestionBankBatchQuestionLinkRecord]
    let paperID: String
    @State private var selectedModuleTitle: String
    @State private var questionNumber: String
    @State private var isPaperEditorPresented = false
    @State private var showsPaperDeletionConfirmation = false
    @State private var showsPaperActionAlert = false
    @State private var paperActionAlertTitle = "操作未完成"
    @State private var paperActionAlertMessage = ""

    init(paperID: String, initialModuleTitle: String, initialQuestionNumber: String) {
        self.paperID = paperID
        _selectedModuleTitle = State(initialValue: initialModuleTitle)
        _questionNumber = State(initialValue: initialQuestionNumber)
    }

    private var paperRecord: QuestionBankRecord? {
        records.first { $0.paperID == paperID && $0.kind == QuestionBankRepository.paperKind }
    }
    private var paper: QuestionBankPaper? { paperRecord?.decoded(QuestionBankPaper.self) }
    private var modules: [QuestionBankRecord] {
        records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind }
            .filter { selectedModuleTitle.isEmpty || $0.title == selectedModuleTitle }
            .filter { module in
                guard let number = Int(questionNumber), number > 0 else { return true }
                return records.contains { $0.paperID == paperID && $0.moduleID == module.stableID
                    && $0.kind == QuestionBankRepository.questionKind && $0.questionNumber == number }
            }
            .sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
    }
    private var allModuleTitles: [String] {
        Array(Set(records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind }
            .compactMap(\.title))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let paper {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(paper.title).font(AppTheme.sectionTitleFont)
                        Text([String(paper.year), paper.examType, paper.volume]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("全部模块") { selectedModuleTitle = "" }
                        ForEach(allModuleTitles, id: \.self) { title in Button(title) { selectedModuleTitle = title } }
                    } label: { filterLabel(selectedModuleTitle.isEmpty ? "全部模块" : selectedModuleTitle) }
                    HStack(spacing: 6) {
                        TextField("题号", text: $questionNumber).keyboardType(.numberPad).frame(width: 64)
                        if !questionNumber.isEmpty {
                            Button { questionNumber = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 11).frame(height: 34)
                    .background(AppTheme.secondaryBackground, in: Capsule())
                    Spacer()
                }
                if modules.isEmpty {
                    NativeStatusCard(title: "没有匹配模块", detail: "更改模块或题号筛选条件。", systemImage: "line.3.horizontal.decrease", color: AppTheme.accent)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(modules, id: \.compoundID) { moduleRecord in
                            let module = moduleRecord.decoded(QuestionBankModule.self)
                            let count = records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind && $0.moduleID == moduleRecord.stableID }.count
                            NavigationLink {
                                QuestionBankModuleView(paperID: paperID, moduleID: moduleRecord.stableID, initialQuestionNumber: questionNumber)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(String(format: "%02d", module?.sequence ?? moduleRecord.sequence ?? 0))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 36, height: 34, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(module?.title ?? moduleRecord.title ?? "模块")
                                                .font(AppTheme.sectionTitleFont).foregroundStyle(.primary)
                                            Text(count == 0 ? "本次样本未收录题目" : "\(String(count)) 道样题")
                                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 14)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color(uiColor: .separator).opacity(0.45))
                                            .frame(height: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("question-bank-module-\(moduleRecord.stableID)")
                            }
                    }
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(paper?.title ?? "模块目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isPaperEditorPresented = true
                    } label: {
                        Label("重命名或编辑属性", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showsPaperDeletionConfirmation = true
                    } label: {
                        Label("删除试卷", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("试卷管理")
                .accessibilityIdentifier("question-bank-paper-management-menu")
            }
        }
        .sheet(isPresented: $isPaperEditorPresented) {
            if let paper {
                QuestionBankPaperMetadataEditor(paper: paper) { title, year, examType, volume, provinceCode, provinceName in
                    guard let paperRecord else { throw QuestionBankPaperMetadataEditFailure.missingPaper }
                    try QuestionBankRepository.updatePaperMetadata(
                        record: paperRecord,
                        title: title,
                        year: year,
                        examType: examType,
                        volume: volume,
                        provinceCode: provinceCode,
                        provinceName: provinceName,
                        records: records,
                        context: modelContext
                    )
                }
            }
        }
        .confirmationDialog("删除试卷？", isPresented: $showsPaperDeletionConfirmation, titleVisibility: .visible) {
            Button("删除试卷及关联题目与图片", role: .destructive, action: deletePaperFromMenu)
            Button("取消", role: .cancel) { }
        } message: {
            Text("将删除《\(paper?.title ?? "未命名试卷")》及其题目和纸卷图片。学习库笔记与涂鸦会保留；仍被批次来源索引引用的试卷不能删除。")
        }
        .alert(paperActionAlertTitle, isPresented: $showsPaperActionAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(paperActionAlertMessage)
        }
        .secondaryPageTabBarHidden()
    }

    private func deletePaperFromMenu() {
        do {
            try QuestionBankRepository.deletePaper(
                paperID: paperID,
                records: records,
                context: modelContext,
                batchSources: batchSources,
                batchMaterialLinks: batchMaterialLinks,
                batchQuestionLinks: batchQuestionLinks
            )
            dismiss()
        } catch {
            paperActionAlertTitle = "删除未完成"
            paperActionAlertMessage = error.localizedDescription
            showsPaperActionAlert = true
        }
    }

    private func filterLabel(_ value: String) -> some View {
        HStack(spacing: 5) { Text(value).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            .font(AppTheme.auxiliaryFont.weight(.medium)).foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 11).frame(height: 34).background(AppTheme.secondaryBackground, in: Capsule())
    }
}

private struct QuestionBankPaperMetadataEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Int, String, String, String, String) throws -> Void
    @State private var title: String
    @State private var year: String
    @State private var examType: String
    @State private var volume: String
    @State private var provinceCode: String
    @State private var provinceName: String
    @State private var errorMessage: String?

    init(
        paper: QuestionBankPaper,
        onSave: @escaping (String, Int, String, String, String, String) throws -> Void
    ) {
        self.onSave = onSave
        _title = State(initialValue: paper.title)
        _year = State(initialValue: String(paper.year))
        _examType = State(initialValue: paper.examType)
        _volume = State(initialValue: paper.volume)
        _provinceCode = State(initialValue: paper.provinceCode ?? "")
        _provinceName = State(initialValue: paper.provinceName ?? "")
    }

    private var parsedYear: Int? {
        guard let value = Int(year), (1900...2200).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("试卷") {
                    TextField("试卷名称", text: $title)
                        .accessibilityIdentifier("question-bank-paper-title-field")
                    TextField("年份", text: $year)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("question-bank-paper-year-field")
                    TextField("卷别", text: $volume)
                        .accessibilityIdentifier("question-bank-paper-volume-field")
                }
                Section {
                    TextField("考试类别（可自定义）", text: $examType)
                        .accessibilityIdentifier("question-bank-paper-category-field")
                    HStack(spacing: 8) {
                        ForEach(["国考", "联考", "省考"], id: \.self) { value in
                            Button(value) { examType = value }
                                .buttonStyle(.bordered)
                                .tint(examType == value ? AppTheme.accent : .secondary)
                        }
                    }
                } header: {
                    Text("考试类别")
                } footer: {
                    Text("这是试卷分类，和题目科目“行测”分开保存；首页筛选会使用这里的类别。")
                }
                Section("省份（可选）") {
                    TextField("省份名称", text: $provinceName)
                    TextField("省份代码", text: $provinceCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("编辑试卷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || examType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || parsedYear == nil)
                        .accessibilityIdentifier("question-bank-paper-save")
                }
            }
            .alert("保存未完成", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let parsedYear else { return }
        do {
            try onSave(title, parsedYear, examType, volume, provinceCode, provinceName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
