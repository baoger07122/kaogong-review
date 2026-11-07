import Foundation
import CryptoKit

enum WordCategory: String, CaseIterable, Identifiable {
    case idiomDefinition = "idiom-def"
    case idiomComparison = "idiom-compare"
    case wordDefinition = "word-def"
    case wordComparison = "word-compare"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .idiomDefinition: "成语释义"
        case .idiomComparison: "成语组辨析"
        case .wordDefinition: "实词释义"
        case .wordComparison: "实词组辨析"
        }
    }
    var shortTitle: String {
        switch self {
        case .idiomDefinition: "成语"
        case .idiomComparison: "成语辨析"
        case .wordDefinition: "实词"
        case .wordComparison: "实词辨析"
        }
    }
    var systemImage: String {
        switch self {
        case .idiomDefinition: "book.closed"
        case .idiomComparison: "arrow.left.arrow.right"
        case .wordDefinition: "textformat"
        case .wordComparison: "rectangle.2.swap"
        }
    }
    var isComparison: Bool { self == .idiomComparison || self == .wordComparison }
}

enum LibraryContentKind: String, CaseIterable, Identifiable, Hashable {
    case errors = "错题"
    case notes = "笔记"
    case stickies = "便签"
    case words = "词语库"

    var id: String { rawValue }

    var collection: String {
        switch self {
        case .errors: "errors"
        case .notes: "notes"
        case .stickies: "stickies"
        case .words: "words"
        }
    }

    var emptyTitle: String {
        switch self {
        case .errors: "还没有错题"
        case .notes: "还没有笔记"
        case .stickies: "这个模块还没有便签"
        case .words: "还没有词语记录"
        }
    }

    var emptyDetail: String {
        switch self {
        case .errors: "当前范围内还没有收录错题"
        case .notes: "当前范围内还没有记录笔记"
        case .stickies: "便签只保存在当前模块内"
        case .words: "词语库仅属于言语理解的逻辑填空模块"
        }
    }
}

enum LibraryCardSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"

    var id: String { rawValue }
    var columnCount: Int {
        switch self {
        case .small: 3
        case .medium: 2
        case .large: 1
        }
    }

    var questionLineLimit: Int {
        switch self {
        case .small: 2
        case .medium: 3
        case .large: 5
        }
    }

    var imageMaximumHeight: CGFloat {
        switch self {
        case .small: 150
        case .medium: 220
        case .large: 320
        }
    }
}

enum LibraryRoute: Hashable {
    case editor(kind: LibraryContentKind, recordID: String?)
    case shenlunAdaptation(recordID: String)
    case detail(kind: LibraryContentKind, recordID: String)
}

enum ShenlunRecordFormat {
    /// The first explicitly versioned payload shape. Records without this key
    /// are legacy data and must be adapted by the user before editing.
    static let currentVersion = 1
    static let backupCollection = "shenlun-adaptation-backup"
}

struct ShenlunAdaptationValues {
    var questionType = ""
    var questionSource = ""
    var questionNumber = ""
    var score = ""
    var totalScore = ""
    var currentAffairsSupplement = ""
    var myAnswer = ""
    var referenceAnswer = ""
    var myAnswerIssues = ""
    var materialsAnalysis = ""
    var reviewNote = ""
    var materials: [String] = []
    var question = ""
}

enum WordEntryKind: String, CaseIterable, Identifiable, Codable {
    case word = "word"
    case collocation = "collocation"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .word: "词语"
        case .collocation: "常见搭配"
        }
    }
}

struct LinkedWordDetailTarget: Identifiable, Hashable {
    let recordID: String
    var id: String { recordID }
}

struct LibraryScope: Equatable {
    static let dataAnalysisReviewBucket = "待分类"

    var subject: String?
    var module: String?
    var reviewSource: LibraryReviewSource = .real

    var isAll: Bool { subject == nil }
    var hasModuleContext: Bool {
        guard let subject else { return false }
        return module != nil
    }
    var isLogicFill: Bool { subject == "言语理解" && module == "逻辑填空" }

    var title: String {
        if let module { return module }
        if let subject { return subject }
        return "全部"
    }

    func contains(_ record: StoredRecord) -> Bool {
        guard let subject else { return true }
        guard record.subject == subject else { return false }
        guard let module else { return true }
        if subject == "资料分析", (module == Self.dataAnalysisReviewBucket || module == "未分类") {
            let storedModule = record.module?.trimmingCharacters(in: .whitespacesAndNewlines)
            return storedModule == nil
                || storedModule?.isEmpty == true
                || storedModule == "未分类"
                || storedModule == Self.dataAnalysisReviewBucket
                || storedModule.map { SubjectDefinition.legacyDataAnalysisModules.contains($0) } == true
        }
        return record.module == module
    }
}

