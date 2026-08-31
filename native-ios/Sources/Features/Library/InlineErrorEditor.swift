import SwiftData
import SwiftUI
import UIKit

struct InlineErrorEditor: View {
    @Environment(\.modelContext) private var modelContext
    let record: StoredRecord
    let scope: LibraryScope
    let records: [StoredRecord]
    let onClose: () -> Void
    let onFullEdit: () -> Void
    @State private var draft: LibraryRecordDraft
    @State private var saveMessage = ""

    init(
        record: StoredRecord,
        scope: LibraryScope,
        records: [StoredRecord],
        onClose: @escaping () -> Void,
        onFullEdit: @escaping () -> Void
    ) {
        self.record = record
        self.scope = scope
        self.records = records
        self.onClose = onClose
        self.onFullEdit = onFullEdit
        _draft = State(initialValue: LibraryRecordDraft(kind: .errors, scope: scope, record: record))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("就地编辑错题", systemImage: "pencil.line")
                    .font(AppTheme.cardTitleFont)
                Spacer()
                Button("完整编辑", action: onFullEdit)
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28).background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $draft.title)
                .font(AppTheme.inputFont)
                .frame(minHeight: 76)
                .padding(7)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))

            HStack(spacing: 8) {
                TextField("正确答案", text: $draft.correctOption).textFieldStyle(NativeTextFieldStyle())
                TextField("我的答案", text: $draft.userOption).textFieldStyle(NativeTextFieldStyle())
                Picker("状态", selection: $draft.status) {
                    Text("未掌握").tag("未掌握")
                    Text("已掌握").tag("已掌握")
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }

            TextField("错因", text: $draft.errorCause).textFieldStyle(NativeTextFieldStyle())
            NativeRichTextEditor(html: $draft.content, minHeight: 92, mode: .compact)

            HStack {
                if !saveMessage.isEmpty {
                    Text(saveMessage).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.success)
                }
                Spacer()
                Button("保存修改", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
        }
    }

    private func save() {
        do {
            try LibraryRecordRepository.save(kind: .errors, draft: draft, records: records, context: modelContext)
            saveMessage = "已保存"
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            saveMessage = "保存失败"
        }
    }
}
