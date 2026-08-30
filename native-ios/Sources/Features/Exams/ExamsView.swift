import SwiftData
import SwiftUI

private struct ExamEditorTarget: Identifiable { let recordID: String?; var id: String { recordID ?? "new" } }

struct ExamsView: View {
    @Query private var records: [StoredRecord]
    @State private var searchText = ""
    @State private var editorTarget: ExamEditorTarget?

    private var allExams: [StoredRecord] { records.filter { $0.collection == "exams" } }
    private var exams: [StoredRecord] {
        allExams.filter {
            let object = $0.jsonObject ?? [:]
            let name = object["name"] as? String ?? ""
            let note = object["reviewNote"] as? String ?? ""
            return searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText) || note.localizedCaseInsensitiveContains(searchText)
        }.sorted { examDate($0) > examDate($1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    metric("套卷", "\(allExams.count)")
                    metric("平均正确率", "\(averageAccuracy)%")
                    metric("累计用时", "\(totalMinutes) 分")
                }
                HStack {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索套卷或复盘内容", text: $searchText).font(AppTheme.inputFont) }
                        .padding(.horizontal, 11).frame(height: 38).background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10))
                    Button { editorTarget = ExamEditorTarget(recordID: nil) } label: { Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 38, height: 38).background(AppTheme.accent.opacity(0.10), in: Circle()) }.buttonStyle(.plain)
                }
                if exams.isEmpty {
                    NativeStatusCard(title: "暂无套卷", detail: "点击右侧加号记录第一套试卷", systemImage: "doc.text", color: AppTheme.accent)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                        ForEach(exams, id: \.recordID) { exam in
                            Button { editorTarget = ExamEditorTarget(recordID: exam.recordID) } label: { examCard(exam) }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("套卷")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorTarget) { target in
            NavigationStack { ExamEditorView(record: records.first { $0.collection == "exams" && $0.recordID == target.recordID }) }
        }
    }

    private func examCard(_ exam: StoredRecord) -> some View {
        let object = exam.jsonObject ?? [:]
        let accuracy = (object["totalAccuracy"] as? NSNumber)?.intValue ?? 0
        let time = (object["totalTime"] as? NSNumber)?.intValue ?? 0
        let scores = object["subjectScores"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(object["name"] as? String ?? "未命名套卷").font(AppTheme.cardTitleFont).foregroundStyle(.primary).lineLimit(1)
                Spacer(); Text(examDate(exam), format: .dateTime.year().month().day()).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Label("\(accuracy)%", systemImage: "scope"); Label("\(time) 分", systemImage: "clock"); Label("\(scores.count) 科", systemImage: "books.vertical")
            }.font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            if let note = object["reviewNote"] as? String, !note.isEmpty { Text(note).font(AppTheme.bodyFont).foregroundStyle(.secondary).lineLimit(3) }
        }.nativeCard()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit(); Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).nativeCard()
    }
    private var averageAccuracy: Int {
        guard !allExams.isEmpty else { return 0 }
        return allExams.reduce(0) { $0 + (($1.jsonObject?["totalAccuracy"] as? NSNumber)?.intValue ?? 0) } / allExams.count
    }
    private var totalMinutes: Int { allExams.reduce(0) { $0 + (($1.jsonObject?["totalTime"] as? NSNumber)?.intValue ?? 0) } }
    private func examDate(_ record: StoredRecord) -> Date {
        guard let value = record.jsonObject?["examDate"] as? String else { return record.createdAt ?? .distantPast }
        return ExamDraft.dayFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? record.createdAt ?? .distantPast
    }
}