struct LibraryPartitionState {
    var scope: LibraryScope
    var expandedSubject: String?
    var kind: LibraryContentKind
    var searchText: String
    var selectedStatus: String
    var selectedTag: String
    var selectedQuantityType: String
    var renderLimit: Int
    var wordCategory: WordCategory
    var wordSentiment: String
    var wordEntryKind: String
}

struct LibraryImageDisplaySetting: Identifiable, Codable, Equatable, Sendable {
    static let minimumWidthFraction = 0.2
    static let maximumWidthFraction = 1.0
    static let stepWidthFraction = 0.05

    var id: String
    var widthFraction: Double

    init(id: String = UUID().uuidString, widthFraction: Double = 1.0) {
        self.id = id
        self.widthFraction = Self.normalizedWidthFraction(widthFraction)
    }

    var payloadObject: [String: Any] {
        ["id": id, "widthFraction": widthFraction]
    }

    static func normalizedWidthFraction(_ value: Double) -> Double {
        guard value.isFinite else { return maximumWidthFraction }
        let clamped = min(max(value, minimumWidthFraction), maximumWidthFraction)
        return (clamped / stepWidthFraction).rounded() * stepWidthFraction
    }

    static func normalized(_ values: [LibraryImageDisplaySetting], count: Int) -> [LibraryImageDisplaySetting] {
        guard count > 0 else { return [] }
        var usedIDs = Set<String>()
        return (0..<count).map { index in
            let existing = index < values.count ? values[index] : LibraryImageDisplaySetting()
            let candidate = existing.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let id: String
            if !candidate.isEmpty, usedIDs.insert(candidate).inserted {
                id = candidate
            } else {
                let replacement = UUID().uuidString
                usedIDs.insert(replacement)
                id = replacement
            }
            return LibraryImageDisplaySetting(id: id, widthFraction: existing.widthFraction)
        }
    }

    static func normalized(from payload: Any?, count: Int) -> [LibraryImageDisplaySetting] {
        let values = payload as? [[String: Any]] ?? []
        let settings = values.map { value in
            let id = value["id"] as? String ?? ""
            let fraction = (value["widthFraction"] as? NSNumber)?.doubleValue ?? maximumWidthFraction
            return LibraryImageDisplaySetting(id: id, widthFraction: fraction)
        }
        return normalized(settings, count: count)
    }

    static func widthFractions(from payload: Any?, count: Int) -> [Double] {
        let values = payload as? [[String: Any]] ?? []
        return (0..<max(0, count)).map { index in
            guard index < values.count,
                  let number = values[index]["widthFraction"] as? NSNumber else {
                return maximumWidthFraction
            }
            return normalizedWidthFraction(number.doubleValue)
        }
    }
}

struct LibraryRecordSnapshot: Identifiable {
    let record: StoredRecord
    let subject: String
    let module: String
    let title: String
    let summary: String
    let wordCardBody: String
    let tags: [String]
    let status: String?
    let isDifficult: Bool
    let needsReview: Bool
    let createdAt: Date?
    let colorHex: String?
    let isPinned: Bool
    let searchableText: String
    let category: String
    let sentiment: String
    let wordEntryKinds: [String]
    let knowledgePoints: [String]
    let errorCause: String
    let dataAnalysisErrorCause: String
    let dataAnalysisMaterialText: String
    let pitfall: String
    let reminder: String
    let options: [String]
    let dataAnalysisOptionRows: [String]
    let quantityStructure: String
    let weaknessTags: [String]
    let imageValues: [String]
    let imageIdentities: [String]
    let imageMetadataIDs: [String]
    let imageWidthFractions: [Double]
    let comparisonWords: [String]
    let logicComparisonGroups: [LogicComparisonDraft]
    let questionSource: String
    let questionNumber: String
    let reviewSource: LibraryReviewSource
    let sourceExamID: String
    let sourceExamTitle: String

    var id: String { record.compoundID }

