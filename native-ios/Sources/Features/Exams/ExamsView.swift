import SwiftData
import SwiftUI

private struct ExamRecordTarget: Identifiable { let recordID: String; var id: String { recordID } }
private struct ExamEditorTarget: Identifiable { let recordID: String?; var id: String { recordID ?? "new" } }
private enum ExamRange: String, CaseIterable, Identifiable { case all = "全部", month = "本月", threeMonths = "近三月"; var id: String { rawValue } }
private enum ExamTypeFilter: String, CaseIterable, Identifiable { case all = "全部", real = "真题", mock = "模拟卷", pending = "未分类"; var id: String { rawValue } }
private enum ExamSort: String, CaseIterable, Identifiable { case latest = "最新", accuracyHigh = "正确率高→低", accuracyLow = "正确率低→高"; var id: String { rawValue } }

private enum ExamDisplayFormatting {
    static func score(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        let raw = (value as? NSNumber)?.stringValue ?? (value as? String ?? "")
        guard let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 16
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? raw
    }

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 { return "\(hours)小时\(minutes)分\(remainder)秒" }
        if minutes > 0 { return "\(minutes)分\(remainder)秒" }
        return "\(remainder)秒"
    }
}

struct ExamsView: View {
    @Query private var records: [StoredRecord]
    @State private var searchText = ""
    @State private var selectedRange: ExamRange = .all
    @State private var selectedType: ExamTypeFilter = .all
    @State private var selectedSort: ExamSort = .latest
    @State private var editorTarget: ExamEditorTarget?
    @State private var attemptTarget: ExamRecordTarget?

