import SwiftData
import SwiftUI
import UIKit

struct LibraryRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let kind: LibraryContentKind
    let scope: LibraryScope
    let record: StoredRecord
    let onDelete: () -> Void

    @State private var showEditor = false
    @State private var showDelete = false
    @State private var showDoodle = false
    @State private var drawingData = ""

    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var snapshot: LibraryRecordSnapshot { LibraryRecordSnapshot(record: record) }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metadata
                    questionBlock
                    optionsBlock
                    answerAndSource
                    noteBlock
                    drawingPreview
                    reviewBlock
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)

            if showDoodle {
                Color.gray.opacity(0.30).ignoresSafeArea()
                NativePencilDrawingEditor(
                    encodedData: $drawingData,
                    legacyPreviewDataURL: firstText(["drawingPreview", "doodle", "drawingDataURL"]) ?? "",
                    transparentBackground: true,
                    toolbarAtTop: true,
                    onClose: closeDoodle
                )
                .ignoresSafeArea(edges: .bottom)
                .transition(.opacity)
            }

            if showDelete {
                NativeDeleteDialog(
                    title: "删除错题",
                    message: "删除后无法在 App 内恢复。",
                    onDelete: { showDelete = false; onDelete() },
                    onCancel: { showDelete = false }
                )
            }
        }
        .navigationTitle("错题详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showDoodle ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(openDoodle) { Image(systemName: "pencil.and.scribble") }
                    .accessibilityLabel("涂鸦")
                Menu {
                    Button { showEditor = true } label: { Label("编辑错题", systemImage: "pencil") }
                    Button(role: .destructive) { showDelete = true } label: { Label("删除错题", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .navigationDestination(isPresented: $showEditor) {
            LibraryRecordEditorView(kind: kind, scope: scope, record: record)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let status = firstText(["status", "masteryStatus"]) {
                Text(clean(status))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(AppTheme.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
            }
            labeledLine("考点", value: firstText(["knowledgePoint", "point", "topic"]))
            labeledLine("错因", value: firstText(["cause", "errorCause", "reason"]))
            if !snapshot.tags.isEmpty { FlowTagView(values: snapshot.tags) }
        }
    }

    @ViewBuilder private var questionBlock: some View {
        if !clean(snapshot.title).isEmpty {
            Text(clean(snapshot.title))
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(7)
                .textSelection(.enabled)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var optionsBlock: some View {
        if let options = stringArray("options"), !options.isEmpty {
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let letter = String(UnicodeScalar(65 + index)!)
                    let correct = answerLetters.contains(letter)
                    let chosen = userAnswerLetters.contains(letter)
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(letter).")
                            .font(.system(size: 15, weight: .semibold))
                        Text(clean(option))
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success) }
                        else if chosen { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.danger) }
                    }
                    .padding(15)
                    .background(optionBackground(correct: correct, chosen: chosen), in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(correct ? AppTheme.success : (chosen ? AppTheme.danger : Color.primary.opacity(0.08)), lineWidth: 0.8)
                    }
                }
            }
        }
    }

    private var answerAndSource: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledLine("全站正确率", value: firstText(["accuracy", "correctRate"]))
            labeledLine("题目来源", value: firstText(["questionSource", "source"]))
            labeledLine("正确答案", value: firstText(["correctOption", "answer", "correctAnswer"]))
            labeledLine("我的答案", value: firstText(["userOption", "myAnswer"]))
        }
    }

    @ViewBuilder private var noteBlock: some View {
        if let note = firstText(["content", "note", "errorNote", "analysis", "pitfall"]), !clean(note).isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Label("错题笔记", systemImage: "note.text").font(.system(size: 14, weight: .medium))
                Text(clean(note)).font(.system(size: 15, weight: .regular)).lineSpacing(6).textSelection(.enabled)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var drawingPreview: some View {
        if let image = dataURLImage(firstText(["drawingPreview", "doodle", "drawingDataURL"])) {
            VStack(alignment: .leading, spacing: 8) {
                Label("手写笔记", systemImage: "pencil.and.scribble").font(.system(size: 14, weight: .medium))
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
    }

    @ViewBuilder private var reviewBlock: some View {
        if let value = firstText(["reviewNote", "reviewPlan", "nextReviewAt"]), !clean(value).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("复盘记录", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .medium))
                Text(clean(value)).font(.system(size: 15, weight: .regular)).lineSpacing(5)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private func labeledLine(_ label: String, value: String?) -> some View {
        if let value, !clean(value).isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("\(label)：").foregroundStyle(.secondary)
                Text(clean(value)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 13, weight: .regular))
        }
    }

    private var answerLetters: Set<String> { letterSet(firstText(["correctOption", "answer", "correctAnswer"])) }
    private var userAnswerLetters: Set<String> { letterSet(firstText(["userOption", "myAnswer"])) }
    private func letterSet(_ value: String?) -> Set<String> {
        Set((value ?? "").uppercased().filter { $0.isLetter }.map(String.init))
    }
    private func optionBackground(correct: Bool, chosen: Bool) -> Color {
        if correct { return AppTheme.success.opacity(0.09) }
        if chosen { return AppTheme.danger.opacity(0.08) }
        return Color.white
    }

    private func openDoodle() {
        drawingData = firstText(["pencilKitData", "drawingData"]) ?? ""
        withAnimation(.easeInOut(duration: 0.18)) { showDoodle = true }
    }
    private func closeDoodle() {
        saveDrawing()
        withAnimation(.easeInOut(duration: 0.18)) { showDoodle = false }
    }
    private func saveDrawing() {
        var updated = object
        updated["pencilKitData"] = drawingData
        let preview = PencilDrawingCompatibility.previewDataURL(encodedData: drawingData)
        if !preview.isEmpty { updated["drawingPreview"] = preview; updated["doodle"] = preview }
        updated["updatedAt"] = ISO8601DateFormatter().string(from: .now)
        guard let payload = try? JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys]) else { return }
        record.payload = payload
        record.updatedAt = .now
        try? modelContext.save()
    }

    private func firstText(_ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }
    private func stringArray(_ key: String) -> [String]? {
        if let values = object[key] as? [String] { return values }
        if let values = object[key] as? [[String: Any]] { return values.compactMap { ($0["text"] ?? $0["content"] ?? $0["value"]) as? String } }
        return nil
    }
    private func dataURLImage(_ value: String?) -> UIImage? {
        guard let value, let marker = value.range(of: "base64,") else { return nil }
        return Data(base64Encoded: String(value[marker.upperBound...])).flatMap(UIImage.init(data:))
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
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