    init(
        record: StoredRecord,
        linkedWordNamesByID: [String: String] = [:],
        sourceExamTitlesByID: [String: String] = [:],
        reviewSource: LibraryReviewSource = .pending,
        includeImages: Bool = false,
        previousImageSnapshot: LibraryRecordSnapshot? = nil
    ) {
        self.record = record
        let object = record.compatibilityIndexObject ?? [:]
        subject = [record.subject, object["subject"] as? String]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        module = [record.module, object["module"] as? String]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let titleKeys = record.collection == "errors"
            ? ["question", "title", "name", "text", "content"]
            : ["title", "question", "name", "words", "text", "content"]
        title = Self.firstText(in: object, keys: titleKeys)
            .map(Self.plainText) ?? "未命名记录"
        let isShenlun = record.collection == "errors"
            && (record.subject == "申论" || object["subject"] as? String == "申论" || (object["isShenlun"] as? Bool) == true)
        let summaryKeys = isShenlun
            ? ["question", "title"]
            : ["judgmentHint", "commonMeaning", "compareNote", "content", "note", "errorNote", "meaning", "myUnderstanding", "relation", "coreDifference", "question"]
        summary = Self.firstText(in: object, keys: summaryKeys).map(Self.plainText) ?? ""
        let categoryValue = Self.firstText(in: object, keys: ["category", "type"])
            ?? WordCategory.idiomDefinition.rawValue
        if record.collection == "words" {
            let bodyKeys = WordCategory(rawValue: categoryValue)?.isComparison == true
                ? ["judgmentHint", "compareNote", "coreDifference", "commonMeaning", "meaning"]
                : ["commonMeaning", "meaning", "content", "note"]
            wordCardBody = Self.firstText(in: object, keys: bodyKeys) ?? ""
        } else {
            wordCardBody = ""
        }
        status = Self.firstText(in: object, keys: ["status", "masteryStatus"])
        isDifficult = (object["isDifficult"] as? Bool) ?? (object["isDifficult"] as? NSNumber)?.boolValue ?? false
        needsReview = (object["needsReview"] as? Bool) ?? (object["needsReview"] as? NSNumber)?.boolValue ?? false
        colorHex = Self.firstText(in: object, keys: ["color", "colorHex"])
        isPinned = (object["pinned"] as? Bool) ?? (object["pinned"] as? NSNumber)?.boolValue ?? false
        createdAt = record.createdAt ?? Self.date(in: object, keys: ["createdAt", "date", "updatedAt"])
        category = categoryValue
        sentiment = Self.firstText(in: object, keys: ["sentiment"]) ?? ""
        var entryKinds: [String] = []
        if let value = object["entryKind"] as? String, !value.isEmpty { entryKinds.append(value) }
        if let terms = object["compareWords"] as? [[String: Any]] {
            entryKinds.append(contentsOf: terms.compactMap { $0["entryKind"] as? String })
        }
        wordEntryKinds = Array(Set(entryKinds))

        if let points = object["knowledgePoints"] as? [String] {
            knowledgePoints = points.map(Self.plainText).filter { !$0.isEmpty }
        } else if let point = Self.firstText(in: object, keys: ["knowledgePoint", "point", "topic"]) {
            knowledgePoints = point
                .split(whereSeparator: { "、,，".contains($0) })
                .map { Self.plainText(String($0)) }
                .filter { !$0.isEmpty }
        } else {
            knowledgePoints = []
        }
        let quantityErrorCauses = record.collection == "errors" && subject == "数量关系"
            ? LibraryQuantityErrorCauseCompatibility.values(in: object)
            : []
        errorCause = record.collection == "errors" && subject == "数量关系"
            ? quantityErrorCauses.joined(separator: "、")
            : record.collection == "errors" && subject == "资料分析"
                ? LibraryDataAnalysisCauseLayout.rawCause(in: object)
                : Self.firstText(in: object, keys: ["errorCause", "cause", "reason"]).map(Self.plainText) ?? ""
        dataAnalysisErrorCause = LibraryDataAnalysisCauseLayout.rawCause(in: object)
        dataAnalysisMaterialText = Self.firstText(in: object, keys: ["dataAnalysisMaterialText"])
            .map(Self.plainText) ?? ""
        pitfall = Self.firstText(in: object, keys: ["pitfall", "misconception", "thinkingTrap"])
            .map(Self.plainText) ?? ""
        reminder = Self.firstText(in: object, keys: ["reminder"])
            .map(Self.plainText) ?? ""
        options = (object["options"] as? [String] ?? [])
            .map(Self.plainText)
            .filter { !$0.isEmpty }
        dataAnalysisOptionRows = (object["options"] as? [String] ?? [])
            .prefix(4)
            .enumerated()
            .compactMap { index, value in
                let text = Self.plainText(value)
                guard !text.isEmpty, let letter = UnicodeScalar(65 + index) else { return nil }
                return "\(String(letter)). \(text)"
            }
        quantityStructure = Self.firstText(in: object, keys: ["quantityStructure"])
            .map(Self.plainText) ?? ""
        weaknessTags = (object["weaknessTags"] as? [String] ?? [])
            .map(Self.plainText)
            .filter { !$0.isEmpty }
        // Large image data is intentionally excluded from indexPayload. Only views
        // that actually render images should open the full payload.
        let indexedImageCount = (object["imageCount"] as? NSNumber)?.intValue
        let indexedImageMetadata = object["imageDisplayMetadata"]
        let indexedMetadataIDs = Self.imageMetadataIDs(from: indexedImageMetadata, count: indexedImageCount ?? 0)
        let canReuseImages = includeImages
            && indexedImageCount == previousImageSnapshot?.imageValues.count
            && indexedMetadataIDs.count == (indexedImageCount ?? 0)
            && previousImageSnapshot?.imageMetadataIDs == indexedMetadataIDs
        let imageObject: [String: Any]
        if includeImages && !canReuseImages {
            imageObject = record.jsonObject ?? object
        } else {
            imageObject = object
        }
        if !includeImages {
            imageValues = []
        } else if canReuseImages, let previousImageSnapshot {
            imageValues = previousImageSnapshot.imageValues
        } else if let images = imageObject["images"] as? [String], !images.isEmpty {
            imageValues = images
        } else {
            imageValues = Self.firstText(in: imageObject, keys: ["image"]).map { [$0] } ?? []
        }
        let imageMetadata = imageObject["imageDisplayMetadata"] ?? indexedImageMetadata
        imageMetadataIDs = Self.imageMetadataIDs(from: imageMetadata, count: imageValues.count)
        imageIdentities = Self.imageIdentities(
            metadataIDs: imageMetadataIDs,
            values: imageValues,
            ownerID: record.compoundID,
            previous: previousImageSnapshot
        )
        imageWidthFractions = LibraryImageDisplaySetting.widthFractions(
            from: imageMetadata,
            count: imageValues.count
        )
        let linkedWordIDs = object["linkedWordIds"] as? [String] ?? []
        comparisonWords = linkedWordIDs.compactMap { linkedWordNamesByID[$0] }
        if let groups = object["compareGroups"] as? [[String: Any]] {
            logicComparisonGroups = groups.compactMap { value in
                let words = value["words"] as? String ?? ""
                let relation = value["relation"] as? String ?? ""
                guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return LogicComparisonDraft(words: words, relation: relation)
            }
        } else {
            logicComparisonGroups = []
        }
        questionSource = Self.firstText(in: object, keys: ["questionSource", "source"])
            .map(Self.plainText) ?? ""
        questionNumber = Self.firstText(in: object, keys: ["questionNumber"])
            .map(Self.plainText) ?? ""
        self.reviewSource = reviewSource
        sourceExamID = Self.firstText(in: object, keys: ["sourceExamId"]) ?? ""
        sourceExamTitle = sourceExamTitlesByID[sourceExamID] ?? ""

        var values: [String] = []
        if record.collection == "words" {
            if let category = WordCategory(rawValue: category) { values.append(category.shortTitle) }
            values.append(contentsOf: wordEntryKinds.compactMap { WordEntryKind(rawValue: $0)?.title })
        } else if let type = Self.firstText(in: object, keys: ["type", "category", "errorCause"]) {
            values.append(type)
        }
        if record.collection == "errors" {
            if isDifficult { values.append("难题") }
            if needsReview { values.append("待复习") }
        }
        if let points = object["knowledgePoints"] as? [String] { values.append(contentsOf: points) }
        if record.collection == "errors", subject == "数量关系" {
            values.append(contentsOf: quantityErrorCauses)
        } else {
            values.append(contentsOf: weaknessTags)
        }
        if let point = Self.firstText(in: object, keys: ["knowledgePoint"]) { values.append(point) }
        var seen = Set<String>()
        tags = Array(values.filter { !$0.isEmpty && seen.insert($0).inserted })

        let searchableSource = reviewSource == .mock ? sourceExamTitle : questionSource
        var searchValues = [title, summary, quantityStructure, dataAnalysisMaterialText, searchableSource, questionNumber, pitfall, reminder]
        searchValues.append(contentsOf: tags)
        if record.collection == "errors", subject == "数量关系" {
            searchValues.append(contentsOf: quantityErrorCauses)
        } else {
            searchValues.append(contentsOf: weaknessTags)
        }
        searchValues.append(contentsOf: ["pinyin", "meaning", "judgmentHint", "commonMeaning", "example", "compareNote", "myUnderstanding", "collocations", "pos"]
            .compactMap { object[$0] as? String })
        if let terms = object["compareWords"] as? [[String: Any]] {
            searchValues.append(contentsOf: terms.flatMap {
                [$0["name"] as? String, $0["meaning"] as? String].compactMap { $0 }
            })
        }
        searchableText = searchValues.joined(separator: "\n")
    }

