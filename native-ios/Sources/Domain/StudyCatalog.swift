import SwiftUI

struct SubjectDefinition: Identifiable, Hashable {
    let name: String
    let systemImage: String
    let color: Color
    let modules: [String]

    var id: String { name }
    var isFlat: Bool { name == "数量关系" }
    var libraryModules: [String] { name == Self.dataAnalysisSubject ? [] : modules }

    static let dataAnalysisSubject = "资料分析"

    // Existing records and tag catalogs share this module key.
    static let argumentReasoningModule = "逻辑判断"
    static let formalLogicModule = "形式逻辑"

    static func moduleTitle(_ module: String, subject: String?) -> String {
        (subject == nil || subject == "判断推理") && module == argumentReasoningModule ? "论证推理" : module
    }

    static func libraryModuleTitle(_ module: String?, subject: String?) -> String? {
        guard subject != dataAnalysisSubject, let module, !module.isEmpty else { return nil }
        return moduleTitle(module, subject: subject)
    }

    static let all: [SubjectDefinition] = [
        .init(name: "言语理解", systemImage: "book", color: .blue,
              modules: ["逻辑填空", "中心理解", "标题填入", "接语选择", "语句填入", "语句排序", "细节判断题", "词句理解题"]),
        .init(name: "数量关系", systemImage: "number", color: .orange,
              modules: []),
        .init(name: "判断推理", systemImage: "square.grid.2x2", color: .green,
              modules: ["图形推理", "定义判断", "类比推理", argumentReasoningModule, formalLogicModule]),
        .init(name: dataAnalysisSubject, systemImage: "chart.bar", color: .purple,
              modules: ["单题", "综合题"]),
        .init(name: "常识判断", systemImage: "lightbulb", color: .yellow,
              modules: ["政治", "法律", "经济", "人文", "科技", "地理"]),
        .init(name: "申论", systemImage: "pencil.and.outline", color: .mint,
              modules: ["归纳概括", "综合分析", "提出对策", "贯彻执行", "大作文"])
    ]
}

extension StoredRecord {
    var moduleDisplayTitle: String? {
        guard let module, !module.isEmpty else { return nil }
        return SubjectDefinition.libraryModuleTitle(module, subject: subject ?? indexObject?["subject"] as? String)
    }
}

enum QuantityQuestionTypeCatalog {
    static let legacyModules: Set<String> = ["数学运算", "数字推理"]

    static func displayName(for value: String?) -> String {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty || legacyModules.contains(cleaned) ? "未分类" : cleaned
    }
}
