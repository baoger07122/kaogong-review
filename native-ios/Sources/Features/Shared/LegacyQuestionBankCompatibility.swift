import Foundation
import SwiftData

// These payload types keep old QuestionBankRecord rows readable while the
// standalone reader and importer stay out of the production app target.
struct QuestionBankPaper: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var year: Int
    var examType: String
    var volume: String
    var source: String
    var importVersion: String
    var provinceCode: String? = nil
    var provinceName: String? = nil
    var sourcePapers: [QuestionBankSourcePaper]? = nil
}

struct QuestionBankSourcePaper: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var provinceCode: String? = nil
    var provinceName: String? = nil
    var batchID: String? = nil
    var batchName: String? = nil
    var originalFileID: String? = nil
    var originalFileName: String? = nil
    var originalFileSHA256: String? = nil
}

struct QuestionBankProvenance: Codable, Equatable, Sendable, Identifiable {
    var sourcePaperID: String
    var provinceCode: String? = nil
    var provinceName: String? = nil
    var sourceQuestionNumber: Int? = nil
    var sourceQuestionNumbers: [Int]? = nil
    var originalPage: String? = nil
    var evidence: String? = nil

    var id: String {
        [sourcePaperID, sourceQuestionNumber.map(String.init) ?? "",
         (sourceQuestionNumbers ?? []).map(String.init).joined(separator: ","), originalPage ?? ""]
            .joined(separator: "|")
    }
}

struct QuestionBankModule: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var paperID: String
    var sequence: Int
    var title: String
    var instruction: String
    var originalPage: String
}

struct QuestionBankMaterial: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var paperID: String
    var moduleID: String
    var type: String
    var text: String
    var imageAssetID: String
    var applicableQuestions: String
    var originalPage: String
    var provenance: [QuestionBankProvenance]? = nil
}

struct QuestionBankOption: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var imageAssetID: String
}

struct QuestionBankQuestion: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var paperID: String
    var moduleID: String
    var number: Int
    var subject: String
    var type: String
    var materialID: String
    var stem: String
    var stemImageAssetID: String
    var options: [QuestionBankOption]
    var answer: String
    var explanation: String
    var originalPage: String
    var provenance: [QuestionBankProvenance]? = nil
    var isDifficult: Bool? = nil
    var needsReview: Bool? = nil
    var knowledgePoints: [String]? = nil
    var weaknessTags: [String]? = nil
    var errorCause: String? = nil
    var pitfall: String? = nil
    var quantityStructure: String? = nil
    var graphRule: String? = nil
    var recognition: String? = nil
    var note: String? = nil
    var linkedWordIDs: [String]? = nil
    var linkedErrorRecordIDs: [String]? = nil
    var accuracy: Double? = nil

    private enum CodingKeys: String, CodingKey {
        case id, paperID, moduleID, number, subject, type, materialID, stem, stemImageAssetID
        case options, answer, explanation, originalPage, provenance
        case isDifficult, needsReview, knowledgePoints, weaknessTags, accuracy
        case errorCause, pitfall, quantityStructure, graphRule, recognition, note
        case linkedWordIDs = "linkedWordIds"
        case linkedErrorRecordIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        paperID = try container.decode(String.self, forKey: .paperID)
        moduleID = try container.decode(String.self, forKey: .moduleID)
        number = try container.decode(Int.self, forKey: .number)
        subject = try container.decode(String.self, forKey: .subject)
        type = try container.decode(String.self, forKey: .type)
        materialID = try container.decode(String.self, forKey: .materialID)
        stem = try container.decode(String.self, forKey: .stem)
        stemImageAssetID = try container.decode(String.self, forKey: .stemImageAssetID)
        options = try container.decode([QuestionBankOption].self, forKey: .options)
        answer = try container.decode(String.self, forKey: .answer)
        explanation = try container.decode(String.self, forKey: .explanation)
        originalPage = try container.decode(String.self, forKey: .originalPage)
        provenance = try container.decodeIfPresent([QuestionBankProvenance].self, forKey: .provenance)
        isDifficult = try container.decodeIfPresent(Bool.self, forKey: .isDifficult)
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview)
        knowledgePoints = try container.decodeIfPresent([String].self, forKey: .knowledgePoints)
        weaknessTags = try container.decodeIfPresent([String].self, forKey: .weaknessTags)
        errorCause = try container.decodeIfPresent(String.self, forKey: .errorCause)
        pitfall = try container.decodeIfPresent(String.self, forKey: .pitfall)
        quantityStructure = try container.decodeIfPresent(String.self, forKey: .quantityStructure)
        graphRule = try container.decodeIfPresent(String.self, forKey: .graphRule)
        recognition = try container.decodeIfPresent(String.self, forKey: .recognition)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        linkedWordIDs = try container.decodeIfPresent([String].self, forKey: .linkedWordIDs)
        linkedErrorRecordIDs = try container.decodeIfPresent([String].self, forKey: .linkedErrorRecordIDs)
        if let value = try? container.decode(Double.self, forKey: .accuracy) {
            accuracy = value
        } else if let value = try? container.decode(String.self, forKey: .accuracy) {
            accuracy = Double(value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            accuracy = nil
        }
    }
}

