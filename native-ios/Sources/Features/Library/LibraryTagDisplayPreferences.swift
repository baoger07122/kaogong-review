import Combine
import Foundation
import SwiftUI
import SwiftData

struct LibraryTagDisplaySettings: Codable, Equatable {
    var showsKnowledgePointAttribute = true
    var showsMistakeTagAttribute = true
    var showsKnowledgePointCardHeader = true
    var showsMistakeTagCardHeader = false

    static let defaults = LibraryTagDisplaySettings()
}

final class LibraryTagDisplayPreferences: ObservableObject {
    static let shared = LibraryTagDisplayPreferences()

    private struct PersistedState: Codable {
        var settingsByScope: [String: LibraryTagDisplaySettings] = [:]
        var quantityTypeIDsByName: [String: String] = [:]
    }

    private static let storageKey = "native.library.tag-display-preferences.v1"
    @Published private(set) var revision = 0

    private let defaults: UserDefaults
    private var state: PersistedState

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = PersistedState()
        }
    }

    func settings(
        subject: String,
        module: String,
        typeID: String?,
        records: [StoredRecord],
        validTypeIDs: Set<String>? = nil,
        validQuantityTypes: Set<String>? = nil
    ) -> LibraryTagDisplaySettings {
        guard !module.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .defaults
        }

        if subject == "数量关系" {
            let availableTypes = validQuantityTypes ?? Set(QuantityQuestionTypeRepository.types(records: records))
            guard availableTypes.contains(module),
                  let typeID = state.quantityTypeIDsByName[quantityNameKey(module)] else {
                return .defaults
            }
            return state.settingsByScope["quantity-type:\(typeID)"] ?? .defaults
        }

        guard let typeSubject = LibraryErrorTypeSubject(rawValue: subject) else { return .defaults }
        let moduleSettings = state.settingsByScope[moduleKey(subject: subject, module: module)] ?? .defaults
        let normalizedTypeID = typeID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedTypeID, !normalizedTypeID.isEmpty else { return moduleSettings }

        let availableTypeIDs = validTypeIDs ?? Set(
            LibraryErrorTypeRepository.types(for: typeSubject, records: records)
                .filter { $0.isAvailable(in: module) }
                .map(\.id)
        )
        guard availableTypeIDs.contains(normalizedTypeID) else { return .defaults }
        return state.settingsByScope[typeKey(subject: subject, module: module, typeID: normalizedTypeID)] ?? moduleSettings
    }

    func update(
        _ settings: LibraryTagDisplaySettings,
        subject: String,
        module: String,
        typeID: String?,
        records: [StoredRecord]
    ) throws {
        guard !module.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var next = state

        if subject == "数量关系" {
            guard QuantityQuestionTypeRepository.types(records: records).contains(module) else {
                throw PersistenceError.invalidScope
            }
            let nameKey = quantityNameKey(module)
            let id = next.quantityTypeIDsByName[nameKey] ?? UUID().uuidString
            next.quantityTypeIDsByName[nameKey] = id
            next.settingsByScope["quantity-type:\(id)"] = settings
        } else {
            guard let typeSubject = LibraryErrorTypeSubject(rawValue: subject) else {
                throw PersistenceError.invalidScope
            }
            let normalizedTypeID = typeID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedTypeID, !normalizedTypeID.isEmpty {
                let isValidType = LibraryErrorTypeRepository.types(for: typeSubject, records: records)
                    .contains { $0.id == normalizedTypeID && $0.isAvailable(in: module) }
                guard isValidType else { throw PersistenceError.invalidScope }
                next.settingsByScope[typeKey(subject: subject, module: module, typeID: normalizedTypeID)] = settings
            } else {
                next.settingsByScope[moduleKey(subject: subject, module: module)] = settings
            }
        }

        try persist(next)
    }

    func migrateQuantityTypeScope(from oldName: String, to newName: String?) throws {
        var next = state
        let oldKey = quantityNameKey(oldName)
        guard let typeID = next.quantityTypeIDsByName.removeValue(forKey: oldKey) else { return }
        if let newName {
            next.quantityTypeIDsByName[quantityNameKey(newName)] = typeID
        } else {
            next.settingsByScope.removeValue(forKey: "quantity-type:\(typeID)")
        }
        try persist(next)
    }

    func persistedDataSnapshot() -> Data? {
        defaults.data(forKey: Self.storageKey)
    }

    func restorePersistedData(_ data: Data?) {
        if let data {
            defaults.set(data, forKey: Self.storageKey)
            state = (try? JSONDecoder().decode(PersistedState.self, from: data)) ?? PersistedState()
        } else {
            defaults.removeObject(forKey: Self.storageKey)
            state = PersistedState()
        }
        revision &+= 1
    }

    private func persist(_ next: PersistedState) throws {
        let data = try JSONEncoder().encode(next)
        let previousData = defaults.data(forKey: Self.storageKey)
        defaults.set(data, forKey: Self.storageKey)
        guard defaults.data(forKey: Self.storageKey) == data else {
            if let previousData {
                defaults.set(previousData, forKey: Self.storageKey)
            } else {
                defaults.removeObject(forKey: Self.storageKey)
            }
            throw PersistenceError.writeFailed
        }
        state = next
        revision &+= 1
    }

    private func moduleKey(subject: String, module: String) -> String {
        "module:\(keyPart(subject)):\(keyPart(module))"
    }

    private func typeKey(subject: String, module: String, typeID: String) -> String {
        "type:\(keyPart(subject)):\(keyPart(module)):\(keyPart(typeID))"
    }

    private func quantityNameKey(_ name: String) -> String {
        "quantity:\(keyPart(name))"
    }

    private func keyPart(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private enum PersistenceError: LocalizedError {
        case invalidScope
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidScope: return "当前题型范围已失效，请重新选择后再试。"
            case .writeFailed: return "标签展示设置未能保存，原设置已保留。"
            }
        }
    }
}

