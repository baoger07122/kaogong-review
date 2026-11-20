import SwiftData
import SwiftUI

/// Shared ordering screen used by the library manager and both selection flows.
struct KnowledgePointOrderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [StoredRecord]
    var subject: String = ""
    let module: String
    var typeID: String? = nil
    var groupID: String? = nil
    var category: LibraryKnowledgePointGroupCategory = .knowledgePoint

    @State private var names: [String] = []
    @State private var originalNames: [String] = []
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
            .navigationTitle("调整\(category == .mistakeTag ? "错因标签" : "考点")顺序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("完成", action: saveOrder) }
            }
            .overlay {
                if names.isEmpty {
                    let label = category == .mistakeTag ? "错因标签" : "考点"
                    ContentUnavailableView("暂无\(label)", systemImage: "tag", description: Text("当前范围还没有可排序的\(label)。"))
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
        if category == .mistakeTag {
            let allNames = LibraryMistakeTagRepository.tags(
                subject: subject, module: module, typeID: typeID, records: records
            )
            names = LibraryKnowledgePointGroupRepository.names(
                in: groupID, allNames: allNames, subject: subject, module: module,
                typeID: typeID, category: category, records: records
            )
        } else if let typeID {
            let allNames = VerbalReasoningKnowledgePointRepository.tags(module: module, typeID: typeID, records: records, subject: subject)
            names = LibraryKnowledgePointGroupRepository.names(
                in: groupID, allNames: allNames, subject: subject, module: module,
                typeID: typeID, category: category, records: records
            )
        } else {
            let allNames = TagLibraryRepository.tags(kind: .knowledgePoint, module: module, records: records)
            names = LibraryKnowledgePointGroupRepository.names(
                in: groupID, allNames: allNames, subject: subject, module: module,
                category: category, records: records
            )
        }
        originalNames = names
    }

    private func move(from source: IndexSet, to destination: Int) {
        names.move(fromOffsets: source, toOffset: destination)
    }

    private func saveOrder() {
        guard names != originalNames else { dismiss(); return }
        do {
            let latestScopeNames: [String]
            if category == .mistakeTag {
                let allNames = LibraryMistakeTagRepository.tags(
                    subject: subject, module: module, typeID: typeID, records: records
                )
                latestScopeNames = LibraryKnowledgePointGroupRepository.names(
                    in: groupID, allNames: allNames, subject: subject, module: module,
                    typeID: typeID, category: category, records: records
                )
            } else if let typeID {
                let allNames = VerbalReasoningKnowledgePointRepository.tags(
                    module: module, typeID: typeID, records: records, subject: subject
                )
                latestScopeNames = LibraryKnowledgePointGroupRepository.names(
                    in: groupID, allNames: allNames, subject: subject, module: module,
                    typeID: typeID, category: category, records: records
                )
            } else {
                let allNames = TagLibraryRepository.tags(
                    kind: .knowledgePoint, module: module, records: records
                )
                latestScopeNames = LibraryKnowledgePointGroupRepository.names(
                    in: groupID, allNames: allNames, subject: subject, module: module,
                    category: category, records: records
                )
            }
            guard latestScopeNames.count == originalNames.count,
                  Set(latestScopeNames) == Set(originalNames) else {
                throw KnowledgePointOrderSaveError.stale
            }
            if category == .mistakeTag {
                try LibraryMistakeTagRepository.reorder(
                    names, subject: subject, module: module, typeID: typeID, groupID: groupID,
                    records: records, context: modelContext
                )
            } else if let typeID {
                try VerbalReasoningKnowledgePointRepository.reorder(
                    names, module: module, typeID: typeID, records: records, context: modelContext, groupID: groupID,
                    subject: subject
                )
            } else {
                try TagLibraryRepository.reorderKnowledgePoints(
                    names, module: module, groupID: groupID, subject: subject, records: records, context: modelContext
                )
            }
            originalNames = names
            dismiss()
        } catch {
            names = originalNames
            errorMessage = category == .mistakeTag && error is KnowledgePointOrderSaveError
                ? "错因标签清单已变化，本次排序未保存。请关闭后重新打开排序。"
                : error.localizedDescription
        }
    }
}

private enum KnowledgePointOrderSaveError: LocalizedError {
    case stale

    var errorDescription: String? {
        "考点清单已变化，本次排序未保存。请关闭后重新打开排序。"
    }
}
