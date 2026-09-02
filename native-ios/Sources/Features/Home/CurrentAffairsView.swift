import SwiftData
import SwiftUI

private struct CurrentAffairsNote: Identifiable {
    let id: String
    var title: String
    var content: String
    var module: String
    var createdAt: Date
    var updatedAt: Date
}

struct CurrentAffairsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var selectedModule = "全部"
    @State private var searchText = ""
    @State private var editing: CurrentAffairsNote?
    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var draftModule = "政治"

    private let modules = ["全部", "政治", "法律", "经济", "人文", "科技", "地理"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                moduleSelector
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索标题或内容", text: $searchText).font(AppTheme.inputFont)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 11))
                    Button { beginCreate() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(AppTheme.accent, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                if visibleNotes.isEmpty {
                    NativeStatusCard(title: "暂无时政笔记", detail: "点击右上角新增，记录时政与常识内容", systemImage: "doc.text", color: AppTheme.warning)
                } else {
                    ForEach(visibleNotes) { note in
                        Button { beginEdit(note) } label: { noteCard(note) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { remove(note) } label: { Label("删除", systemImage: "trash") }
                            }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("时政常识")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if editing != nil { editorDialog } }
    }

    private var moduleSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modules, id: \.self) { module in
                    Button(module) { selectedModule = module }
                        .font(.system(size: 12, weight: selectedModule == module ? .semibold : .regular))
                        .foregroundStyle(selectedModule == module ? AppTheme.accent : Color.primary)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(selectedModule == module ? AppTheme.accent.opacity(0.10) : AppTheme.secondaryBackground, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var notes: [CurrentAffairsNote] {
        records.compactMap { record in
            guard record.collection == "notes", record.subject == "常识判断", let object = record.jsonObject else { return nil }
            let createdAt = parseDate(object["createdAt"]) ?? record.createdAt ?? .distantPast
            return CurrentAffairsNote(
                id: record.recordID,
                title: (object["title"] as? String) ?? "未命名笔记",
                content: plainText((object["content"] as? String) ?? ""),
                module: record.module ?? (object["module"] as? String) ?? "政治",
                createdAt: createdAt,
                updatedAt: parseDate(object["updatedAt"]) ?? record.updatedAt ?? createdAt
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var visibleNotes: [CurrentAffairsNote] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter {
            (selectedModule == "全部" || $0.module == selectedModule)
                && (keyword.isEmpty || $0.title.localizedCaseInsensitiveContains(keyword) || $0.content.localizedCaseInsensitiveContains(keyword))
        }
    }

    private func noteCard(_ note: CurrentAffairsNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.module)
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppTheme.warning.opacity(0.10), in: Capsule())
                Spacer()
                Text(HomeRecordRepository.chineseDate(note.createdAt, includeYear: false))
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            Text(note.title).font(AppTheme.cardTitleFont)
            if !note.content.isEmpty {
                Text(note.content).font(AppTheme.bodyFont).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var editorDialog: some View {
        NativeEditorDialog(
            title: editing?.id.isEmpty == false ? "编辑时政笔记" : "新增时政笔记",
            canSave: !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { editing = nil },
            onSave: save
        ) {
            TextField("标题", text: $draftTitle).textFieldStyle(NativeTextFieldStyle())
            NativePropertyRow(title: "分类", value: draftModule, systemImage: "folder") {
                let current = modules.dropFirst().firstIndex(of: draftModule) ?? modules.dropFirst().startIndex
                let next = modules.dropFirst().index(after: current)
                draftModule = next == modules.endIndex ? modules[1] : modules[next]
            }
            NativeRichTextEditor(html: $draftContent, minHeight: 130)
        }
    }

    private func beginCreate() {
        editing = CurrentAffairsNote(id: "", title: "", content: "", module: selectedModule == "全部" ? "政治" : selectedModule, createdAt: .now, updatedAt: .now)
        draftTitle = ""
        draftContent = ""
        draftModule = editing?.module ?? "政治"
    }

    private func beginEdit(_ note: CurrentAffairsNote) {
        editing = note
        draftTitle = note.title
        draftContent = note.content
        draftModule = note.module
    }

    private func save() {
        guard let editing else { return }
        let id = editing.id.isEmpty ? "note_\(Int(Date().timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))" : editing.id
        let existing = records.first { $0.collection == "notes" && $0.recordID == id }
        let now = Date()
        var object = existing?.jsonObject ?? [:]
        object["id"] = id
        object["title"] = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        object["content"] = draftContent
        object["subject"] = "常识判断"
        object["module"] = draftModule
        object["createdAt"] = iso(existing?.createdAt ?? editing.createdAt)
        object["updatedAt"] = iso(now)
        guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        if let existing {
            existing.replacePayload(payload)
            existing.subject = "常识判断"
            existing.module = draftModule
            existing.updatedAt = now
        } else {
            modelContext.insert(StoredRecord(collection: "notes", recordID: id, payload: payload, subject: "常识判断", module: draftModule, createdAt: editing.createdAt, updatedAt: now))
        }
        try? modelContext.save()
        self.editing = nil
    }

    private func remove(_ note: CurrentAffairsNote) {
        try? HomeRecordRepository.remove(collection: "notes", id: note.id, records: records, context: modelContext)
    }

    private func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
