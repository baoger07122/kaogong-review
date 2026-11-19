import SwiftData
import SwiftUI

private enum ShenlunWorkspaceListMode: String, CaseIterable, Identifiable {
    case single
    case paper
    var id: String { rawValue }
    var title: String { self == .single ? "单题练习" : "套卷练习" }
    var kind: ShenlunWorkspaceKind { self == .single ? .single : .paper }
}

private struct ShenlunSingleQuestionListRow: Identifiable {
    var practice: ShenlunWorkspacePractice
    var question: ShenlunWorkspaceQuestion
    var answer: ShenlunWorkspaceAnswer?
    var id: String { question.id }
}

struct ShenlunWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: [ShenlunWorkspaceRoute]
    @State private var mode: ShenlunWorkspaceListMode = .single
    @State private var singleTypeFilter = "全部"
    @State private var practices: [ShenlunWorkspacePractice] = []
    @State private var questionsByPractice: [String: [ShenlunWorkspaceQuestion]] = [:]
    @State private var answersByPractice: [String: [String: ShenlunWorkspaceAnswer]] = [:]
    @State private var legacyRecords: [StoredRecord] = []
    @State private var loadError: String?

    init(navigationPath: Binding<[ShenlunWorkspaceRoute]>) {
        _navigationPath = navigationPath
    }

    private var singleRows: [ShenlunSingleQuestionListRow] {
        practices.filter { $0.kind == .single }.flatMap { practice in
            (questionsByPractice[practice.id] ?? []).map { question in
                ShenlunSingleQuestionListRow(practice: practice, question: question, answer: answersByPractice[practice.id]?[question.id])
            }
        }
        .filter { row in
            singleTypeFilter == "全部" || row.question.type.title == singleTypeFilter
        }
        .sorted { $0.practice.updatedAt > $1.practice.updatedAt }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("练习方式", selection: $mode) {
                ForEach(ShenlunWorkspaceListMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if mode == .single {
                Picker("单题筛选", selection: $singleTypeFilter) {
                    ForEach(["全部", "单一题", "公文题", "作文题"], id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
            }

            if let loadError {
                NativeStatusCard(title: "申论工作区暂时无法读取", detail: loadError, systemImage: "exclamationmark.triangle", color: AppTheme.warning)
                    .padding(.horizontal, 16)
            }

            List {
                if mode == .single {
                    if singleRows.isEmpty {
                        ContentUnavailableView("还没有单题练习", systemImage: "doc.text", description: Text("点右上角 + 录入第一道申论题。"))
                            .listRowSeparator(.hidden)
                    }
                    ForEach(singleRows) { row in
                        NavigationLink(value: ShenlunWorkspaceRoute.practice(id: row.practice.id, selectedQuestionID: row.question.id)) {
                            ShenlunSingleQuestionRow(question: row.question, answer: row.answer)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    let papers = practices.filter { $0.kind == .paper }
                    if papers.isEmpty {
                        ContentUnavailableView("还没有套卷", systemImage: "doc.on.doc", description: Text("新建套卷后，可以持续添加题目并独立作答。"))
                            .listRowSeparator(.hidden)
                    }
                    ForEach(papers) { practice in
                        NavigationLink(value: ShenlunWorkspaceRoute.practice(id: practice.id, selectedQuestionID: practice.questionIDs.first)) {
                            ShenlunPaperSummaryRow(
                                practice: practice,
                                questions: questionsByPractice[practice.id] ?? [],
                                answers: answersByPractice[practice.id] ?? [:]
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                if !legacyRecords.isEmpty {
                    Section("旧版申论记录（兼容查阅）") {
                        ForEach(legacyRecords, id: \.compoundID) { record in
                            NavigationLink(value: ShenlunWorkspaceRoute.legacy(recordID: record.recordID)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                                    Text("旧记录 · \(record.createdAt?.formatted(date: .numeric, time: .omitted) ?? "日期未知")")
                                        .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.groupedBackground)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("申论")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { openEditor(kind: .single) } label: { Label("新建单题", systemImage: "doc.badge.plus") }
                    Button { openEditor(kind: .paper) } label: { Label("新建套卷", systemImage: "folder.badge.plus") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityLabel("新建申论练习")
                }
            }
        }
        .navigationDestination(for: ShenlunWorkspaceRoute.self, destination: destination(for:))
        .task { reload() }
        .onChange(of: navigationPath) { oldPath, newPath in
            if newPath.count < oldPath.count { reload() }
        }
    }

    private func openEditor(kind: ShenlunWorkspaceKind) {
        navigationPath.append(.editor(practiceID: nil, questionID: nil, kind: kind))
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
        case let .editor(practiceID, questionID, kind):
            ShenlunWorkspaceEditorView(practiceID: practiceID, questionID: questionID, kind: kind) { practiceID, savedQuestionID in
                reload()
                if !navigationPath.isEmpty { navigationPath.removeLast() }
                navigationPath.append(.practice(id: practiceID, selectedQuestionID: savedQuestionID))
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
            var answerMap: [String: [String: ShenlunWorkspaceAnswer]] = [:]
            for practice in loaded {
                questionMap[practice.id] = try ShenlunWorkspaceRepository.questions(practiceID: practice.id, in: modelContext)
                answerMap[practice.id] = try ShenlunWorkspaceRepository.answers(practiceID: practice.id, in: modelContext)
            }
            practices = loaded
            questionsByPractice = questionMap
            answersByPractice = answerMap
            legacyRecords = try modelContext.fetch(FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.collection == "errors" }))
                .filter(\.isShenlunRecord)
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct ShenlunSingleQuestionRow: View {
    let question: ShenlunWorkspaceQuestion
    let answer: ShenlunWorkspaceAnswer?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(question.title.isEmpty ? "未命名题目" : question.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if !question.source.isEmpty { Text(question.source) }
                if !question.originalNumber.isEmpty { Text("原题号 \(question.originalNumber)") }
                Text(question.type.title)
                Spacer(minLength: 4)
                Text(answer?.isCompleted == true ? "已作答" : "未作答")
                    .foregroundStyle(answer?.isCompleted == true ? AppTheme.success : .secondary)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.7) }
        .padding(.vertical, 3)
    }
}

private struct ShenlunPaperSummaryRow: View {
    let practice: ShenlunWorkspacePractice
    let questions: [ShenlunWorkspaceQuestion]
    let answers: [String: ShenlunWorkspaceAnswer]

    private var completedCount: Int { questions.filter { answers[$0.id]?.isCompleted == true }.count }
    private var scoreCount: Int { questions.filter { answers[$0.id]?.reviewState == .confirmed && answers[$0.id]?.confirmedScore != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(practice.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
            HStack(spacing: 12) {
                Text("\(questions.count) 题")
                Text("\(completedCount) 道独立作答")
                Text("\(scoreCount) 道已确认评分")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.7) }
        .padding(.vertical, 3)
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
