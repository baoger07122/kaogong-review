import SwiftUI
import SwiftData

struct QuestionBankBatchPackageImportPreview: View {
    let jobID: String
    let plan: QuestionBankBatchPackagePlan
    let preview: QuestionBankImportJobPreview
    let isImporting: Bool
    @Binding var importFailure: String?
    let onImport: (Set<QuestionBankBatchQuestionKey>, String) -> Void
    let onCancel: () -> Void

    @State private var confirmedNewQuestionKeys = Set<QuestionBankBatchQuestionKey>()

    private var packagePreview: QuestionBankBatchPackageUpdatePreview {
        preview.packageUpdatePreview ?? QuestionBankBatchPackageUpdatePreview(papers: [])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("包内试卷", value: "\(plan.paperPlans.count) 套")
                    LabeledContent("精确匹配", value: "\(packagePreview.updatablePaperCount) 套")
                    LabeledContent("待核对", value: "\(packagePreview.pendingPaperCount) 套")
                    LabeledContent("新增题目", value: "\(packagePreview.newQuestionCount) 道；默认不导入")
                    Text("写入前校验整包；确认后用单次数据库事务更新。仅按完全相同的 paperID / questionID 对齐，未匹配项会保留为待核，不按名称或题号猜测。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("已有题目的题干、选项、答案和解析会按包内内容更新；难题/复习标记、知识点、作答状态、涂鸦和笔记保留。写入前会按本次任务独立备份原记录及其图片资源，并校验备份清单。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("更新预览")
                }

                ForEach(packagePreview.papers) { paperStatus in
                    Section(paperStatus.title) {
                        if let conflict = paperStatus.conflict {
                            Label(conflict, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !paperStatus.targetFound {
                            Label("本机没有完全相同的 paperID；此卷暂不写入。", systemImage: "clock")
                                .foregroundStyle(.secondary)
                        } else {
                            LabeledContent("本机题目更新", value: "\(paperStatus.matchingQuestionCount) 道")
                            if let paperPlan = plan.paperPlans.first(where: { $0.paper?.id == paperStatus.paperID }),
                               !paperStatus.newQuestionKeys.isEmpty {
                                ForEach(paperStatus.newQuestionKeys) { key in
                                    let number = paperPlan.questions.first(where: { $0.id == key.questionID })?.number ?? 0
                                    Toggle(
                                        "新增第\(number)题（需明确确认）",
                                        isOn: questionConfirmationBinding(for: key)
                                    )
                                    .accessibilityIdentifier("question-bank-batch-confirm-\(key.id)")
                                }
                            } else {
                                Text("没有新增题目。")
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let importFailure {
                    Section("写入未完成") {
                        Label(importFailure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("批量更新预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel).disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "正在写入…" : "确认更新") {
                        onImport(confirmedNewQuestionKeys, preview.revisionToken)
                    }
                    .disabled(isImporting || !plan.canImport || packagePreview.updatablePaperCount == 0
                        || preview.packageUpdatePreview == nil)
                    .accessibilityIdentifier("question-bank-batch-confirm-update")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: preview.revisionToken) { _, _ in
            confirmedNewQuestionKeys.removeAll()
            importFailure = nil
        }
    }

    private func questionConfirmationBinding(
        for key: QuestionBankBatchQuestionKey
    ) -> Binding<Bool> {
        Binding(
            get: { confirmedNewQuestionKeys.contains(key) },
            set: { isConfirmed in
                if isConfirmed { confirmedNewQuestionKeys.insert(key) }
                else { confirmedNewQuestionKeys.remove(key) }
            }
        )
    }
}

struct QuestionBankBatchPackageManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let organizationStore: QuestionBankOrganizationStore

    @State private var exportedPackageURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var paperCount: Int?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("批量题库更新包", systemImage: "shippingbox")
                    .font(AppTheme.sectionTitleFont)
                Text("将本机已导入试卷与图片导出为一个 ZIP。更新包可从右上角“导入真题包”选择；系统会预览精确匹配结果，新题默认不导入，分组和本机作答标记会保持本机值。")
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("可导出试卷", value: paperCount.map { "\($0) 套" } ?? "待读取")
                    .font(AppTheme.bodyFont)
                Button {
                    exportPackage()
                } label: {
                    HStack(spacing: 9) {
                        if isExporting { ProgressView().controlSize(.small) }
                        Label(isExporting ? "正在打包…" : "生成批量 ZIP", systemImage: "square.and.arrow.up")
                    }
                    .font(AppTheme.bodyFont.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(NativePrimaryButtonStyle())
                .disabled(isExporting || paperCount == nil || paperCount == 0)
                .accessibilityIdentifier("question-bank-batch-export")

                if let exportedPackageURL {
                    ShareLink(
                        item: exportedPackageURL,
                        preview: SharePreview(exportedPackageURL.lastPathComponent)
                    ) {
                        Label("分享或存储 ZIP", systemImage: "square.and.arrow.up")
                            .font(AppTheme.bodyFont.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(NativeSecondaryButtonStyle())
                    .accessibilityIdentifier("question-bank-batch-share")
                }
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("批量导出与更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(isExporting)
                }
            }
        }
        .task {
            do {
                paperCount = try await QuestionBankCatalogService.paperSummaries(
                    in: modelContext.container
                ).count
            } catch {
                exportError = "题库目录暂不可用：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func exportPackage() {
        guard !isExporting else { return }
        isExporting = true
        exportedPackageURL = nil
        exportError = nil
        do {
            // Full payloads are read only after the user explicitly starts export.
            let records = try modelContext.fetch(FetchDescriptor<QuestionBankRecord>())
            let snapshot = try QuestionBankBatchPackageExporter.makeSnapshot(
                records: records,
                organizationStore: organizationStore
            )
            let worker = Task.detached(priority: .utility) {
                try QuestionBankBatchPackageExporter.export(snapshot: snapshot)
            }
            Task { @MainActor in
                defer { isExporting = false }
                do {
                    exportedPackageURL = try await worker.value
                } catch {
                    exportError = error.localizedDescription
                }
            }
        } catch {
            isExporting = false
            exportError = error.localizedDescription
        }
    }
}
