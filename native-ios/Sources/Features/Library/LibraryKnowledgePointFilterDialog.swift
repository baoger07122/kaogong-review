import SwiftUI

struct LibraryKnowledgePointPickerEntry: Identifiable, Hashable {
    let item: LibraryKnowledgePointTagItem
    var groupID: String?
    var id: String { item.id }
}

struct LibraryKnowledgePointFilterDialog: View {
    let scopeTitle: String
    let entries: [LibraryKnowledgePointPickerEntry]
    let groups: [LibraryKnowledgePointGroup]
    let initialSelection: [LibraryKnowledgePointReference]
    let onClose: () -> Void
    let onConfirm: ([LibraryKnowledgePointReference]) -> Void

    @State private var selected: [LibraryKnowledgePointReference] = []
    @State private var selectedGroupID: String?
    @State private var search = ""

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var visibleEntries: [LibraryKnowledgePointPickerEntry] {
        guard !query.isEmpty else { return [] }
        return entries.filter { $0.item.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NativeEditorDialog(
            title: "筛选考点",
            canSave: true,
            actionTitle: "确定",
            onClose: onClose,
            onSave: { onConfirm(LibraryKnowledgePointFilterPolicy.unique(selected)) },
            preferredSize: CGSize(width: 420, height: 468),
            spacing: 8
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scopeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(height: 20, alignment: .leading)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索考点", text: $search)
                        .modifier(NativeDirectionalTextFieldNavigation())
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

                if !groups.isEmpty {
                    LibraryKnowledgePointGroupBar(groups: groups, selectedID: selectedGroupID) {
                        selectedGroupID = $0
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !query.isEmpty {
                            tagCollection(for: visibleEntries)
                        } else if groups.isEmpty {
                            if entries.isEmpty {
                                Text("当前范围暂无考点")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                tagCollection(for: entries)
                            }
                        } else {
                            let selectedGroupEntries = entries.filter { $0.groupID == selectedGroupID }
                            if selectedGroupEntries.isEmpty {
                                Text("暂无考点")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                tagCollection(for: selectedGroupEntries)
                            }
                            let groupIDs = Set(groups.map(\.id))
                            let ungrouped = entries.filter { entry in
                                guard let groupID = entry.groupID else { return true }
                                return !groupIDs.contains(groupID)
                            }
                            if !ungrouped.isEmpty {
                                Text("未分组")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                tagCollection(for: ungrouped)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)

                HStack {
                    Text("已选 \(selected.count) 项")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selected.isEmpty {
                        Button("清空") { selected = [] }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(height: 18)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            selected = LibraryKnowledgePointFilterPolicy.unique(initialSelection)
            selectedGroupID = groups.first?.id
        }
    }

    @ViewBuilder
    private func tagCollection(for values: [LibraryKnowledgePointPickerEntry]) -> some View {
        let items = values.map { entry in
            LibraryKnowledgePointTagItem(
                reference: entry.item.reference,
                title: entry.item.title,
                isSelected: selected.contains(entry.item.reference)
            )
        }
        LibraryKnowledgePointTagCollection(
            items: items,
            allowsReordering: false,
            onToggle: toggle,
            onReorder: { _ in false }
        )
    }

    private func toggle(_ reference: LibraryKnowledgePointReference) {
        if selected.contains(reference) { selected.removeAll { $0 == reference } }
        else { selected.append(reference) }
    }
}
