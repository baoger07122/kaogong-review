import Foundation
import SwiftData

struct QuestionBankLibraryTypeMapping: Equatable {
    let subject: String
    let module: String

    var displayName: String {
        [subject, module].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func resolve(subject rawSubject: String, type rawType: String, moduleTitle rawModule: String?) -> Self {
        let subject = rawSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        let module = QuestionBankModuleTitle.normalized(rawModule)
        if let exact = SubjectDefinition.all.first(where: { $0.name == subject }) {
            return Self(subject: exact.name, module: specificModule(for: exact, type: type, module: module))
        }

        if let moduleSubject = SubjectDefinition.all.first(where: {
            $0.name != "数量关系" && ($0.modules.contains(module) || $0.modules.contains(type))
        }) {
            return Self(subject: moduleSubject.name, module: specificModule(for: moduleSubject, type: type, module: module))
        }

        let explicitCoarse = QuestionBankCoarseModule.classify(explicitModuleTitle: module)
        let subjectCoarse = QuestionBankCoarseModule.classify(explicitModuleTitle: subject)
        let typeCoarse = QuestionBankCoarseModule.classify(explicitModuleTitle: type)
        let coarse = [explicitCoarse, subjectCoarse, typeCoarse].first { $0 != .uncategorized }
        if let coarse, coarse != .uncategorized {
            let definition = SubjectDefinition.all.first { $0.name == coarse.rawValue }
            let resolvedModule = definition.map { specificModule(for: $0, type: type, module: module) }
                ?? nonGeneric(type, subject: coarse.rawValue)
                ?? nonGeneric(module, subject: coarse.rawValue)
                ?? ""
            return Self(subject: coarse.rawValue, module: resolvedModule)
        }

        // Keep unfamiliar source labels intact. The editor's general branch can
        // still be used without silently classifying the question.
        return Self(
            subject: subject,
            module: module.isEmpty ? type : module
        )
    }

    private static func specificModule(for subject: SubjectDefinition, type: String, module: String) -> String {
        if subject.name == "数量关系" {
            return nonGeneric(type, subject: subject.name) ?? nonGeneric(module, subject: subject.name) ?? ""
        }
        if subject.modules.contains(type) { return type }
        if subject.modules.contains(module) { return module }
        if module == subject.name || module.isEmpty { return nonGeneric(type, subject: subject.name) ?? "" }
        return module
    }

    private static func nonGeneric(_ value: String, subject: String) -> String? {
        let normalized = QuestionBankModuleTitle.normalized(value)
        guard !normalized.isEmpty, normalized != subject,
              !["行测", "行政职业能力测验", "公务员考试"].contains(normalized) else { return nil }
        return normalized
    }
}

enum QuestionBankSourceDisplay {
    static func rows(
        entries: [QuestionBankProvenance],
        sourcePapers: [QuestionBankSourcePaper]
    ) -> [String] {
        var rows: [String] = []
        var seen = Set<String>()
        for entry in entries {
            guard let source = sourcePapers.first(where: { $0.id == entry.sourcePaperID }),
                  let rawFileName = source.originalFileName else { continue }
            let fileName = cleanedFileName(rawFileName)
            guard !fileName.isEmpty else { continue }
            let numbers = entry.sourceQuestionNumbers?.isEmpty == false
                ? entry.sourceQuestionNumbers ?? []
                : entry.sourceQuestionNumber.map { [$0] } ?? []
            let values = numbers.isEmpty
                ? [fileName]
                : numbers.map { "\(fileName)·第\($0)题" }
            for value in values where seen.insert(value).inserted { rows.append(value) }
        }
        return rows
    }

