import SwiftData
import SwiftUI

private struct ExamRecordTarget: Hashable { let recordID: String }
private struct ExamEditorTarget: Identifiable { let recordID: String?; var id: String { recordID ?? "new" } }
private enum ExamTypeFilter: String, CaseIterable, Identifiable { case all = "全部", real = "真题", mock = "模拟卷"; var id: String { rawValue } }
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

@MainActor
struct ExamsView: View {
    @Environment(\.rootTabBarIsVisible) private var rootTabBarIsVisible
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "exams" }) private var records: [StoredRecord]
    @AppStorage("native.exams.showsReviewNotes") private var showsReviewNotes = true
    @State private var selectedType: ExamTypeFilter = .all
    @State private var selectedSort: ExamSort = .latest
    @State private var editorTarget: ExamEditorTarget?
    @State private var attemptTarget: ExamRecordTarget?
    @State private var expandedNotes: Set<String> = []
    @State private var reviewDrafts = ExamReviewNoteDrafts()

    private var statisticsExams: [StoredRecord] {
        records.filter(matchesSelectedType)
    }
    private var exams: [StoredRecord] {
        statisticsExams.sorted { left, right in
            switch selectedSort {
            case .latest: examDate(left) > examDate(right)
            case .accuracyHigh: accuracy(left) > accuracy(right)
            case .accuracyLow: accuracy(left) < accuracy(right)
            }
        }
    }
    private func matchesSelectedType(_ record: StoredRecord) -> Bool {
        let type = LibraryReviewSource.explicitValue(in: record.indexObject ?? [:]) ?? .pending
        switch selectedType {
        case .all: return true
        case .real: return type == .real
        case .mock: return type == .mock
        }
    }

    var body: some View {
        let visibleExams = exams
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                listFilters
                HStack(spacing: 9) {
                    metric("套卷次数", "\(statisticsExams.count)")
                    metric(scoreMetricTitle, averageScoreText)
                    metric("总体正确率", overallAccuracyText)
                }
                if visibleExams.isEmpty {
                    NativeStatusCard(title: "暂无套卷", detail: "点击加号记录一次真题或模拟卷", systemImage: "doc.text", color: AppTheme.accent)
                } else {
                    HStack {
                        Text("套卷记录")
                            .font(.system(size: 15, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        filterMenu(title: selectedSort.rawValue) {
                            ForEach(ExamSort.allCases) { value in Button(value.rawValue) { selectedSort = value } }
                        }
                    }
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(visibleExams, id: \.recordID) { exam in
                            examCard(exam)
                        }
                    }
                }
            }
            .frame(maxWidth: 900)
            .padding(16)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .overlay(alignment: .bottomTrailing) {
            GeometryReader { geometry in
                Button { editorTarget = ExamEditorTarget(recordID: nil) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(AppTheme.accent, in: Circle())
                        .shadow(color: AppTheme.accent.opacity(0.28), radius: 12, y: 5)
                }
                .buttonStyle(NativePressButtonStyle())
                .accessibilityLabel("记录新套卷")
                .accessibilityIdentifier("exams-add-record")
                .padding(.trailing, 18)
                .padding(.bottom, 8)
                .offset(y: NativeFloatingActionPlacement.maySitAtTabBarTopEdge(
                    windowWidth: geometry.size.width,
                    tabBarVisible: rootTabBarIsVisible
                ) ? 34 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .navigationTitle("套卷统计")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorTarget) { target in
            NavigationStack { ExamEditorView(record: records.first { $0.collection == "exams" && $0.recordID == target.recordID }) }
                .secondaryPageTabBarHidden()
        }
        .navigationDestination(item: $attemptTarget) { target in
            ExamAttemptDetailView(recordID: target.recordID, reviewDrafts: reviewDrafts)
                .secondaryPageTabBarHidden()
        }
    }

    private var listFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filterHeader.frame(minWidth: 210)
                reviewNoteVisibility.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 5) {
                filterHeader
                reviewNoteVisibility.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var reviewNoteVisibility: some View {
        Toggle("显示备注", isOn: $showsReviewNotes)
            .font(.system(size: 13))
            .tint(AppTheme.accent)
            .frame(minHeight: 44)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("exams-show-review-notes")
    }

    private var filterHeader: some View {
        HStack(spacing: 2) {
            ForEach(ExamTypeFilter.allCases) { value in
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
    }

    private func examCard(_ exam: StoredRecord) -> some View {
        let object = exam.indexObject ?? [:]
        let examDraft = ExamDraft(record: exam)
        let score = ExamDisplayFormatting.score(object["score"]).nilIfEmpty ?? "—"
        let date = examDate(exam)
        let metrics = examDraft.metrics
        let correctCount = metrics.correctCount.map(String.init) ?? "—"
        let resultCount = metrics.totalQuestions.map(String.init) ?? "—"
        let accuracy = metrics.accuracyPercent.map { String(format: "%.2f%%", $0) } ?? "—"
        let duration = metrics.totalTimeSeconds.map(ExamDisplayFormatting.compactDuration) ?? "—"
        let note = ExamReviewNote(in: examDraft.original)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                attemptTarget = ExamRecordTarget(recordID: exam.recordID)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(examDraft.name.nilIfEmpty ?? "未命名套卷")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        NativeTagFlow(spacing: 6) {
                            Text("答对 \(correctCount)/\(resultCount)")
                            Text("· \(accuracy)")
                            Text("· \(duration)")
                        }
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(score)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("得分 \(score)")
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exam-open-\(exam.recordID)")
            if showsReviewNotes, let summary = note.summary {
                notePreview(note, summary: summary, recordID: exam.recordID)
            }
            if date != .distantPast {
                Text(date, format: .dateTime.year().month().day())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .nativeCard(padding: 13)
    }

    private func notePreview(_ note: ExamReviewNote, summary: String, recordID: String) -> some View {
        let expanded = expandedNotes.contains(recordID)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded { expandedNotes.remove(recordID) }
                else { expandedNotes.insert(recordID) }
            } label: {
                HStack(spacing: 7) {
                    Text("备注")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                    Text(summary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            .accessibilityIdentifier("exam-review-preview-\(recordID)")
            if expanded {
                ExamReviewNoteContent(note: note)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 8)
        .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard(padding: 13)
        .accessibilityElement(children: .combine)
    }

    private func filterMenu<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack(spacing: 4) { Text(title); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.secondaryBackground, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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

@MainActor
private struct ExamAttemptDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [StoredRecord]
    @AppStorage("native.exams.detail.verbalExpanded.v1") private var verbalExpanded = true
    @AppStorage("native.exams.detail.reasoningExpanded.v1") private var reasoningExpanded = true
    @State private var showEdit = false
    @State private var showAddError = false
    let recordID: String
    let reviewDrafts: ExamReviewNoteDrafts

    private let foldableSubjects = ["言语理解与表达", "判断推理"]

    private var record: StoredRecord? { records.first { $0.collection == "exams" && $0.recordID == recordID } }
    private var draft: ExamDraft { ExamDraft(record: record) }
    private var object: [String: Any] { record?.indexObject ?? [:] }
    private var type: LibraryReviewSource { record.flatMap { LibraryReviewSource.explicitValue(in: $0.indexObject ?? [:]) } ?? .pending }
    private var linkedErrors: [StoredRecord] {
        records.filter { error in
            guard error.collection == "errors" else { return false }
            let examID = (error.indexObject?["sourceExamId"] as? String)
                ?? (error.reviewSourceMetadata["sourceExamId"] as? String)
            return examID == recordID
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width < 360 ? 12 : (geometry.size.width < 520 ? 16 : 20)
            let cardPadding: CGFloat = geometry.size.width < 360 ? 12 : (geometry.size.width < 520 ? 16 : 20)
            let contentWidth = max(1, min(geometry.size.width - horizontalPadding * 2, 900) - cardPadding * 2)

            ScrollView {
                if let record {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryCard(padding: cardPadding, columns: contentWidth >= 480 ? 6 : 3)
                        ExamReviewNoteCard(
                            record: record, note: ExamReviewNote(in: record.jsonObject ?? [:]),
                            padding: cardPadding, drafts: reviewDrafts
                        )
                        resultCard(availableWidth: contentWidth, padding: cardPadding)
                        linkedErrorsCard(padding: cardPadding)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                } else {
                    NativeStatusCard(title: "考试记录不存在", detail: "本次考试可能已被删除", systemImage: "doc.text", color: .secondary)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.groupedBackground)
        }
        .navigationTitle("套卷记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("编辑") { showEdit = true }.disabled(record == nil) }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack { ExamEditorView(record: record) }
                .secondaryPageTabBarHidden()
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
            .secondaryPageTabBarHidden()
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

    private func summaryCard(padding: CGFloat, columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(type.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(type == .pending ? AppTheme.warning : AppTheme.accent)
                Spacer(minLength: 8)
                Text(formattedExamDate)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(object["name"] as? String ?? "未命名套卷")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .topLeading), count: columns),
                      alignment: .leading, spacing: 8) {
                detailMetric("本次得分", maximumScoreValue == "—" ? scoreValue : "\(scoreValue) / \(maximumScoreValue)",
                             highlighted: true)
                ForEach(summaryMetrics) { metric in detailMetric(metric.title, metric.value) }
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
            ExamSummaryMetric(title: "本次用时", value: metrics.totalTimeSeconds.map(ExamDisplayFormatting.compactDuration) ?? "—")
        ]
    }

    private func resultCard(availableWidth: CGFloat, padding: CGFloat) -> some View {
        let columns = moduleColumnWidths(for: availableWidth)
        let rows = moduleDisplayRows
        let header = moduleTableHeader(columns: columns)

        return VStack(alignment: .leading, spacing: 8) {
            Text("模块成绩")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            if rows.isEmpty {
                Text("暂无模块成绩")
                    .font(.system(size: 14))
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
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func moduleResultRow(_ row: ExamModuleDisplayRow, columns: ModuleColumnWidths) -> some View {
        let counts = "\(displayValue(row.result?.correctCount))/\(displayValue(row.result?.totalQuestions))"
        let rawAccuracy = displayValue(row.result?.reportedAccuracy)
        let accuracy = rawAccuracy == "—" || rawAccuracy.hasSuffix("%") ? rawAccuracy : "\(rawAccuracy)%"
        let time = Int(row.result?.timeSeconds ?? "").map(ExamDisplayFormatting.compactDuration) ?? "—"
        let minimumHeight: CGFloat = row.isFoldableParent ? 44 : (row.isChild ? 34 : 38)

        let content = HStack(alignment: .center, spacing: columns.spacing) {
            HStack(alignment: .center, spacing: 4) {
                if row.isFoldableParent {
                    Image(systemName: isExpanded(row.parentSubject) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                Text(row.subject)
                    .font(row.isChild ? .system(size: 14) : .system(size: 15, weight: .semibold))
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

        return Group {
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
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
        let linkedErrors = self.linkedErrors
        return VStack(alignment: .leading, spacing: 10) {
            Text("关联错题")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    linkedErrorSummary(count: linkedErrors.count)
                    Spacer(minLength: 0)
                    linkedErrorActions
                }
                VStack(alignment: .leading, spacing: 6) {
                    linkedErrorSummary(count: linkedErrors.count)
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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        let metadata = [error.subject, error.moduleDisplayTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                        if !metadata.isEmpty {
                            Text(metadata)
                                .font(.system(size: 12))
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

    private func linkedErrorSummary(count: Int) -> some View {
        let wrongCount = draft.metrics.wrongCount.map(String.init) ?? "—"
        return Text("本次答错 \(wrongCount) 题 · 已关联 \(count) 题")
        .font(.system(size: 12))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关联错题")
    }

    private func detailMetric(_ title: String, _ value: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(highlighted ? AppTheme.accent : Color.primary)
                .monospacedDigit()
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
