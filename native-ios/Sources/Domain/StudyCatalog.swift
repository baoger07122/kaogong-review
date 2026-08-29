import SwiftUI

struct SubjectDefinition: Identifiable, Hashable {
    let name: String
    let systemImage: String
    let color: Color
    let modules: [String]

    var id: String { name }
    var isFlat: Bool { name == "资料分析" }

    static let all: [SubjectDefinition] = [
        .init(name: "言语理解", systemImage: "book", color: .blue,
              modules: ["逻辑填空", "中心理解", "标题填入", "接语选择", "语句填入", "语句排序", "细节判断题"]),
        .init(name: "数量关系", systemImage: "number", color: .orange,
              modules: ["数学运算", "数字推理"]),
        .init(name: "判断推理", systemImage: "square.grid.2x2", color: .green,
              modules: ["图形推理", "定义判断", "类比推理", "逻辑判断"]),
        .init(name: "资料分析", systemImage: "chart.bar", color: .purple,
              modules: ["文字材料", "表格材料", "图表材料", "综合材料"]),
        .init(name: "常识判断", systemImage: "lightbulb", color: .yellow,
              modules: ["政治", "法律", "经济", "人文", "科技", "地理"]),
        .init(name: "申论", systemImage: "pencil.and.outline", color: .mint,
              modules: ["归纳概括", "综合分析", "提出对策", "贯彻执行", "大作文"])
    ]
}
