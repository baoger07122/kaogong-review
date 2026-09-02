import Combine
import Foundation
import SwiftData

struct CloudSyncSummary: Equatable {
    let uploaded: Int
    let downloaded: Int

    var message: String { "同步完成：上传 \(uploaded) 条，下载 \(downloaded) 条" }
}

@MainActor
final class CloudSyncCoordinator: ObservableObject {
    static let supportedCollections = ["errors", "notes", "exams", "todos", "subject_reviews", "words"]

    @Published private(set) var email = ""
    @Published private(set) var isWorking = false
    @Published private(set) var message = ""
    @Published private(set) var lastSync: Date?

    private let tokenStore = KeychainTokenStore()
    private let emailKey = "native.cloud.email"
    private let lastSyncKey = "native.cloud.lastSync"

    init() {
        email = UserDefaults.standard.string(forKey: emailKey) ?? ""
        let timestamp = UserDefaults.standard.double(forKey: lastSyncKey)
        lastSync = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    var isLoggedIn: Bool { (try? tokenStore.read()) != nil }

    func login(email: String, password: String, api: APIClient) async {
        await authenticate(email: email, password: password, api: api, registering: false)
    }

    func register(email: String, password: String, api: APIClient) async {
        await authenticate(email: email, password: password, api: api, registering: true)
    }

    func logout() {
        do {
            try tokenStore.delete()
            email = ""
            message = "已退出云同步"
            UserDefaults.standard.removeObject(forKey: emailKey)
        } catch {
            message = "退出失败：\(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    func synchronize(records: [StoredRecord], context: ModelContext, api: APIClient) async {
        guard let token = try? tokenStore.read() else {
            message = "请先登录"
            return
        }
        isWorking = true
        message = "正在安全合并…"
        defer { isWorking = false }

        do {
            var uploaded = 0
            var downloaded = 0
            for collection in Self.supportedCollections {
                let remoteValues = try await api.fetchCollection(collection, token: token)
                let localRecords = records.filter { $0.collection == collection }
                var remoteByID: [String: JSONValue] = [:]
                for value in remoteValues {
                    if let id = recordID(in: value) { remoteByID[id] = value }
                }

                for local in localRecords {
                    let localValue = try JSONDecoder().decode(JSONValue.self, from: local.payload)
                    guard let remote = remoteByID.removeValue(forKey: local.recordID) else {
                        try await api.upsert(localValue, collection: collection, token: token)
                        uploaded += 1
                        continue
                    }

                    if timestamp(of: remote) > timestamp(of: localValue) {
                        try apply(remote, collection: collection, existing: local, context: context)
                        downloaded += 1
                    } else if timestamp(of: localValue) > timestamp(of: remote) {
                        try await api.upsert(localValue, collection: collection, token: token)
                        uploaded += 1
                    }
                }

                for remote in remoteByID.values {
                    try apply(remote, collection: collection, existing: nil, context: context)
                    downloaded += 1
                }
            }
            try context.save()
            let now = Date.now
            lastSync = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSyncKey)
            message = CloudSyncSummary(uploaded: uploaded, downloaded: downloaded).message
        } catch {
            context.rollback()
            message = "同步失败：\(error.localizedDescription)"
        }
    }

    private func authenticate(email: String, password: String, api: APIClient, registering: Bool) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            message = "请输入邮箱和密码"
            return
        }
        isWorking = true
        message = registering ? "正在注册…" : "正在登录…"
        defer { isWorking = false }
        do {
            let session: AuthSession
            if registering {
                session = try await api.register(email: cleanEmail, password: password)
            } else {
                session = try await api.login(email: cleanEmail, password: password)
            }
            try tokenStore.save(session.token)
            self.email = session.email
            UserDefaults.standard.set(session.email, forKey: emailKey)
            message = registering ? "注册成功" : "登录成功"
            objectWillChange.send()
        } catch {
            message = "操作失败：\(error.localizedDescription)"
        }
    }

    private func recordID(in value: JSONValue) -> String? {
        value.objectValue?["id"]?.stringValue
    }

    private func timestamp(of value: JSONValue) -> Date {
        guard let object = value.objectValue else { return .distantPast }
        let text = object["updatedAt"]?.stringValue ?? object["createdAt"]?.stringValue
        return parseDate(text) ?? .distantPast
    }

    private func apply(
        _ value: JSONValue,
        collection: String,
        existing: StoredRecord?,
        context: ModelContext
    ) throws {
        guard let id = recordID(in: value), let object = value.objectValue else { return }
        let payload = try JSONEncoder().encode(value)
        let subject = object["subject"]?.stringValue
        let module = object["module"]?.stringValue
        let createdAt = parseDate(object["createdAt"]?.stringValue)
        let updatedAt = parseDate(object["updatedAt"]?.stringValue)
        if let existing {
            existing.replacePayload(payload)
            existing.subject = subject
            existing.module = module
            existing.createdAt = createdAt
            existing.updatedAt = updatedAt
        } else {
            context.insert(StoredRecord(
                collection: collection,
                recordID: id,
                payload: payload,
                subject: subject,
                module: module,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
    }

    private func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