extension QuestionBankRecord {
    func decoded<Value: Decodable>(_ type: Value.Type) -> Value? {
        try? JSONDecoder().decode(type, from: payload)
    }
}

struct QuestionBankAssetReference: Equatable, Hashable, Sendable, Identifiable {
    let compoundID: String
    let paperID: String
    let stableID: String
    let contentRevision: Int
    let assetRelativePath: String?

    var id: String { compoundID }

    init(record: QuestionBankRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        stableID = record.stableID
        contentRevision = record.contentRevision
        assetRelativePath = record.assetRelativePath
    }
}

enum LegacyQuestionBankRecordKind {
    static let question = "question"
}

enum QuestionBankModuleTitle {
    static func normalized(_ title: String?) -> String {
        var value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for pattern in [
            "^[一二三四五六七八九十百]+[、.．)）]\\s*",
            "^[0-9]+[、.．)）]\\s*",
            "^[（(][一二三四五六七八九十百]+[）)]\\s*"
        ] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum QuestionBankCoarseModule: String {
    case commonKnowledge = "常识判断"
    case language = "言语理解"
    case quantity = "数量关系"
    case reasoning = "判断推理"
    case dataAnalysis = "资料分析"
    case uncategorized = "未分类"

    static func classify(explicitModuleTitle title: String?) -> Self {
        switch QuestionBankModuleTitle.normalized(title) {
        case "常识判断", "常识": .commonKnowledge
        case "言语理解", "言语理解与表达": .language
        case "数量关系": .quantity
        case "判断推理": .reasoning
        case "资料分析": .dataAnalysis
        default: .uncategorized
        }
    }
}

struct QuestionBankLibraryTypeMapping: Equatable {
    let subject: String
    let module: String

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
        let coarse = [
            QuestionBankCoarseModule.classify(explicitModuleTitle: module),
            QuestionBankCoarseModule.classify(explicitModuleTitle: subject),
            QuestionBankCoarseModule.classify(explicitModuleTitle: type)
        ].first { $0 != .uncategorized }
        if let coarse {
            let definition = SubjectDefinition.all.first { $0.name == coarse.rawValue }
            return Self(
                subject: coarse.rawValue,
                module: definition.map { specificModule(for: $0, type: type, module: module) }
                    ?? nonGeneric(type, subject: coarse.rawValue)
                    ?? nonGeneric(module, subject: coarse.rawValue)
                    ?? ""
            )
        }
        return Self(subject: subject, module: module.isEmpty ? type : module)
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
    static func rows(entries: [QuestionBankProvenance], sourcePapers: [QuestionBankSourcePaper]) -> [String] {
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
            let values = numbers.isEmpty ? [fileName] : numbers.map { "\(fileName)·第\($0)题" }
            for value in values where seen.insert(value).inserted { rows.append(value) }
        }
        return rows
    }

    static func cleanedFileName(_ value: String) -> String {
        let pathNormalized = value.replacingOccurrences(of: "\\", with: "/")
        var name = pathNormalized.split(separator: "/").last.map(String.init) ?? pathNormalized
        name = name.replacingOccurrences(of: "网友回忆版", with: "")
        name = name.replacingOccurrences(of: "\\.pdf$", with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"\(\s*\)|（\s*）|\[\s*\]|【\s*】"#, with: "", options: .regularExpression)
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

    var currentQuestion: QuestionBankQuestion { question }

    var typeMapping: QuestionBankLibraryTypeMapping {
        QuestionBankLibraryTypeMapping.resolve(subject: question.subject, type: question.type, moduleTitle: moduleTitle)
    }

    var sourceRows: [String] { sourceRows(for: currentQuestion) }

    func sourceRows(for question: QuestionBankQuestion) -> [String] {
        let questionRows = QuestionBankSourceDisplay.rows(entries: question.provenance ?? [], sourcePapers: sourcePapers)
        guard questionRows.isEmpty, let material else { return questionRows }
        return QuestionBankSourceDisplay.rows(entries: material.provenance ?? [], sourcePapers: sourcePapers)
    }

    var materialSourceRows: [String] {
        guard let material else { return [] }
        return QuestionBankSourceDisplay.rows(entries: material.provenance ?? [], sourcePapers: sourcePapers)
    }

    var answerStateKey: String { "\(selectedOptionID ?? "")|\(isAnswerRevealed)" }

    var detailObject: [String: Any] {
        let current = currentQuestion
        var object: [String: Any] = [:]
        object["question"] = current.stem
        object["options"] = current.options.map(\.text)
        object["correctOption"] = isAnswerRevealed ? displayOptionLetter(for: current.answer) : ""
        object["userOption"] = selectedOptionID.map(displayOptionLetter(for:)) ?? ""
        object["explanation"] = current.explanation
        object["type"] = current.type
        if let accuracy = current.accuracy { object["accuracy"] = accuracy }
        object.removeValue(forKey: "answer")
        object.removeValue(forKey: "correctAnswer")
        object["subject"] = typeMapping.subject
        object["module"] = typeMapping.module
        object["questionNumber"] = String(current.number)
        object["questionSource"] = sourceRows(for: current).joined(separator: "\n")
        object["images"] = current.stemImageAssetID.isEmpty ? [] : [current.stemImageAssetID]
        object["optionImages"] = current.options.map(\.imageAssetID)
        object["knowledgePoints"] = current.knowledgePoints ?? []
        object["weaknessTags"] = current.weaknessTags ?? []
        object["isDifficult"] = current.isDifficult ?? false
        object["needsReview"] = current.needsReview ?? false
        object["errorCause"] = current.errorCause ?? ""
        object["pitfall"] = current.pitfall ?? ""
        object["quantityStructure"] = current.quantityStructure ?? ""
        object["graphRule"] = current.graphRule ?? ""
        object["recognition"] = current.recognition ?? ""
        object["linkedWordIds"] = current.linkedWordIDs ?? []
        object["linkedErrorRecordIDs"] = current.linkedErrorRecordIDs ?? []
        object["note"] = current.note ?? ""
        object.removeValue(forKey: "status")
        object.removeValue(forKey: "masteryStatus")
        return object
    }

    @MainActor
    static func linkedErrorContext(
        paperID: String,
        questionID: String,
        selectedOption: String,
        context: ModelContext
    ) -> QuestionBankQuestionAnalysisContext? {
        let questionKind = "question"
        let moduleKind = "module"
        let materialKind = "material"
        let paperKind = "paper"
        let assetKind = "asset"
        let questionCompoundID = "\(paperID)::\(questionKind)::\(questionID)"
        var descriptor = FetchDescriptor<QuestionBankRecord>(predicate: #Predicate { $0.compoundID == questionCompoundID })
        descriptor.fetchLimit = 1
        guard let questionRecord = (try? context.fetch(descriptor))?.first,
              let question = questionRecord.decoded(QuestionBankQuestion.self) else { return nil }

        var dependencies = [questionRecord]
        let moduleID = question.moduleID
        var moduleDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: #Predicate {
            $0.paperID == paperID && $0.kind == moduleKind && $0.stableID == moduleID
        })
        moduleDescriptor.fetchLimit = 1
        if let module = (try? context.fetch(moduleDescriptor))?.first { dependencies.append(module) }

        if !question.materialID.isEmpty {
            let materialID = question.materialID
            var materialDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: #Predicate {
                $0.paperID == paperID && $0.kind == materialKind && $0.stableID == materialID
            })
            materialDescriptor.fetchLimit = 1
            if let material = (try? context.fetch(materialDescriptor))?.first { dependencies.append(material) }
        }

        var paperDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: #Predicate {
            $0.paperID == paperID && $0.kind == paperKind
        })
        paperDescriptor.fetchLimit = 1
        if let paper = (try? context.fetch(paperDescriptor))?.first { dependencies.append(paper) }

        var assetIDs = Set(question.options.map(\.imageAssetID).filter { !$0.isEmpty })
        if !question.stemImageAssetID.isEmpty { assetIDs.insert(question.stemImageAssetID) }
        if let materialRecord = dependencies.first(where: { $0.kind == materialKind }),
           let material = materialRecord.decoded(QuestionBankMaterial.self), !material.imageAssetID.isEmpty {
            assetIDs.insert(material.imageAssetID)
        }
        if !assetIDs.isEmpty {
            let compoundIDs = assetIDs.map { "\(paperID)::\(assetKind)::\($0)" }
            let requestedIDs = compoundIDs
            let assetDescriptor = FetchDescriptor<QuestionBankRecord>(predicate: #Predicate {
                $0.kind == assetKind && requestedIDs.contains($0.compoundID)
            })
            dependencies.append(contentsOf: (try? context.fetch(assetDescriptor)) ?? [])
        }

        let module = dependencies.first(where: { $0.kind == moduleKind })?.decoded(QuestionBankModule.self)
        let material = question.materialID.isEmpty ? nil : dependencies.first(where: {
            $0.kind == materialKind && $0.stableID == question.materialID
        })?.decoded(QuestionBankMaterial.self)
        let sourcePapers = dependencies.first(where: { $0.kind == paperKind })
            ?.decoded(QuestionBankPaper.self)?.sourcePapers ?? []
        let assetsByID = Dictionary(
            dependencies.filter { $0.kind == assetKind }
                .map { ($0.stableID, QuestionBankAssetReference(record: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalized = selectedOption.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let selectedOptionID: String?
        if let scalar = normalized.unicodeScalars.first, scalar.value >= 65,
           Int(scalar.value - 65) < question.options.count {
            selectedOptionID = question.options[Int(scalar.value - 65)].id
        } else {
            selectedOptionID = question.options.first(where: { $0.id == normalized })?.id
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

    private func displayOptionLetter(for optionID: String) -> String {
        guard let index = currentQuestion.options.firstIndex(where: { $0.id == optionID }), index < 26 else {
            return optionID.uppercased()
        }
        return String(UnicodeScalar(65 + index)!)
    }
}

enum LegacyQuestionBankAssetStore {
    static func url(for relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty,
              !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !relativePath.contains(":"), !relativePath.contains("\0") else { return nil }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let root = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
              ).appendingPathComponent("QuestionBankAssets", isDirectory: true) else { return nil }
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        var candidate = normalizedRoot
        for (index, component) in components.enumerated() {
            candidate.appendPathComponent(String(component))
            candidate = candidate.standardizedFileURL
            guard candidate.pathComponents.count == normalizedRoot.pathComponents.count + index + 1,
                  candidate.pathComponents.starts(with: normalizedRoot.pathComponents) else { return nil }
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return nil }
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.pathComponents.count == normalizedRoot.pathComponents.count + components.count,
              resolved.pathComponents.starts(with: normalizedRoot.pathComponents) else { return nil }
        return candidate
    }
}
