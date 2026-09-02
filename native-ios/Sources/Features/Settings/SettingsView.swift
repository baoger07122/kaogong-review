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
    @State private var isStagingImport = false
    @State private var integrityReport: LocalBackupIntegrityReport?
    @State private var integrityError: String?
    @State private var restoreSafetyMessage: String?
    @State private var restoreSafetyError: String?
    @State private var isCheckingUpdate = false
    @State private var updateMessage: String?
    @State private var showClearData = false
    @State private var clearMessage: String?
    @AppStorage("native.lastLocalBackupAt") private var lastLocalBackupAt = 0.0

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置").font(AppTheme.pageTitleFont)

                settingsSection("本地数据与备份") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.badge.icloud")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("备份到文件或 iCloud Drive").font(AppTheme.cardTitleFont)
                                Text(lastBackupText).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("立即备份", action: prepareExport)
                                .font(AppTheme.actionFont)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 36)
                                .background(AppTheme.accent, in: Capsule())
                                .buttonStyle(NativePressButtonStyle())
                        }
                    }
                    .padding(14)
                    .background(
                        LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1), Color(red: 0.96, green: 0.98, blue: 1)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    settingsDivider
                    settingsActionRow("导入备份并恢复", image: "square.and.arrow.down") { showImporter = true }
                    settingsDivider
                    settingsActionRow("检查备份完整性", image: "checkmark.shield", action: checkBackupIntegrity)
                    settingsDivider
                    settingsActionRow("检查恢复安全性", image: "arrow.uturn.backward.circle", action: checkRestoreSafety)
                    settingsDivider
                    settingsActionRow("清除全部本地数据", image: "trash", color: AppTheme.danger, destructive: true) { showClearData = true }
                    settingsDivider
                    settingsValueRow("原生数据库记录", value: "\(records.count)", image: "externaldrive")
                    backupStatusMessages
                }

                settingsSection("云端 API") {
                    settingsActionRow("检查 Render API", image: "network") { checkRenderAPI() }
                    settingsDivider
                    settingsValueRow("连接状态", value: healthMessage, image: "wave.3.right")
                    settingsDivider
                    NavigationLink { CloudSyncView() } label: {
                        settingsNavigationRow("登录与手动同步", image: "icloud")
                    }.buttonStyle(.plain)
                }

                settingsSection("笔记与便签") {
                    NavigationLink { NoteTypeManagerView() } label: {
                        settingsNavigationRow("笔记类型", image: "tag")
                    }.buttonStyle(.plain)
                    settingsDivider
                    NavigationLink { StickyTagManagerView() } label: {
                        settingsNavigationRow("便签标签", image: "tag.square")
                    }.buttonStyle(.plain)
                }

                settingsSection("版本与更新") {
                    settingsValueRow("当前版本", value: "v\(appVersion)", image: "iphone.gen3")
                    settingsDivider
                    Button { Task { await checkNativeUpdate() } } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(AppTheme.accent).frame(width: 22)
                            Text("检查更新").font(AppTheme.inputFont)
                            Spacer()
                            if isCheckingUpdate { ProgressView().controlSize(.small) }
                            else { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
                        }
                        .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingUpdate)
                    if let updateMessage {
                        Text(updateMessage).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).padding(.leading, 33)
                    }
                    settingsDivider
                    settingsValueRow("Web 基线", value: "v8.25.3", image: "safari")
                    settingsDivider
                    settingsValueRow("原生界面", value: "SwiftUI / UIKit", image: "swift")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(AppTheme.groupedBackground)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if showClearData {
                NativeDeleteDialog(
                    title: "清除全部数据",
                    message: "将永久清除本机全部错题、笔记、便签、套卷、待办及设置，且无法恢复。建议先导出备份。",
                    onDelete: clearAllLocalData,
                    onCancel: { showClearData = false },
                    actionTitle: "清空"
                )
            }
        }
        .sheet(isPresented: $showImporter) {
            BackupDocumentPicker(
                onPick: { url in showImporter = false; stageImportFile(from: url) },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
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

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.055), lineWidth: 0.7) }
        }
    }

    private func settingsActionRow(
        _ title: String,
        image: String,
        color: Color = AppTheme.accent,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: image).foregroundStyle(color).frame(width: 22)
                Text(title).font(AppTheme.inputFont).foregroundStyle(destructive ? color : Color.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsNavigationRow(_ title: String, image: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: image).foregroundStyle(AppTheme.accent).frame(width: 22)
            Text(title).font(AppTheme.inputFont).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 42)
        .contentShape(Rectangle())
    }

    private func settingsValueRow(_ title: String, value: String, image: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: image).foregroundStyle(AppTheme.accent).frame(width: 22)
            Text(title).font(AppTheme.inputFont)
            Spacer()
            Text(value).font(AppTheme.inputFont).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(height: 42)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 33)
    }

    @ViewBuilder
    private var backupStatusMessages: some View {
        if isStagingImport { HStack { ProgressView(); Text("正在从 iCloud 读取备份…") }.font(AppTheme.auxiliaryFont) }
        if importer.isImporting { HStack { ProgressView(); Text("正在校验并导入…") }.font(AppTheme.auxiliaryFont) }
        if let summary = importer.summary { settingsStatus(summary.message, image: "checkmark.circle.fill", color: AppTheme.success) }
        if let error = importer.errorMessage { settingsStatus(error, image: "exclamationmark.triangle.fill", color: AppTheme.danger) }
        if let exportMessage { settingsStatus(exportMessage, image: "doc.badge.checkmark", color: .secondary) }
        if let integrityReport {
            settingsStatus(integrityReport.message, image: integrityReport.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", color: integrityReport.isComplete ? AppTheme.success : AppTheme.warning)
        }
        if let integrityError { settingsStatus("备份自检失败：\(integrityError)", image: "xmark.octagon.fill", color: AppTheme.danger) }
        if let restoreSafetyMessage { settingsStatus(restoreSafetyMessage, image: "checkmark.circle.fill", color: AppTheme.success) }
        if let restoreSafetyError { settingsStatus("恢复安全自检失败：\(restoreSafetyError)", image: "xmark.octagon.fill", color: AppTheme.danger) }
        if let clearMessage { settingsStatus(clearMessage, image: "checkmark.circle.fill", color: AppTheme.success) }
    }

    private func settingsStatus(_ message: String, image: String, color: Color) -> some View {
        Label(message, systemImage: image)
            .font(AppTheme.auxiliaryFont)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func checkRenderAPI() {
        Task {
            do {
                _ = try await apiClient.health()
                healthMessage = "连接正常"
            } catch {
                healthMessage = "连接失败：\(error.localizedDescription)"
            }
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

    private func stageImportFile(from sourceURL: URL) {
        isStagingImport = true
        importer.clearMessages()
        Task {
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
                isStagingImport = false
            }
            do {
                if sourceURL.isFileURL {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
                }
                let data = try await Task.detached(priority: .userInitiated) {
                    var coordinatedError: NSError?
                    var readResult: Result<Data, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinatedError) { coordinatedURL in
                        readResult = Result { try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe]) }
                    }
                    if let coordinatedError { throw coordinatedError }
                    guard let readResult else { throw CocoaError(.fileReadUnknown) }
                    return try readResult.get()
                }.value
                importer.importBackup(data: data, container: modelContext.container)
            } catch {
                importer.reportError(error)
            }
        }
    }

    private func checkBackupIntegrity() {
        do {
            integrityReport = try LocalBackupIntegrityChecker.check(records: records)
            integrityError = nil
        } catch {
            integrityReport = nil
            integrityError = error.localizedDescription
        }
    }

    private func checkRestoreSafety() {
        do {
            restoreSafetyMessage = try LocalRestoreSafetyChecker.check()
            restoreSafetyError = nil
        } catch {
            restoreSafetyMessage = nil
            restoreSafetyError = error.localizedDescription
        }
    }

    @MainActor
    private func checkNativeUpdate() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        do {
            switch try await NativeUpdateChecker.check(currentVersion: appVersion) {
            case .latest(let release):
                updateMessage = "当前已是最新可安装版本 v\(release.version)"
            case .available(let release):
                updateMessage = "发现可安装版本 v\(release.version)，请先备份数据，再前往 GitHub Releases 下载未签名 IPA"
            }
        } catch {
            updateMessage = "检查更新失败，请稍后重试"
        }
    }

    private func clearAllLocalData() {
        do {
            records.forEach(modelContext.delete)
            try modelContext.save()
            try? KeychainTokenStore().delete()
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("native.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            clearMessage = "本机数据已清除"
        } catch {
            modelContext.rollback()
            clearMessage = "清除失败：\(error.localizedDescription)"
        }
        showClearData = false
    }

    private var lastBackupText: String {
        guard lastLocalBackupAt > 0 else {
            return "固定文件名：考公备考系统-backup.json · 暂无备份记录"
        }
        let value = Date(timeIntervalSince1970: lastLocalBackupAt)
        return "上次备份：\(value.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))"
    }
}
