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

    static func detailedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 { return "\(hours)时\(minutes)分\(remainder)秒" }
        if minutes > 0 { return "\(minutes)分\(remainder)秒" }
        return "\(remainder)秒"
    }

    static func compactDuration(_ seconds: Int) -> String {
        guard seconds >= 0 else { return "—" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        if minutes > 0 { return "\(minutes)′\(String(format: "%02d", remainder))″" }
        return "\(remainder)″"
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

private struct ExamModuleDisplayRow: Identifiable {
    let id: String
    let subject: String
    let parentSubject: String
    let result: ExamModuleResult?
    let isChild: Bool
    let isFoldableParent: Bool
    let startsGroup: Bool
}

private struct ExamSummaryMetric: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

private struct ExamAttemptDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [StoredRecord]
    @AppStorage("native.exams.detail.verbalExpanded.v1") private var verbalExpanded = true
    @AppStorage("native.exams.detail.reasoningExpanded.v1") private var reasoningExpanded = true
    @State private var showEdit = false
    @State private var showAddError = false
    let recordID: String

    private let foldableSubjects = ["言语理解与表达", "判断推理"]

    private var record: StoredRecord? { records.first { $0.collection == "exams" && $0.recordID == recordID } }
    private var draft: ExamDraft { ExamDraft(record: record) }
    private var object: [String: Any] { record?.indexObject ?? [:] }
    private var type: LibraryReviewSource { record.flatMap { LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) } ?? .pending }
    private var linkedErrors: [StoredRecord] { records.filter { $0.collection == "errors" && $0.jsonObject?["sourceExamId"] as? String == recordID } }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width < 360 ? 12 : (geometry.size.width < 520 ? 16 : 20)
            let cardPadding: CGFloat = geometry.size.width < 360 ? 12 : (geometry.size.width < 520 ? 16 : 20)
            let contentWidth = min(geometry.size.width - horizontalPadding * 2, 900) - cardPadding * 2

            ScrollView {
                if record != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard(padding: cardPadding)
                        resultCard(availableWidth: contentWidth, padding: cardPadding)
                        linkedErrorsCard(padding: cardPadding)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 940)
                    .frame(maxWidth: .infinity)
                } else {
                    NativeStatusCard(title: "考试记录不存在", detail: "本次考试可能已被删除", systemImage: "doc.text", color: .secondary)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(AppTheme.groupedBackground)
        }
        .navigationTitle("套卷记录")
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

    private var formattedExamDate: String {
        guard let value = object["examDate"] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let date = ExamDraft.dayFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
            return "—"
        }
        return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }

    private var scoreValue: String { ExamDisplayFormatting.score(object["score"]).nilIfEmpty ?? "—" }
    private var maximumScoreValue: String { ExamDisplayFormatting.score(object["maximumScore"]).nilIfEmpty ?? "—" }

    private func summaryCard(padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text(type.title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(type == .pending ? AppTheme.warning : AppTheme.accent)
                Spacer(minLength: 8)
                Text(formattedExamDate)
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(object["name"] as? String ?? "未命名套卷")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("本次得分")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(scoreValue)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("/ \(maximumScoreValue)")
                        .font(.system(.title3))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(summaryMetrics) { metric in detailMetric(metric.title, metric.value) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), alignment: .leading, spacing: 14) {
                    ForEach(summaryMetrics) { metric in detailMetric(metric.title, metric.value) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard(padding: padding)
    }

    private var summaryMetrics: [ExamSummaryMetric] {
        let metrics = draft.metrics
        return [
            ExamSummaryMetric(title: "总题数", value: metrics.totalQuestions.map(String.init) ?? "—"),
            ExamSummaryMetric(title: "答对", value: metrics.correctCount.map(String.init) ?? "—"),
            ExamSummaryMetric(title: "答错", value: metrics.wrongCount.map(String.init) ?? "—"),
            ExamSummaryMetric(title: "正确率", value: metrics.accuracyPercent.map { String(format: "%.2f%%", $0) } ?? "—"),
            ExamSummaryMetric(title: "本次用时", value: metrics.totalTimeSeconds.map(ExamDisplayFormatting.detailedDuration) ?? "—")
        ]
    }

    private func resultCard(availableWidth: CGFloat, padding: CGFloat) -> some View {
        let columns = moduleColumnWidths(for: availableWidth)
        let rows = moduleDisplayRows
        let header = moduleTableHeader(columns: columns)

        return VStack(alignment: .leading, spacing: 8) {
            Text("模块成绩")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.primary)

            if rows.isEmpty {
                Text("暂无模块成绩")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                header
                ForEach(visibleModuleRows) { row in
                    if row.startsGroup {
                        Rectangle()
                            .fill(Color.primary.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.vertical, 3)
                    }
                    moduleResultRow(row, columns: columns)
                }
            }

            if !draft.metrics.conflictModules.isEmpty {
                Text("重复模块有冲突：\(draft.metrics.conflictModules.sorted().joined(separator: "、"))")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
            ForEach(draft.metrics.hierarchyWarnings, id: \.self) { warning in
                Text(warning + "；按父项统计，不重复累计子项。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard(padding: padding)
    }

    private func moduleColumnWidths(for width: CGFloat) -> ModuleColumnWidths {
        if width < 260 { return ModuleColumnWidths(correct: 50, accuracy: 48, time: 56, spacing: 4) }
        if width < 300 { return ModuleColumnWidths(correct: 54, accuracy: 50, time: 60, spacing: 6) }
        if width < 420 { return ModuleColumnWidths(correct: 64, accuracy: 58, time: 76, spacing: 8) }
        return ModuleColumnWidths(correct: 88, accuracy: 72, time: 104, spacing: 12)
    }

    private func moduleTableHeader(columns: ModuleColumnWidths) -> some View {
        HStack(alignment: .bottom, spacing: columns.spacing) {
            Text("模块")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("答对/题数")
                .frame(width: columns.correct, alignment: .trailing)
            Text("正确率")
                .frame(width: columns.accuracy, alignment: .trailing)
            Text("用时")
                .frame(width: columns.time, alignment: .trailing)
        }
        .font(.system(.caption, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func moduleResultRow(_ row: ExamModuleDisplayRow, columns: ModuleColumnWidths) -> some View {
        let counts = "\(displayValue(row.result?.correctCount))/\(displayValue(row.result?.totalQuestions))"
        let rawAccuracy = displayValue(row.result?.reportedAccuracy)
        let accuracy = rawAccuracy == "—" || rawAccuracy.hasSuffix("%") ? rawAccuracy : "\(rawAccuracy)%"
        let time = Int(row.result?.timeSeconds ?? "").map(ExamDisplayFormatting.compactDuration) ?? "—"
        let minimumHeight: CGFloat = row.isChild ? 40 : 44

        let content = HStack(alignment: .center, spacing: columns.spacing) {
            HStack(alignment: .center, spacing: 4) {
                if row.isFoldableParent {
                    Image(systemName: isExpanded(row.parentSubject) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                Text(row.subject)
                    .font(row.isChild ? .system(.body) : .system(.body, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, row.isChild ? 16 : 0)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)

            moduleValue(counts, minimumHeight: minimumHeight)
                .frame(width: columns.correct, alignment: .trailing)
            moduleValue(accuracy, minimumHeight: minimumHeight)
                .frame(width: columns.accuracy, alignment: .trailing)
            moduleValue(time, minimumHeight: minimumHeight)
                .frame(width: columns.time, alignment: .trailing)
        }

        Group {
            if row.isFoldableParent {
                Button { toggleExpanded(row.parentSubject) } label: {
                    content.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.subject)
                .accessibilityValue(isExpanded(row.parentSubject) ? "已展开" : "已收起")
                .accessibilityHint("轻点切换子模块显示")
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moduleValue(_ value: String, minimumHeight: CGFloat) -> some View {
        Text(value)
            .font(.system(.body))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .trailing)
    }

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }

    private var moduleDisplayRows: [ExamModuleDisplayRow] {
        let lines = draft.moduleResults.filter { $0.subject != ExamModuleCatalog.placeholderSubject }
        var orderedParents: [String] = []
        for line in lines where !orderedParents.contains(line.parentSubject) {
            orderedParents.append(line.parentSubject)
        }

        var rows: [ExamModuleDisplayRow] = []
        for (groupIndex, parent) in orderedParents.enumerated() {
            let group = lines.filter { $0.parentSubject == parent }
            let parents = group.filter { $0.subject == parent }
            let children = group.filter { $0.subject != parent }
            let isFoldable = foldableSubjects.contains(parent) && !children.isEmpty
            let beginsGroup = groupIndex > 0

            if parents.isEmpty, !children.isEmpty, ExamModuleCatalog.topLevel.contains(parent) {
                rows.append(ExamModuleDisplayRow(
                    id: "module-parent-\(parent)", subject: parent, parentSubject: parent, result: nil,
                    isChild: false, isFoldableParent: isFoldable, startsGroup: beginsGroup
                ))
            } else {
                for (parentIndex, line) in parents.enumerated() {
                    rows.append(ExamModuleDisplayRow(
                        id: line.id, subject: line.subject, parentSubject: parent, result: line,
                        isChild: false, isFoldableParent: isFoldable, startsGroup: beginsGroup && parentIndex == 0
                    ))
                }
            }

            for (childIndex, line) in children.enumerated() {
                rows.append(ExamModuleDisplayRow(
                    id: line.id, subject: line.subject, parentSubject: parent, result: line,
                    isChild: true, isFoldableParent: false,
                    startsGroup: beginsGroup && parents.isEmpty && !(ExamModuleCatalog.topLevel.contains(parent)) && childIndex == 0
                ))
            }
        }
        return rows
    }

    private var visibleModuleRows: [ExamModuleDisplayRow] {
        moduleDisplayRows.filter { row in
            !row.isChild || !foldableSubjects.contains(row.parentSubject) || isExpanded(row.parentSubject)
        }
    }

    private func isExpanded(_ parent: String) -> Bool {
        switch parent {
        case "言语理解与表达": verbalExpanded
        case "判断推理": reasoningExpanded
        default: true
        }
    }

    private func toggleExpanded(_ parent: String) {
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22)
        withAnimation(animation) {
            switch parent {
            case "言语理解与表达": verbalExpanded.toggle()
            case "判断推理": reasoningExpanded.toggle()
            default: break
            }
        }
    }

    private func linkedErrorsCard(padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关联错题")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    linkedErrorSummary
                    Spacer(minLength: 0)
                    linkedErrorActions
                }
                VStack(alignment: .leading, spacing: 6) {
                    linkedErrorSummary
                    linkedErrorActions
                }
            }

            if linkedErrors.isEmpty {
                Text("尚未关联错题")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedErrors, id: \.recordID) { error in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(error.title)
                            .font(.system(.body))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        let metadata = [error.subject, error.module].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                        if !metadata.isEmpty {
                            Text(metadata)
                                .font(.system(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        if error.recordID != linkedErrors.last?.recordID {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard(padding: padding)
    }

    private var linkedErrorSummary: some View {
        let wrongCount = draft.metrics.wrongCount.map(String.init) ?? "—"
        return Text("本次答错 \(wrongCount) 题 · 已关联 \(linkedErrors.count) 题")
            .font(.system(.subheadline))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var linkedErrorActions: some View {
        Menu {
            Button("选择已有错题") { showEdit = true }
            if type == .mock {
                Button("新增并关联错题") { showAddError = true }
            }
        } label: {
            Text("关联错题")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关联错题")
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ModuleColumnWidths {
    let correct: CGFloat
    let accuracy: CGFloat
    let time: CGFloat
    let spacing: CGFloat
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
