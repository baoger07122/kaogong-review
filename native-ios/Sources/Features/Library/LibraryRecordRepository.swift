import Foundation
import SwiftData

struct LogicComparisonDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var words = ""
    var relation = ""
}

struct ShenlunBiasDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var wrong = ""
    var right = ""
}

struct ShenlunMaterialDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    var content: String

    init(content: String = "") {
        self.content = content
    }
}

struct WordComparisonTermDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var meaning = ""
    var wordID = ""
    var entryKind = WordEntryKind.word.rawValue
    var coreFocus: String?
    var quickDecision: String?
    var legacyID: String?
}

struct LibraryRecordDraft {
    var original: [String: Any] = [:]
    var originalPayload: Data?
    var id = ""
    var subject = "言语理解"
    var module = "逻辑填空"
    var reviewSource: LibraryReviewSource = .real
    var title = ""
    var content = ""
    var type = ""
    var knowledgePoint = ""
    var errorCause = ""
    var centerComprehensionTrap = ""
    var status = "未掌握"
    var isDifficult = false
    var needsReview = false
    var options = ["", "", "", ""]
    var optionImages = ["", "", "", ""]
    var optionImageIDs = [UUID().uuidString, UUID().uuidString, UUID().uuidString, UUID().uuidString]
    var correctOption = ""
    var userOption = ""
    var pitfall = ""
    var reminder = ""
    var quantityStructure = ""
    var weaknessTags = ""
    var quantityErrorCauseIsAuthoritative = false
    var questionSource = ""
    var accuracy = ""
    var questionNumber = ""
    var images: [String] = []
    var imageDisplaySettings: [LibraryImageDisplaySetting] = []
    var compareGroups: [LogicComparisonDraft] = []
    var score = ""
    var totalScore = ""
    var materials: [ShenlunMaterialDraft] = [.init()]
    var dataAnalysisMaterialText = ""
    var myAnswer = ""
    var referenceAnswer = ""
    var myAnswerIssues = ""
    var materialsAnalysis = ""
    var currentAffairsSupplement = ""
    var myFramework = ""
    var standardFramework = ""
    var paragraph = ""
    var bias: [ShenlunBiasDraft] = []
    var wrongList: [String] = []
    var missedList: [String] = []
    var graphRule = ""
    var recognition = ""
    var pencilKitData = ""
    var legacyDrawingPreview = ""
    var mindMapData = ""
    var sourceExamID = ""
    var linkedErrorIDs: [String] = []
    var linkedNoteIDs: [String] = []
    var linkedWordIDs: [String] = []
    var colorHex = "#FFFFFF"
    var pinned = false
    var pinyin = ""
    var sentiment = ""
    var partOfSpeech = ""
    var example = ""
    var myUnderstanding = ""
    var collocations = ""
    var wordSource = ""
    var compareNote = ""
    var commonMeaning = ""
    var wordEntryKind = WordEntryKind.word.rawValue
    var wordCompareTerms: [WordComparisonTermDraft] = []

