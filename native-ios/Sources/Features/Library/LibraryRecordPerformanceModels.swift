import Foundation

struct LibraryRecordDataVersion: Equatable, Hashable {
    let updatedAt: Date?
    let payloadByteCount: Int
    let indexPayloadByteCount: Int
}

struct LibraryVisibleErrorRecordRevision: Equatable {
    let compoundID: String
    let recordID: String
    let collection: String
    let subject: String?
    let module: String?
    let createdAt: Date?
    let dataVersion: LibraryRecordDataVersion
}

struct LibraryVisibleErrorRecordQuery: Equatable {
    let revisions: [LibraryVisibleErrorRecordRevision]
    let collection: String
    let subject: String?
    let module: String?
    let quantityType: String
    let reviewSource: String
    let sourceExamTitleRevision: Int
    let selectedTag: String
    let normalizedSearch: String
    let includesMastered: Bool
}

struct LibraryRecordFilterIndex {
    let status: String?
    let libraryTagValues: [String]
    let snapshotTags: [String]
    let searchableText: String

    init(
        collection: String,
        storedSubject: String?,
        indexObject: [String: Any],
        compatibleObject: [String: Any],
        isMockReview: Bool,
        sourceExamTitle: String
    ) {
        let subject = [storedSubject, compatibleObject["subject"] as? String]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        status = Self.firstText(in: compatibleObject, keys: ["status", "masteryStatus"])
        libraryTagValues = Self.makeLibraryTagValues(
            collection: collection,
            storedSubject: storedSubject,
            indexObject: indexObject,
            dataAnalysisCauseObject: compatibleObject
        )

        var snapshotTagValues: [String] = []
        if collection != "words",
           let type = Self.firstText(in: compatibleObject, keys: ["type", "category", "errorCause"]) {
            snapshotTagValues.append(type)
        }
        if collection == "errors" {
            if Self.bool(in: compatibleObject, key: "isDifficult") { snapshotTagValues.append("难题") }
            if Self.bool(in: compatibleObject, key: "needsReview") { snapshotTagValues.append("待复习") }
        }
        if let points = compatibleObject["knowledgePoints"] as? [String] {
            snapshotTagValues.append(contentsOf: points)
        }
        let quantityErrorCauses = collection == "errors" && subject == "数量关系"
            ? LibraryQuantityErrorCauseCompatibility.values(in: compatibleObject)
            : []
        let weaknessTags = (compatibleObject["weaknessTags"] as? [String] ?? []).map(Self.plainText)
        if collection == "errors", subject == "数量关系" {
            snapshotTagValues.append(contentsOf: quantityErrorCauses)
        } else {
            snapshotTagValues.append(contentsOf: weaknessTags)
        }
        if let point = Self.firstText(in: compatibleObject, keys: ["knowledgePoint"]) {
            snapshotTagValues.append(point)
        }
        var seenSnapshotTags = Set<String>()
        snapshotTags = snapshotTagValues.filter { !$0.isEmpty && seenSnapshotTags.insert($0).inserted }

        let titleKeys = collection == "errors"
            ? ["question", "title", "name", "text", "content"]
            : ["title", "question", "name", "words", "text", "content"]
        let title = Self.firstText(in: compatibleObject, keys: titleKeys).map(Self.plainText) ?? "未命名记录"
        let isShenlun = collection == "errors"
            && (storedSubject == "申论"
                || compatibleObject["subject"] as? String == "申论"
                || (compatibleObject["isShenlun"] as? Bool) == true)
        let summaryKeys = isShenlun
            ? ["question", "title"]
            : ["judgmentHint", "commonMeaning", "compareNote", "content", "note", "errorNote", "meaning", "myUnderstanding", "relation", "coreDifference", "question"]
        let summary = Self.firstText(in: compatibleObject, keys: summaryKeys).map(Self.plainText) ?? ""
        let quantityStructure = Self.firstText(in: compatibleObject, keys: ["quantityStructure"]).map(Self.plainText) ?? ""
        let dataAnalysisMaterial = Self.firstText(in: compatibleObject, keys: ["dataAnalysisMaterialText"]).map(Self.plainText) ?? ""
        let questionSource = Self.firstText(in: compatibleObject, keys: ["questionSource", "source"]).map(Self.plainText) ?? ""
        let questionNumber = Self.firstText(in: compatibleObject, keys: ["questionNumber"]).map(Self.plainText) ?? ""
        let pitfall = Self.firstText(in: compatibleObject, keys: ["pitfall", "misconception", "thinkingTrap"]).map(Self.plainText) ?? ""
        let reminder = Self.firstText(in: compatibleObject, keys: ["reminder"]).map(Self.plainText) ?? ""
        let searchableSource = isMockReview ? sourceExamTitle : questionSource
        var searchValues = [title, summary, quantityStructure, dataAnalysisMaterial, searchableSource, questionNumber, pitfall, reminder]
        searchValues.append(contentsOf: snapshotTags)
        if collection == "errors", subject == "数量关系" {
            searchValues.append(contentsOf: quantityErrorCauses)
        } else {
            searchValues.append(contentsOf: weaknessTags)
        }
        searchValues.append(contentsOf: ["pinyin", "meaning", "judgmentHint", "commonMeaning", "example", "compareNote", "myUnderstanding", "collocations", "pos"]
            .compactMap { compatibleObject[$0] as? String })
        if let terms = compatibleObject["compareWords"] as? [[String: Any]] {
            searchValues.append(contentsOf: terms.flatMap {
                [$0["name"] as? String, $0["meaning"] as? String].compactMap { $0 }
            })
        }
        searchableText = searchValues.joined(separator: "\n")
    }

