import SwiftData
import SwiftUI

struct LibraryWordMigrationCandidate: Identifiable {
    let record: StoredRecord
    let category: WordCategory?
    let originalType: String
    let status: String

    var id: String { record.recordID }
    var title: String {
        let object = record.indexObject ?? record.jsonObject ?? [:]
        for key in ["name", "words", "title", "text"] {
            guard let value = object[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return value
        }
        return ""
    }
}

enum LibraryWordMigrationPolicy {
    static func categoryMenuTitle(_ category: WordCategory) -> String {
        switch category {
        case .wordDefinition: "实词"
        case .idiomDefinition: "成语"
        case .wordComparison: "实词组辨析"
        case .idiomComparison: "成语组辨析"
        }
    }

    static func resolvedCategory(in object: [String: Any]) -> WordCategory? {
        let values = ["category", "type"].compactMap { key -> String? in
            guard let value = object[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let uniqueValues = Set(values)
        guard uniqueValues.count == 1, let rawValue = uniqueValues.first else { return nil }
        return WordCategory(rawValue: rawValue)
    }

    static func candidate(for record: StoredRecord) -> LibraryWordMigrationCandidate? {
        guard record.collection == "words", let object = record.jsonObject else { return nil }
        let category = resolvedCategory(in: object)
        let hasNewBody: Bool
        let hasLegacyBody: Bool
        if category?.isComparison == true {
            hasNewBody = object.keys.contains("comparisonDocument")
            hasLegacyBody = ["commonMeaning", "compareWords", "idiomComparisonContext", "judgmentHint", "content", "meaning", "compareNote", "coreDifference"]
                .contains { object[$0] != nil }
        } else {
            hasNewBody = object.keys.contains("meaning")
            hasLegacyBody = ["content", "judgmentHint"].contains { object[$0] != nil }
        }

        guard category == nil || (!hasNewBody && hasLegacyBody) else { return nil }
        let categoryRaw = (object["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typeRaw = (object["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalType: String
        if !categoryRaw.isEmpty, !typeRaw.isEmpty, categoryRaw != typeRaw {
            originalType = "\(categoryRaw) / \(typeRaw)"
        } else {
            originalType = [categoryRaw, typeRaw].first(where: { !$0.isEmpty }) ?? "未指定"
        }
        return LibraryWordMigrationCandidate(
            record: record,
            category: category,
            originalType: originalType,
            status: category == nil ? "待确认类别" : "待迁移正文"
        )
    }

    static func candidates(from records: [StoredRecord]) -> [LibraryWordMigrationCandidate] {
        records.compactMap(candidate(for:))
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == "待确认类别" }
                let lhsDate = lhs.record.updatedAt ?? lhs.record.createdAt ?? .distantPast
                let rhsDate = rhs.record.updatedAt ?? rhs.record.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.id < rhs.id
            }
    }

    static func originalPreview(in object: [String: Any], sourceCategory: WordCategory?) -> String {
        if let sourceCategory {
            return LibraryComparisonDocumentProjection.wordContent(in: object, category: sourceCategory)
        }
        let hasComparisonFields = ["comparisonDocument", "commonMeaning", "compareWords", "idiomComparisonContext", "compareNote", "coreDifference"]
            .contains { object[$0] != nil }
        return LibraryComparisonDocumentProjection.wordContent(
            in: object,
            category: hasComparisonFields ? .wordComparison : .wordDefinition
        )
    }

    static func initialNewBody(in object: [String: Any], target: WordCategory) -> String {
        LibraryComparisonDocumentProjection.wordContent(in: object, category: target)
    }
}

enum LibraryWordMigrationError: LocalizedError {
    case recordChanged
    case noLongerNeedsMigration
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .recordChanged: "这条词语已在其他位置更改，未覆盖原内容。请返回列表后重新打开。"
        case .noLongerNeedsMigration: "这条词语已完成迁移或不再符合迁移条件。"
        case .invalidRecord: "词语内容无法读取，未写入任何更改。"
        }
    }
}

struct LibraryWordMigrationListView: View {
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "words" }) private var records: [StoredRecord]

    private var candidates: [LibraryWordMigrationCandidate] {
        LibraryWordMigrationPolicy.candidates(from: records)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("迁移旧词语")
                    .font(.system(size: 22, weight: .semibold))
                Text("逐条确认类别和新版正文。迁移会更新原记录，不会复制词条。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if candidates.isEmpty {
                    NativeStatusCard(
                        title: "没有待迁移词语",
                        detail: "当前词语库中的正文和类别都已是新版格式。",
                        systemImage: "checkmark.circle",
                        color: AppTheme.success,
                        minimumHeight: 132
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { candidate in
                            NavigationLink(value: LibraryRoute.wordMigrationDetail(recordID: candidate.id)) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(candidate.title.isEmpty ? "未命名词语" : candidate.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text("原类型：\(candidate.originalType)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Text(candidate.status)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(candidate.category == nil ? AppTheme.warning : AppTheme.accent)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.7)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("迁移旧词语")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryWordMigrationDetailView: View {
    let record: StoredRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCategory: WordCategory?
    @State private var bodyDraft = ""
    @State private var hasEditedBody = false
    @State private var isEditingBody = false
    @State private var isSaving = false
    @State private var isCheckingBodySafety = false
    @State private var isBodySafeToEdit = false
    @State private var bodySafetyCheckID = UUID()
    @State private var errorMessage: String?
    @State private var didInitialize = false
    @State private var originalPayload = Data()
    @State private var originalUpdatedAt: Date?

    private let categoryOrder: [WordCategory] = [.wordDefinition, .idiomDefinition, .wordComparison, .idiomComparison]
    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var candidate: LibraryWordMigrationCandidate? { LibraryWordMigrationPolicy.candidate(for: record) }
    private var originalPreview: String {
        LibraryWordMigrationPolicy.originalPreview(in: object, sourceCategory: candidate?.category)
    }
    private var bodyBinding: Binding<String> {
        Binding(
            get: { bodyDraft },
            set: { bodyDraft = $0; hasEditedBody = true }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let candidate {
                    Text(candidate.title.isEmpty ? "未命名词语" : candidate.title)
                        .font(.system(size: 21, weight: .semibold))
                        .textSelection(.enabled)
                    Text("原类型：\(candidate.originalType) · \(candidate.status)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("目标类别")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(categoryOrder) { category in
                            Button {
                                select(category)
                            } label: {
                                HStack {
                                    Text(LibraryWordMigrationPolicy.categoryMenuTitle(category))
                                    Spacer(minLength: 20)
                                    if selectedCategory == category {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedCategory.map(LibraryWordMigrationPolicy.categoryMenuTitle) ?? "请选择目标类别")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10), lineWidth: 0.7))
                    }
                    .accessibilityIdentifier("word-migration-category")
                }

                migrationContentSection(title: "原内容预览", html: originalPreview)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("新版正文")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if selectedCategory != nil {
                            Button(isEditingBody ? "完成编辑" : "编辑正文") {
                                guard isBodySafeToEdit else {
                                    errorMessage = "这段内容无法确认可无损编辑，原记录已保留。可重新检查，或取消本次迁移。"
                                    return
                                }
                                isEditingBody.toggle()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.accent)
                            .disabled(isCheckingBodySafety || !isBodySafeToEdit)
                        }
                    }
                    if selectedCategory == nil {
                        Text("未知或冲突的原类别需要你手动选择，系统不会自动归类。")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.warning)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    } else if isEditingBody {
                        NativeRichTextEditor(
                            html: bodyBinding,
                            minHeight: 240,
                            documentStyle: true,
                            tableAppearance: .libraryContent
                        )
                        .padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        NativeRichTextDisplay(
                            html: bodyDraft,
                            minHeight: 72,
                            tableAppearance: .libraryContent
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if selectedCategory != nil, !isCheckingBodySafety, !isBodySafeToEdit {
                        HStack {
                            Text("正文无法安全编辑，迁移已阻止；原记录未修改。")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.warning)
                            Spacer(minLength: 4)
                            Button("重新检查") { checkBodySafety(for: bodyDraft) }
                                .font(.system(size: 11, weight: .medium))
                                .buttonStyle(.plain)
                        }
                    } else if isCheckingBodySafety {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text("正在检查正文是否可无损编辑…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    saveMigration()
                } label: {
                    Text(isSaving ? "正在迁移…" : "确认迁移")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(.white)
                        .background(selectedCategory == nil || candidate == nil || !isBodySafeToEdit || isCheckingBodySafety ? Color.gray : AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || selectedCategory == nil || candidate == nil || !isBodySafeToEdit || isCheckingBodySafety)
                .accessibilityIdentifier("word-migration-confirm")
            }
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("迁移词语")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            originalPayload = record.payload
            originalUpdatedAt = record.updatedAt
            selectedCategory = candidate?.category
            bodyDraft = selectedCategory.map { LibraryWordMigrationPolicy.initialNewBody(in: object, target: $0) } ?? ""
            if selectedCategory != nil { checkBodySafety(for: bodyDraft) }
        }
        .alert("迁移未完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func migrationContentSection(title: String, html: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            NativeRichTextDisplay(html: html, minHeight: 72, tableAppearance: .libraryContent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func select(_ category: WordCategory) {
        selectedCategory = category
        if !hasEditedBody {
            bodyDraft = LibraryWordMigrationPolicy.initialNewBody(in: object, target: category)
        }
        checkBodySafety(for: bodyDraft)
    }

    private func checkBodySafety(for html: String) {
        let checkID = UUID()
        bodySafetyCheckID = checkID
        guard !html.isEmpty else {
            isCheckingBodySafety = false
            isBodySafeToEdit = true
            return
        }
        isCheckingBodySafety = true
        isBodySafeToEdit = false
        Task { @MainActor in
            await Task.yield()
            let rendered = NativeRichTextDisplayRenderer.render(html, tableAppearance: .libraryContent)
            let isSafe = NativeRichTextDisplayRenderer.supportsNativeEditingSnapshot(
                sourceHTML: html,
                rendered: rendered
            )
            guard bodySafetyCheckID == checkID else { return }
            guard record.payload == originalPayload, record.updatedAt == originalUpdatedAt else {
                isCheckingBodySafety = false
                isBodySafeToEdit = false
                errorMessage = LibraryWordMigrationError.recordChanged.localizedDescription
                return
            }
            isBodySafeToEdit = isSafe
            isCheckingBodySafety = false
        }
    }

    private func saveMigration() {
        guard !isSaving, isBodySafeToEdit, !isCheckingBodySafety, let selectedCategory else { return }
        isSaving = true
        do {
            try LibraryRecordRepository.migrateLegacyWord(
                record: record,
                expectedPayload: originalPayload,
                expectedUpdatedAt: originalUpdatedAt,
                targetCategory: selectedCategory,
                body: bodyDraft,
                context: modelContext
            )
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
