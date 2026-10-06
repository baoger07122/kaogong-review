import SwiftData
import SwiftUI

struct QuestionBankBatchDetailView: View {
    @Query private var batches: [QuestionBankBatchRecord]
    @Query private var sources: [QuestionBankBatchSourceRecord]
    @Query private var materialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var questionLinks: [QuestionBankBatchQuestionLinkRecord]
    @Query private var records: [QuestionBankRecord]

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
            let left = records.first { row in
                row.paperID == leftLink.sourcePaperID && row.kind == QuestionBankRepository.questionKind
                    && row.stableID == leftLink.sourceQuestionID
            }
            let right = records.first { row in
                row.paperID == rightLink.sourcePaperID && row.kind == QuestionBankRepository.questionKind
                    && row.stableID == rightLink.sourceQuestionID
            }
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
                    if let row = questionRecord(for: link.sourcePaperID, questionID: link.sourceQuestionID),
                       let question = row.decoded(QuestionBankQuestion.self) {
                        NavigationLink {
                            questionDestination(row)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第\(question.number)题 · \(question.stem)")
                                    .font(AppTheme.bodyFont).foregroundStyle(.primary).lineLimit(3)
                                Text(paperTitle(row.paperID)).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
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
                            Text(questionRecord(for: link.sourcePaperID, questionID: link.sourceQuestionID)?
                                .decoded(QuestionBankQuestion.self).map { "第\($0.number)题 · \($0.stem)" }
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
    }

    private func familyTitle(_ value: String) -> String {
        QuestionBankBatchFamily(rawValue: value)?.title ?? value
    }

    private func paperTitle(_ paperID: String) -> String {
        records.first { $0.paperID == paperID && $0.kind == QuestionBankRepository.paperKind }?
            .decoded(QuestionBankPaper.self)?.title ?? paperID
    }

    private func questionRecord(for paperID: String, questionID: String) -> QuestionBankRecord? {
        records.first {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind && $0.stableID == questionID
        }
    }

    @ViewBuilder
    private func paperDestination(_ paperID: String, questionID: String?) -> some View {
        if let row = records.first(where: {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind
                && (questionID == nil || $0.stableID == questionID)
        }), let moduleID = row.moduleID {
            QuestionBankModuleView(paperID: paperID, moduleID: moduleID,
                initialQuestionNumber: String(row.questionNumber ?? 1))
        } else {
            ContentUnavailableView("没有可打开的题目", systemImage: "doc.text.magnifyingglass")
        }
    }

    @ViewBuilder
    private func questionDestination(_ row: QuestionBankRecord) -> some View {
        if let moduleID = row.moduleID {
            QuestionBankModuleView(paperID: row.paperID, moduleID: moduleID,
                initialQuestionNumber: String(row.questionNumber ?? 1))
        } else {
            ContentUnavailableView("题目缺少模块关联", systemImage: "exclamationmark.triangle")
        }
    }
}
