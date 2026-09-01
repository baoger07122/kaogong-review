import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.apiClient) private var apiClient
    @Query private var records: [StoredRecord]
    @StateObject private var importer = LegacyBackupImportCoordinator()
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument: BackupJSONDocument?
    @State private var exportMessage: String?
    @State private var healthMessage = "尚未检查"
    @State private var pendingImportURL: URL?
    @AppStorage("native.lastLocalBackupAt") private var lastLocalBackupAt = 0.0

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var body: some View {
        List {
            Section("本地数据与备份") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.icloud")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("备份到文件或 iCloud Drive")
                                .font(AppTheme.cardTitleFont)
                            Text(lastBackupText)
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button("立即备份") { prepareExport() }
                        .buttonStyle(NativePrimaryButtonStyle())
                        .frame(maxWidth: 210)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)

                Button { showImporter = true } label: {
                    Label("导入备份并恢复", systemImage: "square.and.arrow.down")
                }
                HStack {
                    Label("原生数据库记录", systemImage: "externaldrive")
                    Spacer()
                    Text("\(records.count)").foregroundStyle(.secondary)
                }

                if importer.isImporting {
                    HStack { ProgressView(); Text("正在校验并导入…") }
                }
                if let summary = importer.summary {
                    Label(summary.message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let error = importer.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if let exportMessage {
                    Text(exportMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("云端 API") {
                Button("检查 Render API") {
                    Task {
                        do {
                            _ = try await apiClient.health()
                            healthMessage = "连接正常"
                        } catch {
                            healthMessage = "连接失败：\(error.localizedDescription)"
                        }
                    }
                }
                LabeledContent("状态", value: healthMessage)
                NavigationLink {
                    CloudSyncView()
                } label: {
                    Label("登录与手动同步", systemImage: "icloud")
                }
            }

            Section("笔记与便签") {
                NavigationLink {
                    NoteTypeManagerView()
                } label: {
                    Label("笔记类型", systemImage: "tag")
                }
                NavigationLink {
                    StickyTagManagerView()
                } label: {
                    Label("便签标签", systemImage: "tag.square")
                }
            }

            Section("原生重写") {
                LabeledContent("版本", value: appVersion)
                LabeledContent("基线", value: "Web v8.25.3")
                LabeledContent("界面", value: "SwiftUI / UIKit")
                LabeledContent("WebView", value: "未使用")
                Text("原生功能正在按验收矩阵逐模块重写；已开发项目仍需真机逐项验收。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .overlay {
            if pendingImportURL != nil {
                NativeDeleteDialog(
                    title: "导入数据",
                    message: "导入将覆盖本机现有的错题、笔记、便签、套卷、待办和设置。建议先导出当前备份，确定继续？",
                    onDelete: confirmImport,
                    onCancel: { pendingImportURL = nil },
                    actionTitle: "确认导入"
                )
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingImportURL = url
            case .failure(let error):
                importer.reportError(error)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "考公备考系统-backup.json"
        ) { result in
            switch result {
            case .success:
                lastLocalBackupAt = Date.now.timeIntervalSince1970
                exportMessage = "备份已保存，可由原生版或 Web 版重新导入"
            case .failure(let error):
                exportMessage = "导出失败：\(error.localizedDescription)"
            }
            exportDocument = nil
        }
    }

    private func prepareExport() {
        do {
            exportDocument = try LegacyBackupExporter.makeDocument(records: records)
            exportMessage = nil
            showExporter = true
        } catch {
            exportMessage = "无法生成备份：\(error.localizedDescription)"
        }
    }

    private func confirmImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        importer.importBackup(from: url, into: modelContext)
    }

    private var lastBackupText: String {
        guard lastLocalBackupAt > 0 else {
            return "固定文件名：考公备考系统-backup.json · 暂无备份记录"
        }
        let value = Date(timeIntervalSince1970: lastLocalBackupAt)
        return "上次备份：\(value.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))"
    }
}
