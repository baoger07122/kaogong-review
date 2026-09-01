import SwiftUI

struct LibraryRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: LibraryContentKind
    let scope: LibraryScope
    let record: StoredRecord
    let onDelete: () -> Void

    @State private var showEditor = false
    @State private var showDelete = false

    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var snapshot: LibraryRecordSnapshot { LibraryRecordSnapshot(record: record) }

    var body: some View {
        let subject = record.subject ?? ""
        let module = record.module ?? ""
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    if !subject.isEmpty || !module.isEmpty {
                        Text([subject, module].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(snapshot.title)
                        .font(AppTheme.bodyFont)
                        .fontWeight(.regular)
                        .textSelection(.enabled)
                    if !snapshot.tags.isEmpty {
                        FlowTagView(values: snapshot.tags)
                    }
                }
                .nativeCard()

                if let options = stringArray("options"), !options.isEmpty {
                    detailSection("选项", image: "list.bullet") {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            HStack(alignment: .top, spacing: 9) {
                                Text(String(UnicodeScalar(65 + index)!))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 24, height: 24)
                                    .background(AppTheme.accent.opacity(0.09), in: Circle())
                                Text(clean(option)).font(AppTheme.bodyFont).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                let answerValues = labeledValues([
                    ("正确答案", ["correctOption", "answer", "correctAnswer"]),
                    ("我的答案", ["userOption", "myAnswer"]),
                    ("全站正确率", ["accuracy", "correctRate"]),
                    ("题目来源", ["questionSource", "source"]),
                    ("掌握状态", ["status", "masteryStatus"])
                ])
                if !answerValues.isEmpty {
                    detailSection("答案与来源", image: "checkmark.circle") {
                        ForEach(answerValues, id: \.0) { label, value in
                            HStack(alignment: .top) {
                                Text(label).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                                Text(value).frame(maxWidth: .infinity, alignment: .leading)
                            }.font(AppTheme.inputFont)
                        }
                    }
                }

                let analysis = firstText(["content", "note", "errorNote", "analysis", "pitfall"])
                if let analysis, !clean(analysis).isEmpty {
                    detailSection("错题笔记与解析", image: "note.text") {
                        Text(clean(analysis)).font(AppTheme.bodyFont).textSelection(.enabled)
                    }
                }

                Button(role: .destructive) { showDelete = true } label: {
                    Label("删除这条错题", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NativeDangerButtonStyle())
            }
            .padding(16)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("错题详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button("编辑") { showEditor = true } }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack { LibraryRecordEditorView(kind: kind, scope: scope, record: record) }
        }
        .overlay {
            if showDelete {
                NativeDeleteDialog(
                    title: "删除错题",
                    message: "删除后无法在 App 内恢复。",
                    onDelete: { showDelete = false; onDelete() },
                    onCancel: { showDelete = false }
                )
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, image: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: image).font(AppTheme.cardTitleFont)
            content()
        }
        .nativeCard()
    }

    private func firstText(_ keys: [String]) -> String? {
        keys.lazy.compactMap { object[$0] as? String }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func stringArray(_ key: String) -> [String]? {
        if let values = object[key] as? [String] { return values }
        if let values = object[key] as? [[String: Any]] {
            return values.compactMap { ($0["text"] ?? $0["content"] ?? $0["value"]) as? String }
        }
        return nil
    }

    private func labeledValues(_ definitions: [(String, [String])]) -> [(String, String)] {
        definitions.compactMap { label, keys in
            guard let value = firstText(keys), !clean(value).isEmpty else { return nil }
            return (label, clean(value))
        }
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "(?:^|\\s)[.#]?[a-zA-Z][^{}\\n]{0,80}\\{[^}]*\\}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FlowTagView: View {
    let values: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(values.prefix(4), id: \.self) { value in
                Text(value)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.09), in: Capsule())
            }
        }
    }
}
