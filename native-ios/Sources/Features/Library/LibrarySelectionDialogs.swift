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
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil
    var titleOverride: String? = nil
    var maximumOverride: Int? = nil
    @State private var selected: [String] = []
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var showsKnowledgePointOrder = false

    private var maximum: Int { maximumOverride ?? (kind == .knowledgePoint ? 3 : 1) }
    private var names: [String] {
        var values = TagLibraryRepository.tags(kind: kind, module: module, records: records)
        for value in selected where !values.contains(value) { values.append(value) }
        return values
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NativeEditorDialog(title: "选择\(titleOverride ?? kind.rawValue)", canSave: selected.count <= maximum,
            actionTitle: "确定", onClose: onClose, onSave: {
                selection = orderedSelected.joined(separator: "、")
                onClose()
            }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("搜索或输入新\(titleOverride ?? kind.rawValue)", text: $search)
                        .textFieldStyle(NativeTextFieldStyle()).onSubmit(addTag)
                    Button("新增", action: addTag).font(.system(size: 12))
                        .disabled(query.isEmpty || names.contains(query))
                }
                HStack {
                    Text("已选 \(selected.count)/\(maximum) · 长按标签可重命名或删除")
                    Spacer()
                    if kind == .knowledgePoint {
                        Button("管理顺序") { showsKnowledgePointOrder = true }
                    }
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
        .sheet(isPresented: $showsKnowledgePointOrder) { KnowledgePointOrderView(module: module) }
        .alert("重命名标签", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("标签名称", text: $newName)
                .modifier(NativeDirectionalTextFieldNavigation())
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
        return maximum > 1 ? value.split(whereSeparator: { "、,，".contains($0) }).map(String.init) : [value]
    }
    private var orderedSelected: [String] {
        guard kind == .knowledgePoint else { return selected }
        return names.filter { selected.contains($0) }
    }
    private func toggle(_ name: String) {
        message = nil
        if selected.contains(name) { selected.removeAll { $0 == name } }
        else if maximum == 1 { selected = [name] }
        else if selected.count < maximum { selected.append(name) }
        else { message = "最多选择 \(maximum) 个\(titleOverride ?? kind.rawValue)" }
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
            let result = try TagLibraryRepository.rename(old, to: value, kind: kind, module: module, records: records, context: modelContext)
            onTagMutation?(result)
            selected = selected.map { $0 == old ? value : $0 }
            selection = split(selection).map { $0 == old ? value : $0 }.joined(separator: "、")
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }
    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result = try TagLibraryRepository.delete(name, kind: kind, module: module, records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0 == name }
            selection = split(selection).filter { $0 != name }.joined(separator: "、")
            deleting = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct QuantityQuestionTypeSelectionDialog: View {
    @Query private var records: [StoredRecord]
    @Binding var selection: String
    let onClose: () -> Void

    private var questionTypes: [String] { QuantityQuestionTypeRepository.types(records: records) }

    var body: some View {
        NativeEditorDialog(
            title: "选择题型",
            canSave: true,
            actionTitle: "完成",
            onClose: onClose,
            onSave: onClose
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("题型")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if questionTypes.isEmpty {
                    Text("暂无题型，请先前往设置 → 数量题型管理中新增。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                } else {
                    NativeTagFlow(spacing: 7) {
                        ForEach(questionTypes, id: \.self) { type in
                            Button {
                                selection = selection == type ? "" : type
                                onClose()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(type)
                                    if selection == type { Image(systemName: "checkmark") }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selection == type ? AppTheme.accent : Color.primary)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(
                                    selection == type ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !selection.isEmpty {
                    Button("清除题型") { selection = ""; onClose() }
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }
}

struct QuantityKnowledgePointSelectionDialog: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let currentType: String
    @Binding var selection: String
    let onClose: () -> Void
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil

    @State private var selected: [String] = []
    @State private var browsingType = ""
    @State private var showsCrossType = false
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var showsOrder = false

    private var activeType: String { browsingType.isEmpty ? currentType : browsingType }
    private var questionTypes: [String] { QuantityQuestionTypeRepository.types(records: records) }
    private var names: [String] {
        TagLibraryRepository.tags(kind: .knowledgePoint, module: activeType, records: records)
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NativeEditorDialog(
            title: "选择考点",
            canSave: true,
            actionTitle: "确定",
            onClose: onClose,
            onSave: { selection = orderedSelected.joined(separator: "、"); onClose() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !selected.isEmpty {
                    Text("已选考点").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    NativeTagFlow(spacing: 6) {
                        ForEach(orderedSelected, id: \.self) { name in
                            Button { selected.removeAll { $0 == name } } label: {
                                Label(name, systemImage: "xmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 8).frame(height: 27)
                                    .background(AppTheme.accent.opacity(0.09), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Text(showsCrossType ? "跨题型 · \(activeType)" : "当前题型 · \(currentType)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(showsCrossType ? "返回当前题型" : "＋ 跨题型选择") {
                        if showsCrossType {
                            showsCrossType = false
                            browsingType = currentType
                        } else {
                            showsCrossType = true
                            browsingType = questionTypes.first(where: { $0 != currentType }) ?? currentType
                        }
                        search = ""
                    }
                    .font(.system(size: 11, weight: .semibold))
                }

                if showsCrossType {
                    NativeTagFlow(spacing: 6) {
                        ForEach(questionTypes.filter { $0 != currentType }, id: \.self) { type in
                            Button { browsingType = type; search = "" } label: {
                                Text(type).font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(activeType == type ? AppTheme.accent : Color.primary)
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background(activeType == type ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("搜索或新增考点", text: $search)
                        .textFieldStyle(NativeTextFieldStyle())
                        .onSubmit(addTag)
                    Button("新增", action: addTag)
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(query.isEmpty || activeType.isEmpty || names.contains(query))
                }

                HStack {
                    Spacer()
                    Button("管理顺序") { showsOrder = true }
                        .font(.system(size: 11, weight: .semibold))
                }

                ScrollView {
                    NativeTagFlow(spacing: 6) {
                        ForEach(names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { name in
                            Button { toggle(name) } label: {
                                HStack(spacing: 4) {
                                    Text(name)
                                    if selected.contains(name) { Image(systemName: "checkmark") }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(selected.contains(name) ? AppTheme.accent : Color.primary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(selected.contains(name) ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("重命名") { renaming = name; newName = name }
                                Button("删除标签", role: .destructive) { deleting = name }
                            }
                        }
                    }
                }.frame(maxHeight: 220)
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            }
        }
        .onAppear {
            selected = selection.split(whereSeparator: { "、,，".contains($0) }).map(String.init)
            browsingType = currentType
        }
        .sheet(isPresented: $showsOrder) { KnowledgePointOrderView(module: activeType) }
        .alert("重命名考点", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("考点名称", text: $newName)
                .modifier(NativeDirectionalTextFieldNavigation())
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("当前题型已有记录中的该考点会同步更新。") }
        .alert("删除考点？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从考点库及当前题型已有记录中移除此考点，不删除题目。") }
    }

    private func toggle(_ name: String) {
        if selected.contains(name) { selected.removeAll { $0 == name } }
        else { selected.append(name) }
    }

    private var orderedSelected: [String] {
        let orderedNames = TagLibraryRepository.tags(kind: .knowledgePoint, module: activeType, records: records)
        return orderedNames.filter { selected.contains($0) } + selected.filter { !orderedNames.contains($0) }
    }

    private func addTag() {
        guard !query.isEmpty, !activeType.isEmpty else { return }
        do {
            try TagLibraryRepository.add(query, kind: .knowledgePoint, module: activeType, records: records, context: modelContext)
            if !selected.contains(query) { selected.append(query) }
            search = ""
        } catch { message = "考点保存失败，请重试" }
    }

    private func renameTag() {
        guard let old = renaming else { return }
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !names.contains(value) else {
            message = "名称不能为空或与其他考点重复"
            return
        }
        do {
            let result = try TagLibraryRepository.rename(old, to: value, kind: .knowledgePoint, module: activeType, records: records, context: modelContext)
            onTagMutation?(result)
            selected = selected.map { $0 == old ? value : $0 }
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }

    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result = try TagLibraryRepository.delete(name, kind: .knowledgePoint, module: activeType, records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0 == name }
            deleting = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct VerbalReasoningKnowledgePointSelectionDialog: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let currentModule: String
    @Binding var selection: [LibraryKnowledgePointReference]
    @Binding var legacyDisplaySelection: String
    let onClose: () -> Void
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil
    var onCommit: (([LibraryKnowledgePointReference]) -> String?)? = nil

    @State private var selected: [LibraryKnowledgePointReference] = []
    @State private var browsingModule = ""
    @State private var showsCrossModule = false
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var showsOrder = false

    private var modules: [String] { LibraryErrorTypeSubject.verbalReasoning.modules }
    private var activeModule: String { showsCrossModule ? browsingModule : currentModule }
    private var names: [String] {
        TagLibraryRepository.tags(kind: .knowledgePoint, module: activeModule, records: records)
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filteredNames: [String] {
        var values = names
        for reference in selected where reference.module == activeModule && !values.contains(reference.name) {
            values.append(reference.name)
        }
        return values.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NativeEditorDialog(
            title: "选择考点",
            canSave: true,
            actionTitle: "确定",
            onClose: onClose,
            onSave: commitSelection
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !selected.isEmpty {
                    Text("已选考点").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    NativeTagFlow(spacing: 6) {
                        ForEach(selected, id: \.id) { reference in
                            Button { selected.removeAll { $0 == reference } } label: {
                                Label(selectedTitle(for: reference), systemImage: "xmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 8).frame(height: 27)
                                    .background(AppTheme.accent.opacity(0.09), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Text(showsCrossModule ? "跨模块 · \(activeModule)" : "当前模块 · \(currentModule)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(showsCrossModule ? "返回当前模块" : "＋ 跨模块选择") {
                        if showsCrossModule {
                            showsCrossModule = false
                            browsingModule = currentModule
                        } else {
                            showsCrossModule = true
                            browsingModule = modules.first(where: { $0 != currentModule }) ?? currentModule
                        }
                        search = ""
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(!showsCrossModule && modules.allSatisfy { $0 == currentModule })
                }

                if showsCrossModule {
                    NativeTagFlow(spacing: 6) {
                        ForEach(modules.filter { $0 != currentModule }, id: \.self) { module in
                            Button {
                                browsingModule = module
                                search = ""
                            } label: {
                                Text(module)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(activeModule == module ? AppTheme.accent : Color.primary)
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background(
                                        activeModule == module ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("搜索或新增考点", text: $search)
                        .textFieldStyle(NativeTextFieldStyle())
                        .onSubmit(addTag)
                    Button("新增", action: addTag)
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(query.isEmpty || names.contains(query) || activeModule.isEmpty)
                }

                HStack {
                    Spacer()
                    Button("管理顺序") { showsOrder = true }
                        .font(.system(size: 11, weight: .semibold))
                }

                ScrollView {
                    NativeTagFlow(spacing: 6) {
                        ForEach(filteredNames, id: \.self) { name in
                            let reference = LibraryKnowledgePointReference(module: activeModule, name: name)
                            Button { toggle(reference) } label: {
                                HStack(spacing: 4) {
                                    Text(name)
                                    if selected.contains(reference) { Image(systemName: "checkmark") }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(selected.contains(reference) ? AppTheme.accent : Color.primary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(selected.contains(reference) ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("重命名") { renaming = name; newName = name }
                                Button("删除考点", role: .destructive) { deleting = name }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            }
        }
        .onAppear {
            let available = Set(TagLibraryRepository.tags(kind: .knowledgePoint, module: currentModule, records: records))
            selected = LibraryKnowledgePointReferencePolicy.resolvingLocalReferences(
                selection,
                currentModule: currentModule,
                availableNames: available
            )
            browsingModule = currentModule
        }
        .sheet(isPresented: $showsOrder) { KnowledgePointOrderView(module: activeModule) }
        .alert("重命名考点", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("考点名称", text: $newName).modifier(NativeDirectionalTextFieldNavigation())
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("来源模块中的该考点会同步更新。") }
        .alert("删除考点？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从考点库和引用该来源考点的错题中移除。") }
    }

    private func selectedTitle(for reference: LibraryKnowledgePointReference) -> String {
        guard selected.filter({ $0.name == reference.name }).count > 1 else { return reference.name }
        return "\(reference.module ?? currentModule) · \(reference.name)"
    }

    private func toggle(_ reference: LibraryKnowledgePointReference) {
        if selected.contains(reference) { selected.removeAll { $0 == reference } }
        else { selected.append(reference) }
    }

    private func commitSelection() {
        let values = LibraryKnowledgePointReferencePolicy.uniqueReferences(selected)
        if let error = onCommit?(values) {
            message = error
            return
        }
        selection = values
        legacyDisplaySelection = LibraryKnowledgePointReferencePolicy.displayNames(from: values).joined(separator: "、")
        onClose()
    }

    private func addTag() {
        guard !query.isEmpty, !activeModule.isEmpty, !names.contains(query) else { return }
        do {
            try TagLibraryRepository.add(query, kind: .knowledgePoint, module: activeModule, records: records, context: modelContext)
            toggle(LibraryKnowledgePointReference(module: activeModule, name: query))
            search = ""
        } catch { message = "考点保存失败，请重试" }
    }

    private func renameTag() {
        guard let old = renaming else { return }
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !names.contains(value) else {
            message = "名称不能为空或与当前模块其他考点重复"
            return
        }
        do {
            let result = try TagLibraryRepository.rename(old, to: value, kind: .knowledgePoint, module: activeModule, records: records, context: modelContext)
            onTagMutation?(result)
            selected = selected.map { reference in
                reference.module == activeModule && reference.name == old
                    ? LibraryKnowledgePointReference(module: activeModule, name: value)
                    : reference
            }
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }

    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result = try TagLibraryRepository.delete(name, kind: .knowledgePoint, module: activeModule, records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0.module == activeModule && $0.name == name }
            deleting = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct LibraryRelationSelectionDialog: View {
    let collection: String
    let candidates: [StoredRecord]
    @Binding var selection: [String]
    let onClose: () -> Void
    var onCreateWord: (() -> Void)? = nil
    @State private var selected: [String] = []
    @State private var search = ""
    @State private var wordCategoryFilter: WordCategory?

    private let wordCategoryFilterOrder: [WordCategory] = [
        .idiomDefinition, .idiomComparison, .wordDefinition, .wordComparison
    ]

    var body: some View {
        NativeEditorDialog(title: dialogTitle,
            canSave: true, actionTitle: "确定", onClose: onClose, onSave: { selection = selected; onClose() }) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("搜索", text: $search).textFieldStyle(NativeTextFieldStyle())
                    if collection == "words", let onCreateWord {
                        Button(action: onCreateWord) {
                            Label("新建", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("已选 \(selected.count) 项")
                    Spacer()
                    Button("清空关联") { selected = [] }
                }.font(.system(size: 11))
                if collection == "words" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(wordCategoryFilterOrder) { category in
                                let isSelected = wordCategoryFilter == category
                                Button {
                                    wordCategoryFilter = isSelected ? nil : category
                                } label: {
                                    Text(category.shortTitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
                                        .padding(.horizontal, 9)
                                        .frame(height: 31)
                                        .background(
                                            isSelected ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCandidates, id: \.compoundID) { record in
                            Button {
                                if selected.contains(record.recordID) { selected.removeAll { $0 == record.recordID } }
                                else if collection == "exams" { selected = [record.recordID] }
                                else { selected.append(record.recordID) }
                            } label: {
                                let snapshot = LibraryRecordSnapshot(record: record)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if collection == "errors" {
                                            Text(errorReferenceLine(snapshot))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            Text(snapshot.title)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        } else {
                                            Text(snapshot.title).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(2)
                                        }
                                        if collection == "words" {
                                            Text(snapshot.tags.joined(separator: " · "))
                                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selected.contains(record.recordID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .padding(.horizontal, 7)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if filteredCandidates.isEmpty {
                            VStack(spacing: 7) {
                                Text("暂无符合条件的关联内容")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                if collection == "words", let onCreateWord {
                                    Button(action: onCreateWord) {
                                        Label("直接新建词语", systemImage: "plus.circle")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .contentMargins(.trailing, 8, for: .scrollContent)
                .frame(maxHeight: 320)
            }
        }.onAppear { selected = selection }
    }

    private var filteredCandidates: [StoredRecord] {
        candidates.filter { record in
            guard LibraryRelationCandidateScope.includes(
                candidateCollection: record.collection,
                targetCollection: collection
            ) else { return false }
            let snapshot = LibraryRecordSnapshot(record: record)
            let matchesSearch = search.isEmpty || snapshot.searchableText.localizedCaseInsensitiveContains(search)
            let matchesCategory = collection != "words" || wordCategoryFilter == nil || snapshot.category == wordCategoryFilter?.rawValue
            return matchesSearch && matchesCategory
        }
    }

    private var dialogTitle: String {
        switch collection {
        case "exams": "来源套卷"
        case "notes": "关联笔记"
        case "errors": "关联错题"
        default: "关联词语"
        }
    }

    private func errorReferenceLine(_ snapshot: LibraryRecordSnapshot) -> String {
        let source = snapshot.questionSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = snapshot.questionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = source.isEmpty ? "来源未填写" : source
        let numberText = number.isEmpty
            ? "题号未填写"
            : (number.hasPrefix("第") || number.hasSuffix("题") ? number : "第\(number)题")
        return "\(sourceText) · \(numberText)"
    }

}
