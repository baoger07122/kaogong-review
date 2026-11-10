import SwiftData
import SwiftUI
import UIKit

struct WordReviewView: View {
    private enum OverviewTab: String, CaseIterable, Identifiable, Hashable {
        case today = "待复习"
        case history = "历史"
        var id: String { rawValue }
    }

    private struct SessionEntry: Identifiable {
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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "words"
            || record.collection == "word_review_plans"
            || record.collection == "word_review_history"
    }) private var records: [StoredRecord]

    @State private var tab: OverviewTab = .today
    @State private var selectedCategory: WordCategory = .idiomDefinition
    @State private var activeSession: [SessionEntry] = []
    @State private var sessionIndex = 0
    @State private var isRevealed = false
    @State private var savedHistory: WordReviewHistory?
    @State private var errorMessage: String?
    @State private var reviewDay = Calendar.current.startOfDay(for: .now)

    private var wordRecords: [StoredRecord] { records.filter { $0.collection == "words" } }
    private var planRecords: [StoredRecord] { records.filter { $0.collection == "word_review_plans" } }
    private var historyRecords: [StoredRecord] { records.filter { $0.collection == "word_review_history" } }
    private var wordRecordIDs: [String] { wordRecords.map(\.recordID).sorted() }
    private var plans: [WordReviewPlan] { WordReviewRepository.plans(from: planRecords) }
    private var history: [WordReviewHistory] { WordReviewRepository.history(from: historyRecords) }
    private var groupsByID: [String: WordReviewWordGroup] {
        Dictionary(uniqueKeysWithValues: wordRecords.compactMap { record in
            WordReviewWordGroup(record: record).map { ($0.recordID, $0) }
        })
    }
    private var dueQueue: [WordReviewPlan] {
        return plans.filter { plan in
            !plan.isPaused
                && groupsByID[plan.wordRecordID] != nil
                && WordReviewSchedulingPolicy.isDue(plan.nextDueDate, on: reviewDay)
        }.sorted { lhs, rhs in
            let leftDate = lhs.nextDueDate ?? .distantFuture
            let rightDate = rhs.nextDueDate ?? .distantFuture
            if Calendar.current.startOfDay(for: leftDate) != Calendar.current.startOfDay(for: rightDate) {
                return leftDate < rightDate
            }
            let leftTitle = groupsByID[lhs.wordRecordID]?.title ?? ""
            let rightTitle = groupsByID[rhs.wordRecordID]?.title ?? ""
            if leftTitle != rightTitle { return leftTitle.localizedStandardCompare(rightTitle) == .orderedAscending }
            return lhs.wordRecordID < rhs.wordRecordID
        }
    }
    private var categoryDueQueue: [WordReviewPlan] {
        dueQueue.filter { groupsByID[$0.wordRecordID]?.category == selectedCategory }
    }
    private func dueCount(for category: WordCategory) -> Int {
        dueQueue.filter { groupsByID[$0.wordRecordID]?.category == category }.count
    }
    private var currentEntry: SessionEntry? {
        activeSession.indices.contains(sessionIndex) ? activeSession[sessionIndex] : nil
    }
    private var currentGroup: WordReviewWordGroup? {
        currentEntry.flatMap { groupsByID[$0.wordRecordID] }
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
            synchronizeWordReviewPlans()
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
        .onChange(of: wordRecordIDs) { _, _ in
            synchronizeWordReviewPlans()
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
            .padding(.top, 14)
            .padding(.bottom, 96)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == .today {
                Button {
                    beginDueSession(categoryDueQueue)
                } label: {
                    Text("开始复习")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(categoryDueQueue.isEmpty ? Color.secondary : AppTheme.accent)
                        .background(Color(red: 0.88, green: 0.94, blue: 1.0), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(categoryDueQueue.isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.white)
            }
        }
    }

    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WordCategory.allCases) { category in
                        Button { selectedCategory = category } label: {
                            HStack(spacing: 6) {
                                Text(category.title)
                                Text("\(dueCount(for: category))").monospacedDigit()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(selectedCategory == category ? AppTheme.accent : Color.primary.opacity(0.055), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if categoryDueQueue.isEmpty {
                emptyState(title: "此类暂无待复习词语", detail: "新增或补充词条后，会按加入日期自动安排复习。", image: "checkmark.circle")
            } else {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(categoryDueQueue) { plan in
                        if let group = groupsByID[plan.wordRecordID] {
                            Button { beginDueSession([plan]) } label: {
                                Text(group.title)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .padding(12)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("复习历史").font(.system(size: 18, weight: .semibold))
            if history.isEmpty {
                emptyState(title: "还没有复习记录", detail: "每次提交“不会、模糊、掌握”后都会保存在这里。", image: "clock")
            } else {
                ForEach(history) { item in
                    historyRow(item)
                }
            }
        }
    }

    private var reviewSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let savedHistory {
                    savedFeedbackView(savedHistory)
                } else if let entry = currentEntry, let group = currentGroup {
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

                    if isRevealed {
                        revealedContent(group)
                        NavigationLink(value: AppRoute.wordReviewWordDetail(group.recordID)) {
                            Label("打开原词条", systemImage: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.top, 2)
                        Text("这组词你掌握得怎样？")
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 9) {
                            feedbackButton(.unknown, entry: entry)
                            feedbackButton(.fuzzy, entry: entry)
                            feedbackButton(.mastered, entry: entry)
                        }
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { isRevealed = true }
                        } label: {
                            Label(group.category.isComparison ? "查看辨析" : "查看释义", systemImage: "eye")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    emptyState(title: "词条已不可用", detail: "该词语组可能已被删除，可结束本次复习。", image: "questionmark.folder")
                    Button("返回词语复习") { endSession() }
                }
            }
            .padding(20)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
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

    private func revealedContent(_ group: WordReviewWordGroup) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if group.category.isComparison {
                if !group.commonMeaning.isEmpty { revealSection("共同语义", text: group.commonMeaning) }
                if !group.coreDifference.isEmpty { revealSection("核心区别", text: group.coreDifference) }
                ForEach(group.terms) { term in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(term.name).font(.system(size: 15, weight: .semibold))
                        if !term.meaning.isEmpty { revealRichTextSection("词义", html: term.meaning) }
                        if !term.coreFocus.isEmpty { revealSection("核心侧重", text: term.coreFocus) }
                        if !term.quickDecision.isEmpty { revealSection("一眼判断", text: term.quickDecision) }
                        if !term.example.isEmpty { revealRichTextSection("例句", html: term.example) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
                if !group.judgmentHint.isEmpty { revealRichTextSection("判断提示", html: group.judgmentHint) }
            } else if let term = group.terms.first {
                if !term.pinyin.isEmpty { revealSection("拼音", text: term.pinyin) }
                if !term.partOfSpeech.isEmpty { revealSection("词性", text: term.partOfSpeech) }
                if !term.meaning.isEmpty { revealRichTextSection("释义", html: term.meaning) }
                if !term.example.isEmpty { revealRichTextSection("例句", html: term.example) }
                if !term.myUnderstanding.isEmpty { revealRichTextSection("我的理解", html: term.myUnderstanding) }
                if !term.collocations.isEmpty { revealRichTextSection("常见搭配", html: term.collocations) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func revealRichTextSection(_ title: String, html: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            NativeRichTextDisplay(html: html, minHeight: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
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

    private func savedFeedbackView(_ item: WordReviewHistory) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("已记录：\(item.feedback.title)", systemImage: feedbackIcon(item.feedback))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(feedbackColor(item.feedback))
            Text(item.title).font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(item.nextDueDate.map { "下次计划：\(shortDate($0))" }
                 ?? (item.isContextValidationPending == true ? "等待语境验证" : "本轮未安排下次复习"))
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Button(sessionIndex + 1 < activeSession.count ? "下一组" : "完成") {
                advanceSession()
            }
            .buttonStyle(ReviewPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(red: 0.96, green: 0.98, blue: 0.96), in: RoundedRectangle(cornerRadius: 16))
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

    private func synchronizeWordReviewPlans() {
        do { _ = try WordReviewRepository.enroll(wordRecords, in: modelContext) }
        catch { errorMessage = error.localizedDescription }
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

    private func beginDueSession(_ duePlans: [WordReviewPlan]) {
        var seenIDs = Set<String>()
        let entries = duePlans.compactMap { plan -> SessionEntry? in
            guard groupsByID[plan.wordRecordID] != nil,
                  !plan.isPaused,
                  seenIDs.insert(plan.wordRecordID).inserted else { return nil }
            return SessionEntry(
                wordRecordID: plan.wordRecordID,
                attemptType: plan.status == .waitingToLearn ? .initial : .due
            )
        }
        guard !entries.isEmpty else { return }
        activeSession = entries
        sessionIndex = 0
        isRevealed = false
        savedHistory = nil
    }

    private func submit(_ feedback: WordReviewFeedback, for entry: SessionEntry) {
        guard let group = groupsByID[entry.wordRecordID] else { return }
        do {
            savedHistory = try WordReviewRepository.submit(
                wordRecordID: group.recordID,
                title: group.title,
                categoryTitle: group.categoryTitle,
                feedback: feedback,
                attemptType: entry.attemptType,
                submissionID: entry.submissionID,
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advanceSession() {
        savedHistory = nil
        if sessionIndex + 1 < activeSession.count {
            sessionIndex += 1
            isRevealed = false
        } else {
            endSession()
        }
    }

    private func endSession() {
        activeSession = []
        sessionIndex = 0
        isRevealed = false
        savedHistory = nil
        tab = .today
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ReviewPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

struct WordReviewWordDetailDestination: View {
    let recordID: String

    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "words"
    }) private var words: [StoredRecord]

    var body: some View {
        if let record = words.first(where: { $0.recordID == recordID }) {
            WordLibraryRecordDetailView(record: record)
        } else {
            ContentUnavailableView("词条已删除", systemImage: "text.book.closed", description: Text("该词语组已从词语库移除。"))
        }
    }
}
