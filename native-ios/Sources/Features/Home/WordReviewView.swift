import SwiftData
import SwiftUI
import UIKit

struct WordReviewView: View {
    private enum OverviewTab: String, CaseIterable, Identifiable, Hashable {
        case today = "待复习"
        case history = "历史"
        var id: String { rawValue }
    }

    private struct SessionEntry: Identifiable, Hashable {
        let wordRecordID: String
        let attemptType: WordReviewAttemptType
        let submissionID: String
        var id: String { "\(wordRecordID):\(attemptType.rawValue)" }

        init(wordRecordID: String, attemptType: WordReviewAttemptType) {
            self.wordRecordID = wordRecordID
            self.attemptType = attemptType
            submissionID = UUID().uuidString
        }
    }

    private struct WordDetailKey: Equatable {
        let recordID: String
        let updatedAt: Date?
        let payloadCount: Int
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "words"
            || record.collection == "word_review_plans"
            || record.collection == "word_review_history"
    }) private var records: [StoredRecord]

    @State private var tab: OverviewTab = .today
    @State private var selectedCategory: WordCategory = .idiomDefinition
    @State private var historyCategory: WordCategory?
    @State private var activeSession: [SessionEntry] = []
    @State private var sessionIndex = 0
    @State private var revealedEntry: SessionEntry?
    @State private var sessionGeneration = UUID()
    @State private var submissionInProgressID: String?
    @State private var submissionErrorMessage: String?
    @State private var errorMessage: String?
    @State private var reviewDay = Calendar.current.startOfDay(for: .now)
    @State private var overviewSnapshot: WordReviewOverviewSnapshot?
    @State private var restoreGeneration = 0
    @State private var loadedGroup: WordReviewWordGroup?
    @State private var loadedGroupKey: WordDetailKey?

    private var wordRecords: [StoredRecord] { records.filter { $0.collection == "words" } }
    private var overviewKey: WordReviewOverviewCacheKey {
        var hasher = Hasher()
        for record in records {
            hasher.combine(record.compoundID)
            hasher.combine(record.createdAt)
            hasher.combine(record.updatedAt)
            hasher.combine(record.payload.count)
            hasher.combine(record.indexPayload?.count ?? 0)
        }
        return WordReviewOverviewCacheKey(
            revision: hasher.finalize(),
            reviewDay: reviewDay,
            restoreGeneration: restoreGeneration
        )
    }
    private var currentOverview: WordReviewOverviewSnapshot? {
        guard let overviewSnapshot, overviewSnapshot.key == overviewKey else { return nil }
        return overviewSnapshot
    }
    private var categoryDueWordIDs: [String] {
        currentOverview?.dueWordIDsByCategory[selectedCategory.rawValue] ?? []
    }
    private var currentEntry: SessionEntry? {
        activeSession.indices.contains(sessionIndex) ? activeSession[sessionIndex] : nil
    }
    private var currentGroup: WordReviewWordGroup? {
        guard let currentWordDetailKey, loadedGroupKey == currentWordDetailKey else { return nil }
        return loadedGroup
    }
    private var currentWordDetailKey: WordDetailKey? {
        guard let recordID = currentEntry?.wordRecordID,
              let record = wordRecords.first(where: { $0.recordID == recordID }) else { return nil }
        return WordDetailKey(recordID: recordID, updatedAt: record.updatedAt, payloadCount: record.payload.count)
    }
    private var isReviewing: Bool { !activeSession.isEmpty }

    var body: some View {
        Group {
            if isReviewing {
                reviewSession
            } else {
                overview
            }
        }
        .background(Color.white)
        .navigationTitle("词语复习")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $revealedEntry) { entry in
            reviewedWordDetail(entry)
        }
        .toolbar {
            if !isReviewing {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink(value: AppRoute.studyReport) {
                            Label("学习报告", systemImage: "chart.bar.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            refreshReviewDay()
            while !Task.isCancelled {
                let calendar = Calendar.current
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
                    ?? Date().addingTimeInterval(60)
                let delay = max(1, nextDay.timeIntervalSinceNow)
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
                refreshReviewDay()
            }
        }
        .task(id: overviewKey) {
            await prepareOverview(for: overviewKey)
        }
        .task(id: currentWordDetailKey) {
            await loadCurrentWordGroup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .legacyBackupRestoreDidComplete)) { _ in
            restoreGeneration &+= 1
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: tab == .today ? 12 : 18) {
                Picker("复习视图", selection: $tab) {
                    ForEach(OverviewTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .today: todayContent
                case .history: historyContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, tab == .today ? 10 : 14)
            .padding(.bottom, tab == .today ? 10 : 96)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == .today {
                Button {
                    beginDueSession()
                } label: {
                    Text("开始复习")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(categoryDueWordIDs.isEmpty ? Color.secondary : AppTheme.accent)
                        .background(Color(red: 0.88, green: 0.94, blue: 1.0), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(categoryDueWordIDs.isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.white)
            }
        }
    }

    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            categorySelector(selection: selectedCategory, includesAll: false, count: { category in
                currentOverview?.dueWordIDsByCategory[category.rawValue]?.count ?? 0
            }) { category in
                if let category { selectedCategory = category }
            }

            if currentOverview == nil {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("正在整理复习清单…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 28)
            } else if categoryDueWordIDs.isEmpty {
                emptyState(title: "此类暂无待复习词语", detail: "新增或补充词条后，会按加入日期自动安排复习。", image: "checkmark.circle")
            } else {
                let columns = [GridItem(.adaptive(minimum: 144), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(categoryDueWordIDs, id: \.self) { wordRecordID in
                        if let card = currentOverview?.cardsByID[wordRecordID] {
                            Button { beginDueSession(startingAt: wordRecordID) } label: {
                                Text(card.title)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var historyContent: some View {
        let history = currentOverview?.histories ?? []
        let visibleHistory = historyCategory.map { category in
            history.filter {
                [category.title, category.shortTitle, category.rawValue].contains($0.categoryTitle)
            }
        } ?? history
        return LazyVStack(alignment: .leading, spacing: 12) {
            categorySelector(selection: historyCategory, includesAll: true) { historyCategory = $0 }
            if currentOverview == nil {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if visibleHistory.isEmpty {
                emptyState(
                    title: historyCategory == nil ? "还没有复习记录" : "此类暂无复习记录",
                    detail: "提交评价后可在这里查看。",
                    image: "clock"
                )
            } else {
                ForEach(visibleHistory) { item in
                    historyRow(item)
                }
            }
        }
    }

    private func categorySelector(
        selection: WordCategory?,
        includesAll: Bool,
        count: ((WordCategory) -> Int)? = nil,
        onSelect: @escaping (WordCategory?) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if includesAll {
                    categoryChip("全部", selected: selection == nil) { onSelect(nil) }
                }
                ForEach(WordCategory.allCases) { category in
                    categoryChip(category.title, count: count?(category), selected: selection == category) {
                        onSelect(category)
                    }
                }
            }
        }
    }

    private func categoryChip(
        _ title: String,
        count: Int? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count { Text("\(count)").monospacedDigit() }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(selected ? AppTheme.accent : Color.primary.opacity(0.055), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var reviewSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let entry = currentEntry, let group = currentGroup {
                    HStack {
                        Button("结束") { endSession() }
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(sessionIndex + 1) / \(activeSession.count)")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.categoryTitle)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.accent)
                        Text(group.title)
                            .font(.system(size: 24, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(group.category.isComparison ? "先回忆各词的共同含义、核心侧重和判断线索。" : "先回忆词义、用法和例句。")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(red: 0.95, green: 0.97, blue: 1), in: RoundedRectangle(cornerRadius: 18))

                    Button {
                        submissionErrorMessage = nil
                        revealedEntry = entry
                    } label: {
                        Label(group.category.isComparison ? "查看辨析" : "查看释义", systemImage: "eye")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else if let key = currentWordDetailKey, loadedGroupKey != key {
                    ProgressView("正在打开词语…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else {
                    emptyState(title: "词条已不可用", detail: "可以跳过此词，继续复习。", image: "questionmark.folder")
                    Button("跳过此词") { advanceSession() }
                }
            }
            .padding(20)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func reviewedWordDetail(_ entry: SessionEntry) -> some View {
        WordReviewWordDetailDestination(recordID: entry.wordRecordID, onDeleted: {
            guard currentEntry == entry else { return }
            advanceSession()
        })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if currentEntry == entry {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("掌握程度").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(sessionIndex + 1) / \(activeSession.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if currentWordDetailKey == nil || (loadedGroupKey == currentWordDetailKey && currentGroup == nil) {
                        Button("跳过此词") { advanceSession() }
                    } else {
                        HStack(spacing: 9) {
                            feedbackButton(.unknown, entry: entry)
                            feedbackButton(.fuzzy, entry: entry)
                            feedbackButton(.mastered, entry: entry)
                        }
                        .disabled(currentGroup == nil || submissionInProgressID != nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .background(.white)
            }
        }
        .alert("保存评价失败", isPresented: Binding(
            get: { submissionErrorMessage != nil },
            set: { if !$0 { submissionErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { submissionErrorMessage = nil }
        } message: {
            Text(submissionErrorMessage ?? "")
        }
    }

    private func historyRow(_ item: WordReviewHistory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedbackIcon(item.feedback))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(feedbackColor(item.feedback))
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text("\(item.categoryTitle) · \(shortDateTime(item.reviewedAt)) · \(item.attemptType.title)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(item.feedback.title) · 下次：\(historyNextDescription(item))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.7) }
    }

    private func feedbackButton(_ feedback: WordReviewFeedback, entry: SessionEntry) -> some View {
        Button {
            submit(feedback, for: entry)
        } label: {
            Text(feedback.title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(feedbackColor(feedback).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(feedbackColor(feedback).opacity(0.25), lineWidth: 0.8))
                .foregroundStyle(feedbackColor(feedback))
        }
        .buttonStyle(.plain)
    }

    private func emptyState(title: String, detail: String, image: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: image).font(.system(size: 26, weight: .light)).foregroundStyle(AppTheme.accent.opacity(0.75))
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 15)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
    }

    private func feedbackColor(_ feedback: WordReviewFeedback) -> Color {
        switch feedback {
        case .unknown: AppTheme.warning
        case .fuzzy: Color(red: 0.78, green: 0.52, blue: 0.15)
        case .mastered: AppTheme.success
        }
    }

    private func feedbackIcon(_ feedback: WordReviewFeedback) -> String {
        switch feedback {
        case .unknown: "xmark.circle"
        case .fuzzy: "circle.lefthalf.filled"
        case .mastered: "checkmark.circle"
        }
    }

    private func historyNextDescription(_ item: WordReviewHistory) -> String {
        if let nextDueDate = item.nextDueDate { return shortDate(nextDueDate) }
        return item.isContextValidationPending == true ? "等待语境验证" : "未安排"
    }

    private func refreshReviewDay() {
        let today = Calendar.current.startOfDay(for: .now)
        guard reviewDay != today else { return }
        reviewDay = today
    }

    private func prepareOverview(for key: WordReviewOverviewCacheKey) async {
        let cached = WordReviewOverviewSnapshotCache.shared.snapshot(for: key)
        let snapshot: WordReviewOverviewSnapshot
        if let cached {
            snapshot = cached
        } else {
            let inputs = records.map {
                WordReviewOverviewRecordInput(
                    collection: $0.collection,
                    recordID: $0.recordID,
                    payload: $0.payload,
                    createdAt: $0.createdAt
                )
            }
            let now = Date.now
            let calendar = Calendar.current
            snapshot = await Task.detached(priority: .utility) {
                WordReviewOverviewSnapshotBuilder.build(
                    key: key,
                    records: inputs,
                    now: now,
                    calendar: calendar
                )
            }.value
        }

        guard !Task.isCancelled, key == overviewKey else { return }
        overviewSnapshot = snapshot
        WordReviewOverviewSnapshotCache.shared.store(snapshot)

        do {
            _ = try WordReviewRepository.enrollPreparedCandidates(
                snapshot.enrollmentCandidates,
                wordRecords: wordRecords,
                in: modelContext,
                now: Date.now
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCurrentWordGroup() async {
        guard let key = currentWordDetailKey,
              let record = wordRecords.first(where: { $0.recordID == key.recordID }) else {
            loadedGroup = nil
            loadedGroupKey = nil
            return
        }
        let recordID = record.recordID
        let payload = record.payload
        let group = await Task.detached(priority: .userInitiated) {
            WordReviewWordGroup(recordID: recordID, payload: payload)
        }.value
        guard !Task.isCancelled, currentWordDetailKey == key else { return }
        loadedGroup = group
        loadedGroupKey = key
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func beginDueSession(startingAt wordRecordID: String? = nil) {
        guard let snapshot = currentOverview else { return }
        let dueIDs = categoryDueWordIDs
        let orderedIDs: [String]
        if let wordRecordID {
            guard let startIndex = dueIDs.firstIndex(of: wordRecordID) else { return }
            orderedIDs = Array(dueIDs[startIndex...] + dueIDs[..<startIndex])
        } else {
            orderedIDs = dueIDs
        }
        var seenIDs = Set<String>()
        let entries = orderedIDs.compactMap { wordRecordID -> SessionEntry? in
            guard let plan = snapshot.plansByID[wordRecordID],
                  !plan.isPaused,
                  snapshot.cardsByID[wordRecordID] != nil,
                  seenIDs.insert(wordRecordID).inserted else { return nil }
            return SessionEntry(
                wordRecordID: wordRecordID,
                attemptType: plan.status == .waitingToLearn ? .initial : .due
            )
        }
        guard !entries.isEmpty else { return }
        sessionGeneration = UUID()
        submissionInProgressID = nil
        activeSession = entries
        sessionIndex = 0
        revealedEntry = nil
        submissionErrorMessage = nil
        loadedGroup = nil
        loadedGroupKey = nil
    }

    private func submit(_ feedback: WordReviewFeedback, for entry: SessionEntry) {
        guard submissionInProgressID == nil,
              currentEntry?.submissionID == entry.submissionID,
              currentEntry?.id == entry.id,
              let group = currentGroup,
              group.recordID == entry.wordRecordID else { return }
        let expectedSessionGeneration = sessionGeneration
        submissionInProgressID = entry.submissionID
        do {
            _ = try WordReviewRepository.submit(
                wordRecordID: group.recordID,
                title: group.title,
                categoryTitle: group.categoryTitle,
                feedback: feedback,
                attemptType: entry.attemptType,
                submissionID: entry.submissionID,
                in: modelContext
            )
            guard sessionGeneration == expectedSessionGeneration,
                  currentEntry?.submissionID == entry.submissionID else {
                if submissionInProgressID == entry.submissionID {
                    submissionInProgressID = nil
                }
                return
            }
            submissionInProgressID = nil
            advanceSession()
        } catch {
            if submissionInProgressID == entry.submissionID {
                submissionInProgressID = nil
            }
            submissionErrorMessage = error.localizedDescription
        }
    }

    private func advanceSession() {
        sessionGeneration = UUID()
        submissionInProgressID = nil
        revealedEntry = nil
        submissionErrorMessage = nil
        let availableIDs = Set(wordRecords.map(\.recordID))
        if let nextIndex = activeSession.indices.dropFirst(sessionIndex + 1).first(where: {
            availableIDs.contains(activeSession[$0].wordRecordID)
        }) {
            sessionIndex = nextIndex
            loadedGroup = nil
            loadedGroupKey = nil
        } else {
            endSession()
        }
    }

    private func endSession() {
        sessionGeneration = UUID()
        submissionInProgressID = nil
        activeSession = []
        sessionIndex = 0
        revealedEntry = nil
        submissionErrorMessage = nil
        loadedGroup = nil
        loadedGroupKey = nil
        tab = .today
    }

}

struct WordReviewWordDetailDestination: View {
    private enum WordAction: String, Hashable {
        case edit
        case migrate
    }

    private let recordID: String
    private let onDeleted: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var words: [StoredRecord]
    @State private var action: WordAction?
    @State private var deletionError: String?

    init(recordID: String, onDeleted: (() -> Void)? = nil) {
        self.recordID = recordID
        self.onDeleted = onDeleted
        _words = Query(filter: #Predicate<StoredRecord> { record in
            record.collection == "words" && record.recordID == recordID
        })
    }

    var body: some View {
        Group {
            if let record = words.first {
                WordLibraryRecordDetailView(
                    record: record,
                    onEdit: { action = .edit },
                    onDelete: { deleteWord() },
                    onMigrateLegacyWord: { action = .migrate }
                )
                .id(record.recordID)
            } else {
                ContentUnavailableView("词条已删除", systemImage: "text.book.closed", description: Text("该词语组已从词语库移除。"))
            }
        }
        .navigationDestination(item: $action) { action in
            if let record = words.first {
                switch action {
                case .edit:
                    LibraryRecordEditorView(
                        kind: .words,
                        scope: LibraryScope(subject: record.subject, module: record.module),
                        record: record,
                        onMigrateLegacyWord: { self.action = .migrate }
                    )
                case .migrate:
                    LibraryWordMigrationDetailView(record: record)
                }
            }
        }
        .alert("删除词语失败", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("好", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private func deleteWord() {
        do {
            let errors = try modelContext.fetch(FetchDescriptor<StoredRecord>(
                predicate: #Predicate<StoredRecord> { $0.collection == "errors" }
            ))
            try LibraryRecordRepository.remove(kind: .words, id: recordID, records: words + errors, context: modelContext)
            if let onDeleted { onDeleted() }
            else { dismiss() }
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
