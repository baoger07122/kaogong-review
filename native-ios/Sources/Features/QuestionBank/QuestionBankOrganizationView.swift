import SwiftUI

struct QuestionBankPaperOrganizationView: View {
    private struct GroupEditor: Identifiable {
        let groupID: String?
        var id: String { groupID.map { "edit:\($0)" } ?? "new" }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuestionBankOrganizationStore
    let papers: [QuestionBankHomePaper]

    @State private var groupEditor: GroupEditor?
    @State private var groupEditorName = ""
    @State private var groupEditorError: String?
    @State private var deletingGroupID: String?

    private var papersByID: [String: QuestionBankHomePaper] {
        Dictionary(papers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.snapshot.groups) { group in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text(group.name)
                                .font(AppTheme.bodyFont.weight(.medium))
                            Spacer(minLength: 0)
                            Menu {
                                Button("重命名") {
                                    groupEditorName = group.name
                                    groupEditorError = nil
                                    groupEditor = GroupEditor(groupID: group.id)
                                }
                                Button("删除分组", role: .destructive) {
                                    deletingGroupID = group.id
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("管理分组\(group.name)")
                        }
                    }
                    .onMove(perform: store.moveGroup)
                } header: {
                    Text("分组顺序")
                } footer: {
                    Text("删除分组只会把试卷移到“未分组”，不会删除题目。")
                }

                ForEach(store.snapshot.groups) { group in
                    Section {
                        paperRows(in: group.id)
                    } header: {
                        Text(group.name)
                    }
                }

                Section("未分组") {
                    paperRows(in: nil)
                }
            }
            .navigationTitle("分组与排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                        .accessibilityIdentifier("question-bank-organization-edit")
                    Button {
                        groupEditorName = ""
                        groupEditorError = nil
                        groupEditor = GroupEditor(groupID: nil)
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("新建分组")
                    .accessibilityIdentifier("question-bank-organization-add-group")
                }
            }
            .sheet(item: $groupEditor) { editor in
                NavigationStack {
                    Form {
                        TextField("分组名称", text: $groupEditorName)
                            .accessibilityIdentifier("question-bank-group-name")
                        if let groupEditorError {
                            Text(groupEditorError)
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(AppTheme.danger)
                        }
                        Text(editor.groupID == nil
                             ? "新分组创建后，可以在试卷行中将试卷移入。"
                             : "分组内的试卷和题目不会改变。")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle(editor.groupID == nil ? "新建分组" : "重命名分组")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { groupEditor = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(editor.groupID == nil ? "创建" : "保存") {
                                saveGroup(editor)
                            }
                            .disabled(groupEditorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.height(230)])
            }
            .confirmationDialog(
                "删除分组？",
                isPresented: Binding(
                    get: { deletingGroupID != nil },
                    set: { if !$0 { deletingGroupID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除分组并移出试卷", role: .destructive) {
                    if let id = deletingGroupID { store.deleteGroup(id: id) }
                    deletingGroupID = nil
                }
                Button("取消", role: .cancel) { deletingGroupID = nil }
            } message: {
                Text("试卷会移动到“未分组”，题目内容不会删除。")
            }
        }
    }

    private func saveGroup(_ editor: GroupEditor) {
        let succeeded: Bool
        if let groupID = editor.groupID {
            succeeded = store.renameGroup(id: groupID, to: groupEditorName)
        } else {
            succeeded = store.addGroup(named: groupEditorName)
        }
        if succeeded {
            groupEditor = nil
        } else {
            groupEditorError = "分组名称不能为空或已存在。"
        }
    }

    @ViewBuilder
    private func paperRows(in groupID: String?) -> some View {
        let paperIDs = store.orderedPaperIDs(in: groupID).filter { papersByID[$0] != nil }
        if paperIDs.isEmpty {
            Text("暂无试卷")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.tertiary)
        } else {
            ForEach(paperIDs, id: \.self) { paperID in
                if let paper = papersByID[paperID] {
                    Menu {
                        Button("未分组") { store.movePaper(paperID, to: nil) }
                        if !store.snapshot.groups.isEmpty { Divider() }
                        ForEach(store.snapshot.groups) { group in
                            Button(group.name) { store.movePaper(paperID, to: group.id) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(paper.title)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(paper.title)，更改分组")
                    .accessibilityIdentifier("question-bank-organization-paper-\(paperID)")
                }
            }
            .onMove { offsets, destination in
                store.movePapers(in: groupID, fromOffsets: offsets, toOffset: destination)
            }
        }
    }
}
