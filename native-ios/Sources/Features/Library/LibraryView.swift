import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Binding var navigationPath: [LibraryRoute]
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "errors"
            || record.collection == "notes"
            || record.collection == "stickies"
            || record.collection == "words"
            || record.collection == "exams"
            || record.collection == "keyvalue"
    }) private var records: [StoredRecord]
    @State private var scope = LibraryScope()
    @State private var expandedSubject: String?
    @State private var kind: LibraryContentKind = .errors
    @State private var searchText = ""
    @State private var selectedTag = ""
    @AppStorage("native.library.errors.redoMode") private var redoPracticeEnabled = false
    @AppStorage("native.library.card-size.v1") private var storedCardSize = LibraryCardSize.medium.rawValue
    @AppStorage("native.library.errors.includeMastered.v1") private var includesMasteredErrors = false
    @AppStorage("native.library.controls.category.v2") private var showsCategoryControl = false
    @AppStorage("native.library.controls.card-size.v2") private var showsCardSizeControl = false
    @State private var showNewNoteType = false
    @State private var noteTypeDraft = ""
    @State private var noteTypeColor = NoteTypeRepository.colors[0]
    @State private var deleteTarget: LibraryDeleteTarget?
    @State private var showSearch = false
    @State private var wordCategory: WordCategory = .idiomDefinition
    @State private var wordSentiment = ""
    @State private var wordEntryKind = ""
    @State private var renderLimit = 40
    @State private var selectedQuantityType = ""
    @State private var selectedErrorType = LibraryErrorTypeFilter.all
    @State private var snapshotCache = LibrarySnapshotCache()
    @State private var recordListCache = LibraryRecordListCache()
    @State private var partitionStates: [LibraryReviewSource: LibraryPartitionState] = [:]
    @State private var showBulkSourcePicker = false
    @State private var sourceAssignmentError: String?
    @State private var pendingEditorRouteKey: String?
    @State private var preparedEditDrafts: [String: LibraryRecordDraft] = [:]
    @AppStorage("native.library.graphDisplayMode") private var graphDisplayMode = "cards"
    @AppStorage("native.library.legacyIndexMigrationVersion") private var legacyIndexMigrationVersion = 0

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                LibrarySidebar(
                    records: records,
                    scope: $scope,
                    expandedSubject: $expandedSubject,
                    compact: usesCompactSidebar(in: proxy.size.width),
                    onScopeChanged: resetContextFilters
                )
                .frame(width: sidebarWidth(in: proxy.size.width))
                content(availableWindowWidth: proxy.size.width)
            }
        }
        .background(Color.white)
        .stableRootNavigationBar()
        .onAppear { NativePerformanceLog.event("library onAppear") }
        .onReceive(NotificationCenter.default.publisher(for: .legacyBackupRestoreDidComplete)) { _ in
            snapshotCache.invalidate()
            recordListCache.invalidate()
            ReviewSourceMetadataCache.shared.removeAll()
        }
        .task { await runLegacyIndexMigrationIfNeeded() }
        .onChange(of: quantityQuestionTypes) { _, values in
            if !selectedQuantityType.isEmpty,
               selectedQuantityType != "未分类",
               !values.contains(selectedQuantityType) {
                selectedQuantityType = ""
            }
        }
        .onChange(of: errorTypes) { _, values in
            if let id = selectedErrorType.selectedID, !values.contains(where: { $0.id == id }) {
                selectedErrorType = .all
            }
        }
        .onChange(of: navigationPath) { _, path in
            let activeEditorKey: String? = path.last.flatMap { route in
                guard case let .editor(kind, recordID) = route, let recordID else { return nil }
                return "\(kind.collection)|\(recordID)"
            }
            if let activeEditorKey, let draft = preparedEditDrafts[activeEditorKey] {
                if preparedEditDrafts.count > 1 { preparedEditDrafts = [activeEditorKey: draft] }
            } else if !preparedEditDrafts.isEmpty {
                preparedEditDrafts = [:]
            }
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            destination(for: route)
                .secondaryPageTabBarHidden()
        }
        .sheet(isPresented: $showBulkSourcePicker) {
            LibraryBulkSourceAssignmentView(records: pendingSourceRecords) { selected, source in
                assignPendingRecords(selected, to: source)
            }
        }
        .alert("来源确认失败", isPresented: Binding(
            get: { sourceAssignmentError != nil },
            set: { if !$0 { sourceAssignmentError = nil } }
        )) {
            Button("好", role: .cancel) { sourceAssignmentError = nil }
        } message: { Text(sourceAssignmentError ?? "") }
        .overlay {
            if showNewNoteType {
                noteTypeDialog
            } else if let deleteTarget {
                NativeDeleteDialog(
                    title: "删除\(deleteTarget.kind.rawValue)",
                    message: "删除后无法在 App 内恢复。",
                    onDelete: { remove(deleteTarget); self.deleteTarget = nil },
                    onCancel: { self.deleteTarget = nil }
                )
            }
        }
    }

    private func openEditorAfterMenuDismisses(
        kind: LibraryContentKind,
        recordID: String,
        preparedDraft: LibraryRecordDraft? = nil
    ) {
        let routeKey = "\(kind.collection)|\(recordID)"
        guard pendingEditorRouteKey == nil else { return }
        if let preparedDraft { preparedEditDrafts[routeKey] = preparedDraft }
        pendingEditorRouteKey = routeKey
        LibraryPerformanceLog.editorTransition(
            "push-request",
            recordID: recordID,
            begins: true,
            transitionKey: "route-push"
        )
        Task { @MainActor in
            guard pendingEditorRouteKey == routeKey else { return }
            LibraryPerformanceLog.editorTransition("push-start", recordID: recordID, transitionKey: "route-push")
            await Task.yield()
            guard pendingEditorRouteKey == routeKey else { return }
            LibraryPerformanceLog.editorTransition("push-append", recordID: recordID, transitionKey: "route-push")
            if kind == .errors,
               let record = records.first(where: { $0.collection == kind.collection && $0.recordID == recordID }),
               record.isShenlunRecord,
               record.requiresShenlunAdaptation {
                navigationPath.append(.shenlunAdaptation(recordID: recordID))
            } else {
                navigationPath.append(.editor(kind: kind, recordID: recordID))
            }
            pendingEditorRouteKey = nil
            LibraryPerformanceLog.editorTransition(
                "push-end",
                recordID: recordID,
                completes: true,
                transitionKey: "route-push"
            )
        }
    }

    private func cancelPendingEditorRoute(kind: LibraryContentKind, recordID: String) {
        let routeKey = "\(kind.collection)|\(recordID)"
        guard pendingEditorRouteKey == routeKey else { return }
        pendingEditorRouteKey = nil
        preparedEditDrafts[routeKey] = nil
        LibraryPerformanceLog.editorTransition(
            "push-cancel",
            recordID: recordID,
            details: "detail-action-cancelled",
            completes: true,
            transitionKey: "route-push"
        )
    }

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case let .shenlunAdaptation(recordID):
            shenlunAdaptationDestination(recordID: recordID)
        case let .editor(kind, recordID):
            editorDestination(kind: kind, recordID: recordID)
        case let .detail(kind, recordID):
            if let record = records.first(where: { $0.collection == kind.collection && $0.recordID == recordID }) {
                if kind == .words {
                    WordLibraryRecordDetailView(
                        record: record,
                        onEdit: { openEditorAfterMenuDismisses(kind: .words, recordID: recordID) },
                        onDelete: {
                            remove(LibraryDeleteTarget(kind: kind, recordID: recordID))
                            popCurrentRoute()
                        },
                        onOpenLinkedError: { navigationPath.append(.detail(kind: .errors, recordID: $0)) }
                    )
                } else if kind == .errors, record.isShenlunRecord {
                    ShenlunRecordDetailView(
                        record: record,
                        onEdit: { openEditorAfterMenuDismisses(kind: kind, recordID: recordID) },
                        onDelete: {
                            remove(LibraryDeleteTarget(kind: kind, recordID: recordID))
                            popCurrentRoute()
                        }
                    )
                } else if kind == .notes {
                    LibraryNoteDetailView(
                        record: record,
                        onEdit: { openEditorAfterMenuDismisses(kind: .notes, recordID: recordID) },
                        onDelete: {
                            remove(LibraryDeleteTarget(kind: kind, recordID: recordID))
                            popCurrentRoute()
                        }
                    )
                } else {
                    LibraryRecordDetailView(
                        kind: kind,
                        scope: scope,
                        record: record,
                        onEdit: { activeRecordID in openEditorAfterMenuDismisses(kind: kind, recordID: activeRecordID) },
                        onEditPrepared: { activeRecordID, draft in
                            openEditorAfterMenuDismisses(kind: kind, recordID: activeRecordID, preparedDraft: draft)
                        },
                        onDelete: { activeRecordID in
                            remove(LibraryDeleteTarget(kind: kind, recordID: activeRecordID))
                            popCurrentRoute()
                        },
                        onCancelEditRequest: { requestedRecordID in cancelPendingEditorRoute(kind: kind, recordID: requestedRecordID) },
                        orderedRecordIDs: kind == .errors ? orderedVisibleErrorRecordIDs : [],
                        onOpenLinkedWord: { navigationPath.append(.detail(kind: .words, recordID: $0)) },
                        onOpenLinkedError: { navigationPath.append(.detail(kind: .errors, recordID: $0)) }
                    )
                }
            } else {
                NativeStatusCard(title: "记录不存在", detail: "这条记录可能已经被删除", systemImage: "exclamationmark.triangle", color: .secondary)
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private func shenlunAdaptationDestination(recordID: String) -> some View {
        if let record = records.first(where: { $0.collection == "errors" && $0.recordID == recordID }) {
            ShenlunAdaptationView(record: record) {
                replaceCurrentRoute(with: .editor(kind: .errors, recordID: recordID))
            }
        } else {
            NativeStatusCard(
                title: "记录不存在",
                detail: "无法载入需要适配的申论记录",
                systemImage: "exclamationmark.triangle",
                color: AppTheme.warning
            )
            .padding(20)
        }
    }

    @ViewBuilder
    private func editorDestination(kind: LibraryContentKind, recordID: String?) -> some View {
        if let recordID {
            if let record = records.first(where: { $0.collection == kind.collection && $0.recordID == recordID }) {
                if kind == .errors, record.isShenlunRecord, record.requiresShenlunAdaptation {
                    ShenlunAdaptationView(record: record) {
                        replaceCurrentRoute(with: .editor(kind: .errors, recordID: recordID))
                    }
                } else {
                    recordEditor(kind: kind, recordID: recordID, record: record)
                }
            } else {
                NativeStatusCard(
                    title: "记录不存在",
                    detail: "无法载入原记录，已阻止进入空白新建页面",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
                .padding(20)
            }
        } else {
            recordEditor(kind: kind, recordID: nil, record: nil)
        }
    }

    private func recordEditor(kind: LibraryContentKind, recordID: String?, record: StoredRecord?) -> some View {
        let preparedDraft = recordID.flatMap { preparedEditDrafts["\(kind.collection)|\($0)"] }
        return LibraryRecordEditorView(
            kind: kind,
            scope: recordID == nil ? creationScope : scope,
            record: record,
            preferredType: recordID == nil ? (kind == .words ? wordCategory.rawValue : selectedTag) : "",
            preferredErrorTypeID: recordID == nil && kind == .errors ? selectedErrorType.selectedID : nil,
            preparedDraft: preparedDraft,
            dismissAfterSave: !(recordID == nil && (kind == .errors || kind == .words)),
            onSaved: { savedID in
                if let recordID {
                    preparedEditDrafts["\(kind.collection)|\(recordID)"] = nil
                    return
                }
                guard recordID == nil, kind == .errors || kind == .words else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard !navigationPath.isEmpty else { return }
                    navigationPath[navigationPath.count - 1] = .detail(kind: kind, recordID: savedID)
                }
            }
        )
    }

    private var creationScope: LibraryScope {
        guard scope.subject == "数量关系" else { return scope }
        return LibraryScope(
            subject: "数量关系",
            module: LibraryQuantityTypeSelectionPolicy.concreteType(
                selected: selectedQuantityType,
                availableTypes: quantityQuestionTypes
            ),
            reviewSource: scope.reviewSource
        )
    }

    private func popCurrentRoute() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    private func replaceCurrentRoute(with route: LibraryRoute) {
        guard !navigationPath.isEmpty else { return }
        navigationPath[navigationPath.count - 1] = route
    }

    @MainActor
    private func runLegacyIndexMigrationIfNeeded() async {
        guard legacyIndexMigrationVersion < LibraryLegacyIndexMigration.currentVersion else {
            NativePerformanceLog.event("library legacy index migration already current")
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await LibraryLegacyIndexMigration.runIfNeeded(
                in: modelContext.container,
                storedVersion: legacyIndexMigrationVersion
            )
            legacyIndexMigrationVersion = LibraryLegacyIndexMigration.currentVersion
            NativePerformanceLog.mark("library legacy index migration task", since: started)
        } catch {
            NativePerformanceLog.event("library legacy index migration failed: \(error.localizedDescription)")
        }
    }

    private func content(availableWindowWidth: CGFloat) -> some View {
        let scopedRecords = sortedScopedRecords
        let tagFilteredRecords = filterRecords(matching: selectedTag, from: scopedRecords)
        let renderedSnapshots = snapshots(from: tagFilteredRecords)
        let visibleRecords = displayedRecords(from: renderedSnapshots)
        let visibleTags = showsCategoryControl && canShowCategoryControl ? availableTags(from: scopedRecords) : []
        let hasMoreVisibleRecords = renderLimit < tagFilteredRecords.count
        return VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if pendingSourceCount > 0 {
                        HStack(spacing: 9) {
                            Image(systemName: "questionmark.folder.fill")
                                .foregroundStyle(AppTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("有 \(pendingSourceCount) 条记录待确认来源")
                                    .font(AppTheme.inputFont.weight(.semibold))
                                Text("确认后可在真题或模拟题复盘中筛选。")
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Button("确认") { showBulkSourcePicker = true }
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                        }
                        .padding(11)
                        .background(AppTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                    }
                    if showSearch {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField(searchPrompt, text: $searchText).font(AppTheme.inputFont)
                            Button { searchText = ""; showSearch = false } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).frame(height: 36)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if isQuantityContext, kind == .errors || kind == .notes { quantityTypeBar }
                    if kind == .errors, errorTypeSubject != nil { errorTypeBar }
                    filterBar(availableTags: visibleTags)
                    if kind == .words { wordCategoryBar }
                    if kind == .notes, noteContext != nil { noteTypeBar }
                    if kind == .stickies, stickyContext != nil { stickyTagBar }
                    if visibleRecords.isEmpty {
                        VStack(spacing: 10) {
                            NativeStatusCard(
                                title: emptyTitle,
                                detail: emptyDetail,
                                systemImage: emptyIcon,
                                color: .secondary
                            )
                            if kind == .words {
                                Button(action: importWordSamples) {
                                    Label("导入当前分类示例", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    } else if isGraphReasoningContext, graphDisplayMode == "flashcards" {
                        GraphReasoningFlashcardView(
                            records: visibleRecords,
                            onEdit: { navigationPath.append(.editor(kind: kind, recordID: $0.record.recordID)) }
                        )
                    } else {
                        LibraryMasonryGrid(
                            records: visibleRecords,
                            kind: kind,
                            cardSize: cardSize,
                            partitionKey: "\(kind.collection)|\(scope.subject ?? "")|\(scope.module ?? "")|\(scope.reviewSource.rawValue)|\(includesMasteredErrors)|\(selectedTag)|\(selectedQuantityType)|\(selectedErrorType)|\(searchText)",
                            onOpen: { open($0) },
                            onDelete: { deleteTarget = LibraryDeleteTarget(kind: kind, recordID: $0.record.recordID) },
                            hiddenTags: kind == .notes && !selectedTag.isEmpty ? [selectedTag] : [],
                            hidesQuantityTypeLabel: isQuantityContext
                                && LibraryQuantityTypeSelectionPolicy.concreteType(
                                    selected: selectedQuantityType,
                                    availableTypes: quantityQuestionTypes
                                ) != nil
                        )
                    }
                    if hasMoreVisibleRecords {
                        Button {
                            renderLimit += 40
                        } label: {
                            Label("加载更多", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NativeSecondaryButtonStyle())
                    }
                }
                .padding(14)
            }
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
        .overlay(alignment: .bottomTrailing) {
            GeometryReader { _ in
                if canCreateRecord {
                    Button {
                        navigationPath.append(.editor(kind: kind, recordID: nil))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(AppTheme.accent, in: Circle())
                            .shadow(color: AppTheme.accent.opacity(0.28), radius: 12, y: 5)
                    }
                    .buttonStyle(NativePressButtonStyle())
                    .accessibilityLabel("新增\(kind.rawValue)")
                    .accessibilityIdentifier("library-add-record")
                    .padding(.trailing, 18)
                    .padding(.bottom, 8)
                    .offset(y: NativeFloatingActionPlacement.maySitAtTabBarTopEdge(
                        windowWidth: availableWindowWidth,
                        tabBarVisible: navigationPath.isEmpty
                    ) ? 34 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                reviewSourceSelector
                Spacer(minLength: 0)
                headerMenu
            }

            HStack(spacing: 4) {
                ForEach(availableKinds) { value in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { kind = value }
                        selectedTag = ""
                        renderLimit = 40
                    } label: {
                        Text(value.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(kind == value ? AppTheme.accent : Color.primary)
                            .background(kind == value ? AppTheme.secondaryBackground : Color.clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("library-kind-\(value.rawValue)")
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var headerMenu: some View {
        Menu {
            Button { showSearch = true } label: { Label("搜索", systemImage: "magnifyingglass") }
            if kind == .errors {
                Button { redoPracticeEnabled.toggle() } label: {
                    Label(redoPracticeEnabled ? "错题模式" : "重做模式", systemImage: redoPracticeEnabled ? "doc.text" : "arrow.counterclockwise")
                }
                Toggle(isOn: $includesMasteredErrors) {
                    Label("已掌握", systemImage: "checkmark.circle")
                }
            }
            Section("显示控件") {
                if canShowCategoryControl {
                    Toggle(isOn: $showsCategoryControl) { Label("标签筛选", systemImage: "tag") }
                }
                Toggle(isOn: $showsCardSizeControl) { Label("题卡大小", systemImage: "rectangle.grid.2x2") }
            }
            if hasActiveFilterConditions {
                Section("当前生效筛选") {
                    if !selectedTag.isEmpty { Text("分类：\(selectedTag)") }
                    if !selectedQuantityType.isEmpty { Text("题型：\(selectedQuantityType)") }
                    if kind == .words, let category = WordCategory(rawValue: wordCategory.rawValue) {
                        Text("词语类别：\(category.shortTitle)")
                    }
                    if !wordEntryKind.isEmpty, let entry = WordEntryKind(rawValue: wordEntryKind) {
                        Text("内容类型：\(entry.title)")
                    }
                    if !wordSentiment.isEmpty { Text("感情色彩：\(wordSentiment)") }
                    Button(role: .destructive, action: clearActiveFilters) {
                        Label("清除筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            Section("来源") {
                Button { selectReviewSource(.pending) } label: {
                    Label("待确认来源（\(pendingSourceCount)）", systemImage: "questionmark.folder")
                }
                if pendingSourceCount > 0 {
                    Button { showBulkSourcePicker = true } label: {
                        Label("批量确认来源（\(pendingSourceCount)）", systemImage: "checkmark.square")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 44)
                .background(Color.white, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("题库设置与筛选")
    }

    private var reviewSourceSelector: some View {
        HStack(spacing: 2) {
            ForEach([LibraryReviewSource.real, .mock], id: \.self) { source in
                Button { selectReviewSource(source) } label: {
                    Text(source.title)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 116, height: 34)
                        .foregroundStyle(scope.reviewSource == source ? AppTheme.accent : Color.primary)
                        .background(scope.reviewSource == source ? Color.primary.opacity(0.075) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(width: 116, height: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 44)
        .background {
            Capsule().fill(Color.primary.opacity(0.04)).frame(height: 36)
        }
    }

    private var pendingSourceCount: Int {
        let reviewSources = recordListCache.reviewSources(for: records)
        return records.lazy.filter { record in
            ["errors", "notes", "stickies"].contains(record.collection)
                && scope.contains(record)
                && reviewSources[record.compoundID] == .pending
        }.count
    }

    private var pendingSourceRecords: [StoredRecord] {
        let reviewSources = recordListCache.reviewSources(for: records)
        return records.filter { record in
            ["errors", "notes", "stickies"].contains(record.collection)
                && scope.contains(record)
                && reviewSources[record.compoundID] == .pending
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func assignPendingRecords(_ selectedRecords: [StoredRecord], to source: LibraryReviewSource) {
        do {
            try LibraryReviewSourceRepository.assign(source, to: selectedRecords, allRecords: records, context: modelContext)
            showBulkSourcePicker = false
        } catch {
            sourceAssignmentError = error.localizedDescription
        }
    }

    private func selectReviewSource(_ source: LibraryReviewSource) {
        guard source != scope.reviewSource else { return }
        partitionStates[scope.reviewSource] = LibraryPartitionState(
            scope: scope,
            expandedSubject: expandedSubject,
            kind: kind,
            searchText: searchText,
            selectedTag: selectedTag,
            selectedQuantityType: selectedQuantityType,
            selectedErrorType: selectedErrorType,
            renderLimit: renderLimit,
            wordCategory: wordCategory,
            wordSentiment: wordSentiment,
            wordEntryKind: wordEntryKind
        )
        if let saved = partitionStates[source] {
            scope = saved.scope
            expandedSubject = saved.expandedSubject
            kind = saved.kind
            searchText = saved.searchText
            selectedTag = saved.selectedTag
            selectedQuantityType = saved.selectedQuantityType
            selectedErrorType = saved.selectedErrorType
            renderLimit = saved.renderLimit
            wordCategory = saved.wordCategory
            wordSentiment = saved.wordSentiment
            wordEntryKind = saved.wordEntryKind
        } else {
            scope = LibraryScope(reviewSource: source)
            expandedSubject = nil
            kind = .errors
            resetContextFilters()
        }
    }

    @ViewBuilder
    private func filterBar(availableTags: [String]) -> some View {
        if hasVisibleFilterControls {
        HStack(spacing: 8) {
            if kind == .words {
                Menu {
                    Button("全部内容类型") { wordEntryKind = "" }
                    ForEach(WordEntryKind.allCases) { value in
                        Button(value.title) { wordEntryKind = value.rawValue }
                    }
                } label: {
                    filterLabel(WordEntryKind(rawValue: wordEntryKind)?.title ?? "词语/搭配")
                }
                Menu {
                    Button("全部感情色彩") { wordSentiment = "" }
                    ForEach(["褒义", "贬义", "中性"], id: \.self) { value in
                        Button(value) { wordSentiment = value }
                    }
                } label: {
                    filterLabel(wordSentiment.isEmpty ? "感情色彩" : wordSentiment)
                }
            }

            if showsCategoryControl && canShowCategoryControl && !availableTags.isEmpty {
                Menu {
                    Button(kind == .notes ? "全部标签" : "全部标签/标记") { selectTag("") }
                    ForEach(availableTags, id: \.self) { tag in
                        Button(tag) { selectTag(tag) }
                    }
                } label: {
                    filterLabel(selectedTag.isEmpty ? "标签/标记" : selectedTag)
                }
            }

            if showsCardSizeControl {
                HStack(spacing: 1) {
                    ForEach(LibraryCardSize.allCases) { size in
                        Button(size.rawValue) { storedCardSize = size.rawValue }
                            .font(AppTheme.auxiliaryFont.weight(cardSize == size ? .semibold : .regular))
                            .foregroundStyle(cardSize == size ? AppTheme.accent : Color.secondary)
                            .frame(width: 27, height: 28)
                            .background(cardSize == size ? AppTheme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                            .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if isGraphReasoningContext {
                HStack(spacing: 1) {
                    graphModeButton("卡片", value: "cards")
                    graphModeButton("闪卡", value: "flashcards")
                }
                .padding(3)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        }
    }

    private var canShowCategoryControl: Bool {
        guard kind == .errors else { return false }
        if !selectedTag.isEmpty { return true }
        return sortedScopedRecords.contains { record in
            let object = record.indexObject ?? [:]
            let textKeys = ["type", "category", "errorCause", "knowledgePoint", "point", "topic"]
            if textKeys.contains(where: { key in
                guard let value = object[key] as? String else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) { return true }
            if record.subject == "数量关系",
               !LibraryQuantityErrorCauseCompatibility.values(in: object).isEmpty {
                return true
            }
            return !(object["knowledgePoints"] as? [String] ?? []).isEmpty
                || !(object["weaknessTags"] as? [String] ?? []).isEmpty
                || (object["isDifficult"] as? Bool) == true
                || (object["needsReview"] as? Bool) == true
        }
    }

    private var hasVisibleFilterControls: Bool {
        (showsCategoryControl && canShowCategoryControl)
            || showsCardSizeControl
            || kind == .words
            || isGraphReasoningContext
    }

    private var hasActiveFilterConditions: Bool {
        !selectedTag.isEmpty || !selectedQuantityType.isEmpty || selectedErrorType != .all
            || (kind == .words && (!wordEntryKind.isEmpty || !wordSentiment.isEmpty))
    }

    private func clearActiveFilters() {
        selectedTag = ""
        selectedQuantityType = ""
        selectedErrorType = .all
        wordEntryKind = ""
        wordSentiment = ""
        renderLimit = 40
    }

    private func graphModeButton(_ title: String, value: String) -> some View {
        Button { graphDisplayMode = value } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(graphDisplayMode == value ? AppTheme.accent : Color.secondary)
                .frame(width: 38, height: 28)
                .background(graphDisplayMode == value ? AppTheme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func filterLabel(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(AppTheme.auxiliaryFont)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var availableKinds: [LibraryContentKind] {
        var values: [LibraryContentKind] = [.errors, .notes]
        if scope.isLogicFill { values.append(.words) }
        values.append(.stickies)
        return values
    }

    private func snapshots(from scopedRecords: [StoredRecord]) -> [LibraryRecordSnapshot] {
        let wordNames = snapshotCache.wordNames(in: records)
        let examTitles = snapshotCache.examTitles(in: records)
        return Array(scopedRecords.prefix(renderLimit)).map {
            snapshotCache.snapshot(
                record: $0,
                linkedWordNamesByID: wordNames,
                includeImages: includesQuestionImages(in: $0),
                reviewSource: scope.reviewSource,
                sourceExamTitlesByID: examTitles
            )
        }
    }

    private func includesQuestionImages(in record: StoredRecord) -> Bool {
        guard kind == .errors, record.collection == "errors" else { return false }
        let indexObject = record.indexObject ?? [:]
        let subject = [record.subject, indexObject["subject"] as? String]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { SubjectModuleTitle.normalized($0) } ?? ""
        let module = [record.module, indexObject["module"] as? String]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { SubjectModuleTitle.normalized($0) } ?? ""
        return (subject == "判断推理" && module == "图形推理")
            || (subject == "资料分析" && module == "综合题")
    }

    private var isQuantityContext: Bool { scope.subject == "数量关系" && scope.module == nil }
    private var cardSize: LibraryCardSize {
        get { LibraryCardSize(rawValue: storedCardSize) ?? .medium }
        set { storedCardSize = newValue.rawValue }
    }
    private var isGraphReasoningContext: Bool {
        kind == .errors && scope.subject == "判断推理" && scope.module == "图形推理"
    }
    private var quantityQuestionTypes: [String] { recordListCache.quantityTypes(records: records) }

    private var errorTypeSubject: LibraryErrorTypeSubject? {
        scope.subject.flatMap(LibraryErrorTypeSubject.init(rawValue:))
    }

    private var errorTypes: [LibraryErrorType] {
        guard let errorTypeSubject else { return [] }
        return LibraryErrorTypeRepository.types(for: errorTypeSubject, records: records)
    }

    private var sortedScopedRecords: [StoredRecord] {
        recordListCache.sortedScopedRecords(
            records: records,
            kind: kind,
            scope: scope,
            selectedQuantityType: selectedQuantityType,
            errorTypeFilter: errorTypeSubject == nil ? .all : selectedErrorType,
            validErrorTypeIDs: selectedErrorType == .all ? [] : Set(errorTypes.map(\.id))
        )
    }

    private var orderedVisibleErrorRecordIDs: [String] {
        guard kind == .errors else { return [] }
        let scoped = sortedScopedRecords
        let keyword = normalizedSearch(searchText)
        let examTitles = !keyword.isEmpty && scope.reviewSource == .mock ? snapshotCache.examTitles(in: records) : [:]
        return recordListCache.visibleErrorIDs(
            tag: selectedTag, search: keyword, includesMastered: includesMasteredErrors,
            examTitleRevision: snapshotCache.examTitleRevision
        ) {
            let candidates = filterRecords(matching: selectedTag, from: scoped)
            if keyword.isEmpty && selectedTag.isEmpty {
                if includesMasteredErrors { return candidates.map(\.recordID) }
                return candidates.compactMap { record in
                    let index = record.indexObject ?? [:]
                    let status = [index["status"], index["masteryStatus"]]
                        .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty }
                    return status == "已掌握" ? nil : record.recordID
                }
            }
            let snapshots = candidates.map {
                LibraryRecordSnapshot(record: $0, sourceExamTitlesByID: examTitles, reviewSource: scope.reviewSource)
            }
            return displayedRecords(from: snapshots).map { $0.record.recordID }
        }
    }

    private func displayedRecords(from snapshots: [LibraryRecordSnapshot]) -> [LibraryRecordSnapshot] {
        let keyword = normalizedSearch(searchText)
        return snapshots.filter { snapshot in
            let matchesSearch = keyword.isEmpty || normalizedSearch(snapshot.searchableText).contains(keyword)
            let matchesMasteredVisibility = kind != .errors || includesMasteredErrors || snapshot.status != "已掌握"
            let matchesTag = selectedTag.isEmpty || snapshot.tags.contains(selectedTag)
            let matchesWordCategory = kind != .words || snapshot.category == wordCategory.rawValue
            let matchesWordSentiment = kind != .words || wordSentiment.isEmpty || snapshot.sentiment == wordSentiment
            let matchesWordEntryKind = kind != .words || wordEntryKind.isEmpty || snapshot.wordEntryKinds.contains(wordEntryKind)
            return matchesSearch && matchesMasteredVisibility && matchesTag && matchesWordCategory && matchesWordSentiment && matchesWordEntryKind
        }
    }

    private func normalizedSearch(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }

    private var quantityTypeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(quantityQuestionTypes, id: \.self) { type in
                    quantityTypeChip(type, value: type)
                }
                quantityTypeChip("未分类", value: "未分类")
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .accessibilityIdentifier("library-quantity-type-filter")
    }

    private func quantityTypeChip(_ title: String, value: String) -> some View {
        typeFilterChip(title, selected: selectedQuantityType == value) {
            selectedQuantityType = selectedQuantityType == value ? "" : value
            selectedTag = ""
            renderLimit = 40
        }
    }

    private var errorTypeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(errorTypes) { type in
                    errorTypeChip(type.name, filter: .type(type.id))
                }
                errorTypeChip("未分类", filter: .unclassified)
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .accessibilityIdentifier("library-error-type-filter")
    }

    private func errorTypeChip(_ title: String, filter: LibraryErrorTypeFilter) -> some View {
        typeFilterChip(title, selected: selectedErrorType == filter) {
            selectedErrorType = selectedErrorType == filter ? .all : filter
            selectedTag = ""
            renderLimit = 40
        }
    }

    private func typeFilterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(selected ? AppTheme.accent : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(selected ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var wordCategoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(WordCategory.allCases) { category in
                    Button {
                        wordCategory = category
                        wordSentiment = ""
                        wordEntryKind = ""
                    } label: {
                        Label(category.shortTitle, systemImage: category.systemImage)
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(wordCategory == category ? AppTheme.accent : Color.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 31)
                            .background(
                                wordCategory == category ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func availableTags(from records: [StoredRecord]) -> [String] {
        if kind == .notes, let context = noteContext {
            return NoteTypeRepository.types(subject: context.subject, module: context.module, records: records).map(\.name)
        }
        if kind == .stickies, let context = stickyContext {
            return StickyTagRepository.tags(subject: context.subject, module: context.module, records: records).map(\.name)
        }
        return Set(recordListCache.tagIndex(for: records, buildTags: tagValues).values.flatMap { $0 }).sorted()
    }

    private func filterRecords(matching tag: String, from records: [StoredRecord]) -> [StoredRecord] {
        guard kind == .errors, !tag.isEmpty else { return records }
        let tags = recordListCache.tagIndex(for: records, buildTags: tagValues)
        return records.filter { tags[$0.compoundID]?.contains(tag) == true }
    }

    private func tagValues(for record: StoredRecord) -> [String] {
        let object = record.indexObject ?? [:]
        var values: [String] = []
        let isDataAnalysis = record.subject == "资料分析" || object["subject"] as? String == "资料分析"
        let usesTextCause = LibraryDataAnalysisCauseLayout.usesTextCause(
            subject: record.subject ?? (object["subject"] as? String ?? ""),
            module: record.module ?? (object["module"] as? String ?? "")
        )
        let baseKeys = usesTextCause ? ["type", "category"] : ["type", "category", "errorCause"]
        if let baseTag = baseKeys.compactMap({ object[$0] as? String }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            values.append(baseTag)
        }
        if record.collection == "errors" {
            let isDifficult = (object["isDifficult"] as? Bool) ?? (object["isDifficult"] as? NSNumber)?.boolValue ?? false
            let needsReview = (object["needsReview"] as? Bool) ?? (object["needsReview"] as? NSNumber)?.boolValue ?? false
            if isDifficult { values.append("难题") }
            if needsReview { values.append("待复习") }
        }
        if let points = object["knowledgePoints"] as? [String] {
            values.append(contentsOf: points)
        } else if let point = object["knowledgePoint"] as? String {
            values.append(contentsOf: point.split(whereSeparator: { "、,，".contains($0) }).map(String.init))
        }
        if record.subject == "数量关系" || object["subject"] as? String == "数量关系" {
            values.append(contentsOf: LibraryQuantityErrorCauseCompatibility.values(in: object))
        } else if isDataAnalysis {
            values.append(contentsOf: LibraryDataAnalysisCauseLayout.splitLines(LibraryDataAnalysisCauseLayout.rawCause(in: record.compatibilityIndexObject ?? object)))
        } else {
            values.append(contentsOf: object["weaknessTags"] as? [String] ?? [])
        }
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func selectTag(_ tag: String) {
        selectedTag = tag
        renderLimit = 40
    }

    private var noteContext: (subject: String, module: String)? {
        if isQuantityContext, quantityQuestionTypes.contains(selectedQuantityType) {
            return ("数量关系", selectedQuantityType)
        }
        guard let subject = scope.subject, scope.hasModuleContext else { return nil }
        return (subject, scope.module ?? "")
    }

    private var stickyContext: (subject: String, module: String)? {
        guard let subject = scope.subject, scope.hasModuleContext else { return nil }
        return (subject, scope.module ?? "")
    }

    private var noteTypeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                noteTypeChip(title: "全部", color: "#0066CC", selected: selectedTag.isEmpty) { selectedTag = "" }
                ForEach(availableNoteTypes) { item in
                    noteTypeChip(title: item.name, color: item.color, selected: selectedTag == item.name) { selectedTag = item.name }
                }
                Button {
                    noteTypeDraft = ""
                    noteTypeColor = NoteTypeRepository.colors[0]
                    showNewNoteType = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 29, height: 29)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var availableNoteTypes: [NoteTypeDefinition] {
        guard let context = noteContext else { return [] }
        return NoteTypeRepository.types(subject: context.subject, module: context.module, records: records)
    }

    private var stickyTagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                noteTypeChip(title: "全部", color: "#0066CC", selected: selectedTag.isEmpty) { selectedTag = "" }
                ForEach(availableStickyTags) { item in
                    noteTypeChip(title: item.name, color: item.color, selected: selectedTag == item.name) { selectedTag = item.name }
                }
            }
        }
    }

    private var availableStickyTags: [StickyTagDefinition] {
        guard let context = stickyContext else { return [] }
        return StickyTagRepository.tags(subject: context.subject, module: context.module, records: records)
    }

    private func noteTypeChip(title: String, color: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(selected ? Color(homeHex: color) : .secondary)
                .padding(.horizontal, 10).frame(height: 29)
                .background(selected ? Color(homeHex: color).opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
        }.buttonStyle(.plain)
    }

    private var noteTypeDialog: some View {
        NativeEditorDialog(
            title: "新增笔记标签",
            canSave: !noteTypeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { showNewNoteType = false },
            onSave: saveNoteType
        ) {
            TextField("标签名称", text: $noteTypeDraft).textFieldStyle(NativeTextFieldStyle())
            HStack(spacing: 12) {
                ForEach(NoteTypeRepository.colors, id: \.self) { color in
                    Button { noteTypeColor = color } label: {
                        Circle().fill(Color(homeHex: color)).frame(width: 27, height: 27)
                            .overlay(Circle().stroke(noteTypeColor == color ? Color.primary : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func saveNoteType() {
        guard let context = noteContext else { return }
        let name = noteTypeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? NoteTypeRepository.add(name, color: noteTypeColor, subject: context.subject, module: context.module, records: records, context: modelContext)
        selectedTag = name
        showNewNoteType = false
    }

    private var emptyTitle: String {
        if scope.reviewSource == .pending { return "暂无待确认来源的\(kind.rawValue)" }
        return kind.emptyTitle
    }

    private var emptyDetail: String {
        if scope.reviewSource == .pending {
            return pendingSourceCount > 0 ? "有 \(pendingSourceCount) 条记录待确认，可点上方按钮批量分类。" : "当前模块没有待确认来源的记录。"
        }
        return kind.emptyDetail
    }

    private var emptyIcon: String {
        switch kind {
        case .errors: "checklist"
        case .notes: "note.text"
        case .stickies: "note"
        case .words: "character.book.closed"
        }
    }

    private var searchPrompt: String {
        switch kind {
        case .errors: "搜索错题 / 知识点"
        case .notes: "搜索笔记标题 / 内容"
        case .stickies: "搜索便签内容"
        case .words: "搜索词语 / 释义"
        }
    }

    private func resetContextFilters() {
        searchText = ""
        selectedTag = ""
        wordSentiment = ""
        wordEntryKind = ""
        selectedQuantityType = ""
        selectedErrorType = .all
        renderLimit = 40
        if kind == .words && !scope.isLogicFill { kind = .notes }
    }

    private func sidebarWidth(in width: CGFloat) -> CGFloat {
        usesCompactSidebar(in: width) ? 96 : min(184, max(156, width * 0.22))
    }

    private func usesCompactSidebar(in width: CGFloat) -> Bool {
        width < 760
    }

    private var canCreateRecord: Bool {
        scope.reviewSource != .pending
            && !(kind == .words && !scope.isLogicFill)
    }

    private func remove(_ target: LibraryDeleteTarget) {
        try? LibraryRecordRepository.remove(kind: target.kind, id: target.recordID, records: records, context: modelContext)
    }

    private func open(_ snapshot: LibraryRecordSnapshot) {
        if kind == .errors || kind == .words || kind == .notes {
            navigationPath.append(.detail(kind: kind, recordID: snapshot.record.recordID))
        } else {
            navigationPath.append(.editor(kind: kind, recordID: snapshot.record.recordID))
        }
    }

    private func importWordSamples() {
        guard kind == .words, scope.isLogicFill else { return }
        let now = Date.now
        for sample in WordSampleData.samples(for: wordCategory) {
            var object = sample
            let id = "word-native-\(UUID().uuidString.lowercased())"
            object["id"] = id
            object["category"] = wordCategory.rawValue
            object["type"] = wordCategory.rawValue
            object["subject"] = "言语理解"
            object["module"] = "逻辑填空"
            object["createdAt"] = ISO8601DateFormatter().string(from: now)
            object["updatedAt"] = ISO8601DateFormatter().string(from: now)
            guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
            modelContext.insert(StoredRecord(
                collection: "words",
                recordID: id,
                payload: payload,
                subject: "言语理解",
                module: "逻辑填空",
                createdAt: now,
                updatedAt: now
            ))
        }
        try? modelContext.save()
    }
}

private struct LibraryBulkSourceAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    let records: [StoredRecord]
    let onAssign: ([StoredRecord], LibraryReviewSource) -> Void
    @State private var selectedIDs = Set<String>()
    @State private var searchText = ""

    private var visibleRecords: [StoredRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("已选 \(selectedIDs.count) / \(records.count)").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    Spacer()
                    Button(selectedIDs.count == records.count ? "清空" : "全选当前范围") {
                        selectedIDs = selectedIDs.count == records.count ? [] : Set(records.map(\.compoundID))
                    }.font(AppTheme.auxiliaryFont.weight(.semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                List(visibleRecords, id: \.compoundID) { record in
                    Button {
                        if selectedIDs.contains(record.compoundID) { selectedIDs.remove(record.compoundID) }
                        else { selectedIDs.insert(record.compoundID) }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: selectedIDs.contains(record.compoundID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(record.compoundID) ? AppTheme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(2)
                                Text("\(record.collection == "errors" ? "错题" : (record.collection == "notes" ? "笔记" : "便签")) · \([record.subject, record.module].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / "))")
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Button("设为真题") { submit(.real) }.buttonStyle(NativeSecondaryButtonStyle()).disabled(selectedIDs.isEmpty)
                    Button("设为模拟题") { submit(.mock) }.buttonStyle(NativePrimaryButtonStyle()).disabled(selectedIDs.isEmpty)
                }
                .padding(14)
            }
            .navigationTitle("确认待分类来源")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索题目或笔记")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func submit(_ source: LibraryReviewSource) {
        onAssign(records.filter { selectedIDs.contains($0.compoundID) }, source)
        dismiss()
    }
}

private struct LibraryDeleteTarget: Identifiable {
    let kind: LibraryContentKind
    let recordID: String
    var id: String { "\(kind.rawValue):\(recordID)" }
}