    private var allExams: [StoredRecord] { records.filter { $0.collection == "exams" } }
    private var pendingExamCount: Int {
        allExams.filter {
            LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) == nil
                || LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) == .pending
        }.count
    }
    private var statisticsExams: [StoredRecord] {
        allExams.filter { record in
            let type = LibraryReviewSource.explicitValue(in: record.indexObject ?? [:]) ?? .pending
            let matchesType: Bool = switch selectedType {
            case .all: true
            case .real: type == .real
            case .mock: type == .mock
            case .pending: type == .pending
            }
            return matchesType && matchesRange(examDate(record))
        }
    }
    private var exams: [StoredRecord] {
        allExams.filter { record in
            let object = record.indexObject ?? [:]
            let name = object["name"] as? String ?? ""
            let note = object["reviewNote"] as? String ?? ""
            let matchesSearch = searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText) || note.localizedCaseInsensitiveContains(searchText)
            let type = LibraryReviewSource.explicitValue(in: object) ?? .pending
            let matchesType: Bool = switch selectedType {
            case .all: true
            case .real: type == .real
            case .mock: type == .mock
            case .pending: type == .pending
            }
            return matchesSearch && matchesRange(examDate(record)) && matchesType
        }.sorted { left, right in
            switch selectedSort {
            case .latest: examDate(left) > examDate(right)
            case .accuracyHigh: accuracy(left) > accuracy(right)
            case .accuracyLow: accuracy(left) < accuracy(right)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterHeader
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    metric("套卷记录", "\(statisticsExams.count)")
                    metric(scoreMetricTitle, averageScoreText)
                    metric("总体正确率", overallAccuracyText)
                }
                HStack(alignment: .center, spacing: 10) {
                    Text("套卷记录").font(AppTheme.sectionTitleFont)
                    Spacer(minLength: 8)
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索套卷或复盘内容", text: $searchText).font(AppTheme.inputFont) }
                        .padding(.horizontal, 11).frame(maxWidth: 300).frame(height: 38).background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10))
                    Button { editorTarget = ExamEditorTarget(recordID: nil) } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 38, height: 38).background(AppTheme.accent.opacity(0.10), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("记录新套卷")
                }
                if exams.isEmpty {
                    NativeStatusCard(title: "暂无套卷", detail: "点击加号记录一次真题或模拟卷", systemImage: "doc.text", color: AppTheme.accent)
                } else {
                    HStack {
                        Text("共 \(exams.count) 次").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                        Spacer()
                        filterMenu(title: selectedSort.rawValue) {
                            ForEach(ExamSort.allCases) { value in Button(value.rawValue) { selectedSort = value } }
                        }
                    }
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(exams, id: \.recordID) { exam in
                            Button { attemptTarget = ExamRecordTarget(recordID: exam.recordID) } label: {
                                examCard(exam)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("套卷统计")
        .navigationBarTitleDisplayMode(.inline)
        .rootTabBarContentInset()
        .sheet(item: $editorTarget) { target in
            NavigationStack { ExamEditorView(record: records.first { $0.collection == "exams" && $0.recordID == target.recordID }) }
        }
        .sheet(item: $attemptTarget) { target in
            NavigationStack { ExamAttemptDetailView(recordID: target.recordID) }
        }
    }

    private var filterHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach([ExamTypeFilter.all, .real, .mock]) { value in
                    Button { selectedType = value } label: {
                        Text(value.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedType == value ? AppTheme.accent : Color.primary)
                            .background(selectedType == value ? Color.white : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.055), in: Capsule())
            Spacer(minLength: 4)
            filterMenu(title: selectedRange.rawValue) {
                ForEach(ExamRange.allCases) { value in Button(value.rawValue) { selectedRange = value } }
            }
            Menu {
                Button("查看未分类套卷（\(pendingExamCount)）") { selectedType = .pending }
                Button("返回当前分类") { selectedType = .all }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.secondaryBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多套卷分类")
        }
    }

    private func examCard(_ exam: StoredRecord) -> some View {
        let object = exam.indexObject ?? [:]
        let examDraft = ExamDraft(record: exam)
        let type = LibraryReviewSource.explicitValue(in: object) ?? .pending
        let score = ExamDisplayFormatting.score(object["score"])
        let maximum = ExamDisplayFormatting.score(object["maximumScore"])
        let correctCount = examDraft.metrics.correctCount.map(String.init) ?? "—"
        let resultCount = examDraft.metrics.totalQuestions.map(String.init) ?? "—"
        let duration = examDraft.metrics.totalTimeSeconds.map(ExamDisplayFormatting.duration) ?? "—"
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(type.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(type == .pending ? AppTheme.warning : AppTheme.accent)
                    .padding(.horizontal, 7).padding(.vertical, 3).background((type == .pending ? AppTheme.warning : AppTheme.accent).opacity(0.08), in: Capsule())
                Text(examDate(exam), format: .dateTime.year().month().day()).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(object["name"] as? String ?? "未命名套卷")
                    .font(AppTheme.cardTitleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(score.isEmpty ? "—" : score)分")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                    if !maximum.isEmpty {
                        Text("/ \(maximum)")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 8) {
                examMetric("\(correctCount)/\(resultCount)题", systemImage: "checkmark.circle")
                examMetric(examDraft.metrics.accuracyPercent.map { String(format: "%.2f%%", $0) } ?? "—", systemImage: "percent")
                examMetric(duration, systemImage: "clock")
            }
            .font(AppTheme.auxiliaryFont)
            .foregroundStyle(.secondary)
            if let note = object["reviewNote"] as? String, !note.isEmpty {
                Text(plainText(note)).font(AppTheme.bodyFont).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Text("查看本次统计").font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(AppTheme.accent)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }

    private func examMetric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .regular))
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
            Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).nativeCard()
    }

    private func filterMenu<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack(spacing: 4) { Text(title); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
                .font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).frame(height: 34).background(AppTheme.secondaryBackground, in: Capsule())
        }
    }

    private var accuracyRows: [(Int, Int)] {
        statisticsExams.compactMap { record in
            guard let object = record.indexObject,
                  let total = intValue(object["totalQuestions"]),
                  let correct = intValue(object["correctCount"]),
                  total > 0, correct >= 0, correct <= total else { return nil }
            return (total, correct)
        }
    }
    private var overallAccuracyText: String {
        let total = accuracyRows.reduce(0) { $0 + $1.0 }
        guard total > 0 else { return "—" }
        let correct = accuracyRows.reduce(0) { $0 + $1.1 }
        return String(format: "%.2f%%", Double(correct) * 100 / Double(total))
    }
    private var scoreEntries: [(score: Double, maximum: Double, date: Date)] {
        statisticsExams.compactMap { record in
            let object = record.indexObject ?? [:]
            guard let score = Double(numberText(object["score"])),
                  let maximum = Double(numberText(object["maximumScore"])), maximum > 0 else { return nil }
            return (score, maximum, examDate(record))
        }
    }
    private var scoreMetricTitle: String {
        "平均得分"
    }
    private var averageScoreText: String {
        guard let latest = scoreEntries.max(by: { $0.date < $1.date }) else { return "—" }
        let comparable = scoreEntries.filter { abs($0.maximum - latest.maximum) < 0.0001 }
        guard !comparable.isEmpty else { return "—" }
        return formatNumber(comparable.reduce(0) { $0 + $1.score } / Double(comparable.count))
    }

    private func accuracy(_ record: StoredRecord) -> Double {
        let object = record.indexObject ?? [:]
        guard let total = intValue(object["totalQuestions"]), let correct = intValue(object["correctCount"]), total > 0 else { return -1 }
        return Double(correct) / Double(total)
    }
    private func matchesRange(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch selectedRange {
        case .all: return true
        case .month:
            let components = calendar.dateComponents([.year, .month], from: .now)
            return date >= (calendar.date(from: components) ?? .distantPast)
        case .threeMonths:
            return date >= (calendar.date(byAdding: .month, value: -3, to: .now) ?? .distantPast)
        }
    }
    private func examDate(_ record: StoredRecord) -> Date {
        guard let value = record.indexObject?["examDate"] as? String else { return record.createdAt ?? .distantPast }
        return ExamDraft.dayFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? record.createdAt ?? .distantPast
    }
    private func numberText(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return (value as? NSNumber)?.stringValue ?? (value as? String ?? "")
    }
    private func intValue(_ value: Any?) -> Int? { Int(numberText(value)) }
    private func formatNumber(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value) }
    private func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ExamAttemptDetailView: View {
    @Query private var records: [StoredRecord]
    @State private var showEdit = false
    @State private var showAddError = false
    let recordID: String

    private var record: StoredRecord? { records.first { $0.collection == "exams" && $0.recordID == recordID } }
    private var draft: ExamDraft { ExamDraft(record: record) }
    private var object: [String: Any] { record?.indexObject ?? [:] }
    private var type: LibraryReviewSource { record.flatMap { LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) } ?? .pending }
    private var linkedErrors: [StoredRecord] { records.filter { $0.collection == "errors" && $0.jsonObject?["sourceExamId"] as? String == recordID } }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    resultCard
                    if !draft.rawReport.isEmpty {
                        DisclosureGroup("报告原文") {
                            Text(draft.rawReport).font(AppTheme.auxiliaryFont).textSelection(.enabled).padding(.top, 6)
                        }.nativeCard()
                    }
                    if !draft.reviewNote.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            NativeFieldLabel(title: "复盘笔记")
                            Text(draft.reviewNote.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
                                .font(AppTheme.bodyFont).foregroundStyle(.secondary)
                        }.nativeCard()
                    }
                    linkedErrorsCard
                    HStack {
                        Button("编辑本次记录") { showEdit = true }.buttonStyle(NativeSecondaryButtonStyle())
                        if type == .mock {
                            Button { showAddError = true } label: { Label("添加错题", systemImage: "plus") }
                                .buttonStyle(NativePrimaryButtonStyle())
                        }
                    }
                }.padding(20)
            } else {
                NativeStatusCard(title: "考试记录不存在", detail: "本次考试可能已被删除", systemImage: "doc.text", color: .secondary).padding(20)
            }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(object["name"] as? String ?? "考试详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("编辑") { showEdit = true }.disabled(record == nil) }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack { ExamEditorView(record: record) }
        }
        .sheet(isPresented: $showAddError) {
            NavigationStack {
                LibraryRecordEditorView(
                    kind: .errors,
                    scope: LibraryScope(reviewSource: .mock),
                    preferredSourceExamID: recordID,
                    dismissAfterSave: true
                )
            }
        }
    }

    private var summaryCard: some View {
        let score = ExamDisplayFormatting.score(object["score"])
        let maximum = ExamDisplayFormatting.score(object["maximumScore"])
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(type.title).font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(type == .pending ? AppTheme.warning : AppTheme.accent)
                Spacer()
                if let value = object["examDate"] as? String { Text(value).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
            }
            Text("得分：\(score.isEmpty ? "未知" : score) / \(maximum.isEmpty ? "未知" : maximum)")
                .font(AppTheme.bodyFont.weight(.semibold))
            HStack(spacing: 14) {
                detailMetric("总题数", draft.metrics.totalQuestions.map(String.init) ?? "未知")
                detailMetric("答对", draft.metrics.correctCount.map(String.init) ?? "未知")
                detailMetric("答错", draft.metrics.wrongCount.map(String.init) ?? "未知")
                detailMetric("正确率", draft.metrics.accuracyPercent.map { String(format: "%.2f%%", $0) } ?? "未知")
            }
            detailMetric("总用时", draft.metrics.totalTimeSeconds.map(ExamDisplayFormatting.duration) ?? "未知")
        }.nativeCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            NativeFieldLabel(title: "模块成绩")
            ForEach(draft.moduleResults) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.subject).font(AppTheme.inputFont.weight(.medium))
                    Spacer()
                    Text("\(line.correctCount.isEmpty ? "—" : line.correctCount)/\(line.totalQuestions.isEmpty ? "—" : line.totalQuestions)")
                    Text(line.reportedAccuracy.isEmpty ? "—" : "\(line.reportedAccuracy)%")
                    Text(Int(line.timeSeconds).map(ExamDisplayFormatting.duration) ?? "—")
                }.font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            if !draft.metrics.conflictModules.isEmpty {
                Text("重复模块有冲突：\(draft.metrics.conflictModules.sorted().joined(separator: "、"))").font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
            ForEach(draft.metrics.hierarchyWarnings, id: \.self) { warning in
                Text(warning + "；按父项统计，不重复累计子项。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
        }.nativeCard()
    }

    private var linkedErrorsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NativeFieldLabel(title: "关联错题")
                Spacer()
                Text("\(linkedErrors.count) 条").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            Text("这次报告中的答错数与应用中已录入错题数分别统计。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            ForEach(linkedErrors, id: \.recordID) { error in
                HStack {
                    Text(error.title).font(AppTheme.inputFont).lineLimit(2)
                    Spacer()
                    Text([error.subject, error.module].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            if linkedErrors.isEmpty { Text("尚未关联错题").font(AppTheme.auxiliaryFont).foregroundStyle(.tertiary) }
        }.nativeCard()
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
