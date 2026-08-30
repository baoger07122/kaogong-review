import SwiftData
import SwiftUI

struct CloudSyncView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @StateObject private var coordinator = CloudSyncCoordinator()
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            if coordinator.isLoggedIn {
                Section("账户") {
                    LabeledContent("已登录", value: coordinator.email)
                    if let lastSync = coordinator.lastSync {
                        LabeledContent("上次同步", value: lastSync.formatted(date: .numeric, time: .shortened))
                    } else {
                        LabeledContent("上次同步", value: "尚未同步")
                    }
                    Button("退出登录", role: .destructive) { coordinator.logout() }
                }

                Section("手动同步") {
                    Button {
                        Task { await coordinator.synchronize(records: records, context: modelContext, api: apiClient) }
                    } label: {
                        Label("立即安全合并", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    .disabled(coordinator.isWorking)

                    Text("同步错题、笔记、套卷、待办、复习记录和词语库。先比较更新时间，再决定上传或下载；云端缺少的记录不会删除本地数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("便签、倒数日、标签和其他设置尚未进入服务端云集合，请继续使用完整 JSON 备份保存。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else {
                Section("登录云同步") {
                    TextField("邮箱", text: $email)
                        .font(AppTheme.inputFont)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("密码", text: $password)
                        .font(AppTheme.inputFont)
                    HStack {
                        Button("登录") {
                            Task { await coordinator.login(email: email, password: password, api: apiClient) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("注册") {
                            Task { await coordinator.register(email: email, password: password, api: apiClient) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(coordinator.isWorking)
                }
            }

            if coordinator.isWorking {
                Section { HStack { ProgressView(); Text(coordinator.message) } }
            } else if !coordinator.message.isEmpty {
                Section("结果") { Text(coordinator.message) }
            }
        }
        .navigationTitle("云同步")
        .onAppear { if email.isEmpty { email = coordinator.email } }
    }
}
