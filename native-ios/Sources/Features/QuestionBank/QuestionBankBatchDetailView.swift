import SwiftData
import SwiftUI

struct QuestionBankBatchDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var batches: [QuestionBankBatchRecord]
    @Query private var sources: [QuestionBankBatchSourceRecord]
    @Query private var materialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var questionLinks: [QuestionBankBatchQuestionLinkRecord]
    @State private var questionPreviewsByCompoundID: [String: QuestionBankBatchQuestionPreview] = [:]
    @State private var paperTitlesByID: [String: String] = [:]
    @State private var loadError: String?

    let batchID: String

    private var batch: QuestionBankBatchRecord? { batches.first { $0.identityKey == batchID } }
    private var batchSources: [QuestionBankBatchSourceRecord] {
        sources.filter { $0.batchID == batchID }.sorted { $0.importedAt < $1.importedAt }
    }
    private var uniqueQuestions: [QuestionBankBatchQuestionLinkRecord] {
        questionLinks.filter {
            $0.batchID == batchID && $0.status == QuestionBankBatchLinkStatus.unique.rawValue
                && $0.canonicalPaperID == $0.sourcePaperID && $0.canonicalQuestionID == $0.sourceQuestionID
        }.sorted { leftLink, rightLink in
            let left = questionPreviewsByCompoundID[questionCompoundID(leftLink)]
            let right = questionPreviewsByCompoundID[questionCompoundID(rightLink)]
            return (left?.year ?? 0, left?.questionNumber ?? 0) < (right?.year ?? 0, right?.questionNumber ?? 0)
        }
    }
    private var pendingQuestions: [QuestionBankBatchQuestionLinkRecord] {
        questionLinks.filter {
            $0.batchID == batchID && (QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending ?? false)
        }
    }

    var body: some View {
        List {
            if let batch {
                Section("批次概况") {
                    LabeledContent("类别 / 年份", value: "\(familyTitle(batch.family)) · \(batch.year)")
                    LabeledContent("来源", value: "\(batch.sourceCount) 个")
                    LabeledContent("唯一材料", value: "\(batch.uniqueMaterialCount) 份")
                    LabeledContent("唯一题目", value: "\(batch.uniqueQuestionCount) 道")
                    LabeledContent("待核", value: "\(batch.pendingCount) 条")
                }
            }
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.danger)
                    Button("重试") { Task { await loadBatchPreviews() } }
                }
            }
            Section {
                DisclosureGroup("来源明细（\(batchSources.count)）") {
                    ForEach(batchSources, id: \.sourceID) { source in
                        let sourceMetadata = try? JSONDecoder().decode(
                            QuestionBankBatchMetadata.self, from: source.metadataPayload
                        )
                        let provinces = sourceMetadata?.sourceProvinces?.map(\.name).joined(separator: "、") ?? ""
                        NavigationLink {
                            paperDestination(source.paperID, questionID: nil)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(paperTitle(source.paperID)).font(AppTheme.bodyFont)
                                Text("\(source.sourceID) · 修订 \(source.revision) · \(source.sourceQuestionCount) 题 · 新唯一 \(source.uniqueQuestionCount) · 重复 \(source.duplicateQuestionCount) · 待核 \(source.pendingQuestionCount)")
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text("材料 \(source.sourceMaterialCount) 份 · 新唯一 \(source.uniqueMaterialCount) · 重复 \(source.duplicateMaterialCount) · 待核 \(source.pendingMaterialCount)")
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).lineLimit(2)
                                Text("导入 \(source.importedAt.formatted(date: .abbreviated, time: .shortened)) · SHA-256 \(source.sourceSHA256.prefix(12))\(provinces.isEmpty ? "" : " · 来源：\(provinces)")")
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.tertiary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            Section("批次唯一题目（\(uniqueQuestions.count)）") {
                ForEach(uniqueQuestions, id: \.compoundID) { link in
                    if let question = questionPreviewsByCompoundID[questionCompoundID(link)] {
                        NavigationLink {
                            questionDestination(question)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第\(question.questionNumber)题 · \(question.stem)")
                                    .font(AppTheme.bodyFont).foregroundStyle(.primary).lineLimit(3)
                                Text(paperTitle(question.paperID)).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("待人工核对（\(pendingQuestions.count)）") {
                if pendingQuestions.isEmpty {
                    Text("没有待核题目").foregroundStyle(.secondary)
                } else {
                    ForEach(pendingQuestions, id: \.compoundID) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(questionPreviewsByCompoundID[questionCompoundID(link)]
                                .map { "第\($0.questionNumber)题 · \($0.stem)" }
                                ?? "来源题目")
                                .font(AppTheme.bodyFont)
                            Text(link.pendingReason ?? "精确匹配未能确认；来源记录仍保留。")
                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                            Text(paperTitle(link.sourcePaperID)).font(AppTheme.auxiliaryFont).foregroundStyle(.tertiary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !materialLinks.filter({ $0.batchID == batchID && QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending == true }).isEmpty {
                Section("待人工核对的材料") {
                    ForEach(materialLinks.filter {
                        $0.batchID == batchID && QuestionBankBatchLinkStatus(rawValue: $0.status)?.isPending == true
                    }, id: \.compoundID) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("材料 \(link.sourceMaterialID)").font(AppTheme.bodyFont)
                            Text(link.pendingReason ?? "精确匹配未能确认；来源材料仍保留。")
                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(batch?.displayName ?? "跨卷批次")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: batchID + "|" + batchQuestionKey) { await loadBatchPreviews() }
    }

    private func familyTitle(_ value: String) -> String {
        QuestionBankBatchFamily(rawValue: value)?.title ?? value
    }

    private var batchQuestionKey: String {
        questionLinks.filter { $0.batchID == batchID }
            .map(\.compoundID).sorted().joined(separator: "|")
    }

    private func questionCompoundID(_ link: QuestionBankBatchQuestionLinkRecord) -> String {
        "\(link.sourcePaperID)::\(QuestionBankRepository.questionKind)::\(link.sourceQuestionID)"
    }

    private func paperTitle(_ paperID: String) -> String {
        paperTitlesByID[paperID] ?? paperID
    }

    @ViewBuilder
    private func paperDestination(_ paperID: String, questionID: String?) -> some View {
        if let row = questionPreviewsByCompoundID.values
            .filter({ $0.paperID == paperID && (questionID == nil || $0.questionID == questionID) })
            .sorted(by: { $0.questionNumber < $1.questionNumber }).first {
            questionDestination(row)
        } else {
            ContentUnavailableView("批次中没有可打开的题目", systemImage: "doc.text.magnifyingglass")
        }
    }

    @ViewBuilder
    private func questionDestination(_ row: QuestionBankBatchQuestionPreview) -> some View {
        if row.moduleID.isEmpty {
            ContentUnavailableView("题目缺少模块关联", systemImage: "exclamationmark.triangle")
        } else {
            QuestionBankModuleView(paperID: row.paperID, moduleID: row.moduleID,
                initialQuestionNumber: String(row.questionNumber))
        }
    }

    @MainActor
    private func loadBatchPreviews() async {
        let links = questionLinks.filter { $0.batchID == batchID }
        let questionIDs = Set(links.map(questionCompoundID))
        let paperIDs = Set(links.map(\.sourcePaperID).filter { !$0.isEmpty })
            .union(batchSources.map(\.paperID).filter { !$0.isEmpty })
        guard !questionIDs.isEmpty || !paperIDs.isEmpty else {
            questionPreviewsByCompoundID = [:]
            paperTitlesByID = [:]
            loadError = nil
            return
        }
        do {
            let snapshot = try await QuestionBankBatchDetailDataService.load(
                container: modelContext.container,
                questionCompoundIDs: questionIDs,
                paperIDs: paperIDs
            )
            guard !Task.isCancelled else { return }
            questionPreviewsByCompoundID = snapshot.questionsByCompoundID
            paperTitlesByID = snapshot.paperTitlesByID
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct QuestionBankBatchQuestionPreview: Sendable {
    let paperID: String
    let questionID: String
    let moduleID: String
    let questionNumber: Int
    let year: Int
    let stem: String
}

private struct QuestionBankBatchDetailSnapshot: Sendable {
    let questionsByCompoundID: [String: QuestionBankBatchQuestionPreview]
    let paperTitlesByID: [String: String]
}

private enum QuestionBankBatchDetailDataService {
    static func load(
        container: ModelContainer,
        questionCompoundIDs: Set<String>,
        paperIDs: Set<String>
    ) async throws -> QuestionBankBatchDetailSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let questionKind = QuestionBankRepository.questionKind
            var previews: [String: QuestionBankBatchQuestionPreview] = [:]
            let ids = questionCompoundIDs.sorted()
            for start in stride(from: 0, to: ids.count, by: 128) {
                try Task.checkCancellation()
                let end = min(start + 128, ids.count)
                let pageIDs = Array(ids[start..<end])
                let predicate = #Predicate<QuestionBankRecord> {
                    $0.kind == questionKind && pageIDs.contains($0.compoundID)
                }
                var descriptor = FetchDescriptor<QuestionBankRecord>(predicate: predicate)
                descriptor.fetchLimit = pageIDs.count
                for record in try context.fetch(descriptor) {
                    guard let question = record.decoded(QuestionBankQuestion.self) else { continue }
                    previews[record.compoundID] = QuestionBankBatchQuestionPreview(
                        paperID: record.paperID,
                        questionID: record.stableID,
                        moduleID: record.moduleID ?? question.moduleID,
                        questionNumber: record.questionNumber ?? question.number,
                        year: record.year ?? 0,
                        stem: question.stem
                    )
                }
            }

            let paperKind = QuestionBankRepository.paperKind
            var titles: [String: String] = [:]
            let orderedPapers = paperIDs.sorted()
            for start in stride(from: 0, to: orderedPapers.count, by: 128) {
                try Task.checkCancellation()
                let end = min(start + 128, orderedPapers.count)
                let pageIDs = Array(orderedPapers[start..<end])
                let predicate = #Predicate<QuestionBankRecord> {
                    $0.kind == paperKind && pageIDs.contains($0.paperID)
                }
                var descriptor = FetchDescriptor<QuestionBankRecord>(predicate: predicate)
                descriptor.fetchLimit = pageIDs.count
                for record in try context.fetch(descriptor) {
                    titles[record.paperID] = record.title
                }
            }
            return QuestionBankBatchDetailSnapshot(
                questionsByCompoundID: previews,
                paperTitlesByID: titles
            )
        }.value
    }
}
