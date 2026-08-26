import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.apiClient) private var apiClient
    @Query private var records: [StoredRecord]
    @StateObject private var importer = LegacyBackupImportCoordinator()
    @State private var showImporter = false
    @State private var healthMessage = "尚未检查"

    var body: some View {
        List {
            Section("数据迁移") {
                Button {
                    showImporter = true
                } label: {
                    Label("导入 Web 备份 JSON", systemImage: "square.and.arrow.down")
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
            }

            Section("原生重写") {
                LabeledContent("版本", value: "8.26.4")
                LabeledContent("基线", value: "Web v8.25.3")
                LabeledContent("界面", value: "SwiftUI / UIKit")
                LabeledContent("WebView", value: "未使用")
                Text("当前为第一阶段测试包：导航、数据兼容层和备份导入可测试；业务编辑功能按验收矩阵分阶段开放。")
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
    }
}
