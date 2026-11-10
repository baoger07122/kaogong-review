import SwiftData
import SwiftUI
import UIKit

struct WordReviewView: View {
    private enum OverviewTab: String, CaseIterable, Identifiable, Hashable {
        case today = "今日"
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
    @State private var selectedCategoryID = WordCategory.idiomDefinition.rawValue
    @State private var activeSession: [SessionEntry] = []
    @State private var sessionIndex = 0
    @State private var isRevealed = false
    @State private var savedHistory: WordReviewHistory?
    @State private var errorMessage: String?
    @State private var reviewDay = Calendar.current.startOfDay(for: .now)

    private var wordRecords: [StoredRecord] { records.filter { $0.collection == "words" } }
    private var wordRecordIDs: [String] { wordRecords.map(\.recordID).sorted() }
    private var planRecords: [StoredRecord] { records.filter { $0.collection == "word_review_plans" } }
    private var historyRecords: [StoredRecord] { records.filter { $0.collection == "word_review_history" } }
    private var plans: [WordReviewPlan] { WordReviewRepository.plans(from: planRecords) }
    private var history: [WordReviewHistory] { WordReviewRepository.history(from: historyRecords) }
    private var groupsByID: [String: WordReviewWordGroup] {
        Dictionary(uniqueKeysWithValues: wordRecords.compactMap { record in
            WordReviewWordGroup(record: record).map { ($0.recordID, $0) }
        })
    }
    private var selectedCategory: WordCategory {
        WordCategory(rawValue: selectedCategoryID) ?? .idiomDefinition
    }
    private var selectedDueQueue: [WordReviewPlan] {
        dueQueue.filter { groupsByID[$0.wordRecordID]?.category == selectedCategory }
    }
    private var dueQueue: [WordReviewPlan] {
        return plans.filter { plan in
            groupsByID[plan.wordRecordID] != nil
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
        .onChange(of: scenePhase) { _, value in
            if value == .active { refreshReviewDay() }
        }
        .task(id: wordRecordIDs) {
            do {
                _ = try WordReviewRepository.enroll(wordRecords, in: modelContext)
                let hasSelectedCategory = wordRecords.contains {
                    WordReviewWordGroup(record: $0)?.category.rawValue == selectedCategoryID
                }
                if !hasSelectedCategory,
                   let firstAvailableCategory = WordCategory.allCases.first(where: { category in
                       wordRecords.contains { WordReviewWordGroup(record: $0)?.category == category }
                   }) {
                    selectedCategoryID = firstAvailableCategory.rawValue
                }
            } catch {
                errorMessage = error.localizedDescription
            }
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
            .padding(.bottom, 40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var todayContent: some View {
        let queue = selectedDueQueue
        return VStack(alignment: .leading, spacing: 16) {
            categorySelector

            HStack(spacing: 0) {
                dueMetric("待复习", value: queue.count)
                dueMetric("今日到期", value: queue.filter { isDueToday($0.nextDueDate) }.count)
                dueMetric("已逾期", value: queue.filter { isOverdue($0.nextDueDate) }.count)
            }
            .padding(.vertical, 15)
            .background(Color(red: 0.95, green: 0.97, blue: 1), in: RoundedRectangle(cornerRadius: 16))

            if queue.isEmpty {
                selectedCategoryEmptyState
            } else {
                HStack {
                    Text("\(selectedCategory.title) · \(queue.count) 条待复习")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button("开始全部") { beginSession(queue) }
                    .font(.system(size: 13, weight: .medium))
                }
                VStack(spacing: 8) {
                    ForEach(queue) { plan in
                        if let group = groupsByID[plan.wordRecordID] {
                            Button { beginSession([plan]) } label: {
                                reviewGroupRow(group, detail: dueDescription(plan.nextDueDate), trailing: "开始")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var categorySelector: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(WordCategory.allCases) { category in
                let isSelected = category == selectedCategory
                Button {
                    selectedCategoryID = category.rawValue
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 13, weight: .medium))
                        Text(category.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 2)
                        Text("\(dueQueue.filter { groupsByID[$0.wordRecordID]?.category == category }.count)")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        isSelected ? AppTheme.accent.opacity(0.09) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppTheme.accent.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityLabel("选择词语类别")
    }

    @ViewBuilder
    private var selectedCategoryEmptyState: some View {
        if !dueQueue.isEmpty {
            emptyState(
                title: "此类别暂无待复习词语",
                detail: "其他类别还有 \(dueQueue.count) 条到期内容，可切换上方类别查看。",
                image: selectedCategory.systemImage
            )
        } else if let nextDueDate = plans
            .filter({ groupsByID[$0.wordRecordID] != nil })
            .compactMap(\.nextDueDate)
            .filter({ Calendar.current.startOfDay(for: $0) > reviewDay })
            .min() {
            emptyState(
                title: "下一次复习在 \(shortDate(nextDueDate))",
                detail: "新词会从加入当天进入复习；后续日期根据每次掌握情况安排。",
                image: "calendar"
            )
        } else if groupsByID.isEmpty {
            emptyState(
                title: "词语库还没有可复习词条",
                detail: "新增词语后会按加入日期自动进入复习。",
                image: "books.vertical"
            )
        } else {
            emptyState(
                title: "今天没有待复习词语",
                detail: "词语会按加入日期和复习结果自动安排。",
                image: "checkmark.circle"
            )
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
                        Text(group.category.isComparison
                             ? "先回忆各词的共同含义、核心侧重和判断线索。"
                             : "先回忆这个词的含义和典型用法。")
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
                        Text(group.category.isComparison ? "这组词你掌握得怎样？" : "这个词你掌握得怎样？")
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
                    emptyState(title: "词条已不可用", detail: "该词语可能已被删除，可结束本次复习。", image: "questionmark.folder")
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

    private func dueMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(value)").font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewGroupRow(_ group: WordReviewWordGroup, detail: String, trailing: String) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(group.categoryTitle) · \(detail)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(trailing).font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.accent)
        }
        .padding(13)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.10), lineWidth: 0.8))
        .contentShape(RoundedRectangle(cornerRadius: 13))
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
                        if !term.meaning.isEmpty { revealSection("释义", text: term.meaning) }
                        if !term.coreFocus.isEmpty { revealSection("核心侧重", text: term.coreFocus) }
                        if !term.quickDecision.isEmpty { revealSection("一眼判断", text: term.quickDecision) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
                if !group.judgmentHint.isEmpty { revealRichTextSection("判断提示", html: group.judgmentHint) }
            } else {
                if !group.pinyin.isEmpty { revealSection("拼音", text: group.pinyin) }
                if !group.partOfSpeech.isEmpty { revealSection("词性", text: group.partOfSpeech) }
                if !group.meaning.isEmpty { revealRichTextSection("释义", html: group.meaning) }
                if !group.example.isEmpty { revealSection("例句", text: group.example) }
                if !group.myUnderstanding.isEmpty { revealSection("我的理解", text: group.myUnderstanding) }
                if !group.collocations.isEmpty { revealSection("常见搭配", text: group.collocations) }
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
            Text(item.nextDueDate.map { "下次复习：\(shortDate($0))" }
                 ?? (item.isContextValidationPending == true ? "等待语境验证" : "本轮未安排下次复习"))
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Button(sessionIndex + 1 < activeSession.count ? "下一项" : "完成") {
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

    private func dueDescription(_ date: Date?) -> String {
        guard let date else { return "尚未安排日期" }
        if isOverdue(date) { return "逾期至 \(shortDate(date))" }
        if isDueToday(date) { return "今天到期" }
        return "\(shortDate(date))到期"
    }

    private func isDueToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private func isOverdue(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: .now)
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

    private func beginSession(_ plans: [WordReviewPlan]) {
        var seenIDs = Set<String>()
        let valid = plans.filter { plan in
            groupsByID[plan.wordRecordID] != nil && seenIDs.insert(plan.wordRecordID).inserted
        }
        guard !valid.isEmpty else { return }
        activeSession = valid.map { plan in
            SessionEntry(
                wordRecordID: plan.wordRecordID,
                attemptType: plan.status == .waitingToLearn ? .initial : .due
            )
        }
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
            ContentUnavailableView("词条已删除", systemImage: "text.book.closed", description: Text("该词语已从词语库移除。"))
        }
    }
}
