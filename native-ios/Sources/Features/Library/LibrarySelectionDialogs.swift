import SwiftData
import SwiftUI

/// Reuses the app's centered editor dialog, rather than embedding choices in the form.
struct LibraryTagSelectionDialog: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let kind: ManagedTagKind
    let module: String
    @Binding var selection: String
    let onClose: () -> Void
    @State private var selected: [String] = []
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?

    private var maximum: Int { kind == .knowledgePoint ? 3 : 1 }
    private var names: [String] {
        var values = TagLibraryRepository.tags(kind: kind, module: module, records: records)
        for value in selected where !values.contains(value) { values.append(value) }
        return values
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NativeEditorDialog(title: "选择\(kind.rawValue)", canSave: selected.count <= maximum,
            actionTitle: "确定", onClose: onClose, onSave: {
                selection = selected.joined(separator: "、")
                onClose()
            }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("搜索或输入新\(kind.rawValue)", text: $search)
                        .textFieldStyle(NativeTextFieldStyle()).onSubmit(addTag)
                    Button("新增", action: addTag).font(.system(size: 12))
                        .disabled(query.isEmpty || names.contains(query))
                }
                HStack {
                    Text("已选 \(selected.count)/\(maximum) · 长按标签可重命名或删除")
                    Spacer()
                    Button("清空选择") { selected = [] }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                ScrollView {
                    NativeTagFlow {
                        ForEach(names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { name in
                            Button { toggle(name) } label: {
                                HStack(spacing: 4) {
                                    Text(name)
                                    if selected.contains(name) { Image(systemName: "checkmark") }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(selected.contains(name) ? AppTheme.accent : Color.primary)
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .background(selected.contains(name) ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("重命名") { renaming = name; newName = name }
                                Button("删除标签", role: .destructive) { deleting = name }
                            }
                        }
                    }
                }.frame(maxHeight: 260)
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            }
        }
        .onAppear { selected = split(selection) }
        .alert("重命名标签", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("标签名称", text: $newName)
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("同模块内已有记录的该标签会同步更新。") }
        .alert("删除标签？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从标签库及同模块已有记录中移除此标签，不删除题目。") }
    }

    private func split(_ value: String) -> [String] {
        guard !value.isEmpty else { return [] }
        return kind == .knowledgePoint ? value.split(whereSeparator: { "、,，".contains($0) }).map(String.init) : [value]
    }
    private func toggle(_ name: String) {
        message = nil
        if selected.contains(name) { selected.removeAll { $0 == name } }
        else if maximum == 1 { selected = [name] }
        else if selected.count < maximum { selected.append(name) }
        else { message = "最多选择 \(maximum) 个考点" }
    }
    private func addTag() {
        let value = query
        guard !value.isEmpty, !names.contains(value) else { return }
        do {
            try TagLibraryRepository.add(value, kind: kind, module: module, records: records, context: modelContext)
            toggle(value)
            search = ""
        } catch { message = "标签保存失败，请重试" }
    }
    private func renameTag() {
        guard let old = renaming else { return }
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !names.contains(value) else {
            message = "名称不能为空或与其他标签重复"; return
        }
        do {
            try TagLibraryRepository.rename(old, to: value, kind: kind, module: module, records: records, context: modelContext)
            selected = selected.map { $0 == old ? value : $0 }
            selection = split(selection).map { $0 == old ? value : $0 }.joined(separator: "、")
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }
    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            try TagLibraryRepository.delete(name, kind: kind, module: module, records: records, context: modelContext)
            selected.removeAll { $0 == name }
            selection = split(selection).filter { $0 != name }.joined(separator: "、")
            deleting = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct LibraryRelationSelectionDialog: View {
    let collection: String
    let candidates: [StoredRecord]
    @Binding var selection: [String]
    let onClose: () -> Void
    @State private var selected: [String] = []
    @State private var search = ""

    var body: some View {
        NativeEditorDialog(title: collection == "exams" ? "来源套卷" : (collection == "notes" ? "关联笔记" : "关联词语"),
            canSave: true, actionTitle: "确定", onClose: onClose, onSave: { selection = selected; onClose() }) {
            VStack(spacing: 8) {
                TextField("搜索", text: $search).textFieldStyle(NativeTextFieldStyle())
                HStack {
                    Text("已选 \(selected.count) 项")
                    Spacer()
                    Button("清空关联") { selected = [] }
                }.font(.system(size: 11))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }, id: \.compoundID) { record in
                            Button {
                                if selected.contains(record.recordID) { selected.removeAll { $0 == record.recordID } }
                                else if collection == "exams" { selected = [record.recordID] }
                                else { selected.append(record.recordID) }
                            } label: {
                                HStack {
                                    Text(record.title).font(.system(size: 13)).lineLimit(2)
                                    Spacer()
                                    Image(systemName: selected.contains(record.recordID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(AppTheme.accent)
                                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if candidates.isEmpty { Text("暂无可关联内容").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                }.frame(maxHeight: 280)
            }
        }.onAppear { selected = selection }
    }
}