    static func cleanedFileName(_ value: String) -> String {
        let pathNormalized = value.replacingOccurrences(of: "\\", with: "/")
        var name = pathNormalized.split(separator: "/").last.map(String.init) ?? pathNormalized
        name = name.replacingOccurrences(of: "网友回忆版", with: "")
        name = name.replacingOccurrences(of: "\\.pdf$", with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(
            of: #"\(\s*\)|（\s*）|\[\s*\]|【\s*】"#,
            with: "",
            options: .regularExpression
        )
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .·_-—"))
    }
}

struct QuestionBankQuestionAnalysisContext {
    let record: QuestionBankRecord
    let question: QuestionBankQuestion
    let moduleTitle: String?
    let material: QuestionBankMaterial?
    let sourcePapers: [QuestionBankSourcePaper]
    let assetsByID: [String: QuestionBankAssetReference]
    let selectedOptionID: String?
    let isAnswerRevealed: Bool

    func replacingRecord(_ record: QuestionBankRecord) -> Self {
        Self(
            record: record,
            question: question,
            moduleTitle: moduleTitle,
            material: material,
            sourcePapers: sourcePapers,
            assetsByID: assetsByID,
            selectedOptionID: selectedOptionID,
            isAnswerRevealed: isAnswerRevealed
        )
    }

    var currentQuestion: QuestionBankQuestion {
        record.decoded(QuestionBankQuestion.self) ?? question
    }

    var typeMapping: QuestionBankLibraryTypeMapping {
        QuestionBankLibraryTypeMapping.resolve(
            subject: question.subject,
            type: question.type,
            moduleTitle: moduleTitle
        )
    }

    var sourceRows: [String] {
        sourceRows(for: currentQuestion)
    }

    func sourceRows(for question: QuestionBankQuestion) -> [String] {
        let questionRows = QuestionBankSourceDisplay.rows(
            entries: question.provenance ?? [],
            sourcePapers: sourcePapers
        )
        guard questionRows.isEmpty, let material else { return questionRows }
        return QuestionBankSourceDisplay.rows(
            entries: material.provenance ?? [],
            sourcePapers: sourcePapers
        )
    }

    var materialSourceRows: [String] {
        guard let material else { return [] }
        return QuestionBankSourceDisplay.rows(
            entries: material.provenance ?? [],
            sourcePapers: sourcePapers
        )
    }

    var answerStateKey: String {
        "\(selectedOptionID ?? "")|\(isAnswerRevealed)"
    }

    var doodleRecordID: String {
        QuestionBankDoodleRepository.recordID(paperID: question.paperID, scope: .question(question.id))
    }

    var detailObject: [String: Any] {
        let question = currentQuestion
        var object = rawObject
        object["question"] = question.stem
        object["options"] = question.options.map(\.text)
        object["correctOption"] = isAnswerRevealed ? displayOptionLetter(for: question.answer) : ""
        object["userOption"] = selectedOptionID.map { displayOptionLetter(for: $0) } ?? ""
        object.removeValue(forKey: "answer")
        object.removeValue(forKey: "correctAnswer")
        object["subject"] = typeMapping.subject
        object["module"] = typeMapping.module
        object["questionNumber"] = String(question.number)
        object["questionSource"] = sourceRows.joined(separator: "\n")
        object["images"] = question.stemImageAssetID.isEmpty ? [] : [question.stemImageAssetID]
        object["optionImages"] = question.options.map(\.imageAssetID)
        object["knowledgePoints"] = question.knowledgePoints ?? []
        object["weaknessTags"] = question.weaknessTags ?? []
        object["isDifficult"] = question.isDifficult ?? false
        object["needsReview"] = question.needsReview ?? false
        object["errorCause"] = question.errorCause ?? ""
        object["pitfall"] = question.pitfall ?? ""
        object["quantityStructure"] = question.quantityStructure ?? ""
        object["graphRule"] = question.graphRule ?? ""
        object["recognition"] = question.recognition ?? ""
        object["linkedWordIds"] = question.linkedWordIDs ?? []
        object["linkedErrorRecordIDs"] = question.linkedErrorRecordIDs ?? []
        object["note"] = question.note ?? ""
        object.removeValue(forKey: "status")
        object.removeValue(forKey: "masteryStatus")
        return object
    }

