import SwiftUI
import SwiftData
import OSLog

private enum QuestionBankImportSheet: Identifiable {
    case picker(UUID)
    case preparing(UUID)
    case preview(String, QuestionBankImportPlan, QuestionBankImportJobPreview)
    case batchPreview(String, QuestionBankBatchPackagePlan, QuestionBankImportJobPreview)

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

    func update(runID: UUID, progress: QuestionBankImportJobProgress) {
        guard activeRunID == runID else { return }
        let count = progress.totalCount > 0
            ? " \(progress.processedCount)/\(progress.totalCount)"
            : ""
        message = "\(fileName)／\(progress.phaseLabel)\(count)"
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
    @Query private var batchIndexes: [QuestionBankBatchRecord]
    @Query private var batchSources: [QuestionBankBatchSourceRecord]
    @Query private var batchMaterialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var batchQuestionLinks: [QuestionBankBatchQuestionLinkRecord]
    @StateObject private var importProgress = QuestionBankImportProgressModel()
    @StateObject private var importSelection = QuestionBankImportSelectionCoordinator()
    @StateObject private var organizationStore = QuestionBankOrganizationStore()
    @StateObject private var catalogHomeStore = QuestionBankCatalogHomeStore()
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var isFiltersExpanded = false
    @State private var selectedYear = ""
    @State private var selectedExamType = ""
    @State private var selectedProvince = ""
    @State private var selectedCoarseModule: QuestionBankCoarseModule?
    @State private var selectedQuestionType = ""
    @State private var selectedDifficultOnly = false
    @State private var selectedNeedsReviewOnly = false
    @State private var selectedKnowledgePoint = ""
    @State private var selectedWeaknessTag = ""
    @State private var paperPendingDeletion: QuestionBankCatalogPaperSummary?
    @State private var showsPaperDeletionConfirmation = false
    @State private var activeImportSheet: QuestionBankImportSheet?
    @State private var showsBatchPackageManager = false
    @State private var showsOrganizationManager = false
    @State private var collapsedOrganizationSections: Set<String> = []
    @State private var isPreparingImport = false
    @State private var isCancellingImport = false
    @State private var isCommittingImport = false
    @State private var searchRetryGeneration = 0
    @State private var inlineImportFailure: String?
    @State private var showImportAlert = false
    @State private var importAlertTitle = "导入未完成"
    @State private var importAlertMessage = ""
    @State private var activeImportID: UUID?
    @State private var activeImportJobID: String?
    @State private var importWorkerID: UUID?
    @State private var importWorker: Task<(jobID: String, prepared: QuestionBankPreparedImport), Error>?
    @State private var didRecoverImportJobs = false
    @State private var isHomeRouteVisible = false
    @State private var isCatalogHomeVisible = false
    @State private var needsCatalogHomeReload = true

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
            questionNumber: searchedQuestionNumber.map { String($0) } ?? "",
            difficultOnly: selectedDifficultOnly,
            needsReviewOnly: selectedNeedsReviewOnly,
            knowledgePoint: selectedKnowledgePoint,
            weaknessTag: selectedWeaknessTag
        )
    }

    private var searchedQuestionNumber: Int? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(query), value > 0 {
            let isKnownPaperYear = catalogHomeStore.containsPaper(year: value)
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
            || selectedQuestionType.isEmpty == false || selectedDifficultOnly
            || selectedNeedsReviewOnly || !selectedKnowledgePoint.isEmpty || !selectedWeaknessTag.isEmpty
    }

    private var activeFilterSummary: String {
        var values: [String] = []
        if !selectedYear.isEmpty { values.append(selectedYear) }
        if !selectedExamType.isEmpty { values.append(selectedExamType) }
        if !selectedProvince.isEmpty { values.append(selectedProvince) }
        if let selectedCoarseModule { values.append(selectedCoarseModule.rawValue) }
        if !selectedQuestionType.isEmpty { values.append(selectedQuestionType) }
        if selectedDifficultOnly { values.append("难题") }
        if selectedNeedsReviewOnly { values.append("待复习") }
        if !selectedKnowledgePoint.isEmpty { values.append("知识点：\(selectedKnowledgePoint)") }
        if !selectedWeaknessTag.isEmpty { values.append("弱项：\(selectedWeaknessTag)") }
        return values.joined(separator: " · ")
    }

    private func clearFilters() {
        selectedYear = ""
        selectedExamType = ""
        selectedProvince = ""
        selectedCoarseModule = nil
        selectedQuestionType = ""
        selectedDifficultOnly = false
        selectedNeedsReviewOnly = false
        selectedKnowledgePoint = ""
        selectedWeaknessTag = ""
    }

    var body: some View {
        Group {
            if let snapshot = catalogHomeStore.snapshot,
               let result = catalogHomeStore.filtered(matching: homeFilter) {
                let filter = homeFilter
                let candidates = result.visiblePapers
                let visibleByID = Dictionary(
                    candidates.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let organizationSections = makeOrganizationSections(for: candidates)
                let visiblePapers = organizationSections
                    .flatMap(\.paperIDs)
                    .compactMap { visibleByID[$0] }
                questionBankConfiguredContent(
                    snapshot: snapshot,
                    filter: filter,
                    filterResult: result,
                    organizationSections: organizationSections,
                    visiblePapers: visiblePapers,
                    visibleByID: visibleByID
                )
            } else if catalogHomeStore.snapshot == nil || !catalogHomeStore.isCurrent {
                questionBankLoadingContent
            } else if catalogHomeStore.status?.state != .ready {
                questionBankLoadingContent
            } else {
                questionBankSearchLoadingContent
            }
        }
        .task(id: "\(catalogHomeStore.requestGeneration)|\(isCatalogHomeVisible)") {
            guard isCatalogHomeVisible else { return }
            let generation = catalogHomeStore.requestGeneration
            await Task.yield()
            await catalogHomeStore.load(in: modelContext.container, generation: generation)
        }
        .task(id: "\(isHomeRouteVisible)|\(didRecoverImportJobs)") {
            guard isHomeRouteVisible, !didRecoverImportJobs else { return }
            didRecoverImportJobs = true
            do {
                let recovered = try await QuestionBankImportJobService.shared.recover(in: modelContext.container)
                guard !Task.isCancelled, activeImportSheet == nil, !recovered.isEmpty else { return }
                let job = recovered[0]
                activeImportJobID = job.jobID
                switch job.prepared {
                case .single(let plan):
                    activeImportSheet = .preview(job.jobID, plan, job.preview)
                case .batch(let package):
                    activeImportSheet = .batchPreview(job.jobID, package, job.preview)
                }
                importProgress.setMessage("已恢复未完成的真题导入，请核对后确认")
            } catch {
                importLogger.error("question bank import recovery failed (\(String(reflecting: type(of: error)), privacy: .public))")
            }
        }
        .task(id: "\(searchIndexQuery)|\(catalogHomeStore.requestGeneration)|\(catalogHomeStore.loadedGeneration ?? -1)|\(catalogHomeStore.status?.state.rawValue ?? "none")|\(searchRetryGeneration)|\(isCatalogHomeVisible)") {
            guard isCatalogHomeVisible,
                  catalogHomeStore.snapshot != nil,
                  catalogHomeStore.status?.state == .ready,
                  searchedQuestionNumber == nil,
                  !searchIndexQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                catalogHomeStore.beginSearch("")
                return
            }
            let query = searchIndexQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            catalogHomeStore.beginSearch(query)
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                await catalogHomeStore.search(query, in: modelContext.container)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .task(id: catalogHomeStore.filterRequestID(for: homeFilter)) {
            guard isCatalogHomeVisible else { return }
            await catalogHomeStore.prepareFilter(matching: homeFilter, in: modelContext.container)
        }
        .onAppear {
            isHomeRouteVisible = true
            isCatalogHomeVisible = rootTabSelection.wrappedValue == .questionBank
            if isCatalogHomeVisible, needsCatalogHomeReload || catalogHomeStore.snapshot == nil {
                needsCatalogHomeReload = false
                catalogHomeStore.requestReload()
            }
            if catalogHomeStore.isCurrent, let snapshot = catalogHomeStore.snapshot {
                organizationStore.reconcile(paperIDs: snapshot.papers.map(\.paperID))
            }
            NativePerformanceLog.event("question bank onAppear")
            processPendingExternalFileIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: QuestionBankRecordChangeSignal.notification)) { notification in
            guard let catalogChanges = QuestionBankRecordChangeSignal.catalogChanges(notification: notification) else {
                needsCatalogHomeReload = true
                guard isCatalogHomeVisible else { return }
                needsCatalogHomeReload = false
                catalogHomeStore.requestReload()
                return
            }
            guard !catalogChanges.isEmpty else { return }
            needsCatalogHomeReload = true
            guard isCatalogHomeVisible else { return }
            needsCatalogHomeReload = false
            if catalogChanges.contains(where: { $0.kind == .structure }) {
                catalogHomeStore.requestReload()
            } else {
                Task { @MainActor in
                    let updated = await catalogHomeStore.refreshQuestions(
                        for: catalogChanges,
                        in: modelContext.container
                    )
                    guard updated else {
                        if isCatalogHomeVisible {
                            catalogHomeStore.requestReload()
                        } else {
                            needsCatalogHomeReload = true
                        }
                        return
                    }
                    searchRetryGeneration &+= 1
                }
            }
        }
        .onChange(of: catalogHomeStore.loadedGeneration) { _, _ in
            guard catalogHomeStore.isCurrent, let snapshot = catalogHomeStore.snapshot else { return }
            organizationStore.reconcile(paperIDs: snapshot.papers.map(\.paperID))
        }
        .onDisappear {
            isHomeRouteVisible = false
            isCatalogHomeVisible = false
            catalogHomeStore.cancelLoad()
            if isPreparingImport { cancelPreparingImport() }
        }
        .onChange(of: importRouter.pendingRequestIDs) { _, _ in
            processPendingExternalFileIfPossible()
        }
        .onChange(of: rootTabSelection.wrappedValue) { _, selectedTab in
            isCatalogHomeVisible = selectedTab == .questionBank && isHomeRouteVisible
            if isCatalogHomeVisible {
                if needsCatalogHomeReload || catalogHomeStore.snapshot == nil {
                    needsCatalogHomeReload = false
                    catalogHomeStore.requestReload()
                }
                processPendingExternalFileIfPossible()
            } else {
                catalogHomeStore.cancelLoad()
            }
        }
    }

    private var questionBankLoadingContent: some View {
        VStack(spacing: 12) {
            catalogStatusCard
            if let errorMessage = catalogHomeStore.errorMessage {
                Text(errorMessage).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger)
                Button("重试") { retryCatalogLoad() }.buttonStyle(NativePrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color.white)
        .navigationTitle("真题库")
        .navigationBarTitleDisplayMode(.inline)
        .rootTabBarContentInset()
        .toolbar { questionBankToolbar() }
    }

    private var questionBankSearchLoadingContent: some View {
        VStack(spacing: 12) {
            if catalogHomeStore.isSearching {
                ProgressView("正在搜索题目…")
            } else if catalogHomeStore.isPreparingFilter {
                ProgressView("正在筛选题目…")
            } else if catalogHomeStore.errorMessage != nil {
                Text(catalogHomeStore.errorMessage ?? "搜索失败")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger)
                Button("重试搜索") { searchRetryGeneration &+= 1 }
            } else {
                ProgressView("正在准备题目列表…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color.white)
        .navigationTitle("真题库")
        .navigationBarTitleDisplayMode(.inline)
        .rootTabBarContentInset()
        .toolbar { questionBankToolbar() }
    }

    private var catalogStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if catalogHomeStore.isLoading { ProgressView().controlSize(.small) }
                Text(catalogStateTitle).font(AppTheme.cardTitleFont)
            }
            if let status = catalogHomeStore.status, status.totalSourceRowCount != nil {
                let total = max(status.totalSourceRowCount ?? 0, 0)
                Text("目录已处理 \(status.indexedSourceRowCount) / \(total) 条源记录")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                ProgressView(value: total == 0 ? 0 : Double(status.indexedSourceRowCount) / Double(total))
            } else if let status = catalogHomeStore.status, status.indexedSourceRowCount > 0 {
                Text("已处理 \(status.indexedSourceRowCount) 条源记录")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            } else if catalogHomeStore.status?.state == .notStarted {
                Text("首次打开将在后台建立题目目录；离开页面可暂停，之后继续。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private var catalogStateTitle: String {
        switch catalogHomeStore.status?.state {
        case .building: "正在建立题目目录"
        case .paused: "题目目录已暂停"
        case .needsRepair: "题目目录需要更新"
        case .ready: "题目目录已就绪"
        case .notStarted, nil: catalogHomeStore.isLoading ? "正在准备题目目录" : "题目目录尚未就绪"
        }
    }

    private func retryCatalogLoad() {
        catalogHomeStore.requestReload()
    }

    private func questionBankConfiguredContent(
        snapshot: QuestionBankCatalogHomeSnapshot,
        filter: QuestionBankHomeFilter,
        filterResult: QuestionBankCatalogHomeFilterResult,
        organizationSections: [QuestionBankOrganizationSection],
        visiblePapers: [QuestionBankCatalogPaperSummary],
        visibleByID: [String: QuestionBankCatalogPaperSummary]
    ) -> AnyView {
        var content = AnyView(
            questionBankScrollContent(
                snapshot: snapshot,
                filter: filter,
                filterResult: filterResult,
                organizationSections: organizationSections,
                visiblePapers: visiblePapers,
                visibleByID: visibleByID
            )
            .background(Color.white)
            .navigationTitle("真题库")
            .navigationBarTitleDisplayMode(.inline)
        )
        content = AnyView(content.toolbar { questionBankToolbar() })
        content = AnyView(content.rootTabBarContentInset())
        content = AnyView(content.sheet(item: $activeImportSheet, onDismiss: handleImportSheetDismissal) { sheet in
            importSheetContent(sheet)
        })
        content = AnyView(content.sheet(isPresented: $showsOrganizationManager) {
            QuestionBankPaperOrganizationView(store: organizationStore, papers: snapshot.papers)
        })
        content = AnyView(content.sheet(isPresented: $showsBatchPackageManager) {
            QuestionBankBatchPackageManagerView(
                organizationStore: organizationStore
            )
        })
        content = AnyView(content.alert(importAlertTitle, isPresented: $showImportAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importAlertMessage)
        })
        content = AnyView(content.confirmationDialog(
            "删除试卷？",
            isPresented: $showsPaperDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除试卷及关联题目与图片", role: .destructive) { deletePendingPaper() }
            Button("取消", role: .cancel) { paperPendingDeletion = nil }
        } message: {
            Text("将删除《\(paperPendingDeletion?.title ?? "未命名试卷")》及其题目和纸卷图片。学习库笔记与涂鸦会保留；仍被批次来源索引引用的试卷不能删除。")
        })
        content = AnyView(content.onChange(of: isPreparingImport) { _, isPreparing in
            if !isPreparing { processPendingExternalFileIfPossible() }
        })
        content = AnyView(content.onChange(of: isCommittingImport) { _, isCommitting in
            if !isCommitting { processPendingExternalFileIfPossible() }
        })
        content = AnyView(content.onChange(of: showImportAlert) { _, isShowing in
            if !isShowing { processPendingExternalFileIfPossible() }
        })
        return content
    }

    @ToolbarContentBuilder
    private func questionBankToolbar() -> some ToolbarContent {
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
                    .accessibilityIdentifier("question-bank-import")
                    Button {
                        clearFilters()
                        searchText = ""
                    } label: {
                        Label("清除筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Button {
                        showsOrganizationManager = true
                    } label: {
                        Label("管理分组与排序", systemImage: "folder")
                    }
                    .accessibilityIdentifier("question-bank-organization-manager")
                    Button {
                        showsBatchPackageManager = true
                    } label: {
                        Label("批量导出/更新包", systemImage: "square.and.arrow.up.on.square")
                    }
                    .accessibilityIdentifier("question-bank-batch-package-manager")
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

    @ViewBuilder
    private func importSheetContent(_ sheet: QuestionBankImportSheet) -> some View {
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
            case .preview(let jobID, let plan, let preview):
                QuestionBankImportPreview(
                    jobID: jobID,
                    plan: plan,
                    preview: preview,
                    isImporting: isCommittingImport,
                    importFailure: $inlineImportFailure,
                    onImport: { correctedPlan, decision, batchMetadata, revisionToken in
                        commitImport(
                            jobID: jobID,
                            plan: correctedPlan,
                            decision: decision,
                            batchMetadata: batchMetadata,
                            revisionToken: revisionToken
                        )
                    },
                    onCancel: { cancelImportJob(jobID: jobID) }
                )
            case .batchPreview(let jobID, let plan, let preview):
                QuestionBankBatchPackageImportPreview(
                    jobID: jobID,
                    plan: plan,
                    preview: preview,
                    isImporting: isCommittingImport,
                    importFailure: $inlineImportFailure,
                    onImport: { keys, revisionToken in
                        commitBatchImport(
                            jobID: jobID,
                            package: plan,
                            confirmedNewQuestionKeys: keys,
                            revisionToken: revisionToken
                        )
                    },
                    onCancel: { cancelImportJob(jobID: jobID) }
                )
            }
        }

    private func questionBankScrollContent(
        snapshot: QuestionBankCatalogHomeSnapshot,
        filter: QuestionBankHomeFilter,
        filterResult: QuestionBankCatalogHomeFilterResult,
        organizationSections: [QuestionBankOrganizationSection],
        visiblePapers: [QuestionBankCatalogPaperSummary],
        visibleByID: [String: QuestionBankCatalogPaperSummary]
    ) -> AnyView {
        return AnyView(ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if catalogHomeStore.status?.state != .ready || catalogHomeStore.errorMessage != nil {
                        catalogStatusCard
                        if let errorMessage = catalogHomeStore.errorMessage {
                            Text(errorMessage).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger)
                            Button("重试") { retryCatalogLoad() }.buttonStyle(NativePrimaryButtonStyle())
                        }
                    }
                    if catalogHomeStore.isSearching {
                        Label("正在搜索题目…", systemImage: "magnifyingglass")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
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
                        filterControls(snapshot: snapshot)
                    } else if hasActiveFilters {
                        activeFilterSummaryRow
                    }

                    if filter.hasQuestionRestriction {
                        NavigationLink {
                            QuestionBankCrossPaperReaderView(
                                filter: filter,
                                paperIDs: filterResult.visiblePapers.map(\.paperID)
                            )
                        } label: {
                            Label("查看本范围全部题目（\(filterResult.totalQuestionCount) 题）", systemImage: "rectangle.stack")
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
                            title: snapshot.papers.isEmpty ? "还没有导入真题" : "没有符合条件的试卷",
                            detail: snapshot.papers.isEmpty
                                ? "优先导入单文件 JSON 真题包；旧版 ZIP 套卷也可继续使用。"
                                : "调整年份、考试类型、省份、模块、题型或搜索关键词后重试。",
                            systemImage: "books.vertical",
                            color: AppTheme.accent
                        )
                    } else {
                        paperSections(
                            snapshot: snapshot,
                            filter: filter,
                            filterResult: filterResult,
                            sections: organizationSections,
                            visibleByID: visibleByID
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        )
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

    private func filterControls(snapshot: QuestionBankCatalogHomeSnapshot) -> some View {
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
            if let module = selectedCoarseModule, !snapshot.questionTypeOptions(for: module).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        typeFilterChip("全部", value: "")
                        ForEach(snapshot.questionTypeOptions(for: module), id: \.self) { type in
                            typeFilterChip(type, value: type)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                filterMenu(title: "年份", selection: $selectedYear, options: snapshot.years)
                filterMenu(title: "考试类别", selection: $selectedExamType, options: snapshot.examTypes)
                filterMenu(title: "省份", selection: $selectedProvince, options: snapshot.provinces)
                Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
                questionTagFilterChip("难题", isSelected: $selectedDifficultOnly,
                                      identifier: "question-bank-difficult-filter")
                questionTagFilterChip("待复习", isSelected: $selectedNeedsReviewOnly,
                                      identifier: "question-bank-review-filter")
                if !snapshot.knowledgePoints.isEmpty {
                    filterMenu(title: "知识点", selection: $selectedKnowledgePoint, options: snapshot.knowledgePoints)
                }
                if !snapshot.weaknessTags.isEmpty {
                    filterMenu(title: "弱项", selection: $selectedWeaknessTag, options: snapshot.weaknessTags)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func questionTagFilterChip(
        _ title: String,
        isSelected: Binding<Bool>,
        identifier: String
    ) -> some View {
        Button { isSelected.wrappedValue.toggle() } label: {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(isSelected.wrappedValue ? .white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isSelected.wrappedValue ? AppTheme.accent : AppTheme.secondaryBackground,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected.wrappedValue ? .isSelected : [])
        .accessibilityIdentifier(identifier)
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

    private func paperCard(_ paper: QuestionBankCatalogPaperSummary, questionCount: Int) -> some View {
        HStack(spacing: 12) {
            Text(paper.title)
                .font(AppTheme.cardTitleFont)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(questionCount)题")
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.white, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
        }
        .contentShape(Capsule())
    }

    private func paperRow(
        _ paper: QuestionBankCatalogPaperSummary,
        questionCount: Int,
        filter: QuestionBankHomeFilter
    ) -> some View {
        QuestionBankPaperSwipeRow(onDelete: {
            paperPendingDeletion = paper
            showsPaperDeletionConfirmation = true
        }) {
            if filter.hasQuestionRestriction {
                NavigationLink {
                    QuestionBankCrossPaperReaderView(filter: filter, paperID: paper.id)
                } label: {
                    paperCard(paper, questionCount: questionCount)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("question-bank-paper-\(paper.id)")
            } else {
                NavigationLink {
                    paperDestination(for: paper)
                } label: {
                    paperCard(paper, questionCount: questionCount)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("question-bank-paper-\(paper.id)")
            }
        }
        .contextMenu {
            Menu("移动到分组") {
                Button("未分组") { organizationStore.movePaper(paper.id, to: nil) }
                if !organizationStore.snapshot.groups.isEmpty {
                    Divider()
                    ForEach(organizationStore.snapshot.groups) { group in
                        Button(group.name) {
                            organizationStore.movePaper(paper.id, to: group.id)
                        }
                    }
                }
            }
        }
    }

    private func makeOrganizationSections(for candidates: [QuestionBankCatalogPaperSummary]) -> [QuestionBankOrganizationSection] {
        let paperIDs = candidates.map(\.paperID)
        let sections = organizationStore.sections(for: paperIDs)
        let assignedCount = sections.reduce(0) { total, section in total + section.paperIDs.count }
        guard assignedCount == candidates.count else {
            guard !candidates.isEmpty else { return [] }
            return [QuestionBankOrganizationSection(
                id: QuestionBankOrganizationSection.ungroupedID,
                groupID: nil,
                title: "未分组",
                paperIDs: paperIDs
            )]
        }
        return sections
    }

    private func paperSections(
        snapshot: QuestionBankCatalogHomeSnapshot,
        filter: QuestionBankHomeFilter,
        filterResult: QuestionBankCatalogHomeFilterResult,
        sections: [QuestionBankOrganizationSection],
        visibleByID: [String: QuestionBankCatalogPaperSummary]
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                paperSection(
                    section,
                    snapshot: snapshot,
                    filter: filter,
                    filterResult: filterResult,
                    visibleByID: visibleByID
                )
            }
        }
    }

    private func paperSection(
        _ section: QuestionBankOrganizationSection,
        snapshot: QuestionBankCatalogHomeSnapshot,
        filter: QuestionBankHomeFilter,
        filterResult: QuestionBankCatalogHomeFilterResult,
        visibleByID: [String: QuestionBankCatalogPaperSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if collapsedOrganizationSections.contains(section.id) {
                        collapsedOrganizationSections.remove(section.id)
                    } else {
                        collapsedOrganizationSections.insert(section.id)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: collapsedOrganizationSections.contains(section.id)
                        ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(section.title)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                    Text("\(section.paperIDs.count)")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.title)，\(section.paperIDs.count)套试卷")
            .accessibilityValue(collapsedOrganizationSections.contains(section.id) ? "已收起" : "已展开")
            .accessibilityIdentifier("question-bank-paper-group-\(section.id)")

            if !collapsedOrganizationSections.contains(section.id) {
                ForEach(section.paperIDs, id: \.self) { paperID in
                    if let paper = visibleByID[paperID] {
                        paperRow(
                            paper,
                            questionCount: filterResult.questionCount(for: paper.paperID),
                            filter: filter
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paperDestination(for paper: QuestionBankCatalogPaperSummary) -> some View {
        if let target = questionTarget(for: paper.paperID) {
            QuestionBankModuleView(
                paperID: paper.paperID,
                moduleID: target.moduleID,
                initialQuestionNumber: String(target.questionNumber)
            )
        } else {
            QuestionBankPaperView(
                paperID: paper.paperID,
                initialModuleTitle: "",
                initialQuestionNumber: searchedQuestionNumber.map { String($0) } ?? ""
            )
        }
    }

    private func questionTarget(for paperID: String) -> (moduleID: String, questionNumber: Int)? {
        guard let searchedQuestionNumber,
              let route = catalogHomeStore.snapshot?.questionRoute(
                paperID: paperID,
                questionNumber: searchedQuestionNumber
              ) else { return nil }
        return (route.moduleID, route.questionNumber)
    }

    private func deletePendingPaper() {
        guard let paper = paperPendingDeletion else { return }
        do {
            let result = try QuestionBankRepository.deletePaper(
                paperID: paper.paperID,
                context: modelContext,
                assetRoot: nil,
                batchSources: batchSources,
                batchMaterialLinks: batchMaterialLinks,
                batchQuestionLinks: batchQuestionLinks
            )
            organizationStore.removePaper(paper.paperID)
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
        if let jobID = activeImportJobID {
            activeImportJobID = nil
            Task { await QuestionBankImportJobService.shared.cancel(jobID: jobID, in: modelContext.container) }
        }
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
        let container = modelContext.container
        let worker = Task {
            try await QuestionBankImportJobService.shared.prepare(from: url, source: source, in: container) { update in
                Task { @MainActor in progress.update(runID: runID, progress: update) }
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
                let (jobID, prepared) = try await worker.value
                activeImportJobID = jobID
                guard activeImportID == runID else {
                    await QuestionBankImportJobService.shared.cancel(jobID: jobID, in: container)
                    return
                }
                if let pickerRequestID,
                   !importSelection.markPreviewReady(requestID: pickerRequestID) {
                    await QuestionBankImportJobService.shared.cancel(jobID: jobID, in: container)
                    return
                }
                let nextSheet: QuestionBankImportSheet
                do {
                    switch prepared {
                    case .single(let plan):
                        let preview = try await QuestionBankImportJobService.shared.preview(
                            jobID: jobID,
                            planOverride: plan,
                            metadata: plan.batchMetadata,
                            in: container
                        )
                        importLogger.info("package validation finished: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count), errors=\(plan.errors.count)")
                        nextSheet = .preview(jobID, plan, preview)
                    case .batch(let plan):
                        let preview = try await QuestionBankImportJobService.shared.preview(
                            jobID: jobID,
                            packageOverride: plan,
                            in: container
                        )
                        importLogger.info("batch package validation finished: papers=\(plan.paperPlans.count), assets=\(plan.manifest.assets.count)")
                        nextSheet = .batchPreview(jobID, plan, preview)
                    }
                } catch {
                    await QuestionBankImportJobService.shared.cancel(jobID: jobID, in: container)
                    throw error
                }
                activeImportSheet = nextSheet
                importProgress.finish(runID: runID)
            } catch is CancellationError {
                if activeImportID == runID {
                    importProgress.finish(runID: runID, message: "已取消读取")
                }
            } catch let failure as QuestionBankImportJobFailure where failure == .cancelled {
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

    private func commitImport(
        jobID: String,
        plan: QuestionBankImportPlan,
        decision: QuestionBankImportDecision,
        batchMetadata: QuestionBankBatchMetadata?,
        revisionToken: String
    ) {
        guard !isCommittingImport else { return }
        isCommittingImport = true
        inlineImportFailure = nil
        let container = modelContext.container
        let progress = importProgress
        Task { @MainActor in
            defer { isCommittingImport = false }
            do {
                let importResult = try await QuestionBankImportJobService.shared.commitSingle(
                    jobID: jobID,
                    plan: plan,
                    decision: decision,
                    metadata: batchMetadata,
                    expectedRevisionToken: revisionToken,
                    in: container,
                    onProgress: { update in
                        Task { @MainActor in
                            let count = update.totalCount > 0
                                ? " \(update.processedCount)/\(update.totalCount)"
                                : ""
                            progress.setMessage("\(update.phaseLabel)\(count)")
                        }
                    }
                )
                activeImportSheet = nil
                activeImportJobID = nil
                importLogger.info("atomic import committed: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count)")
                importAlertTitle = "导入完成"
                let batchSuffix = importResult.batchSummary.map {
                    "；批次新增唯一题 \($0.uniqueQuestions)，精确重复 \($0.duplicateQuestions)，待核 \($0.suspectedQuestions + $0.conflictingQuestions)"
                } ?? ""
                let backupSuffix = importResult.payloadBackupFileName.map {
                    "；更新前题目及图片备份：\($0)（应用支持目录/QuestionBankImportBackups）"
                } ?? ""
                importAlertMessage = "已导入“\(plan.paper?.title ?? "试卷")”：\(plan.modules.count) 个模块、\(plan.questions.count) 道题目\(batchSuffix)\(backupSuffix)。套卷成绩记录和学习库数据未更改。"
                showImportAlert = true
            } catch {
                let errorType = String(reflecting: type(of: error))
                importLogger.error("atomic import failed and was rolled back (\(errorType, privacy: .public))")
                inlineImportFailure = error.localizedDescription
                if let failure = error as? QuestionBankImportJobFailure, failure == .stalePreview {
                    do {
                        let refreshed = try await QuestionBankImportJobService.shared.preview(
                            jobID: jobID,
                            planOverride: plan,
                            metadata: batchMetadata,
                            in: container
                        )
                        activeImportSheet = .preview(jobID, plan, refreshed)
                    } catch {
                        inlineImportFailure = "\(failure.localizedDescription)\n\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func commitBatchImport(
        jobID: String,
        package: QuestionBankBatchPackagePlan,
        confirmedNewQuestionKeys: Set<QuestionBankBatchQuestionKey>,
        revisionToken: String
    ) {
        guard !isCommittingImport else { return }
        isCommittingImport = true
        inlineImportFailure = nil
        let container = modelContext.container
        let progress = importProgress
        Task { @MainActor in
            defer { isCommittingImport = false }
            do {
                let result = try await QuestionBankImportJobService.shared.commitBatch(
                    jobID: jobID,
                    package: package,
                    confirmedNewQuestionKeys: confirmedNewQuestionKeys,
                    expectedRevisionToken: revisionToken,
                    in: container,
                    onProgress: { update in
                        Task { @MainActor in
                            let count = update.totalCount > 0
                                ? " \(update.processedCount)/\(update.totalCount)"
                                : ""
                            progress.setMessage("\(update.phaseLabel)\(count)")
                        }
                    }
                )
                activeImportSheet = nil
                activeImportJobID = nil
                importAlertTitle = "批量更新完成"
                importAlertMessage = "已更新 \(result.updatedPaperCount) 套试卷、\(result.updatedQuestionCount) 道题，新增 \(result.addedQuestionCount) 道已确认题目；\(result.pendingPaperCount) 套试卷因缺少精确 paperID 或存在冲突而待核。未列入更新的题目、作答记录、涂鸦、笔记和本机标记均已保留。更新前题目及图片备份：\(result.payloadBackupFileName)（应用支持目录/QuestionBankImportBackups）。"
                showImportAlert = true
            } catch {
                inlineImportFailure = error.localizedDescription
                if let failure = error as? QuestionBankImportJobFailure, failure == .stalePreview {
                    do {
                        let refreshed = try await QuestionBankImportJobService.shared.preview(
                            jobID: jobID,
                            packageOverride: package,
                            in: container
                        )
                        activeImportSheet = .batchPreview(jobID, package, refreshed)
                    } catch {
                        inlineImportFailure = "\(failure.localizedDescription)\n\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func cancelImportJob(jobID: String) {
        guard !isCommittingImport else { return }
        activeImportSheet = nil
        activeImportJobID = nil
        Task { await QuestionBankImportJobService.shared.cancel(jobID: jobID, in: modelContext.container) }
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
            if revealOffset > 0 {
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
            }

            content
                .offset(x: revealOffset)
                .contentShape(Rectangle())
                .highPriorityGesture(
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
        }
        .contentShape(Rectangle())
        .accessibilityHint("向右滑动以显示删除按钮")
        .clipShape(Capsule())
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
    @Environment(\.modelContext) private var modelContext
    let jobID: String
    let plan: QuestionBankImportPlan
    let isImporting: Bool
    let preview: QuestionBankImportJobPreview
    @State private var records: [QuestionBankStoredRow]
    @State private var batchSources: [QuestionBankBatchSourceSnapshot]
    @State private var revisionToken: String
    @State private var batchPreparationPreview: QuestionBankBatchPreview?
    @State private var batchPreparationError: String?
    @Binding var importFailure: String?
    let onImport: (QuestionBankImportPlan, QuestionBankImportDecision, QuestionBankBatchMetadata?, String) -> Void
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
    @State private var correctedPlan: QuestionBankImportPlan?
    @State private var optionGroupsByID: [String: [String]] = [:]
    @State private var recordsScopeKey: String?

    init(jobID: String, plan: QuestionBankImportPlan, preview: QuestionBankImportJobPreview, isImporting: Bool,
         importFailure: Binding<String?>,
         onImport: @escaping (QuestionBankImportPlan, QuestionBankImportDecision, QuestionBankBatchMetadata?, String) -> Void,
         onCancel: @escaping () -> Void) {
        self.jobID = jobID
        self.plan = plan
        self.preview = preview
        _records = State(initialValue: preview.records)
        _batchSources = State(initialValue: preview.batchSources)
        _revisionToken = State(initialValue: preview.revisionToken)
        _batchPreparationPreview = State(initialValue: preview.batchPreparation)
        _batchPreparationError = State(initialValue: preview.batchPreparationError)
        self.isImporting = isImporting
        self._importFailure = importFailure
        self.onImport = onImport
        self.onCancel = onCancel
        _correctedPlan = State(initialValue: nil)
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

    private var effectivePlan: QuestionBankImportPlan { correctedPlan ?? plan }

    private var expectedRecordsScopeKey: String {
        guard let metadata = currentBatchMetadata else { return "\(effectivePlan.paper?.id ?? "")|none" }
        return [effectivePlan.paper?.id ?? "", metadata.identityKey, metadata.sourceID, metadata.revision,
                String(metadata.year), metadata.volumeID ?? "", metadata.sessionID ?? "",
                metadata.provinceCode ?? "", metadata.sourceProvinces?.map { "\($0.code):\($0.name)" }.joined(separator: ",") ?? ""]
            .joined(separator: "|")
    }

    private var pendingOptionCorrections: [QuestionBankImportOptionCorrection] {
        QuestionBankMultiBlankImportCorrection.pendingOptions(in: effectivePlan)
    }

    private var canApplyOptionCorrections: Bool {
        !pendingOptionCorrections.isEmpty && pendingOptionCorrections.allSatisfy { correction in
            let groups = optionGroupsByID[correction.id] ?? []
            guard groups.count == correction.blankCount,
                  groups.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return false
            }
            let joined = groups.joined(separator: QuestionBankMultiBlankOptionText.canonicalSeparator)
            return QuestionBankMultiBlankOptionText.validationMessage(
                for: joined,
                blankCount: correction.blankCount
            ) == nil
        }
    }

    private var batchPreparationResult: QuestionBankBatchPreview? {
        guard recordsScopeKey == expectedRecordsScopeKey,
              effectivePlan.canImport, currentBatchMetadata != nil,
              currentBatchMetadata?.validationError == nil,
              let batchPreparationPreview else { return nil }
        return batchPreparationPreview
    }

    private var duplicatePaperRecord: QuestionBankStoredRow? {
        guard let paper = plan.paper else { return nil }
        return records.first {
            $0.kind == QuestionBankRepository.paperKind
                && ($0.stableID == paper.id || $0.normalizedPaperKey == paper.duplicateKey)
        }
    }

    private var existingSourcePaperRecord: QuestionBankStoredRow? {
        guard includesBatch, let metadata = currentBatchMetadata else { return nil }
        guard recordsScopeKey == expectedRecordsScopeKey else { return nil }
        let stableSourceID = metadata.sourceID.trimmedNonempty
        guard let source = batchSources.first(where: { $0.sourceID == stableSourceID }) else { return nil }
        return records.first { $0.paperID == source.paperID && $0.kind == QuestionBankRepository.paperKind }
    }

    private var replacementPaperRecord: QuestionBankStoredRow? {
        if currentBatchMetadata != nil && recordsScopeKey != expectedRecordsScopeKey { return nil }
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
        onImport(effectivePlan, decision, currentBatchMetadata, revisionToken)
    }

    private func optionGroupBinding(
        for correction: QuestionBankImportOptionCorrection,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let groups = optionGroupsByID[correction.id] ?? []
                return groups.indices.contains(index) ? groups[index] : ""
            },
            set: { value in
                var groups = optionGroupsByID[correction.id] ?? Array(repeating: "", count: correction.blankCount)
                guard groups.indices.contains(index) else { return }
                groups[index] = value
                optionGroupsByID[correction.id] = groups
            }
        )
    }

    private func applyOptionCorrections() {
        let corrections = Dictionary(uniqueKeysWithValues: pendingOptionCorrections.map { correction in
            let groups = optionGroupsByID[correction.id] ?? []
            return (correction.id, groups.joined(separator: QuestionBankMultiBlankOptionText.canonicalSeparator))
        })
        guard let revised = QuestionBankMultiBlankImportCorrection.apply(
            to: effectivePlan,
            correctedTextByOptionID: corrections
        ) else { return }
        correctedPlan = revised
        optionGroupsByID = [:]
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
            if let batchPreparationError { return batchPreparationError }
            return nil
        }()
        let preparedBatch = batchResult
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
                        } else if let preview = preparedBatch {
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
                if !pendingOptionCorrections.isEmpty {
                    Section("多空逻辑填空选项校对") {
                        Text("这些多空选项没有明确的词语边界。请对照原卷，逐项填写每个空对应的词语；应用不会猜测中文边界。")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                        ForEach(pendingOptionCorrections) { correction in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("第\(correction.questionNumber)题 · 选项\(correction.optionID)")
                                    .font(AppTheme.bodyFont.weight(.semibold))
                                Text("原始选项：\(correction.currentText)")
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                ForEach(0..<correction.blankCount, id: \.self) { index in
                                    TextField(
                                        "第\(index + 1)个空的词语",
                                        text: optionGroupBinding(for: correction, index: index)
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier(
                                        "question-bank-import-correction-\(correction.questionID)-\(correction.optionID)-\(index)"
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Button("应用校对并重新校验", action: applyOptionCorrections)
                            .disabled(!canApplyOptionCorrections)
                            .accessibilityIdentifier("question-bank-import-apply-option-corrections")
                    }
                } else if correctedPlan != nil {
                    Section("选项校对") {
                        Label("已按人工校对结果分开多空选项词语", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text("导入文件本身未被修改。")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                    }
                }
                if !effectivePlan.errors.isEmpty {
                    Section("校验错误（修复后再导入）") {
                        ForEach(Array(effectivePlan.errors.enumerated()), id: \.offset) { _, error in
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
                    .disabled(!effectivePlan.canImport || isImporting
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
                Text("按来源标识的修订关系、试卷 ID，或年份、考试类型、卷别和名称识别替换目标。替换失败时仍保留原数据。\(replacementContinuityWarning ?? "替换包的稳定 ID 与现有数据一致，原涂鸦仍按原题目 ID 关联。")如果你手动编辑过题干或选项文字，替换试卷会覆盖本地修改。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: preview.revisionToken) { _, _ in
            records = preview.records
            batchSources = preview.batchSources
            revisionToken = preview.revisionToken
            batchPreparationPreview = preview.batchPreparation
            batchPreparationError = preview.batchPreparationError
            recordsScopeKey = expectedRecordsScopeKey
        }
        .task(id: expectedRecordsScopeKey) {
            let requestKey = expectedRecordsScopeKey
            let requestedPlan = effectivePlan
            let requestedMetadata = currentBatchMetadata
            let container = modelContext.container
            recordsScopeKey = nil
            batchPreparationPreview = nil
            batchPreparationError = nil
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                let updated = try await QuestionBankImportJobService.shared.preview(
                    jobID: jobID,
                    planOverride: requestedPlan,
                    metadata: requestedMetadata,
                    in: container
                )
                guard !Task.isCancelled, requestKey == expectedRecordsScopeKey else { return }
                records = updated.records
                batchSources = updated.batchSources
                revisionToken = updated.revisionToken
                batchPreparationPreview = updated.batchPreparation
                batchPreparationError = updated.batchPreparationError
                recordsScopeKey = requestKey
                importFailure = nil
            } catch is CancellationError {
                // A newer metadata edit will request a fresh bounded snapshot.
            } catch {
                importFailure = "读取替换目标失败：\(error.localizedDescription)"
            }
        }
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

private struct QuestionBankPaperModuleSummary: Identifiable {
    let module: QuestionBankCatalogModuleSummary

    var id: String { module.sourceCompoundID }
}

private struct QuestionBankPaperView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var answerStateStore = QuestionBankAnswerStateStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rootTabSelection) private var rootTabSelection
    @Query private var batchSources: [QuestionBankBatchSourceRecord]
    @Query private var batchMaterialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var batchQuestionLinks: [QuestionBankBatchQuestionLinkRecord]
    let paperID: String
    let initialQuestionNumber: String
    @State private var paper: QuestionBankCatalogPaperSummary?
    @State private var moduleSummaries: [QuestionBankPaperModuleSummary] = []
    @State private var allModuleTitles: [String] = []
    @State private var paperQuestionIDs: [String] = []
    @State private var paperSnapshotError: String?
    @State private var isLoadingPaperSnapshot = false
    @State private var paperSnapshotTask: Task<Void, Never>?
    @State private var selectedModuleTitle: String
    @State private var isPaperRouteVisible = false
    @State private var isPaperViewVisible = false
    @State private var needsPaperSnapshot = true
    @State private var showsPaperFilters = false
    @State private var isPaperEditorPresented = false
    @State private var showsPaperDeletionConfirmation = false
    @State private var showsClearPaperAnswersConfirmation = false
    @State private var showsPaperActionAlert = false
    @State private var paperActionAlertTitle = "操作未完成"
    @State private var paperActionAlertMessage = ""

    init(paperID: String, initialModuleTitle: String, initialQuestionNumber: String) {
        self.paperID = paperID
        self.initialQuestionNumber = initialQuestionNumber
        _selectedModuleTitle = State(initialValue: initialModuleTitle)
    }

    private var modules: [QuestionBankPaperModuleSummary] {
        guard !selectedModuleTitle.isEmpty else { return moduleSummaries }
        return moduleSummaries.filter { $0.module.title == selectedModuleTitle }
    }

    private func refreshPaperSnapshot() {
        paperSnapshotTask?.cancel()
        isLoadingPaperSnapshot = true
        paperSnapshotError = nil
        paperSnapshotTask = Task { @MainActor in
            do {
                async let paperRow = QuestionBankCatalogService.paperSummary(
                    for: paperID,
                    in: modelContext.container
                )
                async let moduleRows = QuestionBankCatalogService.moduleSummaries(
                    for: paperID,
                    in: modelContext.container
                )
                async let questionRows = QuestionBankCatalogService.questionIDs(
                    for: paperID,
                    in: modelContext.container
                )
                let (paperRow, modules, questions) = try await (paperRow, moduleRows, questionRows)
                guard !Task.isCancelled else { return }
                paper = paperRow
                moduleSummaries = modules.map(QuestionBankPaperModuleSummary.init(module:))
                paperQuestionIDs = questions.map(\.sourceCompoundID)
                allModuleTitles = Array(Set(modules.map(\.title))).sorted()
            } catch is CancellationError {
                return
            } catch {
                paperSnapshotError = error.localizedDescription
            }
            isLoadingPaperSnapshot = false
        }
    }

    private func activatePaperViewIfNeeded() {
        let shouldBeVisible = isPaperRouteVisible && rootTabSelection.wrappedValue == .questionBank
        isPaperViewVisible = shouldBeVisible
        guard shouldBeVisible, needsPaperSnapshot else { return }
        needsPaperSnapshot = false
        refreshPaperSnapshot()
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
                if showsPaperFilters {
                    HStack(spacing: 8) {
                        Menu {
                            Button("全部模块") { selectedModuleTitle = "" }
                                .accessibilityIdentifier("question-bank-paper-module-filter-all")
                            ForEach(allModuleTitles, id: \.self) { title in
                                Button(title) { selectedModuleTitle = title }
                                    .accessibilityIdentifier("question-bank-paper-module-filter-\(title)")
                            }
                        } label: {
                            filterLabel(selectedModuleTitle.isEmpty ? "全部模块" : selectedModuleTitle)
                        }
                        .accessibilityLabel(
                            "本卷模块筛选：\(selectedModuleTitle.isEmpty ? "全部模块" : selectedModuleTitle)"
                        )
                        .accessibilityIdentifier("question-bank-paper-module-filter-menu")
                        Spacer()
                    }
                    .accessibilityIdentifier("question-bank-paper-filter-panel")
                }
                if modules.isEmpty {
                    if isLoadingPaperSnapshot {
                        ProgressView("正在读取模块目录…").frame(maxWidth: .infinity, minHeight: 120)
                    } else if let paperSnapshotError {
                        NativeStatusCard(title: "模块目录暂不可用", detail: paperSnapshotError, systemImage: "exclamationmark.triangle", color: AppTheme.danger)
                    } else if paper == nil {
                        NativeStatusCard(title: "目录尚未就绪", detail: "返回题库首页重试目录回填。", systemImage: "books.vertical", color: AppTheme.accent)
                    } else {
                        NativeStatusCard(title: "没有匹配模块", detail: "更改模块筛选条件。", systemImage: "line.3.horizontal.decrease", color: AppTheme.accent)
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(modules) { moduleSummary in
                            let module = moduleSummary.module
                            let count = module.questionCount
                            NavigationLink {
                                QuestionBankModuleView(
                                    paperID: paperID,
                                    moduleID: module.moduleID,
                                    initialQuestionNumber: initialQuestionNumber
                                )
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(String(format: "%02d", module.sequence))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 36, height: 34, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(module.title)
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
                                .accessibilityIdentifier("question-bank-module-\(module.moduleID)")
                            }
                    }
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(paper?.title ?? "模块目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsPaperFilters.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("筛选模块")
                .accessibilityValue(showsPaperFilters ? "已展开" : "已收起")
                .accessibilityIdentifier("question-bank-paper-filter-toggle")

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
                    Button(role: .destructive) {
                        showsClearPaperAnswersConfirmation = true
                    } label: {
                        Label("清除本卷作答记录", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("question-bank-clear-paper-answers")
                    .disabled(paperQuestionIDs.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("试卷管理")
                .accessibilityIdentifier("question-bank-paper-management-menu")
            }
        }
        .onAppear {
            isPaperRouteVisible = true
            activatePaperViewIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: QuestionBankRecordChangeSignal.notification)) { notification in
            guard QuestionBankRecordChangeSignal.affects(paperID, notification: notification) else { return }
            needsPaperSnapshot = true
            guard isPaperViewVisible, rootTabSelection.wrappedValue == .questionBank else { return }
            needsPaperSnapshot = false
            Task { @MainActor in
                await Task.yield()
                guard isPaperViewVisible, rootTabSelection.wrappedValue == .questionBank else {
                    needsPaperSnapshot = true
                    return
                }
                refreshPaperSnapshot()
            }
        }
        .onChange(of: rootTabSelection.wrappedValue) { _, selectedTab in
            if selectedTab == .questionBank {
                activatePaperViewIfNeeded()
            } else {
                isPaperViewVisible = false
            }
        }
        .onDisappear {
            isPaperRouteVisible = false
            isPaperViewVisible = false
            paperSnapshotTask?.cancel()
            paperSnapshotTask = nil
        }
        .sheet(isPresented: $isPaperEditorPresented) {
            if let paper {
                QuestionBankPaperMetadataEditor(paper: QuestionBankPaper(
                    id: paper.paperID,
                    title: paper.title,
                    year: paper.year,
                    examType: paper.examType,
                    volume: paper.volume,
                    source: "",
                    importVersion: "",
                    provinceCode: paper.provinceCode,
                    provinceName: paper.provinceName
                )) { title, year, examType, volume, provinceCode, provinceName in
                    let paperKind = QuestionBankRepository.paperKind
                    let paperPredicate = #Predicate<QuestionBankRecord> {
                        $0.paperID == paper.paperID && $0.kind == paperKind
                    }
                    guard let paperRecord = try modelContext.fetch(
                        FetchDescriptor<QuestionBankRecord>(predicate: paperPredicate)
                    ).first else { throw QuestionBankPaperMetadataEditFailure.missingPaper }
                    try QuestionBankRepository.updatePaperMetadata(
                        record: paperRecord,
                        title: title,
                        year: year,
                        examType: examType,
                        volume: volume,
                        provinceCode: provinceCode,
                        provinceName: provinceName,
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
        .confirmationDialog("清除本卷作答记录？", isPresented: $showsClearPaperAnswersConfirmation, titleVisibility: .visible) {
            Button("清除本卷作答记录", role: .destructive, action: clearPaperAnswers)
            Button("取消", role: .cancel) { }
        } message: {
            Text("将清除本试卷所有题目的已选选项和答案揭示状态。涂鸦、题目文字修改及试卷数据会保留。")
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

    private func clearPaperAnswers() {
        Task {
            do {
                try await answerStateStore.clear(paperQuestionIDs, paperScope: paperID, in: modelContext.container)
                paperActionAlertTitle = "作答记录已清除"
                paperActionAlertMessage = "已清除本卷 \(paperQuestionIDs.count) 道题的作答记录。"
            } catch {
                paperActionAlertTitle = "清除作答记录失败"
                paperActionAlertMessage = error.localizedDescription
            }
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