struct LibraryTagDisplaySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = LibraryTagDisplayPreferences.shared
    let subject: String
    let module: String
    let typeID: String?
    let scopeDescription: String
    let records: [StoredRecord]
    @State private var errorMessage: String?

    private var settings: LibraryTagDisplaySettings {
        preferences.settings(subject: subject, module: module, typeID: typeID, records: records)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("当前范围：\(scopeDescription)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    settingsGroup(title: "错题属性") {
                        visibilityRow(
                            title: "考点",
                            isVisible: settings.showsKnowledgePointAttribute,
                            accessibilityCategory: "错题属性",
                            accessibilityTitle: "考点"
                        ) { next in
                            var updated = settings
                            updated.showsKnowledgePointAttribute = next
                            save(updated)
                        }
                        visibilityRow(
                            title: "错因标签",
                            isVisible: settings.showsMistakeTagAttribute,
                            accessibilityCategory: "错题属性",
                            accessibilityTitle: "错因标签"
                        ) { next in
                            var updated = settings
                            updated.showsMistakeTagAttribute = next
                            save(updated)
                        }
                    }

                    settingsGroup(title: "卡片顶部") {
                        selectionRow(
                            title: "考点",
                            isSelected: settings.showsKnowledgePointCardHeader,
                            accessibilityCategory: "卡片顶部"
                        ) { next in
                            var updated = settings
                            updated.showsKnowledgePointCardHeader = next
                            save(updated)
                        }
                        selectionRow(
                            title: "错因标签",
                            isSelected: settings.showsMistakeTagCardHeader,
                            accessibilityCategory: "卡片顶部"
                        ) { next in
                            var updated = settings
                            updated.showsMistakeTagCardHeader = next
                            save(updated)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppTheme.danger)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle("标签展示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 10)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        }
    }

    private func visibilityRow(
        title: String,
        isVisible: Bool,
        accessibilityCategory: String,
        accessibilityTitle: String,
        action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { action(!isVisible) } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isVisible ? AppTheme.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accessibilityCategory)，\(accessibilityTitle)，\(isVisible ? "显示" : "隐藏")")
        }
        .frame(minHeight: 44)
    }

    private func selectionRow(
        title: String,
        isSelected: Bool,
        accessibilityCategory: String,
        action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { action(!isSelected) } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accessibilityCategory)，\(title)，\(isSelected ? "已选择" : "未选择")")
        }
        .frame(minHeight: 44)
    }

    private func save(_ updated: LibraryTagDisplaySettings) {
        do {
            try preferences.update(
                updated,
                subject: subject,
                module: module,
                typeID: typeID,
                records: records
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
