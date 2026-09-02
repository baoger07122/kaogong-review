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
                VStack(alignment: .leading, spacing: 12) {
                    metadata
                    imagesBlock
                    questionBlock
                    optionsBlock
                    answerAndSource
                    comparisonBlock
                    noteBlock
                    reviewBlock
                    reviewInfo
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)

            if showDoodle {
                Color.gray.opacity(0.30)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                NativePencilDrawingEditor(
                    encodedData: $drawingData,
                    legacyPreviewDataURL: drawingData.isEmpty ? (firstText(["drawingPreview", "doodle", "drawingDataURL"]) ?? "") : "",
                    transparentBackground: true,
                    toolbarAtTop: false,
                    onClose: closeDoodle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .zIndex(1)
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
        .preference(key: RootBottomBarHiddenPreferenceKey.self, value: true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !showDoodle {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: openDoodle) { Image(systemName: "pencil.and.scribble") }
                        .accessibilityLabel("涂鸦")
                    Menu {
                        Button { showEditor = true } label: { Label("编辑错题", systemImage: "pencil") }
                        Button(role: .destructive) { showDelete = true } label: { Label("删除错题", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .navigationDestination(isPresented: $showEditor) {
            LibraryRecordEditorView(kind: kind, scope: scope, record: record)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let status = recordType {
                Text(clean(status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(status))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(statusColor(status).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            metadataLine("考点", values: knowledgePoints)
            metadataLine("错因", values: textValues(["errorCause", "cause", "reason"]))
            metadataLine("思维误区", values: textValues(["pitfall", "misconception", "thinkingTrap"]))
        }
    }

    @ViewBuilder private var imagesBlock: some View {
        let images = imageValues.compactMap(dataURLImage)
        if !images.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .background(detailBackground, in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                        }
                }
            }
            .padding(.top, 3)
        }
    }

    @ViewBuilder private var questionBlock: some View {
        if !clean(snapshot.title).isEmpty {
            Text(cleanMultiline(snapshot.title))
                .font(.system(size: 14, weight: .regular))
                .lineSpacing(9.8)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(detailBackground, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var optionsBlock: some View {
        if let options = stringArray("options"), !options.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let letter = String(UnicodeScalar(65 + index)!)
                    let correct = answerLetters.contains(letter)
                    let chosen = userAnswerLetters.contains(letter)
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(letter).")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20, alignment: .leading)
                        optionText(option, correct: correct, chosen: chosen)
                            .lineSpacing(5.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(optionBackground(correct: correct, chosen: chosen), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(correct ? AppTheme.success : (chosen ? AppTheme.danger : Color.primary.opacity(0.10)), lineWidth: 0.8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var answerAndSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let accuracy = formattedAccuracy {
                supportingLine("全站正确率", value: accuracy, systemImage: "chart.bar.fill")
            }
            if let source = firstText(["questionSource", "source"]), !clean(source).isEmpty {
                supportingLine("题目来源", value: clean(source), systemImage: "books.vertical.fill")
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var comparisonBlock: some View {
        let groups = comparisonGroups
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("词语辨析")
                    .font(.system(size: 13, weight: .medium))
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("第\(index + 1)组")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let words = group["words"], !clean(words).isEmpty {
                            Text(clean(words)).font(.system(size: 14, weight: .medium))
                        }
                        if let relation = group["relation"], !clean(relation).isEmpty {
                            Text(cleanMultiline(relation))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if index < groups.count - 1 { Divider() }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("错题笔记", systemImage: "note.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let note = firstText(["content", "note", "errorNote", "analysis"]), !clean(note).isEmpty {
                NativeRichTextDisplay(html: note, minHeight: 42)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("点击添加错题笔记")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
            }
        }
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onTapGesture { showEditor = true }
    }

    @ViewBuilder private var reviewBlock: some View {
        if let value = firstText(["reviewNote", "reviewPlan", "nextReviewAt"]), !clean(value).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("复盘记录", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(cleanMultiline(value)).font(.system(size: 14, weight: .regular)).lineSpacing(6)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var reviewInfo: some View {
        let parts = reviewInfoParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
    }

    @ViewBuilder private func metadataLine(_ label: String, values: [String]) -> some View {
        let text = values.map(clean).filter { !$0.isEmpty }.joined(separator: "、")
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(label)：")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text(text)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12, weight: .regular))
        }
    }

    private func supportingLine(_ label: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("\(label)：")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .regular))
    }

    private func optionText(_ option: String, correct: Bool, chosen: Bool) -> Text {
        var text = Text(cleanMultiline(option))
            .font(.system(size: 14, weight: .regular))
        if correct, chosen {
            text = text + Text("  ✓ 正确答案 · 你的选择")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.success)
        } else if correct {
            text = text + Text("  ✓ 正确答案")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.success)
        } else if chosen {
            text = text + Text("  ✕ 你的选择")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.danger)
        }
        return text
    }

    private var answerLetters: Set<String> { letterSet(firstText(["correctOption", "answer", "correctAnswer"])) }
    private var userAnswerLetters: Set<String> { letterSet(firstText(["userOption", "myAnswer"])) }
    private func letterSet(_ value: String?) -> Set<String> {
        Set((value ?? "").uppercased().filter { "ABCD".contains($0) }.map(String.init))
    }
    private func optionBackground(correct: Bool, chosen: Bool) -> Color {
        if correct { return AppTheme.success.opacity(0.09) }
        if chosen { return AppTheme.danger.opacity(0.08) }
        return Color.white
    }

    private var detailBackground: Color { Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0) }

    private var recordType: String? {
        if let value = firstText(["type"]), ["错题", "不确定题"].contains(clean(value)) { return clean(value) }
        return firstText(["status", "masteryStatus"]).map(clean)
    }

    private var knowledgePoints: [String] {
        if let values = stringArray("knowledgePoints"), !values.isEmpty { return values }
        return textValues(["knowledgePoint", "point", "topic"])
            .flatMap { $0.split(whereSeparator: { "、,，".contains($0) }).map(String.init) }
    }

    private var imageValues: [String] {
        if let values = object["images"] as? [String], !values.isEmpty { return values }
        return firstText(["image"]).map { [$0] } ?? []
    }

    private var comparisonGroups: [[String: String]] {
        guard let values = object["compareGroups"] as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            let words = value["words"] as? String ?? ""
            let relation = value["relation"] as? String ?? ""
            guard !clean(words).isEmpty || !clean(relation).isEmpty else { return nil }
            return ["words": words, "relation": relation]
        }
    }

    private var reviewInfoParts: [String] {
        var values: [String] = []
        if let createdAt = record.createdAt {
            values.append("收录于 \(Self.dateFormatter.string(from: createdAt))")
        }
        if let count = firstText(["reviewCount"]), let number = Int(clean(count)), number > 0 {
            values.append("复习 \(number) 次")
        }
        if let rawDate = firstText(["lastReviewDate"]), let date = ISO8601DateFormatter().date(from: rawDate) {
            values.append("上次复习 \(Self.dateFormatter.string(from: date))")
        }
        return values
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private var formattedAccuracy: String? {
        guard let raw = firstText(["accuracy", "correctRate"]), !clean(raw).isEmpty else { return nil }
        let value = clean(raw)
        return value.contains("%") ? value : "\(value)%"
    }

    private func statusColor(_ value: String) -> Color {
        value.contains("不确定") ? AppTheme.warning : AppTheme.danger
    }

    private func textValues(_ keys: [String]) -> [String] {
        firstText(keys).map { [$0] } ?? []
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
        if !drawingData.isEmpty {
            updated["drawingPreview"] = preview
            updated["doodle"] = preview
        }
        updated["updatedAt"] = ISO8601DateFormatter().string(from: .now)
        guard let payload = try? JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys]) else { return }
        record.replacePayload(payload)
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

    private func cleanMultiline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
