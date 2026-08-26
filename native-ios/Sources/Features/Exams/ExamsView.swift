import SwiftData
import SwiftUI

struct ExamsView: View {
    @Query private var records: [StoredRecord]
    @State private var searchText = ""

    private var exams: [StoredRecord] {
        records
            .filter { $0.collection == "exams" && (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        Group {
            if exams.isEmpty {
                ContentUnavailableView("暂无套卷", systemImage: "doc.text", description: Text("可在设置中导入 Web 备份进行核对。"))
            } else {
                List(exams, id: \.compoundID) { exam in
                    NavigationLink { RecordJSONDetailView(record: exam) } label: { RecordRow(record: exam) }
                }
            }
        }
        .navigationTitle("套卷")
        .searchable(text: $searchText, prompt: "搜索套卷")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { } label: { Image(systemName: "plus") }
                    .disabled(true)
                    .accessibilityLabel("新增套卷将在后续阶段开放")
            }
        }
    }
}

