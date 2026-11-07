import SwiftData
import SwiftUI

struct WordReviewView: View {
    private enum OverviewTab: String, CaseIterable, Identifiable, Hashable {
        case today = "今日"
        case plan = "计划"
        case history = "历史"
        var id: String { rawValue }
    }

    private struct SessionEntry: Identifiable {
        let wordRecordID: String
        let attemptType: WordReviewAttemptType
        var id: String { "\(wordRecordID):\(attemptType.rawValue)" }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "words"
            || record.collection == "word_review_plans"
            || record.collection == "word_review_history"
    }) private var records: [StoredRecord]

    @State private var tab: OverviewTab = .today
    @State private var isShowingCatalog = false
    @State private var searchText = ""
    @State private var catalogFilter = "全部"
    @State private var selectedCatalogIDs = Set<String>()
    @State private var activeSession: [SessionEntry] = []
    @State private var sessionIndex = 0
    @State private var isRevealed = false
    @State private var savedHistory: WordReviewHistory?
    @State private var errorMessage: String?

    private var wordRecords: [StoredRecord] { records.filter { $0.collection == "words" } }
    private var planRecords: [StoredRecord] { records.filter { $0.collection == "word_review_plans" } }
    private var historyRecords: [StoredRecord] { records.filter { $0.collection == "word_review_history" } }
    private var plans: [WordReviewPlan] { WordReviewRepository.plans(from: planRecords) }
    private var visiblePlans: [WordReviewPlan] { plans.filter { groupsByID[$0.wordRecordID] != nil } }
    private var history: [WordReviewHistory] { WordReviewRepository.history(from: historyRecords) }
    private var groupsByID: [String: WordReviewWordGroup] {
        Dictionary(uniqueKeysWithValues: wordRecords.compactMap { record in
            WordReviewWordGroup(record: record).map { ($0.recordID, $0) }
        })
    }
    private var dueQueue: [WordReviewPlan] {
        let today = Calendar.current.startOfDay(for: .now)
        return plans.filter { plan in
            !plan.isPaused
                && groupsByID[plan.wordRecordID] != nil
                && WordReviewSchedulingPolicy.isDue(plan.nextDueDate, on: today)
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
        .sheet(isPresented: $isShowingCatalog, onDismiss: { selectedCatalogIDs.removeAll() }) {
            catalogSheet
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
                case .plan: planContent
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                dueMetric("待复习", value: dueQueue.count)
                dueMetric("今日到期", value: dueQueue.filter { isDueToday($0.nextDueDate) }.count)
                dueMetric("已逾期", value: dueQueue.filter { isOverdue($0.nextDueDate) }.count)
            }
            .padding(.vertical, 15)
            .background(Color(red: 0.95, green: 0.97, blue: 1), in: RoundedRectangle(cornerRadius: 16))

            if dueQueue.isEmpty {
                emptyState(
                    title: "今天没有到期词语组",
                    detail: plans.isEmpty ? "从成语辨析或实词辨析词条加入复习计划。" : "新的复习会按计划日期进入队列。",
                    image: "checkmark.circle"
                )
            } else {
                HStack {
                    Text("到期词语组").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button("开始全部") {
                        beginSession(dueQueue.map(\.wordRecordID), type: .due)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                VStack(spacing: 8) {
                    ForEach(dueQueue) { plan in
                        if let group = groupsByID[plan.wordRecordID] {
                            Button { beginSession([plan.wordRecordID], type: .due) } label: {
                                reviewGroupRow(group, detail: dueDescription(plan.nextDueDate), trailing: "开始")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("复习计划").font(.system(size: 18, weight: .semibold))
                    Text("\(visiblePlans.count) 个已加入词语组")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { isShowingCatalog = true } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
            }

            HStack(spacing: 6) {
                statusMetric("待学习", count: count(.waitingToLearn), color: .secondary)
                statusMetric("待训练", count: count(.training), color: AppTheme.warning)
                statusMetric("待验证", count: count(.verification), color: AppTheme.accent)
                statusMetric("已稳定", count: count(.stable), color: AppTheme.success)
            }

            if visiblePlans.isEmpty {
                emptyState(title: "还没有复习计划", detail: "可从词条详情加入，也可批量选择现有辨析组。", image: "books.vertical")
            } else {
                VStack(spacing: 10) {
                    ForEach(visiblePlans.sorted(by: planOrder)) { plan in
                        if let group = groupsByID[plan.wordRecordID] {
                            planCard(plan, group: group)
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
                        Text("先回忆各词的共同含义、核心侧重和判断线索。")
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
                            Label("查看辨析", systemImage: "eye")
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

    private var catalogSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索词语组", text: $searchText)
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Picker("词语类型", selection: $catalogFilter) {
                    Text("全部").tag("全部")
                    Text("成语组").tag("成语组")
                    Text("实词组").tag("实词组")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                List(catalogGroups) { group in
                    let isAdded = plans.contains { $0.wordRecordID == group.recordID }
                    Button {
                        guard !isAdded else { return }
                        if selectedCatalogIDs.contains(group.recordID) {
                            selectedCatalogIDs.remove(group.recordID)
                        } else {
                            selectedCatalogIDs.insert(group.recordID)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isAdded ? "checkmark.circle.fill" : selectedCatalogIDs.contains(group.recordID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isAdded ? AppTheme.success : selectedCatalogIDs.contains(group.recordID) ? AppTheme.accent : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                                Text(isAdded ? "已在计划中" : group.categoryTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdded)
                }
                .listStyle(.plain)
            }
            .navigationTitle("添加辨析组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { isShowingCatalog = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("加入 \(selectedCatalogIDs.count)") { addSelectedGroups() }
                        .disabled(selectedCatalogIDs.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var catalogGroups: [WordReviewWordGroup] {
        wordRecords.compactMap(WordReviewWordGroup.init(record:))
            .filter { catalogFilter == "全部" || $0.categoryTitle == catalogFilter }
            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
            .sorted {
                if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                return $0.recordID < $1.recordID
            }
    }

    private func dueMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(value)").font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusMetric(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.system(size: 18, weight: .semibold)).foregroundStyle(color).monospacedDigit()
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
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

    private func planCard(_ plan: WordReviewPlan, group: WordReviewWordGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Text(group.categoryTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(plan.isPaused ? "已暂停" : plan.status.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(plan.isPaused ? Color.secondary : statusColor(plan.status))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(statusColor(plan.status).opacity(plan.isPaused ? 0.07 : 0.11), in: Capsule())
            }
            HStack(spacing: 7) {
                if plan.status == .verification {
                    Text(plan.isContextValidationPending ? "待语境验证" : "第 \(plan.verificationRound) 轮")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(plan.nextDueDate.map(dueDescription) ?? "尚未安排日期")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                if plan.status == .waitingToLearn {
                    Button("完成整理") { perform { try WordReviewRepository.finishPreparation(wordRecordID: plan.wordRecordID, in: modelContext) } }
                        .buttonStyle(ReviewSmallButtonStyle(isPrimary: true))
                }
                    Button(plan.isPaused ? "恢复计划" : "暂停") {
                    perform { try WordReviewRepository.setPaused(!plan.isPaused, wordRecordID: plan.wordRecordID, in: modelContext) }
                }
                .buttonStyle(ReviewSmallButtonStyle(isPrimary: false))
                Button("提前复习") { beginSession([plan.wordRecordID], type: .early) }
                    .buttonStyle(ReviewSmallButtonStyle(isPrimary: false))
            }
        }
        .padding(13)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))
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
                Text("\(item.feedback.title) · 下次：\(item.nextDueDate.map(shortDate) ?? "待语境验证/未安排")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.7) }
    }

    private func revealedContent(_ group: WordReviewWordGroup) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if !group.commonMeaning.isEmpty { revealSection("共同语义", text: group.commonMeaning) }
            if !group.coreDifference.isEmpty { revealSection("核心区别", text: group.coreDifference) }
            ForEach(group.terms) { term in
                VStack(alignment: .leading, spacing: 5) {
                    Text(term.name).font(.system(size: 15, weight: .semibold))
                    if !term.coreFocus.isEmpty { revealSection("核心侧重", text: term.coreFocus) }
                    if !term.quickDecision.isEmpty { revealSection("一眼判断", text: term.quickDecision) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            if !group.judgmentHint.isEmpty { revealRichTextSection("判断提示", html: group.judgmentHint) }
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
            Text(item.nextDueDate.map { "下次计划：\(shortDate($0))" } ?? "本轮完成，等待语境验证")
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

    private func count(_ status: WordReviewPlanStatus) -> Int {
        visiblePlans.filter { $0.status == status }.count
    }

    private func planOrder(_ lhs: WordReviewPlan, _ rhs: WordReviewPlan) -> Bool {
        let order: [WordReviewPlanStatus: Int] = [.waitingToLearn: 0, .training: 1, .verification: 2, .stable: 3]
        if order[lhs.status] != order[rhs.status] { return order[lhs.status, default: 0] < order[rhs.status, default: 0] }
        let left = groupsByID[lhs.wordRecordID]?.title ?? ""
        let right = groupsByID[rhs.wordRecordID]?.title ?? ""
        if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
        return lhs.wordRecordID < rhs.wordRecordID
    }

    private func statusColor(_ status: WordReviewPlanStatus) -> Color {
        switch status {
        case .waitingToLearn: .secondary
        case .training: AppTheme.warning
        case .verification: AppTheme.accent
        case .stable: AppTheme.success
        }
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
        return "计划 \(shortDate(date))"
    }

    private func isDueToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private func isOverdue(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: .now)
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

    private func beginSession(_ ids: [String], type: WordReviewAttemptType) {
        var seenIDs = Set<String>()
        let uniqueIDs = ids.filter { seenIDs.insert($0).inserted }
        let valid = uniqueIDs.filter { groupsByID[$0] != nil }
        guard !valid.isEmpty else { return }
        activeSession = valid.map { SessionEntry(wordRecordID: $0, attemptType: type) }
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
                submissionID: UUID().uuidString,
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

    private func addSelectedGroups() {
        let selected = wordRecords.filter { selectedCatalogIDs.contains($0.recordID) }
        do {
            _ = try WordReviewRepository.enroll(selected, in: modelContext)
            isShowingCatalog = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ReviewSmallButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isPrimary ? Color.white : AppTheme.accent)
            .padding(.horizontal, 11)
            .frame(height: 31)
            .background(isPrimary ? AppTheme.accent : AppTheme.accent.opacity(0.08), in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
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
            WordLibraryRecordDetailView(record: record, showsReviewAction: true)
        } else {
            ContentUnavailableView("词条已删除", systemImage: "text.book.closed", description: Text("该词语组已从词语库移除。"))
        }
    }
}
