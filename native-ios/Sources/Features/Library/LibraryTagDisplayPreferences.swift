import Combine
import Foundation
import SwiftUI

struct LibraryTagDisplaySettings: Codable, Equatable {
    var showsKnowledgePointAttribute = true
    var showsMistakeTagAttribute = true
    var showsKnowledgePointCardHeader = true
    var showsMistakeTagCardHeader = false

    static let defaults = LibraryTagDisplaySettings()
}

struct LibraryTagDisplayScope {
    fileprivate static let quantity = Self(subject: "数量关系", moduleName: nil)
    fileprivate static let dataAnalysis = Self(subject: SubjectDefinition.dataAnalysisSubject, moduleName: nil)

    private let subject: String
    private let module: String?

    private init(subject: String, moduleName: String?) {
        self.subject = subject
        module = moduleName
    }

    init?(subject: String, module: String) {
        let subject = SubjectModuleTitle.normalized(subject)
        if subject == Self.quantity.subject || subject == Self.dataAnalysis.subject {
            self.init(subject: subject, moduleName: nil)
            return
        }

        let module = SubjectModuleTitle.normalized(module)
        guard LibraryErrorTypeSubject(rawValue: subject) != nil, !module.isEmpty else { return nil }
        self.init(subject: subject, moduleName: module)
    }

    var title: String {
        guard let module else { return subject }
        return "\(subject) · \(SubjectDefinition.moduleTitle(module, subject: subject))"
    }

    fileprivate var storageKey: String {
        "module:\(Self.keyPart(subject)):\(Self.keyPart(module ?? ""))"
    }

    fileprivate static var legacyDataAnalysisKeys: [String] {
        LibraryErrorTypeSubject.dataAnalysis.modules.map {
            Self(subject: dataAnalysis.subject, moduleName: $0).storageKey
        }
    }

    private static func keyPart(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Self.loadState(defaults.data(forKey: Self.storageKey))
    }

    private static func loadState(_ data: Data?) -> PersistedState {
        guard let data, var decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }

        var typedSettingsByModule: [String: [LibraryTagDisplaySettings]] = [:]
        let quantityTypeKeys = Set(decoded.quantityTypeIDsByName.values.map { "quantity-type:\($0)" })
        for (key, settings) in decoded.settingsByScope {
            if quantityTypeKeys.contains(key) {
                typedSettingsByModule[LibraryTagDisplayScope.quantity.storageKey, default: []].append(settings)
                continue
            }
            let parts = key.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "type" else { continue }
            typedSettingsByModule["module:\(parts[1]):\(parts[2])", default: []].append(settings)
        }
        for (key, settings) in typedSettingsByModule where decoded.settingsByScope[key] == nil {
            if let first = settings.first, settings.allSatisfy({ $0 == first }) {
                decoded.settingsByScope[key] = first
            }
        }
        let analysisKey = LibraryTagDisplayScope.dataAnalysis.storageKey
        if decoded.settingsByScope[analysisKey] == nil {
            let saved = LibraryTagDisplayScope.legacyDataAnalysisKeys.compactMap { decoded.settingsByScope[$0] }
            if let first = saved.first, saved.allSatisfy({ $0 == first }) {
                decoded.settingsByScope[analysisKey] = first
            }
        }
        return decoded
    }

    func settings(for scope: LibraryTagDisplayScope?) -> LibraryTagDisplaySettings {
        guard let scope else { return .defaults }
        return state.settingsByScope[scope.storageKey] ?? .defaults
    }

    func update(
        _ settings: LibraryTagDisplaySettings,
        for scope: LibraryTagDisplayScope
    ) throws {
        var next = state
        next.settingsByScope[scope.storageKey] = settings
        try persist(next)
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

    private enum PersistenceError: LocalizedError {
        case writeFailed

        var errorDescription: String? { "标签展示设置未能保存，原设置已保留。" }
    }
}

struct LibraryTagDisplaySettingsSheet: View {
    @ObservedObject private var preferences = LibraryTagDisplayPreferences.shared
    let scope: LibraryTagDisplayScope
    let onClose: () -> Void
    @State private var errorMessage: String?

    private var settings: LibraryTagDisplaySettings {
        preferences.settings(for: scope)
    }

    var body: some View {
        NativeEditorDialog(
            title: "标签展示",
            canSave: true,
            actionTitle: "完成",
            onClose: onClose,
            onSave: onClose,
            preferredSize: CGSize(width: 420, height: 420),
            spacing: 12
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("当前范围：\(scope.title)")
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
                .padding(.vertical, 4)
            }
        }
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
            try preferences.update(updated, for: scope)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
