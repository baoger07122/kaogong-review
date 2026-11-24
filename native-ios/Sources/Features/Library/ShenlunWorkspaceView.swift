import SwiftData
import SwiftUI

private struct ShenlunSingleQuestionListRow: Identifiable {
    var practice: ShenlunWorkspacePractice
    var question: ShenlunWorkspaceQuestion
    var history: ShenlunWorkspaceAttemptHistory?
    var id: String { question.id }
}

struct ShenlunWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: [ShenlunWorkspaceRoute]
    @State private var mode: ShenlunWorkspaceKind = .single
    @State private var singleTypeFilter: ShenlunWorkspaceQuestionType?
    @State private var practices: [ShenlunWorkspacePractice] = []
    @State private var questionsByPractice: [String: [ShenlunWorkspaceQuestion]] = [:]
    @State private var historiesByPractice: [String: [String: ShenlunWorkspaceAttemptHistory]] = [:]
    @State private var legacyRecords: [StoredRecord] = []
    @State private var loadError: String?

    init(navigationPath: Binding<[ShenlunWorkspaceRoute]>) {
        _navigationPath = navigationPath
    }

    private var singleRows: [ShenlunSingleQuestionListRow] {
        var rows: [ShenlunSingleQuestionListRow] = []
        for practice in practices where practice.kind == .single {
            let questions = questionsByPractice[practice.id] ?? []
            let histories = historiesByPractice[practice.id] ?? [:]
            for question in questions {
                if let singleTypeFilter, question.type != singleTypeFilter { continue }
                rows.append(ShenlunSingleQuestionListRow(practice: practice, question: question, history: histories[question.id]))
            }
        }
        return rows.sorted { $0.practice.updatedAt > $1.practice.updatedAt }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                sidebar(windowWidth: width)
                practiceContent(windowWidth: width)
            }
            .overlay(alignment: .bottomTrailing) {
                NativeFloatingCreateButton(
                    windowWidth: width,
                    tabBarVisible: navigationPath.isEmpty,
                    label: mode == .single ? "新建单题" : "新建套卷",
                    identifier: "shenlun-add-practice",
                    action: openEditor
                )
            }
        }
        .background(AppTheme.groupedBackground)
        .stableRootNavigationBar()
        .navigationDestination(for: ShenlunWorkspaceRoute.self, destination: destination(for:))
        .task { reload() }
        .onChange(of: navigationPath) { oldPath, newPath in
            if newPath.count < oldPath.count { reload() }
        }
    }

    private func sidebar(windowWidth: CGFloat) -> some View {
        let compact = windowWidth < 760
        return ScrollView {
            VStack(spacing: 4) {
                if compact { Color.clear.frame(height: 8) }
                ForEach(ShenlunWorkspaceKind.allCases) { item in
                    let selected = item == mode
                    Button {
                        mode = item
                    } label: {
                        LibrarySidebarRowLabel(
                            compact: compact,
                            title: item.title,
                            systemImage: item == .single ? "square.and.pencil" : "doc.on.doc",
                            color: item == .single ? AppTheme.accent : .teal,
                            count: practices.lazy.filter { $0.kind == item }.count,
                            selected: selected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("shenlun-entry-\(item.rawValue)")
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, compact ? 0 : 16)
            .padding(.bottom, 24)
        }
        .frame(width: sidebarWidth(for: windowWidth))
        .background(AppTheme.secondaryBackground.opacity(0.72))
    }

    private func sidebarWidth(for width: CGFloat) -> CGFloat {
        if width >= 760 { return min(184, max(156, width * 0.22)) }
        if width <= 440 { return 72 }
        return width < 635 ? 82 : 96
    }

    private func practiceContent(windowWidth: CGFloat) -> some View {
        let narrow = windowWidth <= 440
        let gutter: CGFloat = narrow ? 12 : (windowWidth < 635 ? 16 : 22)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("申论")
                    .font(AppTheme.pageTitleFont)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                if mode == .single {
                    NativeTagFlow(spacing: 7) {
                        filterChip("全部", type: nil)
                        ForEach(ShenlunWorkspaceQuestionType.allCases) { type in
                            filterChip(type.title, type: type)
                        }
                    }
                    .accessibilityIdentifier("shenlun-single-filters")
                }
                if let loadError {
                    NativeStatusCard(title: "申论工作区暂时无法读取", detail: loadError, systemImage: "exclamationmark.triangle", color: AppTheme.warning)
                } else if mode == .single {
                    singlePracticeList(twoColumns: windowWidth >= 635)
                } else {
                    paperPracticeList(narrow: narrow)
                }
                if !legacyRecords.isEmpty {
                    legacyPracticeList
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 10)
            .padding(.bottom, 74)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filterChip(_ title: String, type: ShenlunWorkspaceQuestionType?) -> some View {
        let selected = singleTypeFilter == type
        return Button {
            singleTypeFilter = type
        } label: {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(selected ? AppTheme.accent : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(selected ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(NativePressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func singlePracticeList(twoColumns: Bool) -> some View {
        let rows = singleRows
        if rows.isEmpty {
            emptyPracticeCard(
                title: singleTypeFilter == nil ? "还没有单题练习" : "这一题型暂无练习",
                symbol: "square.and.pencil"
            )
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 13, alignment: .top), count: twoColumns ? 2 : 1), spacing: 13) {
                ForEach(rows) { row in
                    NavigationLink(value: ShenlunWorkspaceRoute.practice(id: row.practice.id, selectedQuestionID: row.question.id)) {
                        ShenlunSingleQuestionRow(question: row.question, history: row.history, minimumHeight: twoColumns ? 129 : 112)
                    }
                    .buttonStyle(NativePressButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func paperPracticeList(narrow: Bool) -> some View {
        let papers = practices.filter { $0.kind == .paper }
        if papers.isEmpty {
            emptyPracticeCard(title: "还没有套卷", symbol: "doc.on.doc")
        } else {
            LazyVStack(spacing: 13) {
                ForEach(papers) { practice in
                    NavigationLink(value: ShenlunWorkspaceRoute.practice(id: practice.id, selectedQuestionID: practice.questionIDs.first)) {
                        ShenlunPaperSummaryRow(
                            practice: practice,
                            questions: questionsByPractice[practice.id] ?? [],
                            histories: historiesByPractice[practice.id] ?? [:],
                            narrow: narrow
                        )
                    }
                    .buttonStyle(NativePressButtonStyle())
                }
            }
        }
    }

    private var legacyPracticeList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text("旧版申论记录（兼容查阅）")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(legacyRecords, id: \.compoundID) { record in
                NavigationLink(value: ShenlunWorkspaceRoute.legacy(recordID: record.recordID)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                        Text("旧记录 · \(record.createdAt?.formatted(date: .numeric, time: .omitted) ?? "日期未知")")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shenlunEntryCardSurface()
                }
                .buttonStyle(NativePressButtonStyle())
            }
        }
    }

    private func emptyPracticeCard(title: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 52, height: 52)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 175)
        .shenlunEntryCardSurface()
    }

    private func openEditor() {
        navigationPath.append(.editor(
            practiceID: nil,
            questionID: nil,
            kind: mode,
            preferredQuestionType: mode == .single ? (singleTypeFilter ?? .single) : .single
        ))
    }

    @ViewBuilder
    private func destination(for route: ShenlunWorkspaceRoute) -> some View {
        switch route {
        case let .practice(id, selectedQuestionID):
            if let practice = try? ShenlunWorkspaceRepository.practice(id: id, in: modelContext) {
                ShenlunPracticeDetailView(
                    practice: practice,
                    selectedQuestionID: selectedQuestionID,
                    onEditQuestion: { questionID in
                        navigationPath.append(.editor(practiceID: id, questionID: questionID, kind: practice.kind))
                    },
                    onAddQuestion: {
                        navigationPath.append(.editor(practiceID: id, questionID: nil, kind: practice.kind))
                    },
                    onPracticeChanged: reload
                )
            } else {
                NativeStatusCard(title: "练习不存在", detail: "该练习可能已被删除。", systemImage: "exclamationmark.triangle", color: AppTheme.warning)
                    .padding(20)
            }
        case let .editor(practiceID, questionID, kind, preferredQuestionType):
            ShenlunWorkspaceEditorView(
                practiceID: practiceID, questionID: questionID, kind: kind, preferredQuestionType: preferredQuestionType
            ) { savedPracticeID, savedQuestionID in
                reload()
                if practiceID == nil, kind == .single, singleTypeFilter != nil,
                   let savedQuestion = questionsByPractice[savedPracticeID]?.first(where: { $0.id == savedQuestionID }) {
                    singleTypeFilter = savedQuestion.type
                }
                if !navigationPath.isEmpty { navigationPath.removeLast() }
                navigationPath.append(.practice(id: savedPracticeID, selectedQuestionID: savedQuestionID))
            }
        case let .legacy(recordID):
            ShenlunLegacyRecordDestination(recordID: recordID, adapting: false) {
                navigationPath.append(.legacyAdaptation(recordID: recordID))
            } onAdapted: {
                if !navigationPath.isEmpty { navigationPath.removeLast() }
                navigationPath.append(.legacy(recordID: recordID))
            }
        case let .legacyAdaptation(recordID):
            ShenlunLegacyRecordDestination(recordID: recordID, adapting: true) {
                if !navigationPath.isEmpty { navigationPath.removeLast() }
                navigationPath.append(.legacy(recordID: recordID))
            } onAdapted: {
                if !navigationPath.isEmpty { navigationPath.removeLast() }
                navigationPath.append(.legacy(recordID: recordID))
            }
        }
    }

    private func reload() {
        do {
            let loaded = try ShenlunWorkspaceRepository.practices(in: modelContext)
            var questionMap: [String: [ShenlunWorkspaceQuestion]] = [:]
            for practice in loaded {
                questionMap[practice.id] = try ShenlunWorkspaceRepository.questions(practiceID: practice.id, in: modelContext)
            }
            let histories = try ShenlunWorkspaceRepository.attemptHistories(in: modelContext)
            var historyMap: [String: [String: ShenlunWorkspaceAttemptHistory]] = [:]
            for history in histories.values {
                historyMap[history.practiceID, default: [:]][history.questionID] = history
            }
            practices = loaded
            questionsByPractice = questionMap
            historiesByPractice = historyMap
            legacyRecords = try modelContext.fetch(FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.collection == "errors" }))
                .filter(\.isShenlunRecord)
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private extension View {
    func shenlunEntryCardSurface() -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct ShenlunSingleQuestionRow: View {
    let question: ShenlunWorkspaceQuestion
    let history: ShenlunWorkspaceAttemptHistory?
    let minimumHeight: CGFloat

    private var completionCount: Int { history?.completed.count ?? 0 }

    private var scoreDetails: String? {
        guard let answer = history?.latestScored, let score = answer.confirmedScore else { return nil }
        let number = score.formatted(.number.precision(.fractionLength(0...2)))
        let result = answer.fullScore(for: question)
            .map { "\(number) / \($0.formatted(.number.precision(.fractionLength(0...2)))) 分" } ?? "\(number) 分"
        guard let date = answer.completedAt else { return result }
        return "\(result) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var sourceDetails: String {
        [question.source, question.originalNumber.isEmpty ? "" : "原题号 \(question.originalNumber)"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(question.type.title)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 4)
                Text(completionCount > 0 ? "已完成 \(completionCount) 次" : "未作答")
                    .font(.system(size: 12))
                    .foregroundStyle(completionCount > 0 ? AppTheme.success : .secondary)
            }
            .lineLimit(1)
            Text(question.title.isEmpty ? "未命名题目" : question.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(3)
            if !sourceDetails.isEmpty {
                Text(sourceDetails)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let scoreDetails {
                Text(scoreDetails)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color.primary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .shenlunEntryCardSurface()
    }
}

private struct ShenlunPaperSummaryRow: View {
    let practice: ShenlunWorkspacePractice
    let questions: [ShenlunWorkspaceQuestion]
    let histories: [String: ShenlunWorkspaceAttemptHistory]
    let narrow: Bool

    private var completedCount: Int { questions.filter { histories[$0.id]?.completed.isEmpty == false }.count }
    private var scoreCount: Int { questions.filter { histories[$0.id]?.latestScored != nil }.count }

    var body: some View {
        HStack(spacing: narrow ? 10 : 13) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: narrow ? 18 : 22, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: narrow ? 32 : 41, height: narrow ? 32 : 41)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: narrow ? 9 : 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(practice.name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                Text("\(questions.count) 题 · \(completedCount) 已作答 · \(scoreCount) 已确认评分")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.primary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, narrow ? 11 : 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .shenlunEntryCardSurface()
    }
}

private struct ShenlunLegacyRecordDestination: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "errors" }) private var records: [StoredRecord]

    let recordID: String
    let adapting: Bool
    let onEdit: () -> Void
    let onAdapted: () -> Void

    private var record: StoredRecord? { records.first { $0.recordID == recordID && $0.isShenlunRecord } }

    var body: some View {
        Group {
            if let record {
                if adapting {
                    ShenlunAdaptationView(record: record, onAdapted: onAdapted)
                } else {
                    ShenlunRecordDetailView(
                        record: record,
                        onEdit: onEdit,
                        onDelete: {
                            modelContext.delete(record)
                            try? modelContext.save()
                            dismiss()
                        }
                    )
                }
            } else {
                NativeStatusCard(title: "旧记录不存在", detail: "这条兼容记录可能已被删除。", systemImage: "exclamationmark.triangle", color: AppTheme.warning)
                    .padding(20)
            }
        }
    }
}