    init(kind: LibraryContentKind, scope: LibraryScope, record: StoredRecord? = nil) {
        original = record?.jsonObject ?? [:]
        originalPayload = record?.payload
        id = record?.recordID ?? ""
        reviewSource = record == nil
            ? scope.reviewSource
            : (LibraryReviewSource.explicitValue(in: original) ?? ((original["questionBankPaperID"] as? String)?.isEmpty == false ? .real : .pending))
        subject = (original["subject"] as? String)
            ?? ((kind == .errors && (original["isShenlun"] as? Bool) == true) ? "申论" : nil)
            ?? scope.subject
            ?? "言语理解"
        let defaultModules = SubjectDefinition.all.first { $0.name == subject }?.modules ?? []
        let storedModule = (original["module"] as? String) ?? scope.module
        let hasOriginalModule = original["module"] as? String
        if record != nil, subject == "资料分析",
           hasOriginalModule?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            module = hasOriginalModule ?? ""
        } else if subject == "数量关系" {
            let cleanedModule = storedModule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            module = QuantityQuestionTypeCatalog.legacyModules.contains(cleanedModule) ? "" : cleanedModule
        } else {
            module = storedModule ?? defaultModules.first ?? ""
        }
        title = LibraryRecordDraft.text(original, keys: ["title", "question", "name", "words", "text"])
        content = LibraryRecordDraft.text(original, keys: ["judgmentHint", "content", "note", "meaning", "myUnderstanding"])
        if kind == .errors, let note = original["note"] as? String { content = note }
        if content.isEmpty, !(kind == .errors && original["note"] is String), let legacyContent = original["content"] {
            content = LegacyRichTextConverter.html(from: legacyContent)
        }
        type = LibraryRecordDraft.text(original, keys: ["type", "tag", "category"])
        if kind == .words {
            title = LibraryRecordDraft.firstNonEmptyText(original, keys: ["name", "words", "title", "text"])
            type = LibraryRecordDraft.firstNonEmptyText(original, keys: ["category", "type", "tag"])
            let category = WordCategory(rawValue: type) ?? .idiomDefinition
            content = category.isComparison
                ? LibraryRecordDraft.firstNonEmptyText(original, keys: ["judgmentHint", "content", "meaning"])
                : LibraryRecordDraft.firstNonEmptyText(original, keys: ["meaning", "content", "judgmentHint"])
        }
        knowledgePoint = LibraryRecordDraft.text(original, keys: ["knowledgePoint"])
        if let values = original["knowledgePoints"] as? [String], !values.isEmpty {
            knowledgePoint = values.joined(separator: "、")
        }
        quantityErrorCauseIsAuthoritative = LibraryQuantityErrorCauseCompatibility.isAuthoritative(in: original)
        errorCause = kind == .errors && subject == "数量关系"
            ? LibraryQuantityErrorCauseCompatibility.values(in: original).joined(separator: "、")
            : (kind == .errors && LibraryErrorCauseCompatibility.usesLineEditor(subject: subject, module: module)
                ? LibraryErrorCauseCompatibility.rawCause(in: original)
                : LibraryRecordDraft.text(original, keys: ["errorCause", "cause", "reason"]))
        centerComprehensionTrap = original["centerComprehensionTrap"] as? String ?? ""
        status = LibraryRecordDraft.text(original, keys: ["status", "masteryStatus"]).isEmpty ? "未掌握" : LibraryRecordDraft.text(original, keys: ["status", "masteryStatus"])
        isDifficult = (original["isDifficult"] as? Bool) ?? (original["isDifficult"] as? NSNumber)?.boolValue ?? false
        needsReview = (original["needsReview"] as? Bool) ?? (original["needsReview"] as? NSNumber)?.boolValue ?? false
        if let values = original["options"] as? [String], !values.isEmpty {
            options = values + Array(repeating: "", count: max(0, 4 - values.count))
        }
        if let values = original["optionImages"] as? [String], !values.isEmpty {
            optionImages = values + Array(repeating: "", count: max(0, 4 - values.count))
        }
        let storedOptionImageIDs = original["optionImageIDs"] as? [String] ?? []
        optionImageIDs = optionImages.indices.map { index in
            let candidate = index < storedOptionImageIDs.count
                ? storedOptionImageIDs[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return candidate.isEmpty ? UUID().uuidString : candidate
        }
        correctOption = LibraryRecordDraft.text(original, keys: ["correctOption"])
        userOption = LibraryRecordDraft.text(original, keys: ["userOption"])
        pitfall = LibraryRecordDraft.text(original, keys: ["pitfall"])
        reminder = LibraryRecordDraft.text(original, keys: ["reminder"])
        quantityStructure = LibraryRecordDraft.text(original, keys: ["quantityStructure"])
        if let values = original["weaknessTags"] as? [String], !values.isEmpty {
            weaknessTags = values.joined(separator: "、")
        }
        questionSource = LibraryRecordDraft.text(original, keys: ["questionSource", "source"])
        questionNumber = LibraryRecordDraft.text(original, keys: ["questionNumber"])
        accuracy = LibraryRecordDraft.numberText(original["accuracy"])
        images = (original["images"] as? [String]) ?? (original["image"] as? String).map { [$0] } ?? []
        imageDisplaySettings = LibraryImageDisplaySetting.normalized(
            from: original["imageDisplayMetadata"],
            count: images.count
        )
        if let groups = original["compareGroups"] as? [[String: Any]] {
            compareGroups = groups.map { .init(words: $0["words"] as? String ?? "", relation: $0["relation"] as? String ?? "") }
        }
        score = LibraryRecordDraft.numberText(original["score"])
        totalScore = LibraryRecordDraft.numberText(original["totalScore"])
        if let storedMaterials = original["materials"] as? [String], !storedMaterials.isEmpty {
            materials = storedMaterials.map { ShenlunMaterialDraft(content: $0) }
        }
        dataAnalysisMaterialText = LibraryRecordDraft.text(original, keys: ["dataAnalysisMaterialText"])
        myAnswer = LibraryRecordDraft.text(original, keys: ["myAnswer"])
        referenceAnswer = LibraryRecordDraft.text(original, keys: ["referenceAnswer"])
        myAnswerIssues = LibraryRecordDraft.text(original, keys: ["myAnswerIssues"])
        materialsAnalysis = LibraryRecordDraft.text(original, keys: ["materialsAnalysis"])
        currentAffairsSupplement = LibraryRecordDraft.text(original, keys: ["currentAffairsSupplement"])
        myFramework = LibraryRecordDraft.text(original, keys: ["myFramework"])
        standardFramework = LibraryRecordDraft.text(original, keys: ["stdFramework"])
        paragraph = LibraryRecordDraft.text(original, keys: ["paragraph"])
        if let rows = original["bias"] as? [[String: Any]] {
            bias = rows.map { .init(wrong: $0["wrong"] as? String ?? "", right: $0["right"] as? String ?? "") }
        }
        wrongList = original["wrongList"] as? [String] ?? []
        missedList = original["missedList"] as? [String] ?? []
        graphRule = LibraryRecordDraft.text(original, keys: ["graphRule", "patternRule"])
        recognition = LibraryRecordDraft.text(original, keys: ["recognition", "recognitionPath"])
        pencilKitData = LibraryRecordDraft.text(original, keys: ["pencilKitData", "drawingData"])
        legacyDrawingPreview = LibraryRecordDraft.text(original, keys: ["legacyDrawingPreview", "drawingPreview", "handNote", "doodle"])
        mindMapData = LibraryRecordDraft.text(original, keys: ["mindMap", "mindMapData"])
        sourceExamID = LibraryRecordDraft.text(original, keys: ["sourceExamId"])
        linkedErrorIDs = (original["linkedErrors"] as? [String]) ?? (original["relatedErrorIds"] as? [String]) ?? []
        linkedNoteIDs = original["linkedNoteIds"] as? [String] ?? []
        linkedWordIDs = original["linkedWordIds"] as? [String] ?? []
        colorHex = LibraryRecordDraft.text(original, keys: ["color", "colorHex"]).isEmpty ? "#FFFFFF" : LibraryRecordDraft.text(original, keys: ["color", "colorHex"])
        pinned = (original["pinned"] as? Bool) ?? false
        pinyin = LibraryRecordDraft.text(original, keys: ["pinyin"])
        sentiment = LibraryRecordDraft.text(original, keys: ["sentiment"])
        partOfSpeech = LibraryRecordDraft.text(original, keys: ["pos", "partOfSpeech"])
        example = LibraryRecordDraft.text(original, keys: ["example"])
        myUnderstanding = LibraryRecordDraft.text(original, keys: ["myUnderstanding"])
        collocations = LibraryRecordDraft.text(original, keys: ["collocations"])
        wordSource = LibraryRecordDraft.text(original, keys: ["source"])
        compareNote = LibraryRecordDraft.text(original, keys: ["compareNote", "coreDifference"])
        commonMeaning = LibraryRecordDraft.text(original, keys: ["commonMeaning"])
        let storedWordEntryKind = LibraryRecordDraft.text(original, keys: ["entryKind"])
        wordEntryKind = storedWordEntryKind.isEmpty ? WordEntryKind.word.rawValue : storedWordEntryKind
        if let terms = original["compareWords"] as? [[String: Any]] {
            wordCompareTerms = terms.map {
                .init(
                    name: $0["name"] as? String ?? "",
                    meaning: $0["meaning"] as? String ?? "",
                    wordID: ($0["wordId"] as? String) ?? ($0["id"] as? String) ?? "",
                    entryKind: ($0["entryKind"] as? String) ?? WordEntryKind.word.rawValue,
                    coreFocus: ($0["coreFocus"] as? String) ?? ($0["focus"] as? String),
                    quickDecision: ($0["quickDecision"] as? String) ?? ($0["decision"] as? String),
                    legacyID: $0["id"] as? String
                )
            }
            if storedWordEntryKind.isEmpty {
                wordEntryKind = wordCompareTerms.first?.entryKind ?? WordEntryKind.word.rawValue
            }
        } else if type.contains("compare") {
            let names = title.components(separatedBy: " vs ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            wordCompareTerms = names.map { .init(name: $0) }
        }

        if kind == .words {
            partOfSpeech = LibraryRecordDraft.firstNonEmptyText(original, keys: ["pos", "partOfSpeech"])
            compareNote = LibraryRecordDraft.firstNonEmptyText(original, keys: ["compareNote", "coreDifference"])
        }

        if kind == .stickies {
            content = LibraryRecordDraft.text(original, keys: ["content", "text"])
        }
        if kind == .errors, subject == "申论" {
            status = LibraryRecordDraft.text(original, keys: ["status"]).isEmpty ? "待吸收" : LibraryRecordDraft.text(original, keys: ["status"])
        }
    }

    func hasSameEditableValues(as other: LibraryRecordDraft) -> Bool {
        subject == other.subject
            && module == other.module
            && reviewSource == other.reviewSource
            && title == other.title
            && content == other.content
            && type == other.type
            && knowledgePoint == other.knowledgePoint
            && errorCause == other.errorCause
            && centerComprehensionTrap == other.centerComprehensionTrap
            && status == other.status
            && isDifficult == other.isDifficult
            && needsReview == other.needsReview
            && options == other.options
            && optionImages == other.optionImages
            && optionImageIDs == other.optionImageIDs
            && correctOption == other.correctOption
            && userOption == other.userOption
            && pitfall == other.pitfall
            && reminder == other.reminder
            && quantityStructure == other.quantityStructure
            && weaknessTags == other.weaknessTags
            && quantityErrorCauseIsAuthoritative == other.quantityErrorCauseIsAuthoritative
            && questionSource == other.questionSource
            && accuracy == other.accuracy
            && questionNumber == other.questionNumber
            && images == other.images
            && imageDisplaySettings == other.imageDisplaySettings
            && compareGroups == other.compareGroups
            && score == other.score
            && totalScore == other.totalScore
            && materials == other.materials
            && dataAnalysisMaterialText == other.dataAnalysisMaterialText
            && myAnswer == other.myAnswer
            && referenceAnswer == other.referenceAnswer
            && myAnswerIssues == other.myAnswerIssues
            && materialsAnalysis == other.materialsAnalysis
            && currentAffairsSupplement == other.currentAffairsSupplement
            && myFramework == other.myFramework
            && standardFramework == other.standardFramework
            && paragraph == other.paragraph
            && bias == other.bias
            && wrongList == other.wrongList
            && missedList == other.missedList
            && graphRule == other.graphRule
            && recognition == other.recognition
            && pencilKitData == other.pencilKitData
            && legacyDrawingPreview == other.legacyDrawingPreview
            && mindMapData == other.mindMapData
            && sourceExamID == other.sourceExamID
            && linkedErrorIDs == other.linkedErrorIDs
            && linkedNoteIDs == other.linkedNoteIDs
            && linkedWordIDs == other.linkedWordIDs
            && colorHex == other.colorHex
            && pinned == other.pinned
            && pinyin == other.pinyin
            && sentiment == other.sentiment
            && partOfSpeech == other.partOfSpeech
            && example == other.example
            && myUnderstanding == other.myUnderstanding
            && collocations == other.collocations
            && wordSource == other.wordSource
            && compareNote == other.compareNote
            && commonMeaning == other.commonMeaning
            && wordEntryKind == other.wordEntryKind
            && wordCompareTerms == other.wordCompareTerms
    }

    mutating func appendQuestionImage(_ source: String) {
        synchronizeQuestionImageSettings()
        images.append(source)
        imageDisplaySettings.append(LibraryImageDisplaySetting())
    }

    mutating func setOptionImage(_ source: String, at index: Int) {
        guard index >= 0 else { return }
        while optionImages.count <= index { optionImages.append("") }
        while optionImageIDs.count <= index { optionImageIDs.append(UUID().uuidString) }
        guard optionImages[index] != source else { return }
        optionImages[index] = source
        optionImageIDs[index] = UUID().uuidString
    }

    mutating func removeQuestionImage(at index: Int) {
        synchronizeQuestionImageSettings()
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        imageDisplaySettings.remove(at: index)
    }

    mutating func replaceQuestionImage(id: String, with source: String) {
        synchronizeQuestionImageSettings()
        guard let index = imageDisplaySettings.firstIndex(where: { $0.id == id }), images.indices.contains(index) else { return }
        let widthFraction = imageDisplaySettings[index].widthFraction
        images[index] = source
        imageDisplaySettings[index] = LibraryImageDisplaySetting(widthFraction: widthFraction)
    }

    mutating func moveQuestionImage(from sourceIndex: Int, to targetIndex: Int) {
        synchronizeQuestionImageSettings()
        guard images.indices.contains(sourceIndex), imageDisplaySettings.indices.contains(sourceIndex) else { return }
        let image = images.remove(at: sourceIndex)
        let setting = imageDisplaySettings.remove(at: sourceIndex)
        let destination = min(max(targetIndex, 0), images.count)
        images.insert(image, at: destination)
        imageDisplaySettings.insert(setting, at: destination)
    }

    mutating func setQuestionImageWidth(id: String, fraction: Double) {
        synchronizeQuestionImageSettings()
        guard let index = imageDisplaySettings.firstIndex(where: { $0.id == id }) else { return }
        imageDisplaySettings[index].widthFraction = LibraryImageDisplaySetting.normalizedWidthFraction(fraction)
    }

    private mutating func synchronizeQuestionImageSettings() {
        imageDisplaySettings = LibraryImageDisplaySetting.normalized(imageDisplaySettings, count: images.count)
    }

    private static func text(_ object: [String: Any], keys: [String]) -> String {
        for key in keys where object[key] is String { return object[key] as? String ?? "" }
        return ""
    }

    private static func firstNonEmptyText(_ object: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return ""
    }

    private static func numberText(_ value: Any?) -> String {
        if let value = value as? NSNumber { return value.stringValue }
        return value as? String ?? ""
    }
}

enum ShenlunAdaptationError: LocalizedError, Equatable {
    case notShenlunRecord
    case alreadyAdapted
    case contextHasPendingChanges
    case invalidNumber(field: String)

