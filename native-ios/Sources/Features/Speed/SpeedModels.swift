import Foundation

enum SpeedScreen: Equatable {
    case home, practice, result, history, statistics, estimateTable
}

enum SpeedMode: String, Codable, CaseIterable, Identifiable {
    case train = "训练"
    case race = "竞速"
    var id: String { rawValue }
}

enum SpeedCustomNumberMode: String, Codable, CaseIterable, Identifiable {
    case none = "不限制"
    case fixed = "固定数字"
    case range = "随机范围"
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

    var ratingThresholds: SpeedRatingThresholds? {
        switch self {
        case .addsub2: .init(excellent: 18, good: 22, pass: 28)
        case .add3, .sub3, .mul3x1: .init(excellent: 35, good: 45, pass: 60)
        case .addsub3: .init(excellent: 40, good: 50, pass: 70)
        case .mul2x1: .init(excellent: 20, good: 28, pass: 40)
        case .div3x1: .init(excellent: 24, good: 30, pass: 38)
        case .div5x3: .init(excellent: 45, good: 70, pass: 100)
        case .spDen: .init(excellent: 10, good: 15, pass: 20)
        case .est05: .init(excellent: 20, good: 30, pass: 45)
        case .base: .init(excellent: 35, good: 50, pass: 70)
        case .growth: .init(excellent: 30, good: 45, pass: 60)
        case .dataReal: nil
        }
    }
}

struct SpeedRatingThresholds: Equatable {
    let excellent: Double
    let good: Double
    let pass: Double

    func rating(for seconds: Double) -> SpeedRating {
        if seconds <= excellent { return .excellent }
        if seconds <= good { return .good }
        if seconds <= pass { return .pass }
        return .keepGoing
    }
}

enum SpeedRating: String {
    case excellent = "优秀"
    case good = "良好"
    case pass = "合格"
    case keepGoing = "加油"
}

struct SpeedSettings: Codable, Equatable {
    var confirmAuto = true
    var useScreenKeyboard = true
    var sequential = false
    var nightMode = false
    var noNegative = false
    var quickMemo = true
    var soundEnabled: Bool? = true
    var selectedType: SpeedTypeKey = .addsub2
    var customTypes: [SpeedTypeKey] = [.addsub2]
    var customNumberMode: SpeedCustomNumberMode?
    var customFixedNumbers: [Int]?
    var customRangeMinimum: Int?
    var customRangeMaximum: Int?
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