    func matches(selectedTag: String, normalizedSearch: String, includesMastered: Bool) -> Bool {
        if !selectedTag.isEmpty,
           (!libraryTagValues.contains(selectedTag) || !snapshotTags.contains(selectedTag)) {
            return false
        }
        if !includesMastered, status == "已掌握" { return false }
        if !normalizedSearch.isEmpty,
           !Self.normalized(searchableText).contains(normalizedSearch) {
            return false
        }
        return true
    }

    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }

    static func makeLibraryTagValues(
        collection: String,
        storedSubject: String?,
        indexObject: [String: Any],
        dataAnalysisCauseObject: [String: Any]
    ) -> [String] {
        let isDataAnalysis = storedSubject == "资料分析"
            || indexObject["subject"] as? String == "资料分析"
        var values: [String] = []
        let baseTagKeys = isDataAnalysis ? ["type", "category"] : ["type", "category", "errorCause"]
        if let baseTag = baseTagKeys
            .compactMap({ indexObject[$0] as? String })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            values.append(baseTag)
        }
        if collection == "errors" {
            if bool(in: indexObject, key: "isDifficult") { values.append("难题") }
            if bool(in: indexObject, key: "needsReview") { values.append("待复习") }
        }
        if let points = indexObject["knowledgePoints"] as? [String] {
            values.append(contentsOf: points)
        } else if let point = indexObject["knowledgePoint"] as? String {
            values.append(contentsOf: point.split(whereSeparator: { "、,，".contains($0) }).map(String.init))
        }
        if storedSubject == "数量关系" || indexObject["subject"] as? String == "数量关系" {
            values.append(contentsOf: LibraryQuantityErrorCauseCompatibility.values(in: indexObject))
        } else if isDataAnalysis {
            values.append(contentsOf: LibraryDataAnalysisCauseLayout.splitLines(
                LibraryDataAnalysisCauseLayout.rawCause(in: dataAnalysisCauseObject)
            ))
        } else {
            values.append(contentsOf: indexObject["weaknessTags"] as? [String] ?? [])
        }
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func firstText(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func bool(in object: [String: Any], key: String) -> Bool {
        (object[key] as? Bool) ?? (object[key] as? NSNumber)?.boolValue ?? false
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
}

struct LibraryRecordSwipePreviewContent: Equatable {
    let subjectLine: String
    let title: String
    let options: [String]

    init(subject: String?, module: String?, indexPayload: Data?, payload: Data) {
        let indexedObject = Self.decode(indexPayload)
        let object: [String: Any]
        if let indexedObject, Self.hasPreviewFields(indexedObject) {
            object = indexedObject
        } else {
            object = Self.decode(payload) ?? indexedObject ?? [:]
        }
        let moduleText = module?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subjectText = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        subjectLine = moduleText.isEmpty ? subjectText : moduleText
        title = [object["question"] as? String, object["title"] as? String, object["content"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "未命名题目"
        options = object["options"] as? [String] ?? []
    }

    private static func decode(_ data: Data?) -> [String: Any]? {
        guard let data,
              let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else { return nil }
        return object
    }

    private static func hasPreviewFields(_ object: [String: Any]) -> Bool {
        let hasText = ["question", "title", "content"].contains { key in
            (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let hasOptions = (object["options"] as? [String])?.isEmpty == false
        return hasText || hasOptions
    }
}
