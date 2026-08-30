import Foundation
import SwiftData

enum ManagedTagKind: String, CaseIterable, Identifiable {
    case knowledgePoint = "考点"
    case errorCause = "错因"
    var id: String { rawValue }
    var recordID: String { self == .knowledgePoint ? "kp_library" : "kp_ec_library" }
}

enum TagLibraryRepository {
    static func tags(kind: ManagedTagKind, module: String, records: [StoredRecord]) -> [String] {
        let library = load(kind: kind, records: records)
        if let values = library[module], !values.isEmpty { return values }
        return kind == .knowledgePoint ? (defaults[module] ?? ["待复盘"]) : ["待复盘"]
    }

    static func add(_ name: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !(library[module] ?? []).contains(value) else { return }
        library[module, default: []].append(value)
        try save(library, kind: kind, records: records, context: context)
    }

    static func move(_ name: String, direction: Int, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        guard var values = library[module], let index = values.firstIndex(of: name) else { return }
        let destination = index + direction
        guard values.indices.contains(destination) else { return }
        values.swapAt(index, destination)
        library[module] = values
        try save(library, kind: kind, records: records, context: context)
    }

    static func rename(_ oldName: String, to newName: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != oldName, !(library[module] ?? []).contains(value) else { return }
        library[module] = (library[module] ?? []).map { $0 == oldName ? value : $0 }
        try save(library, kind: kind, records: records, context: context)
        try updateReferences(oldName: oldName, newName: value, kind: kind, module: module, records: records, context: context)
    }

    static func delete(_ name: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        library[module] = (library[module] ?? []).filter { $0 != name }
        try save(library, kind: kind, records: records, context: context)
        try updateReferences(oldName: name, newName: nil, kind: kind, module: module, records: records, context: context)
    }

    private static func loadWithDefaults(kind: ManagedTagKind, records: [StoredRecord]) -> [String: [String]] {
        var result = kind == .knowledgePoint ? defaults : errorDefaults
        load(kind: kind, records: records).forEach { result[$0.key] = $0.value }
        return result
    }

    private static func load(kind: ManagedTagKind, records: [StoredRecord]) -> [String: [String]] {
        guard
            let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == kind.recordID })?.jsonObject,
            let raw = object["value"] as? [String: Any]
        else { return [:] }
        return raw.reduce(into: [:]) { result, entry in
            result[entry.key] = (entry.value as? [String]) ?? (entry.value as? [Any])?.compactMap { $0 as? String } ?? []
        }
    }

    private static func save(_ library: [String: [String]], kind: ManagedTagKind, records: [StoredRecord], context: ModelContext) throws {
        let object: [String: Any] = ["key": kind.recordID, "value": library]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == kind.recordID }) {
            record.payload = payload
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: kind.recordID, payload: payload, updatedAt: .now))
        }
        try context.save()
    }

    private static func updateReferences(
        oldName: String,
        newName: String?,
        kind: ManagedTagKind,
        module: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        for record in records where record.module == module && (record.collection == "errors" || record.collection == "notes") {
            guard var object = record.jsonObject else { continue }
            var changed = false
            if kind == .knowledgePoint {
                if var values = object["knowledgePoints"] as? [String], values.contains(oldName) {
                    values = values.compactMap { $0 == oldName ? newName : $0 }
                    object["knowledgePoints"] = values
                    changed = true
                }
                if object["knowledgePoint"] as? String == oldName {
                    object["knowledgePoint"] = newName ?? ""
                    changed = true
                }
            } else if object["errorCause"] as? String == oldName {
                object["errorCause"] = newName ?? ""
                changed = true
            }
            if changed {
                record.payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                record.updatedAt = .now
            }
        }
        try context.save()
    }

    private static let errorDefaults: [String: [String]] = Dictionary(
        uniqueKeysWithValues: SubjectDefinition.all.flatMap(\.modules).map { ($0, ["待复盘"]) }
    )

    private static let defaults: [String: [String]] = [
        "逻辑填空": ["待复盘", "关联词语", "成语辨析", "实词辨析", "语境分析"],
        "中心理解": ["待复盘", "主旨概括", "意图判断", "主题词定位", "行文脉络"],
        "标题填入": ["待复盘", "标题拟定", "标题选择", "新闻标题"],
        "接语选择": ["待复盘", "承接推断", "话题衔接", "尾句分析"],
        "语句填入": ["待复盘", "居中填空", "段首填空", "段尾填空"],
        "语句排序": ["待复盘", "首句判定", "相邻句捆绑", "整体排序"],
        "细节判断题": ["待复盘", "细节理解", "细节查找", "是非判断"],
        "数学运算": ["待复盘", "行程问题", "工程问题", "利润问题", "排列组合", "概率问题", "几何问题", "浓度问题", "容斥问题"],
        "数字推理": ["待复盘", "等差数列", "等比数列", "递推数列", "多次方数列", "分数数列", "组合数列"],
        "图形推理": ["待复盘", "位置规律", "样式规律", "数量规律", "空间重构", "平面拼合"],
        "定义判断": ["待复盘", "社会类", "经济类", "法律类", "管理类", "心理类"],
        "类比推理": ["待复盘", "逻辑关系", "语义关系", "语法关系", "常识关系"],
        "逻辑判断": ["待复盘", "翻译推理", "真假推理", "分析推理", "削弱加强", "前提假设", "解释评价"],
        "文字材料": ["待复盘", "增长率", "比重", "倍数", "平均数", "增长量"],
        "表格材料": ["待复盘", "增长率", "比重", "倍数", "平均数", "增长量"],
        "图表材料": ["待复盘", "增长率", "比重", "倍数", "平均数", "增长量"],
        "综合材料": ["待复盘", "增长率", "比重", "倍数", "平均数", "增长量"],
        "政治": ["待复盘", "时政热点", "马克思主义基本原理", "中国特色社会主义", "党建理论"],
        "法律": ["待复盘", "宪法", "行政法", "民法", "刑法", "诉讼法"],
        "经济": ["待复盘", "宏观经济", "微观经济", "国际经济", "财政金融"],
        "人文": ["待复盘", "历史常识", "文学常识", "文化常识", "艺术常识"],
        "科技": ["待复盘", "科技史", "前沿科技", "生活常识", "信息技术"],
        "地理": ["待复盘", "自然地理", "人文地理", "中国地理", "世界地理"],
        "归纳概括": ["待复盘", "概括问题", "概括原因", "概括影响", "概括做法"],
        "综合分析": ["待复盘", "词句理解", "评论分析", "比较分析", "启示分析"],
        "提出对策": ["待复盘", "直接对策", "间接对策", "经验借鉴", "创新对策"],
        "贯彻执行": ["待复盘", "倡议书", "通知", "汇报", "讲话稿", "调研报告"],
        "大作文": ["待复盘", "议论文", "策论文", "政论文", "评论文"]
    ]
}