    var mockSourceTitleDisplay: String? {
        guard record.collection == "errors", reviewSource == .mock else { return nil }
        let title = Self.abbreviatedMockExamTitle(sourceExamTitle) ?? sourceExamTitle
        return title.isEmpty ? "未关联套卷" : title
    }

    var mockQuestionNumberDisplay: String {
        guard !questionNumber.isEmpty else { return "" }
        return questionNumber.contains("第") || questionNumber.contains("题")
            ? questionNumber
            : "第\(questionNumber)题"
    }

    var sourceDisplay: String {
        if let title = mockSourceTitleDisplay {
            return mockQuestionNumberDisplay.isEmpty ? title : "\(title) · \(mockQuestionNumberDisplay)"
        }
        switch (questionSource.isEmpty, questionNumber.isEmpty) {
        case (false, false): return "\(questionSource)-\(questionNumber)"
        case (false, true): return questionSource
        case (true, false): return questionNumber
        case (true, true): return ""
        }
    }

    private static func abbreviatedMockExamTitle(_ title: String) -> String? {
        let compact = title.filter { !$0.isWhitespace }
        let pattern = #"^(20\d{2})年?国考.*?(?:第)?([0-9]+|[零〇一二两三四五六七八九十百千]+)季"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
              match.numberOfRanges == 3,
              let yearRange = Range(match.range(at: 1), in: compact),
              let seasonRange = Range(match.range(at: 2), in: compact),
              let season = seasonNumber(String(compact[seasonRange]))
        else { return nil }
        return "\(compact[yearRange])国考\(season)季"
    }

