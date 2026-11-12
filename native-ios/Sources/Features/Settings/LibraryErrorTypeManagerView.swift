import SwiftData
import SwiftUI

private struct LibraryErrorTypeModuleSelection: Identifiable {
    let module: String?
    var id: String { module ?? "legacy" }
}

struct LibraryErrorTypeModulesView: View {
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "keyvalue" }) private var records: [StoredRecord]
    @State private var selectedModule: LibraryErrorTypeModuleSelection?

    private let subject = LibraryErrorTypeSubject.verbalReasoning

    var body: some View {
        List {
            ForEach(subject.modules, id: \.self) { module in
                moduleLink(module, module: module, accessibilityID: "verbal-error-module-\(module)")
            }
            if LibraryErrorTypeRepository.types(for: subject, records: records).contains(where: { $0.module == nil }) {
                moduleLink("原有通用类型", module: nil, accessibilityID: "verbal-error-module-legacy")
            }
        }
        .navigationTitle(subject.managementTitle)
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
        .accessibilityHint("打开\(title)错误类型管理")
    }
}

struct LibraryErrorTypeManagerView: View {
    let subject: LibraryErrorTypeSubject
    var module: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "keyvalue" }) private var records: [StoredRecord]
    @State private var isEditing = false
    @State private var editingID: String?
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool
    @State private var deletingType: LibraryErrorType?
    @State private var errorMessage: String?

    private var types: [LibraryErrorType] {
        LibraryErrorTypeRepository.types(for: subject, records: records).filter { $0.module == module }
    }

    private var canAddType: Bool {
        subject != .verbalReasoning || module != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("错误类型").font(AppTheme.sectionTitleFont)
                    Spacer()
                    if canAddType {
                        Button { beginEdit(nil) } label: { Label("新增", systemImage: "plus") }
                            .font(AppTheme.inputFont.weight(.semibold))
                    }
                }
                if types.isEmpty {
                    NativeStatusCard(
                        title: "暂无错误类型", detail: canAddType ? "点击新增建立第一项" : "",
                        systemImage: "tag", color: AppTheme.accent
                    )
                } else {
                    typeRows
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle(module ?? (subject == .verbalReasoning ? "原有通用类型" : subject.managementTitle))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isEditing {
                NativeEditorDialog(
                    title: editingID == nil ? "新增错误类型" : "修改错误类型",
                    canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: finishEditing,
                    onSave: saveEditor
                ) {
                    TextField("错误类型名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
                        .focused($isNameFocused)
                }
            } else if let deletingType {
                NativeDeleteDialog(
                    title: "删除错误类型",
                    message: "删除“\(deletingType.name)”后，相关错题会归入未分类。",
                    onDelete: {
                        if save(types.filter { $0.id != deletingType.id }) { self.deletingType = nil }
                    },
                    onCancel: { self.deletingType = nil }
                )
            }
        }
        .alert("未能保存错误类型", isPresented: Binding(
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
            editingID = nil
            draftName = ""
            deletingType = nil
            NativePerformanceLog.event("settings.error-types.manager.close module=\(module ?? "legacy")")
        }
    }

    private var typeRows: some View {
        let entries = types
        return VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 10) {
                    Text(entry.name).font(AppTheme.bodyFont)
                    Spacer()
                    Button { move(from: index, to: index - 1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                        .accessibilityLabel("上移\(entry.name)")
                    Button { move(from: index, to: index + 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == entries.count - 1)
                        .accessibilityLabel("下移\(entry.name)")
                    Button { beginEdit(entry) } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("编辑\(entry.name)")
                    Button { deletingType = entry } label: {
                        Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                    }
                    .accessibilityLabel("删除\(entry.name)")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(minHeight: 44)
                if index < entries.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
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
            errorMessage = "请使用与现有类型不同的名称。“未分类”用于尚未设置错误类型的题目。"
            return
        }
        if let editingID {
            guard let index = entries.firstIndex(where: { $0.id == editingID }) else {
                errorMessage = "这项错误类型已不存在。"
                return
            }
            entries[index].name = name
        } else {
            entries.append(LibraryErrorType(id: UUID().uuidString, name: name, module: module))
        }
        if save(entries) { finishEditing() }
    }

    private func move(from source: Int, to destination: Int) {
        var entries = types
        guard entries.indices.contains(source), entries.indices.contains(destination) else { return }
        entries.swapAt(source, destination)
        _ = save(entries)
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
