import Foundation

enum SpeedScreen: Equatable {
    case home, practice, result, history, statistics, estimateTable
}

enum SpeedMode: String, Codable, CaseIterable, Identifiable {
    case train = "训练"
    case race = "竞速"
    var id: String { rawValue }
}

enum SpeedTypeKey: String, Codable, CaseIterable, Identifiable {
    case addsub2, add3, sub3, addsub3, mul2x1, mul3x1, div3x1, div5x3, spDen, est05, base, growth, dataReal
    var id: String { rawValue }

    var name: String {
        switch self {
        case .addsub2: "两位数加减"
        case .add3: "三位数加法"
        case .sub3: "三位数减法"
        case .addsub3: "三位数加减"
        case .mul2x1: "两位数乘一位数"
        case .mul3x1: "三位数乘一位数"
        case .div3x1: "三位数除一位数"
        case .div5x3: "五位数除三位数"
        case .spDen: "特殊分母练习"
        case .est05: "估算练习"
        case .base: "基期练习"
        case .growth: "增量练习"
        case .dataReal: "资料分析实战"
        }
    }

    var isAvailable: Bool { self != .dataReal }
    var isDataAnalysis: Bool { [.base, .growth, .dataReal].contains(self) }
}

struct SpeedSettings: Codable, Equatable {
    var confirmAuto = true
    var useScreenKeyboard = true
    var sequential = false
    var nightMode = false
    var noNegative = false
    var quickMemo = true
    var selectedType: SpeedTypeKey = .addsub2
    var customTypes: [SpeedTypeKey] = [.addsub2]
    var questionCount = 10
    var mode: SpeedMode = .train
}

struct SpeedQuestion: Codable, Identifiable, Equatable {
    let id: String
    let type: SpeedTypeKey
    let expression: String
    let answer: Double
    var input = ""
    var isCorrect: Bool?
    var timeUsed: Double = 0
    var memo = ""
}

struct SpeedRecord: Codable, Identifiable, Equatable {
    let id: String
    let date: Date
    let name: String
    let mode: SpeedMode
    let totalTime: Double
    let correctCount: Int
    let totalCount: Int
    let details: [SpeedQuestion]
}

struct SpeedEstimateRow: Codable, Identifiable, Equatable {
    var id: String
    var minimum: Int
    var maximum: Int
    var value: Int
}
