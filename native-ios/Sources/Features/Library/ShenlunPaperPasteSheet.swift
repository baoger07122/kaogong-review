import SwiftUI

struct ShenlunPaperPasteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var entries: [ShenlunPaperPasteEntry] = []

    let kind: ShenlunPaperPasteKind
    let onConfirm: ([ShenlunPaperPasteEntry]) -> Void

    private var isMaterial: Bool { kind == .materials }
    private var title: String { isMaterial ? "批量粘贴材料" : "批量粘贴题目" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isMaterial
                         ? "在「材料 1」「材料 2」各自换行处拆分。也可用单独一行 --- 分隔。"
                         : "在「第 1 题」「第 2 题」或「一、」「二、」各自换行处拆分。也可用单独一行 --- 分隔。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $source)
                        .font(.system(size: 15))
                        .frame(height: 180)
                        .padding(5)
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)) }
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("shenlun-batch-paste-text")
                    Button("预览拆分") { entries = ShenlunPaperPasteParser.parse(source, kind: kind) }
                        .buttonStyle(NativeSecondaryButtonStyle())
                        .disabled(source.allSatisfy(\.isWhitespace))
                    if !entries.isEmpty {
                        Text(isMaterial ? "\(entries.count) 份材料" : "\(entries.count) 道题")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(entries.indices, id: \.self) { index in
                            preview(entries[index], index: index)
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: source) { _, _ in entries.removeAll() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入套卷") {
                        onConfirm(entries)
                        dismiss()
                    }
                    .disabled(entries.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func preview(_ entry: ShenlunPaperPasteEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.heading ?? (isMaterial ? "材料 \(index + 1)" : "第 \(index + 1) 题"))
                .font(.system(size: 13, weight: .semibold))
            Text(entry.text.isEmpty ? "内容为空，加入后可补录。" : entry.text)
                .font(.system(size: 14))
                .lineLimit(3)
            if !entry.instructions.isEmpty {
                Text(entry.instructions)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