    var errorDescription: String? {
        switch self {
        case .notShenlunRecord:
            return "这条记录不是申论记录，未执行适配。"
        case .alreadyAdapted:
            return "这条申论记录已完成适配，未再次写入。"
        case .contextHasPendingChanges:
            return "当前还有未保存的其他更改。请先保存或取消后再适配；本次未修改记录。"
        case let .invalidNumber(field):
            let label = field == "score" ? "得分" : "总分"
            return "\(label)必须是数字，或留空。"
        }
    }
}

enum LibraryRecordSaveError: LocalizedError {
    case pendingReviewSource
    case invalidExistingPayload(String)
    case recordChanged(String)
    case invalidPreparedIndex

    var errorDescription: String? {
        switch self {
        case .pendingReviewSource:
            "请选择真题复盘或模拟题复盘后再保存。"
        case .invalidExistingPayload(let recordID):
            "记录 \(recordID) 的原始数据无法解析，未覆盖原记录。"
        case .recordChanged(let recordID):
            "记录 \(recordID) 已在其他位置更新，请重新载入后再保存。"
        case .invalidPreparedIndex:
            "题目索引准备失败，未写入记录。"
        }
    }
}

// Captured by value on the main actor. The worker reads this JSON-backed draft
// snapshot and never receives a StoredRecord or ModelContext reference.
fileprivate struct LibraryRecordPayloadPreparationInput: @unchecked Sendable {
    let draft: LibraryRecordDraft
    let kind: LibraryContentKind
    let id: String
    let now: Date
    let existingCreatedAt: Date
    let sourceExamIDToSave: String
    let preservesUnassignedAnalysisModule: Bool
}

private struct LibraryRecordPreparedPayload: Sendable {
    let payload: Data
    let indexPayload: Data
}

private enum LibraryRecordPayloadPreparer {
    static func prepare(input: LibraryRecordPayloadPreparationInput) async throws -> LibraryRecordPreparedPayload {
        try await Task.detached(priority: .userInitiated) {
            let preparationStart = ProcessInfo.processInfo.systemUptime
            let object = LibraryRecordRepository.makePayloadObject(from: input)
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let indexPayload = StoredRecord.makeIndexPayload(from: payload, collection: input.kind.collection) else {
                throw LibraryRecordSaveError.invalidPreparedIndex
            }
            LibraryPerformanceLog.mark("record.save.data-and-index.prepare", since: preparationStart)
            return LibraryRecordPreparedPayload(payload: payload, indexPayload: indexPayload)
        }.value
    }
}

enum LibraryRecordRepository {
    fileprivate static func makePayloadObject(from input: LibraryRecordPayloadPreparationInput) -> [String: Any] {
        let draft = input.draft
        let kind = input.kind
        let id = input.id
        let now = input.now
        let existingCreatedAt = input.existingCreatedAt
        let sourceExamIDToSave = input.sourceExamIDToSave
        let preservesUnassignedAnalysisModule = input.preservesUnassignedAnalysisModule
        var object = draft.original
        let previousPencilKitData = object["pencilKitData"] as? String ?? ""
        object["id"] = id
        object["subject"] = draft.subject
        if preservesUnassignedAnalysisModule {
            if let originalModule = draft.original["module"] as? String {
                object["module"] = originalModule
            } else {
                object.removeValue(forKey: "module")
            }
        } else {
            object["module"] = draft.module
        }
        object["updatedAt"] = iso(now)
        object["createdAt"] = object["createdAt"] ?? iso(existingCreatedAt)

        switch kind {
        case .errors:
            object["reviewSource"] = draft.reviewSource.rawValue
            let knowledgePoints = draft.knowledgePoint
                .split(whereSeparator: { "、,，".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            object["question"] = draft.title
            object["type"] = draft.type.isEmpty ? "错题" : draft.type
            object["note"] = draft.content
            object["knowledgePoints"] = knowledgePoints
            object["knowledgePoint"] = knowledgePoints.first ?? ""
            object["errorCause"] = draft.errorCause
            if LibraryErrorCauseCompatibility.isCenterUnderstanding(subject: draft.subject, module: draft.module) {
                object["centerComprehensionTrap"] = draft.centerComprehensionTrap
            }
            object["status"] = draft.status
            object["isDifficult"] = draft.isDifficult
            object["needsReview"] = draft.needsReview
            var optionCount = max(draft.options.count, draft.optionImages.count)
            while optionCount > 0 {
                let index = optionCount - 1
                let text = index < draft.options.count ? draft.options[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let image = index < draft.optionImages.count ? draft.optionImages[index] : ""
                if !text.isEmpty || !image.isEmpty { break }
                optionCount -= 1
            }
            object["options"] = (0..<optionCount).map { $0 < draft.options.count ? draft.options[$0] : "" }
            object["optionImages"] = (0..<optionCount).map { $0 < draft.optionImages.count ? draft.optionImages[$0] : "" }
            object["optionImageIDs"] = (0..<optionCount).map { index in
                index < draft.optionImageIDs.count ? draft.optionImageIDs[index] : UUID().uuidString
            }
            object["correctOption"] = draft.correctOption
            object["userOption"] = draft.userOption
            object["reminder"] = draft.reminder
            object["quantityStructure"] = draft.quantityStructure
            if draft.subject == "数量关系" {
                if let legacyWeaknessTags = draft.original["weaknessTags"] {
                    object["weaknessTags"] = legacyWeaknessTags
                }
                LibraryQuantityErrorCauseCompatibility.markAuthoritative(in: &object)
            } else {
                object["weaknessTags"] = splitList(draft.weaknessTags)
            }
            object["questionSource"] = draft.questionSource
            object["questionNumber"] = draft.questionNumber
            if draft.subject == "资料分析" {
                if draft.dataAnalysisMaterialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    object.removeValue(forKey: "dataAnalysisMaterialText")
                } else {
                    object["dataAnalysisMaterialText"] = draft.dataAnalysisMaterialText
                }
            }
            let sourceMetadata = QuestionSourceMetadata.parse(draft.questionSource)
            object["sourceYear"] = sourceMetadata.year.map { $0 as Any } ?? NSNull()
            object["sourceExamType"] = sourceMetadata.examType.map { $0 as Any } ?? NSNull()
            object["sourceRegion"] = sourceMetadata.region.map { $0 as Any } ?? NSNull()
            object["accuracy"] = Double(draft.accuracy.replacingOccurrences(of: "%", with: "")) ?? 0
            object["images"] = draft.images
            object.removeValue(forKey: "image")
            let imageDisplaySettings = LibraryImageDisplaySetting.normalized(
                draft.imageDisplaySettings,
                count: draft.images.count
            )
            if imageDisplaySettings.isEmpty {
                object.removeValue(forKey: "imageDisplayMetadata")
            } else {
                object["imageDisplayMetadata"] = imageDisplaySettings.map(\.payloadObject)
            }
            object["graphRule"] = draft.graphRule
            object["recognition"] = draft.recognition
            object["sourceExamId"] = sourceExamIDToSave.isEmpty ? NSNull() : sourceExamIDToSave
            object["linkedNoteIds"] = draft.linkedNoteIDs
            object["linkedWordIds"] = draft.linkedWordIDs
            object["pencilKitData"] = draft.pencilKitData
            if draft.legacyDrawingPreview.isEmpty {
                if draft.pencilKitData.isEmpty, !previousPencilKitData.isEmpty {
                    object.removeValue(forKey: "drawingPreview")
                    object.removeValue(forKey: "handNote")
                }
            } else {
                object["legacyDrawingPreview"] = draft.legacyDrawingPreview
                object["drawingPreview"] = draft.legacyDrawingPreview
            }
            object["reviewCount"] = object["reviewCount"] ?? 0
            object["lastReviewDate"] = object["lastReviewDate"] ?? iso(now)
            if draft.subject == "申论" {
                object["isShenlun"] = true
                object["shenlunFormatVersion"] = ShenlunRecordFormat.currentVersion
                if let score = Int(draft.score.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    object["score"] = score
                } else {
                    object.removeValue(forKey: "score")
                }
                if let totalScore = Int(draft.totalScore.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    object["totalScore"] = totalScore
                } else {
                    object.removeValue(forKey: "totalScore")
                }
                object["source"] = draft.questionSource
                object["materials"] = draft.materials
                    .map(\.content)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                object["myAnswer"] = draft.myAnswer
                object["referenceAnswer"] = draft.referenceAnswer
                object["myAnswerIssues"] = draft.myAnswerIssues
                object["materialsAnalysis"] = draft.materialsAnalysis
                object["currentAffairsSupplement"] = draft.currentAffairsSupplement
                object["myFramework"] = draft.myFramework
                object["stdFramework"] = draft.standardFramework
                object["paragraph"] = draft.paragraph
                object["bias"] = draft.bias.filter { !$0.wrong.isEmpty || !$0.right.isEmpty }.map { ["wrong": $0.wrong, "right": $0.right] }
                object["wrongList"] = draft.wrongList.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                object["missedList"] = draft.missedList.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                object["knowledgePoints"] = []
                object["options"] = []
                object["errorCause"] = ""
            }
        case .notes:
            object["reviewSource"] = draft.reviewSource.rawValue
            object["title"] = draft.title
            object["content"] = draft.content
            object["type"] = draft.type
            object["knowledgePoint"] = draft.knowledgePoint
            object["knowledgePoints"] = splitList(draft.knowledgePoint)
            object["quantityStructure"] = draft.quantityStructure
            object["weaknessTags"] = splitList(draft.weaknessTags)
            object["linkedErrors"] = draft.linkedErrorIDs
            object["linkedReviews"] = object["linkedReviews"] ?? []
            object["mindMap"] = draft.mindMapData
            object["pencilKitData"] = draft.pencilKitData
            if draft.legacyDrawingPreview.isEmpty {
                if draft.pencilKitData.isEmpty, !previousPencilKitData.isEmpty {
                    object.removeValue(forKey: "drawingPreview")
                    object.removeValue(forKey: "doodle")
                }
            } else {
                object["legacyDrawingPreview"] = draft.legacyDrawingPreview
                object["drawingPreview"] = draft.legacyDrawingPreview
            }
        case .stickies:
            object["reviewSource"] = draft.reviewSource.rawValue
            object["content"] = draft.content
            object["tag"] = draft.type.trimmingCharacters(in: .whitespacesAndNewlines)
            object["color"] = draft.colorHex
            object["pinned"] = draft.pinned
        case .words:
            let category = wordCategory(from: draft.type)
            object["name"] = draft.title
            object["words"] = draft.title
            object["meaning"] = category.isComparison ? "" : draft.content
            object["judgmentHint"] = category.isComparison ? draft.content : ""
            object["category"] = draft.type
            object["type"] = draft.type
            object["entryKind"] = draft.wordEntryKind
            object["commonMeaning"] = draft.commonMeaning
            object["linkedErrors"] = draft.linkedErrorIDs
            object["relatedErrorIds"] = draft.linkedErrorIDs
            object["pinyin"] = draft.pinyin
            object["sentiment"] = draft.sentiment
            object["pos"] = draft.partOfSpeech
            object["example"] = draft.example
            object["myUnderstanding"] = draft.myUnderstanding
            object["collocations"] = draft.collocations
            object["source"] = draft.wordSource
            object["compareNote"] = draft.compareNote
            object["compareWords"] = draft.wordCompareTerms
                .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { term -> [String: Any] in
                    var value: [String: Any] = [
                        "name": term.name,
                        "meaning": term.meaning,
                        "wordId": term.wordID,
                        "entryKind": draft.wordEntryKind
                    ]
                    if let legacyID = term.legacyID, !legacyID.isEmpty { value["id"] = legacyID }
                    if category == .wordComparison {
                        if let coreFocus = term.coreFocus, !coreFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            value["coreFocus"] = coreFocus
                        }
                        if let quickDecision = term.quickDecision, !quickDecision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            value["quickDecision"] = quickDecision
                        }
                    }
                    return value
                }
        }

        return object
    }

