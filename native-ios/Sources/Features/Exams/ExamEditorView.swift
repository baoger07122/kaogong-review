import SwiftData
import SwiftUI

struct ExamEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let recordID: String?
    @State private var draft: ExamDraft
    @State private var selectedSubject = SubjectDefinition.all[0].name
    @State private var showDelete = false

    init(record: StoredRecord? = nil) { recordID = record?.recordID; _draft = State(initialValue: ExamDraft(record: record)) }
    private var errors: [StoredRecord] { records.filter { $0.collection == "errors" }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 11) {
                    TextField("套卷名称", text: $draft.name).textFieldStyle(NativeTextFieldStyle())
                    DatePicker("考试日期", selection: $draft.examDate, displayedComponents: .date).font(AppTheme.inputFont)
                    HStack {
                        TextField("总正确率 %", text: $draft.totalAccuracy).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
                        TextField("总用时（分钟）", text: $draft.totalTime).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
                        TextField("目标分数", text: $draft.targetScore).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
                    }
                }.nativeCard()
                subjectScoreSection
                linkedErrorsSection
                VStack(alignment: .leading, spacing: 8) {
                    NativeFieldLabel(title: "复盘笔记")
                    NativeRichTextEditor(html: $draft.reviewNote, minHeight: 150)
                }.nativeCard()
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(recordID == nil ? "记录套卷" : "编辑套卷")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            if recordID != nil { ToolbarItem(placement: .bottomBar) { Button("删除", role: .destructive) { showDelete = true } } }
        }
        .confirmationDialog("删除套卷", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove); Button("取消", role: .cancel) {}
        } message: { Text("关联错题会保留，只解除套卷关系。") }
    }

    private var subjectScoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NativeFieldLabel(title: "科目成绩")
                Spacer()
                Menu {
                    ForEach(SubjectDefinition.all) { value in Button(value.name) { selectedSubject = value.name; addSubject(value.name) } }
                } label: { Label("添加科目", systemImage: "plus") }.font(AppTheme.inputFont.weight(.semibold))
            }
            ForEach($draft.subjectScores) { $score in
                HStack {
                    Text(score.subject).font(AppTheme.inputFont.weight(.semibold)).frame(width: 74, alignment: .leading)
                    TextField("正确数", text: $score.score).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
                    Text("/").foregroundStyle(.secondary)
                    TextField("总题数", text: $score.totalScore).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
                    Button { draft.subjectScores.removeAll { $0.subject == score.subject } } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                }
            }
        }.nativeCard()
    }

    private var linkedErrorsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { NativeFieldLabel(title: "关联错题"); Spacer(); Text("已选 \(draft.linkedErrorIDs.count)").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
            if errors.isEmpty { Text("暂无错题可关联").font(AppTheme.bodyFont).foregroundStyle(.secondary) }
            else {
                ForEach(errors.prefix(40), id: \.recordID) { error in
                    Button { toggleError(error.recordID) } label: {
                        HStack {
                            Image(systemName: draft.linkedErrorIDs.contains(error.recordID) ? "checkmark.circle.fill" : "circle").foregroundStyle(draft.linkedErrorIDs.contains(error.recordID) ? AppTheme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 2) { Text(error.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(1); Text([error.subject, error.module].compactMap { $0 }.joined(separator: " · ")).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                }
                if errors.count > 40 { Text("当前先显示最近40条错题，可后续通过搜索精确关联。" ).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
            }
        }.nativeCard()
    }

    private func addSubject(_ name: String) { if !draft.subjectScores.contains(where: { $0.subject == name }) { draft.subjectScores.append(.init(subject: name, score: "", totalScore: "")) } }
    private func toggleError(_ id: String) { if draft.linkedErrorIDs.contains(id) { draft.linkedErrorIDs.remove(id) } else { draft.linkedErrorIDs.insert(id) } }
    private func save() { try? ExamRepository.save(draft, records: records, context: modelContext); dismiss() }
    private func remove() { guard let recordID else { return }; try? ExamRepository.remove(id: recordID, records: records, context: modelContext); dismiss() }
}
