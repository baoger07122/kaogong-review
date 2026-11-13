import SwiftData
import SwiftUI

/// Shared ordering screen used by the library manager and both selection flows.
struct KnowledgePointOrderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [StoredRecord]
    let module: String
    var typeID: String? = nil

    @State private var names: [String] = []
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                ForEach(names, id: \.self) { name in
                    Text(name).font(AppTheme.bodyFont)
                }
                .onMove(perform: move)
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("调整考点顺序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .overlay {
                if names.isEmpty {
                    ContentUnavailableView("暂无考点", systemImage: "tag", description: Text("当前范围还没有可排序的考点。"))
                }
            }
            .alert("排序保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        if let typeID {
            names = VerbalReasoningKnowledgePointRepository.tags(module: module, typeID: typeID, records: records)
        } else {
            names = TagLibraryRepository.tags(kind: .knowledgePoint, module: module, records: records)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        names.move(fromOffsets: source, toOffset: destination)
        do {
            if let typeID {
                try VerbalReasoningKnowledgePointRepository.reorder(
                    names, module: module, typeID: typeID, records: records, context: modelContext
                )
            } else {
                try TagLibraryRepository.reorderKnowledgePoints(names, module: module, records: records, context: modelContext)
            }
        } catch {
            reload()
            errorMessage = error.localizedDescription
        }
    }
}