    @MainActor
    @discardableResult static func save(
        kind: LibraryContentKind,
        draft: LibraryRecordDraft,
        records: [StoredRecord],
        context: ModelContext
    ) async throws -> String {
        guard kind != .errors || draft.reviewSource != .pending else {
            throw LibraryRecordSaveError.pendingReviewSource
        }
        let performanceStart = ProcessInfo.processInfo.systemUptime
        let now = Date()
        let id = draft.id.isEmpty ? makeID(kind: kind) : draft.id
        let existing = records.first { $0.collection == kind.collection && $0.recordID == id }
        let expectedExistingPayload = existing?.payload
        let expectedExistingUpdatedAt = existing?.updatedAt
        if let existing {
            guard let _ = existing.jsonObject else {
                throw LibraryRecordSaveError.invalidExistingPayload(existing.recordID)
            }
            guard let originalPayload = draft.originalPayload,
                  originalPayload == existing.payload else {
                throw LibraryRecordSaveError.recordChanged(existing.recordID)
            }
        }
        var sourceExamIDToSave = draft.sourceExamID
        if kind == .errors, !sourceExamIDToSave.isEmpty {
            let exam = records.first { $0.collection == "exams" && $0.recordID == sourceExamIDToSave }
            if exam == nil
                || LibraryReviewSource.explicitValue(in: exam?.indexObject ?? [:]) != draft.reviewSource {
                sourceExamIDToSave = ""
            }
        }
        let previousSourceExamID = draft.original["sourceExamId"] as? String ?? ""
        let previousLinkedErrors = (draft.original["linkedErrors"] as? [String]) ?? (draft.original["relatedErrorIds"] as? [String]) ?? []
        let previousLinkedNotes = draft.original["linkedNoteIds"] as? [String] ?? []
        let previousLinkedWords = draft.original["linkedWordIds"] as? [String] ?? []
        let preservesUnassignedAnalysisModule = existing != nil
            && draft.subject == "资料分析"
            && draft.module.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (draft.original["module"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        let payloadInput = LibraryRecordPayloadPreparationInput(
            draft: draft,
            kind: kind,
            id: id,
            now: now,
            existingCreatedAt: existing?.createdAt ?? now,
            sourceExamIDToSave: sourceExamIDToSave,
            preservesUnassignedAnalysisModule: preservesUnassignedAnalysisModule
        )
        let preparedPayload = try await LibraryRecordPayloadPreparer.prepare(input: payloadInput)

        let transactionStart = ProcessInfo.processInfo.systemUptime
        try context.transaction {
            if let existing {
                guard existing.payload == expectedExistingPayload,
                      existing.updatedAt == expectedExistingUpdatedAt,
                      existing.payload == draft.originalPayload else {
                    throw LibraryRecordSaveError.recordChanged(existing.recordID)
                }
            }
            if kind == .errors || (kind == .notes && draft.subject == "数量关系") {
                try TagLibraryRepository.add(
                    splitList(draft.knowledgePoint),
                    kind: .knowledgePoint,
                    module: draft.module,
                    records: records,
                    context: context,
                    persist: false
                )
                if kind == .errors,
                   !LibraryErrorCauseCompatibility.usesLineEditor(subject: draft.subject, module: draft.module),
                   !(draft.subject == "判断推理" && draft.module == "类比推理") {
                    let causes = draft.subject == "数量关系"
                        ? LibraryQuantityErrorCauseCompatibility.values(
                            errorCause: draft.errorCause,
                            weaknessTags: nil,
                            authoritative: true
                        )
                        : [draft.errorCause]
                    try TagLibraryRepository.add(
                        causes,
                        kind: .errorCause,
                        module: draft.module,
                        records: records,
                        context: context,
                        persist: false
                    )
                }
            }
            if let existing {
                existing.replacePayload(
                    preparedPayload.payload,
                    indexPayload: preparedPayload.indexPayload
                )
                existing.subject = draft.subject
                existing.module = preservesUnassignedAnalysisModule ? draft.original["module"] as? String : draft.module
                existing.updatedAt = now
            } else {
                context.insert(StoredRecord(
                    collection: kind.collection,
                    recordID: id,
                    payload: preparedPayload.payload,
                    subject: draft.subject,
                    module: draft.module,
                    createdAt: now,
                    updatedAt: now,
                    precomputedIndexPayload: preparedPayload.indexPayload
                ))
            }
            switch kind {
            case .errors:
                try syncSingleRelation(collection: "exams", arrayKey: "linkedErrorIds", oldID: previousSourceExamID, newID: sourceExamIDToSave, linkedID: id, records: records)
                try syncArrayRelations(collection: "notes", arrayKey: "linkedErrors", oldIDs: previousLinkedNotes, newIDs: draft.linkedNoteIDs, linkedID: id, records: records)
                try syncArrayRelations(collection: "words", arrayKey: "linkedErrors", oldIDs: previousLinkedWords, newIDs: draft.linkedWordIDs, linkedID: id, records: records)
                try syncArrayRelations(collection: "words", arrayKey: "relatedErrorIds", oldIDs: previousLinkedWords, newIDs: draft.linkedWordIDs, linkedID: id, records: records)
                if existing == nil, draft.reviewSource == .mock {
                    try LibraryMockExamMemory.remember(sourceExamIDToSave, records: records, context: context)
                }
            case .notes:
                try syncArrayRelations(collection: "errors", arrayKey: "linkedNoteIds", oldIDs: previousLinkedErrors, newIDs: draft.linkedErrorIDs, linkedID: id, records: records)
            case .words:
                try syncArrayRelations(collection: "errors", arrayKey: "linkedWordIds", oldIDs: previousLinkedErrors, newIDs: draft.linkedErrorIDs, linkedID: id, records: records)
            case .stickies:
                break
            }
        }
        LibraryPerformanceLog.mark("record.save.transaction", since: transactionStart)
        let contextSaveStart = ProcessInfo.processInfo.systemUptime
        try context.save()
        LibraryPerformanceLog.mark("record.save.context", since: contextSaveStart)
        LibraryPerformanceLog.mark("record.save.total", since: performanceStart)
        return id
    }

    /// Converts one legacy 申论 payload after the user has reviewed every
    /// destination field. The original bytes and canonical payload are saved
    /// together in one transaction; the first backup is never overwritten.
    static func adaptShenlunRecord(
        record: StoredRecord,
        values: ShenlunAdaptationValues,
        context: ModelContext
    ) throws {
        guard record.isShenlunRecord else { throw ShenlunAdaptationError.notShenlunRecord }
        guard record.requiresShenlunAdaptation else { throw ShenlunAdaptationError.alreadyAdapted }
        guard !context.hasChanges else { throw ShenlunAdaptationError.contextHasPendingChanges }

        let backupID = record.recordID
        let backupCompoundID = "\(ShenlunRecordFormat.backupCollection):\(backupID)"
        let backupDescriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.compoundID == backupCompoundID }
        )
        let backup = try context.fetch(backupDescriptor).first
        let snapshot: StoredRecord?
        if backup == nil {
            snapshot = StoredRecord(
                collection: ShenlunRecordFormat.backupCollection,
                recordID: backupID,
                payload: record.payload,
                subject: record.subject,
                module: record.module,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        } else {
            snapshot = nil
        }

        var object = record.jsonObject ?? [:]
        let now = Date()
        object["id"] = record.recordID
        object["subject"] = "申论"
        let module = values.questionType.trimmingCharacters(in: .whitespacesAndNewlines)
        object["module"] = module.isEmpty ? (record.module ?? "") : module
        object["isShenlun"] = true
        object["shenlunFormatVersion"] = ShenlunRecordFormat.currentVersion
        object["updatedAt"] = iso(now)
        if object["createdAt"] == nil, let createdAt = record.createdAt {
            object["createdAt"] = iso(createdAt)
        }

        setText(values.question, keys: ["question"], in: &object)
        setText(values.questionSource, keys: ["questionSource", "source"], in: &object)
        setText(values.questionNumber, keys: ["questionNumber"], in: &object)
        try setInteger(values.score, key: "score", in: &object)
        try setInteger(values.totalScore, key: "totalScore", in: &object)
        setText(values.currentAffairsSupplement, keys: ["currentAffairsSupplement"], in: &object)
        setText(values.myAnswer, keys: ["myAnswer"], in: &object)
        setText(values.referenceAnswer, keys: ["referenceAnswer"], in: &object)
        setText(values.myAnswerIssues, keys: ["myAnswerIssues"], in: &object)
        setText(values.materialsAnalysis, keys: ["materialsAnalysis"], in: &object)
        setText(values.reviewNote, keys: ["note"], in: &object)
        object["materials"] = values.materials
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let wasAutosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = wasAutosaveEnabled }

        do {
            try context.transaction {
                if let snapshot { context.insert(snapshot) }
                record.replacePayload(payload)
                record.subject = "申论"
                record.module = object["module"] as? String
                record.updatedAt = now
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func setText(_ value: String, keys: [String], in object: inout [String: Any]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for key in keys { object.removeValue(forKey: key) }
        if !trimmed.isEmpty { object[keys[0]] = value }
    }

    private static func setInteger(_ value: String, key: String, in object: inout [String: Any]) throws {
        object.removeValue(forKey: key)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let number = Int(trimmed) else { throw ShenlunAdaptationError.invalidNumber(field: key) }
        object[key] = number
    }

    private static func splitList(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func wordCategory(from value: String) -> WordCategory {
        WordCategory(rawValue: value) ?? .idiomDefinition
    }

    @MainActor
    static func updateLinkedWords(
        error: StoredRecord,
        newIDs: [String],
        wordRecords: [StoredRecord],
        context: ModelContext
    ) throws {
        var object = error.jsonObject ?? [:]
        let linkedWordIDs = object["linkedWordIds"] as? [String] ?? []
        let reverseWordIDs = wordRecords.compactMap { word -> String? in
            guard word.collection == "words" else { return nil }
            let wordObject = word.jsonObject ?? [:]
            let directIDs = wordObject["linkedErrors"] as? [String] ?? []
            let legacyIDs = wordObject["relatedErrorIds"] as? [String] ?? []
            return (directIDs + legacyIDs).contains(error.recordID) ? word.recordID : nil
        }
        let existingWordIDs = Set(wordRecords.filter { $0.collection == "words" }.map(\.recordID))
        let oldIDs = LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
            linkedWordIDs + reverseWordIDs,
            existingIDs: existingWordIDs
        )
        let uniqueIDs = LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
            newIDs,
            existingIDs: existingWordIDs
        )
        let now = Date.now
        try context.transaction {
            object["linkedWordIds"] = uniqueIDs
            object["updatedAt"] = iso(now)
            error.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            error.updatedAt = now
            try syncArrayRelations(
                collection: "words", arrayKey: "linkedErrors",
                oldIDs: oldIDs, newIDs: uniqueIDs, linkedID: error.recordID, records: wordRecords
            )
            try syncArrayRelations(
                collection: "words", arrayKey: "relatedErrorIds",
                oldIDs: oldIDs, newIDs: uniqueIDs, linkedID: error.recordID, records: wordRecords
            )
        }
        try context.save()
    }

    @MainActor
    static func updateLinkedErrors(
        word: StoredRecord,
        newIDs: [String],
        errorRecords: [StoredRecord],
        context: ModelContext
    ) throws {
        var object = word.jsonObject ?? [:]
        let reverseErrorIDs = errorRecords.compactMap { error -> String? in
            guard error.collection == "errors" else { return nil }
            return (error.jsonObject?["linkedWordIds"] as? [String] ?? []).contains(word.recordID)
                ? error.recordID
                : nil
        }
        let existingErrorIDs = Set(errorRecords.filter { $0.collection == "errors" }.map(\.recordID))
        let oldIDs = LibraryWordErrorAssociationPolicy.resolvedErrorIDs(
            linkedErrors: object["linkedErrors"] as? [String],
            relatedErrorIDs: object["relatedErrorIds"] as? [String],
            reverseLinkedErrorIDs: reverseErrorIDs,
            existingErrorIDs: existingErrorIDs
        )
        let uniqueIDs = LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
            newIDs,
            existingIDs: existingErrorIDs
        )
        let now = Date.now
        try context.transaction {
            object["linkedErrors"] = uniqueIDs
            object["relatedErrorIds"] = uniqueIDs
            object["updatedAt"] = iso(now)
            word.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            word.updatedAt = now
            try syncArrayRelations(
                collection: "errors",
                arrayKey: "linkedWordIds",
                oldIDs: oldIDs,
                newIDs: uniqueIDs,
                linkedID: word.recordID,
                records: errorRecords
            )
        }
        try context.save()
    }

    @MainActor
    static func remove(kind: LibraryContentKind, id: String, records: [StoredRecord], context: ModelContext) throws {
        guard let record = records.first(where: { $0.collection == kind.collection && $0.recordID == id }) else { return }
        let object = record.jsonObject ?? [:]
        try context.transaction {
            switch kind {
            case .errors:
                let reverseWordIDs = records.compactMap { word -> String? in
                    guard word.collection == "words" else { return nil }
                    let wordObject = word.compatibilityIndexObject ?? [:]
                    let directErrorIDs = wordObject["linkedErrors"] as? [String] ?? []
                    let legacyErrorIDs = wordObject["relatedErrorIds"] as? [String] ?? []
                    return (directErrorIDs + legacyErrorIDs).contains(id) ? word.recordID : nil
                }
                let linkedWordIDs = LibraryWordErrorAssociationPolicy.uniqueExistingIDs(
                    (object["linkedWordIds"] as? [String] ?? []) + reverseWordIDs,
                    existingIDs: Set(records.filter { $0.collection == "words" }.map(\.recordID))
                )
                try syncSingleRelation(
                    collection: "exams", arrayKey: "linkedErrorIds",
                    oldID: object["sourceExamId"] as? String ?? "", newID: "", linkedID: id, records: records
                )
                try syncArrayRelations(
                    collection: "notes", arrayKey: "linkedErrors",
                    oldIDs: object["linkedNoteIds"] as? [String] ?? [], newIDs: [], linkedID: id, records: records
                )
                try syncArrayRelations(
                    collection: "words", arrayKey: "linkedErrors",
                    oldIDs: linkedWordIDs, newIDs: [], linkedID: id, records: records
                )
                try syncArrayRelations(
                    collection: "words", arrayKey: "relatedErrorIds",
                    oldIDs: linkedWordIDs, newIDs: [], linkedID: id, records: records
                )
            case .notes:
                try syncArrayRelations(
                    collection: "errors", arrayKey: "linkedNoteIds",
                    oldIDs: object["linkedErrors"] as? [String] ?? [], newIDs: [], linkedID: id, records: records
                )
            case .words:
                let reverseErrorIDs = records.compactMap { error -> String? in
                    guard error.collection == "errors" else { return nil }
                    return (error.compatibilityIndexObject?["linkedWordIds"] as? [String] ?? []).contains(id)
                        ? error.recordID
                        : nil
                }
                let linkedErrorIDs = LibraryWordErrorAssociationPolicy.resolvedErrorIDs(
                    linkedErrors: object["linkedErrors"] as? [String],
                    relatedErrorIDs: object["relatedErrorIds"] as? [String],
                    reverseLinkedErrorIDs: reverseErrorIDs,
                    existingErrorIDs: Set(records.filter { $0.collection == "errors" }.map(\.recordID))
                )
                try syncArrayRelations(
                    collection: "errors", arrayKey: "linkedWordIds",
                    oldIDs: linkedErrorIDs, newIDs: [], linkedID: id, records: records
                )
            case .stickies:
                break
            }
            context.delete(record)
        }
        try context.save()
    }

    private static func makeID(kind: LibraryContentKind) -> String {
        let prefix: String
        switch kind {
        case .errors: prefix = "err"
        case .notes: prefix = "note"
        case .stickies: prefix = "sticky"
        case .words: prefix = "word"
        }
        return "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))"
    }

    private static func syncSingleRelation(
        collection: String, arrayKey: String, oldID: String, newID: String,
        linkedID: String, records: [StoredRecord]
    ) throws {
        if !oldID.isEmpty, oldID != newID,
           let record = records.first(where: { $0.collection == collection && $0.recordID == oldID }) {
            try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: false)
        }
        if !newID.isEmpty, oldID != newID,
           let record = records.first(where: { $0.collection == collection && $0.recordID == newID }) {
            try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: true)
        }
    }