    func makeEditorDraft() -> LibraryRecordDraft {
        let question = currentQuestion
        return makeEditorDraft(using: question)
    }

    func makeEditorDraft(using question: QuestionBankQuestion) -> LibraryRecordDraft {
        let mapping = QuestionBankLibraryTypeMapping.resolve(
            subject: question.subject,
            type: question.type,
            moduleTitle: moduleTitle
        )
        var draft = LibraryRecordDraft(
            kind: .errors,
            scope: LibraryScope(subject: mapping.subject, module: mapping.module)
        )
        draft.original = rawObject
        draft.id = question.id
        draft.subject = mapping.subject
        draft.module = mapping.module
        draft.title = question.stem
        draft.options = question.options.map(\.text)
        draft.images = question.stemImageAssetID.isEmpty ? [] : [question.stemImageAssetID]
        draft.optionImages = question.options.map(\.imageAssetID)
        draft.correctOption = displayOptionLetter(for: question.answer)
        draft.userOption = selectedOptionID.map { displayOptionLetter(for: $0) } ?? ""
        draft.errorCause = question.errorCause ?? ""
        draft.pitfall = question.pitfall ?? ""
        draft.quantityStructure = question.quantityStructure ?? ""
        draft.graphRule = question.graphRule ?? ""
        draft.recognition = question.recognition ?? ""
        draft.knowledgePoint = (question.knowledgePoints ?? []).joined(separator: "、")
        draft.weaknessTags = (question.weaknessTags ?? []).joined(separator: "、")
        draft.content = question.note ?? ""
        draft.questionSource = sourceRows(for: question).joined(separator: "\n")
        draft.questionNumber = String(question.number)
        draft.linkedWordIDs = question.linkedWordIDs ?? []
        draft.linkedErrorIDs = question.linkedErrorRecordIDs ?? []
        draft.type = ""
        draft.status = ""
        return draft
    }

    @MainActor
    static func linkedErrorContext(
        paperID: String,
        questionID: String,
        selectedOption: String,
        context: ModelContext
    ) -> QuestionBankQuestionAnalysisContext? {
        let questionKind = QuestionBankRepository.questionKind
        let questionCompoundID = "\(paperID)::\(questionKind)::\(questionID)"
        var questionDescriptor = FetchDescriptor<QuestionBankRecord>(
            predicate: #Predicate { $0.compoundID == questionCompoundID }
        )
        questionDescriptor.fetchLimit = 1
        guard let questionRecord = (try? context.fetch(questionDescriptor))?.first,
              let question = questionRecord.decoded(QuestionBankQuestion.self) else { return nil }

        var dependencies = [questionRecord]
        let moduleKind = QuestionBankRepository.moduleKind
        let materialKind = QuestionBankRepository.materialKind
        let paperKind = QuestionBankRepository.paperKind
        let moduleID = question.moduleID
        let modulePredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID && $0.kind == moduleKind && $0.stableID == moduleID
        }
        var moduleDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: modulePredicate)
        moduleDescriptor.fetchLimit = 1
        if let moduleRecord = (try? context.fetch(moduleDescriptor))?.first {
            dependencies.append(moduleRecord)
        }

