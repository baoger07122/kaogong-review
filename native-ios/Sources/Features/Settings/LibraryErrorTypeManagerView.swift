import SwiftData
import SwiftUI

private struct LibraryErrorTypeModuleSelection: Identifiable {
    let module: String?
    var id: String { module ?? "legacy" }
}

struct LibraryErrorTypeModulesView: View {
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "keyvalue" }) private var records: [StoredRecord]
    @State private var selectedModule: LibraryErrorTypeModuleSelection?

    let subject: LibraryErrorTypeSubject

    var body: some View {
        List {
            ForEach(subject.modules, id: \.self) { module in
                moduleLink(
                    SubjectDefinition.moduleTitle(module, subject: subject.rawValue),
                    module: module, accessibilityID: "error-type-module-\(subject.rawValue)-\(module)"
                )
            }
            if LibraryErrorTypeRepository.types(for: subject, records: records).contains(where: { $0.module == nil }) {
                moduleLink("原有通用类型", module: nil, accessibilityID: "error-type-module-legacy-\(subject.rawValue)")
            }
        }
        .navigationTitle(subject.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedModule) { selection in
            NavigationStack {
                LibraryErrorTypeManagerView(subject: subject, module: selection.module)
                    .secondaryPageTabBarHidden()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("返回") { selectedModule = nil }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private func moduleLink(
        _ title: String,
        module: String? = nil,
        accessibilityID: String
    ) -> some View {
        Button {
            NativePerformanceLog.event("settings.error-types.module.tap module=\(module ?? "legacy")")
            selectedModule = LibraryErrorTypeModuleSelection(module: module)
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(title)
        .accessibilityHint("打开\(title)题型管理")
    }
}

struct LibraryErrorTypeManagerView: View {
    let subject: LibraryErrorTypeSubject
    var module: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "keyvalue" }) private var records: [StoredRecord]
    @State private var isEditing = false
    @State private var sortMode: EditMode = .inactive
    @State private var editingID: String?
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool
    @State private var deletingType: LibraryErrorType?
    @State private var errorMessage: String?

    private var types: [LibraryErrorType] {
        let entries = LibraryErrorTypeRepository.types(for: subject, records: records)
        return subject == .dataAnalysis ? entries : entries.filter { $0.module == module }
    }

    private var typeLabel: String { subject == .dataAnalysis ? "错误类型" : "题型" }

    private var navigationTitle: String {
        if subject == .dataAnalysis { return subject.rawValue }
        return module.map { SubjectDefinition.moduleTitle($0, subject: subject.rawValue) } ?? "原有通用类型"
    }

    private var canAddType: Bool {
        subject != .verbalReasoning || module != nil
    }

    var body: some View {
        let entries = types
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(typeLabel).font(AppTheme.sectionTitleFont)
                Spacer(minLength: 0)
                Button(sortMode.isEditing ? "完成排序" : "调整顺序") {
                    sortMode = sortMode.isEditing ? .inactive : .active
                }
                .font(AppTheme.inputFont.weight(.semibold))
                .lineLimit(1)
                .disabled(entries.count < 2 && !sortMode.isEditing)
                if canAddType {
                    Button { beginEdit(nil) } label: { Label("新增\(typeLabel)", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                        .lineLimit(1)
                        .disabled(sortMode.isEditing)
                }
            }
            if entries.isEmpty {
                NativeStatusCard(
                    title: "暂无\(typeLabel)", detail: canAddType ? "点击新增建立第一项" : "",
                    systemImage: "tag", color: AppTheme.accent
                )
            } else {
                typeRows(entries)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isEditing {
                NativeEditorDialog(
                    title: editingID == nil ? "新增\(typeLabel)" : "修改\(typeLabel)",
                    canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: finishEditing,
                    onSave: saveEditor
                ) {
                    TextField("\(typeLabel)名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
                        .focused($isNameFocused)
                }
            } else if let deletingType {
                NativeDeleteDialog(
                    title: "删除\(typeLabel)",
                    message: "删除“\(deletingType.name)”后，相关错题会归入未分类。",
                    onDelete: {
                        if save(types.filter { $0.id != deletingType.id }) { self.deletingType = nil }
                    },
                    onCancel: { self.deletingType = nil }
                )
            }
        }
        .alert("未能保存\(typeLabel)", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            NativePerformanceLog.event("settings.error-types.manager.present module=\(module ?? "legacy")")
        }
        .onDisappear {
            isNameFocused = false
            isEditing = false
            sortMode = .inactive
            editingID = nil
            draftName = ""
            deletingType = nil
            NativePerformanceLog.event("settings.error-types.manager.close module=\(module ?? "legacy")")
        }
    }

    private func typeRows(_ entries: [LibraryErrorType]) -> some View {
        List {
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Text(entry.name).font(AppTheme.bodyFont)
                    Spacer(minLength: 0)
                    if !sortMode.isEditing {
                        Button { beginEdit(entry) } label: {
                            Image(systemName: "pencil").foregroundStyle(AppTheme.accent)
                        }
                        .accessibilityLabel("编辑\(entry.name)")
                        Button { deletingType = entry } label: {
                            Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                        }
                        .accessibilityLabel("删除\(entry.name)")
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .frame(minHeight: 44)
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                .listRowSeparator(entry.id == entries.last?.id ? .hidden : .visible, edges: .bottom)
                .listRowBackground(AppTheme.secondaryBackground)
            }
            .onMove(perform: sortMode.isEditing ? { source, destination in
                move(source, to: destination, displayed: entries)
            } : nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.editMode, $sortMode)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func beginEdit(_ type: LibraryErrorType?) {
        editingID = type?.id
        draftName = type?.name ?? ""
        isEditing = true
        isNameFocused = true
    }

    private func finishEditing() {
        isNameFocused = false
        isEditing = false
        editingID = nil
        draftName = ""
    }

    private func saveEditor() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var entries = types
        guard name != "未分类", !entries.contains(where: {
            $0.id != editingID && $0.name.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }) else {
            errorMessage = "请使用与现有类型不同的名称。“未分类”用于尚未设置\(typeLabel)的题目。"
            return
        }
        if let editingID {
            guard let index = entries.firstIndex(where: { $0.id == editingID }) else {
                errorMessage = "这项\(typeLabel)已不存在。"
                return
            }
            entries[index].name = name
        } else {
            entries.append(LibraryErrorType(id: UUID().uuidString, name: name, module: module))
        }
        if save(entries) { finishEditing() }
    }

    private func move(_ source: IndexSet, to destination: Int, displayed: [LibraryErrorType]) {
        let current = types
        guard displayed.map(\.id) == current.map(\.id) else {
            errorMessage = "题型列表已更新，请重新拖动排序。"
            return
        }
        var reordered = current
        reordered.move(fromOffsets: source, toOffset: destination)
        if reordered != current { _ = save(reordered) }
    }

    private func save(_ entries: [LibraryErrorType]) -> Bool {
        do {
            try LibraryErrorTypeRepository.save(entries, for: subject, module: module, records: records, context: modelContext)
            NativePerformanceLog.event("settings.error-types.saved module=\(module ?? "legacy")")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
