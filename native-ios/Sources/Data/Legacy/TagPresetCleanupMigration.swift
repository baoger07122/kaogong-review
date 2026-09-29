import Foundation
import SwiftData

/// Removes the old built-in tag catalogue once. After this migration all tags
/// are user-owned, so a user may add a previously built-in name again later.
enum TagPresetCleanupMigration {
    private static let markerKey = "native.tagPresetCleanup.9.22.5"

    static func runIfNeeded(in container: ModelContainer) throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: markerKey) else { return }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<StoredRecord>())

        for record in records {
            guard var object = record.jsonObject else { continue }
            var changed = false

            if record.collection == "keyvalue",
               ["kp_library", "kp_ec_library", "kp_trap_library"].contains(record.recordID),
               var library = object["value"] as? [String: Any] {
                for (module, rawValues) in library {
                    let values = (rawValues as? [String]) ?? (rawValues as? [Any])?.compactMap { $0 as? String } ?? []
                    let blocked = record.recordID == "kp_library" ? presets(for: module) : Set(["待复盘"])
                    let cleaned = values.filter { !blocked.contains($0) }
                    if cleaned != values {
                        library[module] = cleaned
                        changed = true
                    }
                }
                object["value"] = library
            } else if record.collection == "errors" || record.collection == "notes" {
                let blocked = presets(for: record.module)
                if var values = object["knowledgePoints"] as? [String] {
                    let cleaned = values.filter { !blocked.contains($0) }
                    if cleaned != values {
                        object["knowledgePoints"] = cleaned
                        changed = true
                    }
                }
                if let value = object["knowledgePoint"] as? String, blocked.contains(value) {
                    object["knowledgePoint"] = (object["knowledgePoints"] as? [String])?.first ?? ""
                    changed = true
                }
                if object["errorCause"] as? String == "待复盘" {
                    object["errorCause"] = ""
                    changed = true
                }
                if var values = object["weaknessTags"] as? [String], values.contains("待复盘") {
                    values.removeAll { $0 == "待复盘" }
                    object["weaknessTags"] = values
                    changed = true
                }
            }

            if changed {
                record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                record.updatedAt = .now
            }
        }

        try context.save()
        defaults.set(true, forKey: markerKey)
    }

    private static func presets(for module: String) -> Set<String> {
        Set((legacyKnowledgePoints[module] ?? []) + ["待复盘"])
    }

    private static let legacyKnowledgePoints: [String: [String]] = [
        "逻辑填空": ["关联词语", "成语辨析", "实词辨析", "语境分析"],
        "中心理解": ["主旨概括", "意图判断", "主题词定位", "行文脉络"],
        "标题填入": ["标题拟定", "标题选择", "新闻标题"],
        "接语选择": ["承接推断", "话题衔接", "尾句分析"],
        "语句填入": ["居中填空", "段首填空", "段尾填空"],
        "语句排序": ["首句判定", "相邻句捆绑", "整体排序"],
        "细节判断题": ["细节理解", "细节查找", "是非判断"],
        "植树问题": ["两端植树", "两端不植树", "单端植树", "环形植树"],
        "和差倍比": ["和差倍比", "比例关系", "鸡兔同笼", "盈亏问题"],
        "工程问题": ["效率关系", "合作工程", "赋值法", "牛吃草"],
        "行程问题": ["相遇追及", "流水行船", "环形运动", "平均速度"],
        "排列组合": ["分类分步", "排列", "组合", "错位排列", "环形排列"],
        "概率问题": ["古典概率", "分类分步概率", "条件概率"],
        "几何问题": ["平面几何", "立体几何", "几何面积", "相似比例"],
        "最值问题": ["定和求积最大", "定积求和最小", "极值与范围判断"],
        "经济利润": ["利润率", "折扣", "分段计费"],
        "容斥问题": ["两集合容斥", "三集合容斥", "画图法"],
        "年龄问题": ["年龄差不变", "倍数关系"],
        "浓度问题": ["溶液混合", "反复操作", "十字交叉"],
        "计数问题": ["枚举", "捆绑插空", "隔板法"],
        "图形推理": ["位置规律", "样式规律", "数量规律", "空间重构", "平面拼合"],
        "定义判断": ["社会类", "经济类", "法律类", "管理类", "心理类"],
        "类比推理": ["逻辑关系", "语义关系", "语法关系", "常识关系"],
        "逻辑判断": ["翻译推理", "真假推理", "分析推理", "削弱加强", "前提假设", "解释评价"],
        "文字材料": ["增长率", "比重", "倍数", "平均数", "增长量"],
        "表格材料": ["增长率", "比重", "倍数", "平均数", "增长量"],
        "图表材料": ["增长率", "比重", "倍数", "平均数", "增长量"],
        "综合材料": ["增长率", "比重", "倍数", "平均数", "增长量"],
        "政治": ["时政热点", "马克思主义基本原理", "中国特色社会主义", "党建理论"],
        "法律": ["宪法", "行政法", "民法", "刑法", "诉讼法"],
        "经济": ["宏观经济", "微观经济", "国际经济", "财政金融"],
        "人文": ["历史常识", "文学常识", "文化常识", "艺术常识"],
        "科技": ["科技史", "前沿科技", "生活常识", "信息技术"],
        "地理": ["自然地理", "人文地理", "中国地理", "世界地理"],
        "归纳概括": ["概括问题", "概括原因", "概括影响", "概括做法"],
        "综合分析": ["词句理解", "评论分析", "比较分析", "启示分析"],
        "提出对策": ["直接对策", "间接对策", "经验借鉴", "创新对策"],
        "贯彻执行": ["倡议书", "通知", "汇报", "讲话稿", "调研报告"],
        "大作文": ["议论文", "策论文", "政论文", "评论文"]
    ]
}