    private static func syncArrayRelations(
        collection: String, arrayKey: String, oldIDs: [String], newIDs: [String],
        linkedID: String, records: [StoredRecord]
    ) throws {
        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)
        for relationID in oldSet.subtracting(newSet) {
            if let record = records.first(where: { $0.collection == collection && $0.recordID == relationID }) {
                try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: false)
            }
        }
        for relationID in newSet.subtracting(oldSet) {
            if let record = records.first(where: { $0.collection == collection && $0.recordID == relationID }) {
                try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: true)
            }
        }
    }

    private static func updateRelation(record: StoredRecord, key: String, linkedID: String, include: Bool) throws {
        var object = record.jsonObject ?? [:]
        var values = Set(object[key] as? [String] ?? [])
        guard values.contains(linkedID) != include else { return }
        if include { values.insert(linkedID) } else { values.remove(linkedID) }
        object[key] = Array(values).sorted()
        object["updatedAt"] = iso(.now)
        record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        record.updatedAt = .now
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

enum QuestionBankErrorBookCategory: String, CaseIterable {
    case wrong = "错题"
    case uncertain = "不确定题"
    case cannotSolve = "不会做"
}

private struct QuestionSourceMetadata {
    let year: String?
    let examType: String?
    let region: String?

    static func parse(_ rawValue: String) -> QuestionSourceMetadata {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = firstCapture(#"(20\d{2})"#, in: value)
        let examType = ["国考", "省考", "联考", "事业单位", "选调生", "三支一扶"]
            .first(where: value.contains)
        var region: String?
        if examType == "省考" {
            region = firstCapture(#"([\p{Han}]{2,8}?)(?:省)?省考"#, in: value)
        }
        return QuestionSourceMetadata(year: year, examType: examType, region: region)
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        guard let match = expression.firstMatch(in: value, range: range), match.numberOfRanges > 1 else { return nil }
        return nsValue.substring(with: match.range(at: 1))
    }
}
