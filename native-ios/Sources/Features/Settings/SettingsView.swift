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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var body: some View {
        List {
            Section("数据迁移") {
                Button { showImporter = true } label: {
                    Label("导入 Web 备份 JSON", systemImage: "square.and.arrow.down")
                }
                Button { prepareExport() } label: {
                    Label("导出 Web 兼容备份", systemImage: "square.and.arrow.up")
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

            Section("笔记") {
                NavigationLink {
                    NoteTypeManagerView()
                } label: {
                    Label("笔记类型", systemImage: "tag")
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importer.importBackup(from: url, into: modelContext)
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
                exportMessage = "备份已保存，可由 Web 版重新导入"
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
}