    private static func seasonNumber(_ value: String) -> Int? {
        if let arabic = Int(value) { return arabic }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        var section = 0
        var digit = 0
        for character in value {
            if let number = digits[character] {
                digit = number
            } else if let unit = units[character] {
                section += (digit == 0 ? 1 : digit) * unit
                digit = 0
            } else {
                return nil
            }
        }
        let number = section + digit
        return number > 0 ? number : nil
    }

    private static func firstText(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = object[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    private static func imageMetadataIDs(from payload: Any?, count: Int) -> [String] {
        let values = payload as? [[String: Any]] ?? []
        return (0..<max(0, count)).map { index in
            guard index < values.count else { return "" }
            return (values[index]["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func imageIdentities(
        metadataIDs: [String],
        values: [String],
        ownerID: String,
        previous: LibraryRecordSnapshot?
    ) -> [String] {
        values.indices.map { index in
            let metadataID = metadataIDs.indices.contains(index) ? metadataIDs[index] : ""
            if !metadataID.isEmpty {
            if let previous,
               let previousIndex = previous.imageMetadataIDs.firstIndex(of: metadataID),
                   previous.imageValues.indices.contains(previousIndex),
                   previous.imageIdentities.indices.contains(previousIndex) {
                    if previous.imageValues[previousIndex] == values[index] {
                        return previous.imageIdentities[previousIndex]
                    }
                    return "\(ownerID):\(metadataID):\(contentFingerprint(values[index]))"
                }
                return "\(ownerID):\(metadataID):\(contentFingerprint(values[index]))"
            }
            if let previous,
               previous.imageValues.indices.contains(index),
               previous.imageValues[index] == values[index],
               previous.imageIdentities.indices.contains(index) {
                return previous.imageIdentities[index]
            }
            return "\(ownerID):legacy-\(index):\(contentFingerprint(values[index]))"
        }
    }

    private static func contentFingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func plainText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "(?:^|\\s)[.#]?[a-zA-Z][^{}\\n]{0,80}\\{[^}]*\\}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(in object: [String: Any], keys: [String]) -> Date? {
        let iso = ISO8601DateFormatter()
        for key in keys {
            if let value = object[key] as? String, let date = iso.date(from: value) { return date }
            if let value = object[key] as? Double { return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value) }
        }
        return nil
    }
}

enum LibraryWordCardPreviewText {
    static func render(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>|<script[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<\s*(br|/p|/div|/li)\b[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<\s*p\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }
}