        if !question.materialID.isEmpty {
            let materialID = question.materialID
            let materialPredicate = #Predicate<QuestionBankRecord> {
                $0.paperID == paperID && $0.kind == materialKind && $0.stableID == materialID
            }
            var materialDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: materialPredicate)
            materialDescriptor.fetchLimit = 1
            if let materialRecord = (try? context.fetch(materialDescriptor))?.first {
                dependencies.append(materialRecord)
            }
        }

        let paperPredicate = #Predicate<QuestionBankRecord> {
            $0.paperID == paperID && $0.kind == paperKind
        }
        var paperDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: paperPredicate)
        paperDescriptor.fetchLimit = 1
        if let paperRecord = (try? context.fetch(paperDescriptor))?.first {
            dependencies.append(paperRecord)
        }

        var assetIDs = Set(question.options.map(\.imageAssetID).filter { !$0.isEmpty })
        if !question.stemImageAssetID.isEmpty { assetIDs.insert(question.stemImageAssetID) }
        if let materialRecord = dependencies.first(where: { $0.kind == materialKind }),
           let material = materialRecord.decoded(QuestionBankMaterial.self), !material.imageAssetID.isEmpty {
            assetIDs.insert(material.imageAssetID)
        }
        if !assetIDs.isEmpty {
            let assetKind = QuestionBankRepository.assetKind
            let assetCompoundIDs = assetIDs.map { "\(paperID)::\(assetKind)::\($0)" }
            let assetPredicate = #Predicate<QuestionBankRecord> {
                $0.kind == assetKind && assetCompoundIDs.contains($0.compoundID)
            }
            var assetDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: assetPredicate)
            assetDescriptor.fetchLimit = assetCompoundIDs.count
            dependencies.append(contentsOf: (try? context.fetch(assetDescriptor)) ?? [])
        }
        return linkedErrorContext(
            paperID: paperID,
            questionID: questionID,
            selectedOption: selectedOption,
            records: dependencies
        )
    }

    static func linkedErrorContext(
        paperID: String,
        questionID: String,
        selectedOption: String,
        records: [QuestionBankRecord]
    ) -> QuestionBankQuestionAnalysisContext? {
        guard let questionRecord = records.first(where: {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind
                && $0.stableID == questionID
        }), let question = questionRecord.decoded(QuestionBankQuestion.self) else {
            return nil
        }
        let module = records.first(where: {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind
                && $0.stableID == question.moduleID
        })?.decoded(QuestionBankModule.self)
        let material = question.materialID.isEmpty ? nil : records.first(where: {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.materialKind
                && $0.stableID == question.materialID
        })?.decoded(QuestionBankMaterial.self)
        let sourcePapers = records.first(where: {
            $0.paperID == paperID && $0.kind == QuestionBankRepository.paperKind
        })?.decoded(QuestionBankPaper.self)?.sourcePapers ?? []
        let assetsByID = Dictionary(
            records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.assetKind }
                .map { ($0.stableID, QuestionBankAssetReference(record: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let selectedOptionID: String?
        let normalizedSelection = selectedOption.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let scalar = normalizedSelection.unicodeScalars.first,
           scalar.value >= 65,
           Int(scalar.value - 65) < question.options.count {
            selectedOptionID = question.options[Int(scalar.value - 65)].id
        } else {
            selectedOptionID = question.options.first(where: { $0.id == normalizedSelection })?.id
        }
        return QuestionBankQuestionAnalysisContext(
            record: questionRecord,
            question: question,
            moduleTitle: module?.title,
            material: material,
            sourcePapers: sourcePapers,
            assetsByID: assetsByID,
            selectedOptionID: selectedOptionID,
            isAnswerRevealed: true
        )
    }

    func optionID(forLibraryAnswer value: String) -> String {
        let question = currentQuestion
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let scalar = normalized.unicodeScalars.first,
              scalar.value >= 65, scalar.value < 65 + UInt32(question.options.count) else {
            return normalized
        }
        let index = Int(scalar.value - 65)
        return question.options[index].id
    }

    private var rawObject: [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: record.payload) as? [String: Any] else { return [:] }
        return value
    }

    private func displayOptionLetter(for optionID: String) -> String {
        guard let index = currentQuestion.options.firstIndex(where: { $0.id == optionID }), index < 26 else {
            return optionID.uppercased()
        }
        return String(UnicodeScalar(65 + index)!)
    }
}

struct QuestionBankQuestionAnalysisFields: Equatable {
    var errorCause = ""
    var pitfall = ""
    var quantityStructure = ""
    var graphRule = ""
    var recognition = ""
    var note = ""
    var knowledgePoints: [String] = []
    var weaknessTags: [String] = []
    var linkedWordIDs: [String] = []
    var linkedErrorRecordIDs: [String] = []
    var questionSource = ""
    var questionNumber = ""
}
