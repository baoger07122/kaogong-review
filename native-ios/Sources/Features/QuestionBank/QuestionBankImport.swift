import Foundation
import SwiftData
import OSLog
import ZIPFoundation
import CryptoKit

struct QuestionBankPaper: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var year: Int
    var examType: String
    var volume: String
    var source: String
    var importVersion: String

    var duplicateKey: String {
        [String(year), examType, title, volume]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}

enum QuestionBankBatchFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case national
    case joint
    case provincial

    var title: String {
        switch self {
        case .national: "国考"
        case .joint: "联考"
        case .provincial: "省考"
        }
    }
}

struct QuestionBankSourceProvince: Codable, Equatable, Sendable, Identifiable {
    var code: String
    var name: String
    var id: String { code }
}

/// Optional v1 extension. Every grouping value is supplied explicitly; no paper
/// title, filename, or legacy `paper.volume` value is used to fill it in.
struct QuestionBankBatchMetadata: Codable, Equatable, Sendable {
    var family: QuestionBankBatchFamily
    var sourceID: String
    var revision: String
    var year: Int
    var volumeID: String?
    var volumeName: String?
    var sessionID: String?
    var sessionName: String?
    var sourceProvinces: [QuestionBankSourceProvince]?
    var provinceCode: String?
    var provinceName: String?
    var batchID: String?
    var batchName: String?

    var validationError: String? {
        guard !sourceID.trimmedNonempty.isEmpty else { return "batch.sourceID 不能为空。" }
        guard !revision.trimmedNonempty.isEmpty else { return "batch.revision 不能为空。" }
        guard year > 0 else { return "batch.year 必须是明确的正整数年份。" }
        switch family {
        case .national:
            guard !volumeID.trimmedNonempty.isEmpty, !volumeName.trimmedNonempty.isEmpty else {
                return "国考批次必须明确提供 batch.volumeID 和 batch.volumeName。"
            }
        case .joint:
            guard !sessionID.trimmedNonempty.isEmpty, !sessionName.trimmedNonempty.isEmpty else {
                return "联考批次必须明确提供 batch.sessionID 和 batch.sessionName。"
            }
            let provinces = sourceProvinces ?? []
            guard !provinces.isEmpty,
                  provinces.allSatisfy({ !$0.code.trimmedNonempty.isEmpty && !$0.name.trimmedNonempty.isEmpty }),
                  Set(provinces.map { $0.code.trimmedNonempty }).count == provinces.count else {
                return "联考批次必须提供非空且代码不重复的 batch.sourceProvinces。"
            }
        case .provincial:
            guard !provinceCode.trimmedNonempty.isEmpty, !provinceName.trimmedNonempty.isEmpty,
                  !batchID.trimmedNonempty.isEmpty, !batchName.trimmedNonempty.isEmpty else {
                return "省考批次必须明确提供 provinceCode、provinceName、batchID 和 batchName。"
            }
        }
        return nil
    }

    var identityKey: String {
        let parts: [String]
        switch family {
        case .national:
            parts = [family.rawValue, String(year), volumeID ?? ""]
        case .joint:
            parts = [family.rawValue, String(year), sessionID ?? ""]
        case .provincial:
            parts = [family.rawValue, String(year), provinceCode ?? "", batchID ?? ""]
        }
        return parts.map(Self.keyPart).joined(separator: "|")
    }

    var displayName: String {
        switch family {
        case .national: "\(year)年国考·\(volumeName ?? "")"
        case .joint: "\(year)年联考·\(sessionName ?? "")"
        case .provincial: "\(year)年\(provinceName ?? "")·\(batchName ?? "")"
        }
    }

    private static func keyPart(_ value: String) -> String {
        Data(value.trimmedNonempty.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    var trimmedNonempty: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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
}

struct QuestionBankAsset: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var paperID: String
    var ownerType: String
    var ownerID: String
    var role: String
    var path: String
    var mimeType: String
    var fileName: String
    var originalPage: String
}

enum QuestionBankImportSource: Sendable, Equatable {
    case pickerCopy
    case filesOpenIn
    case trustedLocalFile
}

enum QuestionBankImportPhase: String, Sendable {
    case acquiringFile = "取得本地文件"
    case parsing = "解析文件"
    case validatingImages = "校验图片"
    case preparingPreview = "生成预览"
}

struct QuestionBankJSONAssetV1: Codable, Equatable, Sendable {
    var id: String
    var paperID: String
    var ownerType: String
    var ownerID: String
    var role: String
    var path: String
    var mimeType: String
    var fileName: String
    var originalPage: String
    var dataBase64: String
    var sha256: String

    private enum CodingKeys: String, CodingKey {
        case id, paperID, ownerType, ownerID, role, path, mimeType, fileName, originalPage, dataBase64, sha256
    }

    init(id: String, paperID: String, ownerType: String, ownerID: String, role: String,
         path: String, mimeType: String, fileName: String, originalPage: String,
         dataBase64: String, sha256: String) {
        self.id = id
        self.paperID = paperID
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.role = role
        self.path = path
        self.mimeType = mimeType
        self.fileName = fileName
        self.originalPage = originalPage
        self.dataBase64 = dataBase64
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        paperID = try container.decode(String.self, forKey: .paperID)
        ownerType = try container.decode(String.self, forKey: .ownerType)
        ownerID = (try? container.decode(String.self, forKey: .ownerID)) ?? ""
        role = try container.decode(String.self, forKey: .role)
        path = try container.decode(String.self, forKey: .path)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        fileName = try container.decode(String.self, forKey: .fileName)
        originalPage = try container.decode(String.self, forKey: .originalPage)
        dataBase64 = (try? container.decode(String.self, forKey: .dataBase64)) ?? ""
        sha256 = (try? container.decode(String.self, forKey: .sha256)) ?? ""
    }

    var metadata: QuestionBankAsset {
        QuestionBankAsset(id: id, paperID: paperID, ownerType: ownerType, ownerID: ownerID,
                          role: role, path: path, mimeType: mimeType, fileName: fileName,
                          originalPage: originalPage)
    }
}

private struct QuestionBankJSONPaperFieldsV1: Decodable {
    let value: QuestionBankPaper
    private enum CodingKeys: String, CodingKey { case id, title, year, examType, volume, source, importVersion }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = QuestionBankPaper(id: (try? c.decode(String.self, forKey: .id)) ?? "",
            title: try c.decode(String.self, forKey: .title), year: try c.decode(Int.self, forKey: .year),
            examType: try c.decode(String.self, forKey: .examType), volume: try c.decode(String.self, forKey: .volume),
            source: try c.decode(String.self, forKey: .source), importVersion: try c.decode(String.self, forKey: .importVersion))
    }
}

private struct QuestionBankJSONModuleFieldsV1: Decodable {
    let value: QuestionBankModule
    private enum CodingKeys: String, CodingKey { case id, paperID, sequence, title, instruction, originalPage }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = QuestionBankModule(id: (try? c.decode(String.self, forKey: .id)) ?? "",
            paperID: try c.decode(String.self, forKey: .paperID), sequence: try c.decode(Int.self, forKey: .sequence),
            title: try c.decode(String.self, forKey: .title), instruction: try c.decode(String.self, forKey: .instruction),
            originalPage: try c.decode(String.self, forKey: .originalPage))
    }
}

private struct QuestionBankJSONMaterialFieldsV1: Decodable {
    let value: QuestionBankMaterial
    private enum CodingKeys: String, CodingKey { case id, paperID, moduleID, type, text, imageAssetID, applicableQuestions, originalPage }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = QuestionBankMaterial(id: (try? c.decode(String.self, forKey: .id)) ?? "",
            paperID: try c.decode(String.self, forKey: .paperID), moduleID: try c.decode(String.self, forKey: .moduleID),
            type: try c.decode(String.self, forKey: .type), text: try c.decode(String.self, forKey: .text),
            imageAssetID: try c.decode(String.self, forKey: .imageAssetID),
            applicableQuestions: try c.decode(String.self, forKey: .applicableQuestions),
            originalPage: try c.decode(String.self, forKey: .originalPage))
    }
}

private struct QuestionBankJSONOptionFieldsV1: Decodable {
    let value: QuestionBankOption
    private enum CodingKeys: String, CodingKey { case id, text, imageAssetID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = QuestionBankOption(id: (try? c.decode(String.self, forKey: .id)) ?? "",
            text: try c.decode(String.self, forKey: .text), imageAssetID: try c.decode(String.self, forKey: .imageAssetID))
    }
}

private struct QuestionBankJSONQuestionFieldsV1: Decodable {
    let value: QuestionBankQuestion
    private enum CodingKeys: String, CodingKey {
        case id, paperID, moduleID, number, subject, type, materialID, stem, stemImageAssetID
        case options, answer, explanation, originalPage
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let options = try c.decode([QuestionBankJSONOptionFieldsV1].self, forKey: .options).map(\.value)
        value = QuestionBankQuestion(id: (try? c.decode(String.self, forKey: .id)) ?? "",
            paperID: try c.decode(String.self, forKey: .paperID), moduleID: try c.decode(String.self, forKey: .moduleID),
            number: try c.decode(Int.self, forKey: .number), subject: try c.decode(String.self, forKey: .subject),
            type: try c.decode(String.self, forKey: .type), materialID: try c.decode(String.self, forKey: .materialID),
            stem: try c.decode(String.self, forKey: .stem), stemImageAssetID: try c.decode(String.self, forKey: .stemImageAssetID),
            options: options, answer: try c.decode(String.self, forKey: .answer),
            explanation: try c.decode(String.self, forKey: .explanation), originalPage: try c.decode(String.self, forKey: .originalPage))
    }
}

struct QuestionBankImportJSONV1: Codable, Sendable {
    static let formatIdentifier = "kaogong-question-bank"
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var paper: QuestionBankPaper
    var modules: [QuestionBankModule]
    var materials: [QuestionBankMaterial]
    var questions: [QuestionBankQuestion]
    var assets: [QuestionBankJSONAssetV1]
    var batch: QuestionBankBatchMetadata?

    private enum CodingKeys: String, CodingKey {
        case format, schemaVersion, paper, modules, materials, questions, assets, batch
    }

    init(format: String = QuestionBankImportJSONV1.formatIdentifier,
         schemaVersion: Int = QuestionBankImportJSONV1.currentSchemaVersion,
         paper: QuestionBankPaper, modules: [QuestionBankModule], materials: [QuestionBankMaterial],
         questions: [QuestionBankQuestion], assets: [QuestionBankJSONAssetV1],
         batch: QuestionBankBatchMetadata? = nil) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.paper = paper
        self.modules = modules
        self.materials = materials
        self.questions = questions
        self.assets = assets
        self.batch = batch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        guard format == Self.formatIdentifier else {
            throw DecodingError.dataCorruptedError(forKey: .format, in: container,
                debugDescription: "不是 kaogong 真题库 JSON；备份文件和其他 JSON 不能作为真题包导入。")
        }
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                debugDescription: "不支持真题 JSON schemaVersion=\(schemaVersion)，当前只支持 1。")
        }
        paper = try container.decode(QuestionBankJSONPaperFieldsV1.self, forKey: .paper).value
        modules = try container.decode([QuestionBankJSONModuleFieldsV1].self, forKey: .modules).map(\.value)
        materials = try container.decode([QuestionBankJSONMaterialFieldsV1].self, forKey: .materials).map(\.value)
        questions = try container.decode([QuestionBankJSONQuestionFieldsV1].self, forKey: .questions).map(\.value)
        assets = try container.decode([QuestionBankJSONAssetV1].self, forKey: .assets)
        batch = try container.decodeIfPresent(QuestionBankBatchMetadata.self, forKey: .batch)
    }
}

struct QuestionBankImportPlan: Identifiable, Sendable {
    let id = UUID()
    var paper: QuestionBankPaper?
    var modules: [QuestionBankModule]
    var materials: [QuestionBankMaterial]
    var questions: [QuestionBankQuestion]
    var assets: [QuestionBankAsset]
    var errors: [String]
    var stagingDirectory: URL?
    var batchMetadata: QuestionBankBatchMetadata? = nil
    var sourceFileSHA256: String = ""

    var canImport: Bool { paper != nil && errors.isEmpty && stagingDirectory != nil }
}

struct QuestionBankStoredRow {
    var compoundID: String
    var paperID: String
    var kind: String
    var stableID: String
    var moduleID: String?
    var questionNumber: Int?
    var sequence: Int?
    var year: Int?
    var examType: String?
    var normalizedPaperKey: String?
    var title: String?
    var searchText: String
    var payload: Data
    var assetRelativePath: String?

    func makeRecord() -> QuestionBankRecord {
        QuestionBankRecord(
            compoundID: compoundID, paperID: paperID, kind: kind, stableID: stableID,
            moduleID: moduleID, questionNumber: questionNumber, sequence: sequence,
            year: year, examType: examType, normalizedPaperKey: normalizedPaperKey,
            title: title, searchText: searchText, payload: payload,
            assetRelativePath: assetRelativePath
        )
    }
}

enum QuestionBankImportDecision: Equatable {
    case add
    case replaceExisting
}

enum QuestionBankImportFailure: LocalizedError {
    case invalidPlan
    case duplicatePaper(String)
    case missingStagingFile(String)
    case unsafeAssetPath

    var errorDescription: String? {
        switch self {
        case .invalidPlan:
            "导入包没有通过完整校验，未写入真题库。"
        case .duplicatePaper(let title):
            "已存在同一套试卷“\(title)”。请选择替换，或取消本次导入。"
        case .missingStagingFile(let name):
            "导入时找不到图片文件：\(name)。原有数据未更改。"
        case .unsafeAssetPath:
            "图片路径越出资源目录，未写入真题库。"
        }
    }
}

enum QuestionBankAssetStore {
    static func root(create: Bool = true) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ).appendingPathComponent("QuestionBankAssets", isDirectory: true)
        if create { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        return base
    }

    static func url(for relativePath: String?) -> URL? {
        guard let relativePath else { return nil }
        guard let root = try? root(create: false) else { return nil }
        return url(for: relativePath, under: root)
    }

    /// Resolves a slash-separated relative path without relying on string-prefix
    /// comparisons of absolute URL paths. Existing symlink components are rejected
    /// so a staged or persisted asset cannot escape its trusted root.
    static func url(for relativePath: String, under root: URL) -> URL? {
        guard root.isFileURL, let components = safePathComponents(relativePath) else { return nil }
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = pathComponents(of: normalizedRoot)
        var candidate = normalizedRoot

        for (index, component) in components.enumerated() {
            candidate.appendPathComponent(component, isDirectory: false)
            candidate = candidate.standardizedFileURL
            let candidateComponents = pathComponents(of: candidate)
            guard candidate.isFileURL,
                  candidateComponents.count == rootComponents.count + index + 1,
                  candidateComponents.starts(with: rootComponents) else { return nil }
            if let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]),
               values.isSymbolicLink == true {
                return nil
            }
        }

        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedComponents = pathComponents(of: resolvedCandidate)
        guard resolvedComponents.count == rootComponents.count + components.count,
              resolvedComponents.starts(with: rootComponents) else { return nil }
        return candidate
    }

    /// A diagnostic suitable for device logs: it includes the normalized path tails
    /// and comparison results while withholding the user's full sandbox path.
    static func redactedContainmentDiagnostic(root: URL, candidate: URL) -> String {
        let normalizedRoot = root.standardizedFileURL
        let normalizedCandidate = candidate.standardizedFileURL
        let resolvedRoot = normalizedRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = normalizedCandidate.resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = pathComponents(of: normalizedRoot)
        let candidateComponents = pathComponents(of: normalizedCandidate)
        let resolvedRootComponents = pathComponents(of: resolvedRoot)
        let resolvedCandidateComponents = pathComponents(of: resolvedCandidate)
        let sharedComponents = zip(rootComponents, candidateComponents)
            .prefix(while: { $0.0 == $0.1 }).count
        let legacyStringPrefix = normalizedCandidate.path.hasPrefix(normalizedRoot.path + "/")
        let componentPrefix = candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
        let resolvedComponentPrefix = resolvedCandidateComponents.count > resolvedRootComponents.count
            && resolvedCandidateComponents.starts(with: resolvedRootComponents)
        let rootTrailingSlash = normalizedRoot.path.hasSuffix("/")
        let targetTrailingSlash = normalizedCandidate.path.hasSuffix("/")
        return "rootTail=\(redactedTail(rootComponents)) targetTail=\(redactedTail(candidateComponents)) "
            + "rootComponents=\(rootComponents.count) targetComponents=\(candidateComponents.count) "
            + "sharedPrefixComponents=\(sharedComponents) legacyStringPrefix=\(legacyStringPrefix) "
            + "componentPrefix=\(componentPrefix) resolvedComponentPrefix=\(resolvedComponentPrefix) "
            + "rootTrailingSlash=\(rootTrailingSlash) targetTrailingSlash=\(targetTrailingSlash)"
    }

    private static func safePathComponents(_ path: String) -> [String]? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return parts.map(String.init)
    }

    private static func pathComponents(of url: URL) -> [String] {
        url.standardizedFileURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func redactedTail(_ components: [String]) -> String {
        "…/" + components.suffix(4).joined(separator: "/")
    }
}

enum QuestionBankRepository {
    static let paperKind = "paper"
    static let moduleKind = "module"
    static let materialKind = "material"
    static let questionKind = "question"
    static let assetKind = "asset"

    static func duplicatePaper(for paper: QuestionBankPaper, in records: [QuestionBankRecord]) -> QuestionBankRecord? {
        records.first {
            $0.kind == paperKind && ($0.stableID == paper.id || $0.normalizedPaperKey == paper.duplicateKey)
        }
    }

    /// Copies all image resources to an unreferenced generation directory first, then
    /// replaces/creates all SwiftData rows in one transaction. The previous generation
    /// is removed only after the database transaction has succeeded.
    @MainActor
    static func commit(
        _ plan: QuestionBankImportPlan,
        decision: QuestionBankImportDecision,
        records: [QuestionBankRecord],
        context: ModelContext,
        assetRoot: URL? = nil,
        batchPreparation: QuestionBankBatchPreparation? = nil,
        batches: [QuestionBankBatchRecord] = [],
        sources: [QuestionBankBatchSourceRecord] = [],
        batchMaterialLinks: [QuestionBankBatchMaterialLinkRecord] = [],
        batchQuestionLinks: [QuestionBankBatchQuestionLinkRecord] = []
    ) throws {
        guard plan.canImport, let paper = plan.paper, let stage = plan.stagingDirectory else {
            throw QuestionBankImportFailure.invalidPlan
        }
        let duplicate = duplicatePaper(for: paper, in: records)
        let previousPaperID = batchPreparation?.replacingPaperID ?? duplicate?.paperID
        if let duplicate, let previousPaperID, duplicate.paperID != previousPaperID {
            throw QuestionBankBatchFailure.conflictingReplacementTargets(
                batchPreparation?.metadata.sourceID ?? paper.id
            )
        }
        if let previousPaperID, decision != .replaceExisting {
            let previousTitle = records.first {
                $0.paperID == previousPaperID && $0.kind == paperKind
            }?.title ?? duplicate?.title ?? "未命名试卷"
            throw QuestionBankImportFailure.duplicatePaper(previousTitle)
        }

        let root: URL
        if let assetRoot { root = assetRoot } else { root = try QuestionBankAssetStore.root() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let generation = "\(safePathComponent(paper.id))-\(UUID().uuidString.lowercased())"
        guard let generationURL = QuestionBankAssetStore.url(for: generation, under: root) else {
            throw QuestionBankImportFailure.unsafeAssetPath
        }
        let replacingRows = records.filter { record in
            guard let previousPaperID else { return record.paperID == paper.id }
            return record.paperID == previousPaperID
        }
        let oldGenerations = Set(replacingRows.compactMap { record -> String? in
            guard record.kind == assetKind, let path = record.assetRelativePath else { return nil }
            return path.split(separator: "/").first.map(String.init)
        })

        do {
            if !plan.assets.isEmpty {
                try FileManager.default.createDirectory(at: generationURL, withIntermediateDirectories: true)
                for asset in plan.assets {
                    guard let source = QuestionBankAssetStore.url(for: asset.path, under: stage),
                          FileManager.default.fileExists(atPath: source.path) else {
                        throw QuestionBankImportFailure.missingStagingFile(asset.fileName)
                    }
                    let destinationRelativePath = "\(generation)/\(asset.path)"
                    guard let destinationCandidate = QuestionBankAssetStore.url(
                        for: destinationRelativePath, under: root
                    ) else {
                        throw QuestionBankImportFailure.unsafeAssetPath
                    }
                    try FileManager.default.createDirectory(
                        at: destinationCandidate.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    guard let destination = QuestionBankAssetStore.url(
                        for: destinationRelativePath, under: root
                    ) else {
                        throw QuestionBankImportFailure.unsafeAssetPath
                    }
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }

            let rows = try makeRows(from: plan, generation: generation)
            let desiredIDs = Set(rows.map(\.compoundID))
            let existingByID = Dictionary(uniqueKeysWithValues: replacingRows.map { ($0.compoundID, $0) })
            try context.transaction {
                for old in replacingRows where !desiredIDs.contains(old.compoundID) {
                    context.delete(old)
                }
                for row in rows {
                    if let existing = existingByID[row.compoundID] {
                        existing.update(from: row)
                    } else {
                        context.insert(row.makeRecord())
                    }
                }
                if let batchPreparation {
                    QuestionBankBatchRepository.apply(
                        batchPreparation, batches: batches, sources: sources,
                        materialLinks: batchMaterialLinks, questionLinks: batchQuestionLinks,
                        replacingPaperID: previousPaperID,
                        context: context
                    )
                } else if let previousPaperID {
                    QuestionBankBatchRepository.detachPaperFromBatches(
                        previousPaperID, batches: batches, sources: sources,
                        materialLinks: batchMaterialLinks, questionLinks: batchQuestionLinks,
                        context: context
                    )
                }
            }
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: generationURL)
            throw error
        }

        for oldGeneration in oldGenerations where oldGeneration != generation {
            guard let oldGenerationURL = QuestionBankAssetStore.url(for: oldGeneration, under: root) else { continue }
            try? FileManager.default.removeItem(at: oldGenerationURL)
        }
    }

    private static func makeRows(from plan: QuestionBankImportPlan, generation: String) throws -> [QuestionBankStoredRow] {
        guard let paper = plan.paper else { throw QuestionBankImportFailure.invalidPlan }
        var rows: [QuestionBankStoredRow] = []
        func append<T: Encodable>(kind: String, id: String, value: T, moduleID: String? = nil,
                                  number: Int? = nil, sequence: Int? = nil, title: String? = nil,
                                  search: String = "", normalizedKey: String? = nil,
                                  assetPath: String? = nil) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            rows.append(QuestionBankStoredRow(
                compoundID: "\(paper.id)::\(kind)::\(id)", paperID: paper.id, kind: kind,
                stableID: id, moduleID: moduleID, questionNumber: number, sequence: sequence,
                year: paper.year, examType: paper.examType, normalizedPaperKey: normalizedKey,
                title: title, searchText: search, payload: try encoder.encode(value),
                assetRelativePath: assetPath
            ))
        }
        try append(kind: paperKind, id: paper.id, value: paper, title: paper.title,
                    search: "\(paper.title) \(paper.year) \(paper.examType) \(paper.volume)", normalizedKey: paper.duplicateKey)
        for module in plan.modules {
            try append(kind: moduleKind, id: module.id, value: module, moduleID: module.id,
                       sequence: module.sequence, title: module.title, search: "\(module.title) \(module.instruction)")
        }
        for material in plan.materials {
            try append(kind: materialKind, id: material.id, value: material, moduleID: material.moduleID,
                       title: "共用材料", search: material.text)
        }
        for question in plan.questions {
            let optionSearch = question.options.map(\.text).joined(separator: " ")
            try append(kind: questionKind, id: question.id, value: question, moduleID: question.moduleID,
                       number: question.number, title: "第\(question.number)题",
                       search: "\(question.number) \(question.stem) \(optionSearch)")
        }
        for asset in plan.assets {
            try append(kind: assetKind, id: asset.id, value: asset,
                       moduleID: plan.questions.first(where: { $0.id == asset.ownerID })?.moduleID,
                       title: asset.fileName, search: "\(asset.fileName) \(asset.role)",
                       assetPath: "\(generation)/\(asset.path)")
        }
        return rows
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return result.isEmpty ? "paper" : String(result.prefix(80))
    }
}

enum QuestionBankPackageImporter {
    private static let logger = Logger(subsystem: "com.baoger07122.kaogongreview", category: "QuestionBankPackageImporter")
    static let maxJSONFileBytes: Int64 = 64 * 1024 * 1024
    static let maxJSONImageBytes: Int = 16 * 1024 * 1024
    static let maxJSONImagesTotalBytes: Int64 = 48 * 1024 * 1024
    private static let externalCoordinationTimeout: TimeInterval = 30

    private struct ParsedPackage {
        var paper: QuestionBankPaper?
        var batchMetadata: QuestionBankBatchMetadata?
        var modules: [QuestionBankModule]
        var materials: [QuestionBankMaterial]
        var questions: [QuestionBankQuestion]
        var assets: [QuestionBankAsset]
        var jsonAssets: [QuestionBankJSONAssetV1]
        var errors: [String]
    }

    private final class CoordinationCompletion: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        private let lock = NSLock()
        private var result: Result<Void, Error>?
        private var cancelledOrTimedOut = false

        func complete(_ result: Result<Void, Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelledOrTimedOut else { return false }
            self.result = result
            return true
        }

        func snapshot() -> Result<Void, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return result
        }

        func cancel() -> Bool {
            lock.lock()
            cancelledOrTimedOut = true
            let alreadyCompleted = result != nil
            lock.unlock()
            coordinator.cancel()
            return alreadyCompleted
        }
    }

    private static func logFailure(_ phase: String, error: Error) {
        let errorType = String(reflecting: type(of: error))
        logger.error("\(phase, privacy: .public) failed (\(errorType, privacy: .public))")
    }

    static func prepare(from sourceURL: URL) throws -> QuestionBankImportPlan {
        try prepare(from: sourceURL, source: .trustedLocalFile, onProgress: { _ in })
    }

    static func prepare(from sourceURL: URL, source: QuestionBankImportSource,
                        onProgress: @escaping @Sendable (QuestionBankImportPhase) -> Void) throws -> QuestionBankImportPlan {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard ["zip", "json"].contains(fileExtension) else {
            throw PackageError("请选择单文件真题包：新版 .json 或兼容旧版 .zip。备份 JSON 不是可导入的真题包。")
        }
        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        var temporarySource: URL?
        defer {
            if let temporarySource { try? FileManager.default.removeItem(at: temporarySource) }
        }

        do {
            try checkCancellation()
            let readableSource = try runPhase(.acquiringFile, onProgress: onProgress) {
                let url = try makeReadableSource(from: sourceURL, source: source)
                if source == .filesOpenIn { temporarySource = url }
                if fileExtension == "json" {
                    let byteCount = try fileSize(at: url)
                    guard byteCount <= maxJSONFileBytes else {
                        throw PackageError("真题 JSON 文件为 \(byteCount / 1024 / 1024) MiB，超过 64 MiB 上限。请拆分图片资源后重新生成。")
                    }
                }
                return url
            }
            let sourceFileSHA256 = try sha256(fileAt: readableSource)
            let parsed = try runPhase(.parsing, onProgress: onProgress) {
                fileExtension == "zip"
                    ? try parseZIP(from: readableSource, into: stage)
                    : try parseJSON(from: readableSource)
            }
            let imageAndReferenceErrors = try runPhase(.validatingImages, onProgress: onProgress) {
                var errors = parsed.errors
                if let metadataError = parsed.batchMetadata?.validationError {
                    errors.append(metadataError)
                }
                if let batchYear = parsed.batchMetadata?.year, let paper = parsed.paper, batchYear != paper.year {
                    errors.append("batch.year（\(batchYear)）与 paper.year（\(paper.year)）不一致；请核对来源数据，应用不会代为改写。")
                }
                if !parsed.jsonAssets.isEmpty {
                    errors += try installAndValidateJSONAssets(parsed.jsonAssets, paper: parsed.paper,
                        modules: parsed.modules, materials: parsed.materials, questions: parsed.questions,
                        staging: stage)
                }
                errors += try validate(paper: parsed.paper, modules: parsed.modules,
                    materials: parsed.materials, questions: parsed.questions,
                    assets: parsed.assets, staging: stage)
                return errors
            }
            return try runPhase(.preparingPreview, onProgress: onProgress) {
                try checkCancellation()
                logger.info("package validation finished; modules=\(parsed.modules.count), materials=\(parsed.materials.count), questions=\(parsed.questions.count), images=\(parsed.assets.count), errors=\(imageAndReferenceErrors.count)")
                return QuestionBankImportPlan(paper: parsed.paper, modules: parsed.modules,
                    materials: parsed.materials, questions: parsed.questions, assets: parsed.assets,
                    errors: imageAndReferenceErrors, stagingDirectory: stage,
                    batchMetadata: parsed.batchMetadata, sourceFileSHA256: sourceFileSHA256)
            }
        } catch {
            logFailure("package preparation", error: error)
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    private static func runPhase<T>(_ phase: QuestionBankImportPhase,
                                    onProgress: @Sendable (QuestionBankImportPhase) -> Void,
                                    operation: () throws -> T) rethrows -> T {
        onProgress(phase)
        let startedAt = ProcessInfo.processInfo.systemUptime
        logger.info("import phase started: \(phase.rawValue, privacy: .public)")
        do {
            let result = try operation()
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            logger.info("import phase completed: \(phase.rawValue, privacy: .public), elapsed_ms=\(elapsed, privacy: .public)")
            return result
        } catch {
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            logFailure("\(phase.rawValue) elapsed_ms=\(elapsed)", error: error)
            throw error
        }
    }

    private static func checkCancellation() throws {
        if withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
            throw CancellationError()
        }
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            throw PackageError("无法读取所选文件大小：\(error.localizedDescription)")
        }
    }

    private static func sha256(fileAt url: URL) throws -> String {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw PackageError("无法读取来源文件摘要：\(error.localizedDescription)") }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            throw PackageError("无法计算来源文件 SHA-256：\(error.localizedDescription)")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func makeReadableSource(from sourceURL: URL, source: QuestionBankImportSource) throws -> URL {
        guard sourceURL.isFileURL else { throw PackageError("所选项目不是本地文件。") }
        if source == .filesOpenIn {
            return try coordinateExternalFile(from: sourceURL)
        }
        do {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { throw PackageError("所选项目是文件夹；请选择 .json 或 .zip 单文件真题包。") }
        } catch let error as PackageError {
            throw error
        } catch {
            throw PackageError("无法取得本地文件：\(error.localizedDescription)")
        }
        let byteCount = try fileSize(at: sourceURL)
        guard byteCount > 0 else { throw PackageError("所选真题包是空文件。") }
        if source == .pickerCopy {
            logger.info("picker returned an app-local copy; reading it directly without security scope, iCloud polling, or coordination; bytes=\(byteCount)")
        } else {
            logger.info("trusted local package read directly; bytes=\(byteCount)")
        }
        return sourceURL
    }

    private static func coordinateExternalFile(from sourceURL: URL) throws -> URL {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankOpenIn-\(UUID().uuidString).\(sourceURL.pathExtension.lowercased())")
        let completion = CoordinationCompletion()
        logger.info("Files Open In coordination started")
        DispatchQueue.global(qos: .userInitiated).async {
            let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } }
            var result: Result<Void, Error>?
            var coordinationError: NSError?
            completion.coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges,
                                               error: &coordinationError) { coordinatedURL in
                do {
                    let values = try coordinatedURL.resourceValues(forKeys: [.isDirectoryKey])
                    guard values.isDirectory != true else {
                        throw PackageError("Files 收到的是文件夹；请选择 .json 或 .zip 单文件真题包。")
                    }
                    let byteCount = try fileSize(at: coordinatedURL)
                    guard byteCount > 0 else { throw PackageError("Files 返回的真题文件为空。") }
                    if sourceURL.pathExtension.lowercased() == "json", byteCount > maxJSONFileBytes {
                        throw PackageError("Files 真题 JSON 超过 64 MiB 上限。")
                    }
                    try FileManager.default.copyItem(at: coordinatedURL, to: target)
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
            }
            if let coordinationError {
                result = .failure(PackageError("Files 文件协调失败：\(coordinationError.localizedDescription)"))
            } else if result == nil {
                result = .failure(PackageError("Files 没有提供可读取的真题文件。"))
            }
            let keepCopy = completion.complete(result ?? .failure(PackageError("Files 文件读取失败。")))
            if !keepCopy { try? FileManager.default.removeItem(at: target) }
            completion.semaphore.signal()
        }

        let deadline = ProcessInfo.processInfo.systemUptime + externalCoordinationTimeout
        while completion.semaphore.wait(timeout: .now() + 0.2) != .success {
            do {
                try checkCancellation()
            } catch {
                let alreadyCompleted = completion.cancel()
                if alreadyCompleted { try? FileManager.default.removeItem(at: target) }
                throw error
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                if let result = completion.snapshot() {
                    try result.get()
                    break
                }
                let alreadyCompleted = completion.cancel()
                if alreadyCompleted, let result = completion.snapshot() {
                    try result.get()
                    break
                }
                throw PackageError("Files 文件协调读取超过 30 秒，已停止本次导入。请将文件存储到“我的 iPad”后重试。")
            }
        }
        guard let result = completion.snapshot() else {
            throw PackageError("Files 没有在时限内返回真题文件。")
        }
        do {
            try result.get()
        } catch {
            logFailure("Files Open In coordination", error: error)
            throw PackageError("无法从 Files 读取真题文件：\(error.localizedDescription)")
        }
        let byteCount = try fileSize(at: target)
        guard byteCount > 0 else { throw PackageError("Files 返回的真题文件为空。") }
        logger.info("Files Open In local copy ready; bytes=\(byteCount)")
        return target
    }

    private static func parseZIP(from sourceURL: URL, into stage: URL) throws -> ParsedPackage {
        try checkCancellation()
        logger.info("opening ZIP directly from local source")
        try extractArchive(at: sourceURL, to: stage)
        let workbooks = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "xlsx" }
        guard workbooks.count == 1 else {
            throw PackageError("ZIP 根目录必须且只能包含一个 .xlsx 标准工作簿。")
        }
        logger.info("XLSX table parsing started")
        let tables: [String: [[String: String]]]
        do {
            tables = try XLSXTableReader.read(workbooks[0])
        } catch {
            logFailure("XLSX parsing", error: error)
            throw error
        }
        try checkCancellation()
        var paper: QuestionBankPaper?
        var modules: [QuestionBankModule] = []
        var materials: [QuestionBankMaterial] = []
        var questions: [QuestionBankQuestion] = []
        var assets: [QuestionBankAsset] = []
        var errors: [String] = []
        do { paper = try parsePaper(tables["试卷"] ?? []) }
        catch { logFailure("paper sheet validation", error: error); errors.append("试卷表：\(error.localizedDescription)") }
        do { modules = try parseModules(tables["模块"] ?? []) }
        catch { logFailure("module sheet validation", error: error); errors.append("模块表：\(error.localizedDescription)") }
        do { materials = try parseMaterials(tables["材料"] ?? []) }
        catch { logFailure("materials sheet validation", error: error); errors.append("材料表：\(error.localizedDescription)") }
        do { questions = try parseQuestions(tables["题目"] ?? []) }
        catch { logFailure("questions sheet validation", error: error); errors.append("题目表：\(error.localizedDescription)") }
        do { assets = try parseAssets(tables["图片资源"] ?? []) }
        catch { logFailure("image asset sheet validation", error: error); errors.append("图片资源表：\(error.localizedDescription)") }
        return ParsedPackage(paper: paper, batchMetadata: nil, modules: modules, materials: materials,
            questions: questions, assets: assets, jsonAssets: [], errors: errors)
    }

    private static func parseJSON(from sourceURL: URL) throws -> ParsedPackage {
        try checkCancellation()
        let byteCount = try fileSize(at: sourceURL)
        guard byteCount > 0 else { throw PackageError("真题 JSON 文件为空。") }
        guard byteCount <= maxJSONFileBytes else {
            throw PackageError("真题 JSON 文件超过 64 MiB 上限。")
        }
        let data: Data
        do { data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe]) }
        catch { throw PackageError("无法读取真题 JSON 文件：\(error.localizedDescription)") }
        try checkCancellation()
        let document: QuestionBankImportJSONV1
        do { document = try JSONDecoder().decode(QuestionBankImportJSONV1.self, from: data) }
        catch let error as DecodingError {
            throw PackageError(jsonDecodingMessage(error))
        } catch {
            throw PackageError("真题 JSON 格式无效：\(error.localizedDescription)")
        }
        try checkCancellation()
        return ParsedPackage(paper: document.paper, batchMetadata: document.batch, modules: document.modules,
            materials: document.materials, questions: document.questions,
            assets: document.assets.map(\.metadata), jsonAssets: document.assets, errors: [])
    }

    private static func jsonDecodingMessage(_ error: DecodingError) -> String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            if key.stringValue == "format" && context.codingPath.isEmpty {
                return "所选 JSON 没有真题包 format 标识；备份 JSON 不能作为真题包导入。"
            }
            let missingPath = (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
            return "真题 JSON 缺少必需字段“\(missingPath)”。"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let location = path(context.codingPath)
            return "真题 JSON 字段“\(location.isEmpty ? "根对象" : location)”类型或值无效。"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "真题 JSON schema 无效；请按 kaogong-question-bank v1 格式重新生成。"
        }
    }

    private static func installAndValidateJSONAssets(_ jsonAssets: [QuestionBankJSONAssetV1],
        paper: QuestionBankPaper?, modules: [QuestionBankModule], materials: [QuestionBankMaterial],
        questions: [QuestionBankQuestion], staging: URL) throws -> [String] {
        var errors: [String] = []
        var totalImageBytes: Int64 = 0
        let questionNumbers = Dictionary(questions.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })
        var installedPaths = Set<String>()
        guard let assetsDirectory = QuestionBankAssetStore.url(for: "assets", under: staging) else {
            throw PackageError("真题 JSON 的图片目录路径不安全。")
        }
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        for asset in jsonAssets {
            try checkCancellation()
            let number = questionNumbers[asset.ownerID]
            let subject: String
            if let number { subject = "第\(number)题" }
            else if asset.ownerType == "material" { subject = "共用材料“\(asset.ownerID)”" }
            else { subject = "图片资源“\(asset.id.isEmpty ? "未命名" : asset.id)”" }
            let filename = asset.fileName.isEmpty ? (asset.id.isEmpty ? "未命名图片" : asset.id) : asset.fileName
            let label = "\(paper?.title ?? "真题包")／\(subject)／图片“\(filename)”"
            guard asset.dataBase64.hasPrefix("data:") == false else {
                errors.append("\(label)：dataBase64 必须是纯 Base64，不能包含 data: 前缀。")
                continue
            }
            guard !asset.dataBase64.isEmpty else {
                errors.append("\(label)：缺少图片字段 dataBase64。")
                continue
            }
            guard !asset.sha256.isEmpty else {
                errors.append("\(label)：缺少原始图片字节的 sha256。")
                continue
            }
            let parts = asset.path.split(separator: "/")
            guard parts.count == 2, parts.first == "assets", !parts[1].isEmpty,
                  !parts.contains(".."), !parts.contains("."), !asset.path.contains("\\"), !asset.path.contains(":"),
                  URL(fileURLWithPath: String(parts[1])).lastPathComponent == String(parts[1]),
                  asset.fileName == String(parts[1]) else {
                errors.append("\(label)：path 必须是安全的 assets/文件名路径，且文件名要与 fileName 相同。")
                continue
            }
            guard installedPaths.insert(asset.path).inserted else {
                errors.append("\(label)：与其他图片重复使用 path“\(asset.path)”。")
                continue
            }
            let maximumBase64Length = ((maxJSONImageBytes + 2) / 3) * 4
            guard asset.dataBase64.utf8.count <= maximumBase64Length else {
                errors.append("\(label)：图片超过 16 MiB 单图上限，已拒绝；请保留原图但拆分真题文件。")
                continue
            }
            guard asset.sha256.count == 64, asset.sha256.allSatisfy({ $0.isHexDigit }) else {
                errors.append("\(label)：sha256 必须是 64 位十六进制摘要。")
                continue
            }
            guard let imageData = Data(base64Encoded: asset.dataBase64) else {
                errors.append("\(label)：dataBase64 不是有效的纯 Base64。")
                continue
            }
            guard imageData.count <= maxJSONImageBytes else {
                errors.append("\(label)：图片为 \(imageData.count / 1024 / 1024) MiB，超过 16 MiB 单图上限。")
                continue
            }
            let nextTotal = totalImageBytes + Int64(imageData.count)
            guard nextTotal <= maxJSONImagesTotalBytes else {
                errors.append("\(label)：图片资源总量超过 48 MiB 上限。")
                continue
            }
            totalImageBytes = nextTotal
            let actualHash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
            guard actualHash.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
                errors.append("\(label)：sha256 与图片原始字节不匹配。")
                continue
            }
            let legacyTarget = staging.appendingPathComponent(asset.path).standardizedFileURL
            let legacyStringPrefix = legacyTarget.path.hasPrefix(staging.standardizedFileURL.path + "/")
            let safeTarget = QuestionBankAssetStore.url(for: asset.path, under: staging)
            if !legacyStringPrefix || safeTarget == nil {
                let diagnostic = QuestionBankAssetStore.redactedContainmentDiagnostic(
                    root: staging, candidate: legacyTarget
                )
                logger.info("JSON image normalized-path comparison: \(diagnostic, privacy: .public)")
            }
            guard let target = safeTarget else {
                errors.append("\(label)：图片 path 越出暂存目录。")
                continue
            }
            do { try imageData.write(to: target, options: .atomic) }
            catch { errors.append("\(label)：无法写入本地图片文件：\(error.localizedDescription)") }
        }
        return errors
    }

    static func cleanup(_ plan: QuestionBankImportPlan) {
        if let stagingDirectory = plan.stagingDirectory {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }
    }

    private enum PackageError: LocalizedError {
        case message(String)
        init(_ message: String) { self = .message(message) }
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }

    private static func extractArchive(at source: URL, to stage: URL) throws {
        guard let archive = Archive(url: source, accessMode: .read) else {
            logger.error("ZIP open failed; local copy is not a readable ZIP archive")
            throw PackageError("无法读取 ZIP 文件：内容不是有效 ZIP，或文件已损坏。")
        }
        let archiveEntries = Array(archive)
        logger.info("ZIP opened; entries=\(archiveEntries.count)")
        guard archiveEntries.count <= 800 else { throw PackageError("ZIP 包文件数量超过 800，已拒绝导入。") }
        var totalSize: UInt64 = 0
        var extractedPaths = Set<String>()
        for entry in archiveEntries {
            try checkCancellation()
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let components = path.split(separator: "/")
            guard !path.hasPrefix("/"), !components.isEmpty,
                  !components.contains(".."), !components.contains("."),
                  !path.contains(":") else {
                throw PackageError("ZIP 中包含不安全的路径：\(entry.path)")
            }
            if path.hasPrefix("__MACOSX/") || path == ".DS_Store" { continue }
            guard entry.type == .file || entry.type == .directory else {
                throw PackageError("ZIP 中包含不支持的链接或特殊文件：\(entry.path)")
            }
            guard extractedPaths.insert(path).inserted else {
                throw PackageError("ZIP 中存在重复文件路径：\(entry.path)")
            }
            if entry.type == .directory {
                if path != "assets/" && path != "assets" {
                    throw PackageError("ZIP 仅允许根目录工作簿和 assets 图片目录：\(entry.path)")
                }
                continue
            }
            let isWorkbook = path.lowercased().hasSuffix(".xlsx") && !path.contains("/")
            let isAsset = path.hasPrefix("assets/") && components.count == 2
            guard isWorkbook || isAsset else {
                throw PackageError("ZIP 中存在不符合格式的文件：\(entry.path)。工作簿应位于根目录，图片应位于 assets/。")
            }
            let size = entry.uncompressedSize
            guard size <= 30 * 1024 * 1024 else { throw PackageError("文件过大：\(entry.path)（单文件上限 30 MB）。") }
            totalSize += size
            guard totalSize <= 250 * 1024 * 1024 else { throw PackageError("ZIP 解压总量超过 250 MB，已拒绝导入。") }
            guard let target = QuestionBankAssetStore.url(for: path, under: stage) else {
                throw PackageError("ZIP 中包含越界文件路径：\(entry.path)")
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let checkedTarget = QuestionBankAssetStore.url(for: path, under: stage) else {
                throw PackageError("ZIP 中包含越界文件路径：\(entry.path)")
            }
            do {
                try archive.extract(entry, to: checkedTarget)
            } catch {
                throw PackageError("无法解压 ZIP 文件“\(entry.path)”：文件可能已损坏。\(error.localizedDescription)")
            }
        }
        logger.info("ZIP extraction completed; expanded bytes=\(totalSize)")
    }

    private static func parsePaper(_ rows: [[String: String]]) throws -> QuestionBankPaper {
        let table = try Table(rows: rows, required: ["试卷ID", "试卷名称", "年份", "考试类型"])
        guard table.dataRows.count == 1, let row = table.dataRows.first else {
            throw PackageError("试卷表必须且只能有一条试卷记录。")
        }
        let id = row["试卷ID"].cleaned, title = row["试卷名称"].cleaned
        let year = Int(row["年份"].cleaned) ?? 0
        let examType = row["考试类型"].cleaned
        guard !id.isEmpty, !title.isEmpty, year > 1900, !examType.isEmpty else {
            throw PackageError("试卷ID、名称、有效年份和考试类型均为必填项。")
        }
        return QuestionBankPaper(id: id, title: title, year: year, examType: examType,
                                 volume: row["卷别"].cleaned, source: row["来源"].cleaned,
                                 importVersion: row["导入版本"].cleaned)
    }

    private static func parseModules(_ rows: [[String: String]]) throws -> [QuestionBankModule] {
        let table = try Table(rows: rows, required: ["模块ID", "试卷ID", "模块序号", "模块标题", "模块说明"])
        return try table.dataRows.map { row in
            guard let sequence = Int(row["模块序号"].cleaned), sequence > 0 else {
                throw PackageError("模块“\(row["模块标题"].cleaned)”的序号不是正整数。")
            }
            return QuestionBankModule(id: row["模块ID"].cleaned, paperID: row["试卷ID"].cleaned,
                                      sequence: sequence, title: row["模块标题"].cleaned,
                                      instruction: row["模块说明"].cleaned, originalPage: row["原始页码"].cleaned)
        }
    }

    private static func parseMaterials(_ rows: [[String: String]]) throws -> [QuestionBankMaterial] {
        let table = try Table(rows: rows, required: ["材料ID", "试卷ID", "模块ID", "材料类型", "材料图片资源ID"])
        return table.dataRows.map {
            QuestionBankMaterial(id: $0["材料ID"].cleaned, paperID: $0["试卷ID"].cleaned,
                                 moduleID: $0["模块ID"].cleaned, type: $0["材料类型"].cleaned,
                                 text: $0["材料文字"].cleaned, imageAssetID: $0["材料图片资源ID"].cleaned,
                                 applicableQuestions: $0["适用题号"].cleaned, originalPage: $0["原始页码"].cleaned)
        }
    }

    private static func parseQuestions(_ rows: [[String: String]]) throws -> [QuestionBankQuestion] {
        let required = ["题目ID", "试卷ID", "模块ID", "题号", "科目", "题型", "材料ID", "题干", "题干图片资源ID",
                        "选项A", "选项A图片资源ID", "选项B", "选项B图片资源ID", "选项C", "选项C图片资源ID",
                        "选项D", "选项D图片资源ID", "正确答案"]
        let table = try Table(rows: rows, required: required)
        return try table.dataRows.map { row in
            guard let number = Int(row["题号"].cleaned), number > 0 else {
                throw PackageError("题号“\(row["题号"].cleaned)”不是正整数。")
            }
            let id = row["题目ID"].cleaned
            let options = ["A", "B", "C", "D"].map { letter in
                QuestionBankOption(id: letter, text: row["选项\(letter)"].cleaned,
                                   imageAssetID: row["选项\(letter)图片资源ID"].cleaned)
            }
            return QuestionBankQuestion(id: id, paperID: row["试卷ID"].cleaned, moduleID: row["模块ID"].cleaned,
                                        number: number, subject: row["科目"].cleaned, type: row["题型"].cleaned,
                                        materialID: row["材料ID"].cleaned, stem: row["题干"].cleaned,
                                        stemImageAssetID: row["题干图片资源ID"].cleaned, options: options,
                                        answer: row["正确答案"].cleaned.uppercased(), explanation: row["解析"].cleaned,
                                        originalPage: row["原始页码"].cleaned)
        }
    }

    private static func parseAssets(_ rows: [[String: String]]) throws -> [QuestionBankAsset] {
        let table = try Table(rows: rows, required: ["图片资源ID", "试卷ID", "所属类型", "所属ID", "用途", "相对路径", "MIME类型"])
        return table.dataRows.map { row in
            let path = row["相对路径"].cleaned.replacingOccurrences(of: "\\", with: "/")
            return QuestionBankAsset(id: row["图片资源ID"].cleaned, paperID: row["试卷ID"].cleaned,
                                     ownerType: row["所属类型"].cleaned, ownerID: row["所属ID"].cleaned,
                                     role: row["用途"].cleaned, path: path, mimeType: row["MIME类型"].cleaned.lowercased(),
                                     fileName: row["文件名"].cleaned.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : row["文件名"].cleaned,
                                     originalPage: row["原始页码"].cleaned)
        }
    }

    private static func validate(paper: QuestionBankPaper?, modules: [QuestionBankModule],
                                 materials: [QuestionBankMaterial], questions: [QuestionBankQuestion],
                                 assets: [QuestionBankAsset], staging: URL) throws -> [String] {
        var errors: [String] = []
        guard let paper else { return errors }
        if paper.id.isEmpty { errors.append("试卷ID不能为空。") }
        if paper.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("试卷名称不能为空。") }
        if paper.year <= 1900 { errors.append("试卷年份无效。") }
        if paper.examType.isEmpty { errors.append("考试类型不能为空。") }
        if modules.isEmpty { errors.append("\(paper.title)：模块表至少需要一条模块记录。") }
        reportDuplicates(modules.map(\.id), label: "模块ID", paper: paper.title, errors: &errors)
        reportDuplicates(modules.map(\.sequence), label: "模块序号", paper: paper.title, errors: &errors)
        reportDuplicates(materials.map(\.id), label: "材料ID", paper: paper.title, errors: &errors)
        reportDuplicates(questions.map(\.id), label: "题目ID", paper: paper.title, errors: &errors)
        reportDuplicates(questions.map(\.number), label: "题号", paper: paper.title, errors: &errors)
        let stableIDs: [(String, String)] = [(paper.id, "试卷")] +
            modules.map { ($0.id, "模块") } + materials.map { ($0.id, "材料") } +
            questions.map { ($0.id, "题目") } + assets.map { ($0.id, "图片资源") }
        var entityKindsByID: [String: Set<String>] = [:]
        for (id, kind) in stableIDs where !id.isEmpty {
            entityKindsByID[id, default: []].insert(kind)
        }
        for (id, kinds) in entityKindsByID where kinds.count > 1 {
            errors.append("\(paper.title)：不同实体重复使用 ID“\(id)”（\(kinds.sorted().joined(separator: "、"))）；选项 A–D 除外，它们只在各自题目内命名。")
        }
        let moduleIDs = Set(modules.map(\.id))
        let materialByID = Dictionary(materials.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let questionByID = Dictionary(questions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let assetByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (path, duplicates) in Dictionary(grouping: assets, by: \.path) where duplicates.count > 1 {
            let ownerNumbers = Set(duplicates.compactMap { questionByID[$0.ownerID]?.number })
            let location = ownerNumbers.sorted().map { "第\($0)题" }.joined(separator: "、")
            let questionLabel = location.isEmpty ? "" : "／\(location)"
            errors.append("\(paper.title)\(questionLabel)／图片“\(duplicates.map(\.fileName).joined(separator: "、"))”：多个图片资源共用了路径“\(path)”。")
        }
        for (id, duplicates) in Dictionary(grouping: assets, by: \.id) where duplicates.count > 1 {
            let questionNumber = questionByID[duplicates[0].ownerID]?.number
            let location = questionNumber.map { "／第\($0)题" } ?? ""
            let names = duplicates.map(\.fileName).joined(separator: "、")
            errors.append("\(paper.title)\(location)／图片“\(names)”：图片资源ID“\(id)”重复。")
        }
        for module in modules {
            try checkCancellation()
            if module.id.isEmpty || module.title.isEmpty { errors.append("\(paper.title)：模块ID和标题不能为空。") }
            if module.paperID != paper.id { errors.append("\(paper.title)／模块“\(module.title)”：试卷ID关联不一致。") }
        }
        for material in materials {
            try checkCancellation()
            let label = "\(paper.title)／材料“\(material.id.isEmpty ? "未命名" : material.id)”"
            if material.id.isEmpty { errors.append("\(label)：材料ID不能为空。") }
            if material.paperID != paper.id { errors.append("\(label)：试卷关联缺失或不匹配。") }
            if !moduleIDs.contains(material.moduleID) { errors.append("\(label)：模块ID“\(material.moduleID)”不存在。") }
            if !material.imageAssetID.isEmpty, assetByID[material.imageAssetID] == nil {
                errors.append("\(label)：找不到图片资源“\(material.imageAssetID)”。")
            }
        }

        var referencedAssets = Set<String>()
        func checkAsset(_ id: String, paperLabel: String, questionNumber: Int?, owner: String, role: String) {
            guard !id.isEmpty else { return }
            let qLabel = questionNumber.map { "第\($0)题" } ?? "共用材料"
            guard let asset = assetByID[id] else {
                errors.append("\(paperLabel)／\(qLabel)：缺少图片资源ID“\(id)”（\(role)）。")
                return
            }
            referencedAssets.insert(id)
            if asset.ownerID != owner || asset.role != role {
                errors.append("\(paperLabel)／\(qLabel)／图片“\(asset.fileName)”：所属记录或用途关联不匹配。")
            }
        }
        for question in questions {
            try checkCancellation()
            let label = "\(paper.title)／第\(question.number)题"
            if question.id.isEmpty { errors.append("\(label)：题目ID不能为空。") }
            if question.paperID != paper.id { errors.append("\(label)：试卷ID关联不匹配。") }
            if !moduleIDs.contains(question.moduleID) { errors.append("\(label)：所属模块“\(question.moduleID)”不存在。") }
            if !question.materialID.isEmpty, materialByID[question.materialID] == nil {
                errors.append("\(label)：共用材料“\(question.materialID)”不存在。")
            } else if let linkedMaterial = materialByID[question.materialID],
                      linkedMaterial.moduleID != question.moduleID {
                errors.append("\(label)：关联材料“\(question.materialID)”与题目所属模块不一致。")
            }
            if !["A", "B", "C", "D"].contains(question.answer) {
                errors.append("\(label)：正确答案“\(question.answer)”无效，必须为 A/B/C/D。")
            }
            if question.stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && question.stemImageAssetID.isEmpty {
                errors.append("\(label)：题干和题干图片不能同时为空。")
            }
            if question.options.map(\.id) != ["A", "B", "C", "D"] {
                errors.append("\(label)：选项必须为 A、B、C、D 四项。")
            }
            for option in question.options {
                if option.text.isEmpty && option.imageAssetID.isEmpty {
                    errors.append("\(label)／选项\(option.id)：文字和图片不能同时为空。")
                }
                if !option.imageAssetID.isEmpty {
                    checkAsset(option.imageAssetID, paperLabel: paper.title, questionNumber: question.number,
                               owner: question.id, role: "选项\(option.id)")
                }
            }
            if !question.stemImageAssetID.isEmpty {
                checkAsset(question.stemImageAssetID, paperLabel: paper.title, questionNumber: question.number,
                           owner: question.id, role: "题干整图")
            }
        }
        for material in materials where !material.imageAssetID.isEmpty {
            checkAsset(material.imageAssetID, paperLabel: paper.title, questionNumber: nil,
                       owner: material.id, role: "共用材料")
        }
        for asset in assets {
            try checkCancellation()
            let ownerLabel: String
            if let number = questionByID[asset.ownerID]?.number {
                ownerLabel = "／第\(number)题"
            } else if asset.ownerType == "material" {
                ownerLabel = "／共用材料“\(asset.ownerID)”"
            } else {
                ownerLabel = "／所属记录“\(asset.ownerID)”"
            }
            let label = "\(paper.title)\(ownerLabel)／图片“\(asset.fileName)”（ID：\(asset.id)）"
            if asset.id.isEmpty { errors.append("\(label)：图片资源ID不能为空。") }
            if asset.paperID != paper.id { errors.append("\(label)：试卷关联不匹配。") }
            let parts = asset.path.split(separator: "/")
            if parts.count != 2 || parts.first != "assets" || parts.contains("..") {
                errors.append("\(label)：相对路径必须为 assets/文件名，当前为“\(asset.path)”。")
                continue
            }
            guard let fileURL = QuestionBankAssetStore.url(for: asset.path, under: staging),
                  let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
                errors.append("\(paper.title)／\(asset.ownerType == "question" || asset.ownerType == "option" ? "第\(questionByID[asset.ownerID]?.number ?? 0)题／" : "")图片“\(asset.fileName)”：文件缺失或无法读取。")
                continue
            }
            let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let jpeg = data.starts(with: [0xFF, 0xD8, 0xFF])
            if !((asset.mimeType == "image/png" && png) || (["image/jpeg", "image/jpg"].contains(asset.mimeType) && jpeg)) {
                errors.append("\(label)：文件内容与MIME类型“\(asset.mimeType)”不匹配或不是有效 PNG/JPEG 图片。")
            }
            if asset.ownerType == "material", materialByID[asset.ownerID] == nil {
                errors.append("\(label)：关联材料“\(asset.ownerID)”不存在。")
            } else if ["question", "option"].contains(asset.ownerType), questionByID[asset.ownerID] == nil {
                errors.append("\(label)：关联题目“\(asset.ownerID)”不存在。")
            } else if !["material", "question", "option"].contains(asset.ownerType) {
                errors.append("\(label)：所属类型必须为 material、question 或 option。")
            }
            if !referencedAssets.contains(asset.id) {
                errors.append("\(label)：图片资源没有被材料或题目引用。")
            }
        }
        return errors
    }

    private static func reportDuplicates<Value: Hashable>(_ values: [Value], label: String,
                                                           paper: String, errors: inout [String]) {
        var seen = Set<Value>()
        for value in values where !seen.insert(value).inserted {
            errors.append("\(paper)：发现重复的\(label)“\(value)”。")
        }
    }

    private struct Table {
        let dataRows: [[String: String]]
        init(rows: [[String: String]], required: [String]) throws {
            guard let headerIndex = rows.firstIndex(where: { row in required.allSatisfy { row[$0] != nil } }),
                  let header = rows[safe: headerIndex] else {
                throw PackageError("找不到表头字段：\(required.joined(separator: "、"))。")
            }
            _ = header
            dataRows = rows.dropFirst(headerIndex + 1).filter { row in
                row.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
    }
}

private struct XLSXSheetReference {
    var name: String
    var relationshipID: String
}

private func xmlLocalName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}

private final class XLSXMetadataXMLParser: NSObject, XMLParserDelegate {
    var sheets: [XLSXSheetReference] = []
    var relationships: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        let localName = xmlLocalName(elementName)
        if localName == "sheet", let name = attributes["name"] {
            let rid = attributes.first(where: { $0.key == "id" || $0.key == "r:id" || $0.key.hasSuffix(":id") })?.value ?? ""
            sheets.append(XLSXSheetReference(name: name, relationshipID: rid))
        } else if localName == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            relationships[id] = target
        }
    }
}

private final class XLSXValuesXMLParser: NSObject, XMLParserDelegate {
    let sharedStringMode: Bool
    var sharedStrings: [String] = []
    struct CellValue {
        var value: String
        var type: String
    }
    var rows: [[Int: CellValue]] = []
    private var insideSharedString = false
    private var captureSharedText = false
    private var currentSharedText = ""
    private var rowIndex = -1
    private var columnIndex: Int?
    private var cellType = ""
    private var currentCellText = ""
    private var captureCellText = false

    init(sharedStringMode: Bool) { self.sharedStringMode = sharedStringMode }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        let localName = xmlLocalName(elementName)
        if sharedStringMode {
            if localName == "si" { insideSharedString = true; currentSharedText = "" }
            if localName == "t", insideSharedString { captureSharedText = true }
            return
        }
        if localName == "row" {
            rowIndex = (Int(attributes["r"] ?? "") ?? (rows.count + 1)) - 1
            if rowIndex >= rows.count { rows.append(contentsOf: repeatElement([:], count: rowIndex - rows.count + 1)) }
        } else if localName == "c" {
            columnIndex = Self.columnIndex(from: attributes["r"] ?? "")
            cellType = attributes["t"] ?? ""
            currentCellText = ""
        } else if localName == "v", columnIndex != nil {
            captureCellText = true
        } else if localName == "t", cellType == "inlineStr", columnIndex != nil {
            captureCellText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if sharedStringMode, captureSharedText { currentSharedText += string }
        else if !sharedStringMode, captureCellText { currentCellText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let localName = xmlLocalName(elementName)
        if sharedStringMode {
            if localName == "t" { captureSharedText = false }
            if localName == "si" { sharedStrings.append(currentSharedText); insideSharedString = false }
            return
        }
        if localName == "v" || localName == "t" { captureCellText = false }
        if localName == "c", let columnIndex, rowIndex >= 0, rowIndex < rows.count {
            rows[rowIndex][columnIndex] = CellValue(value: currentCellText, type: cellType)
            self.columnIndex = nil
            cellType = ""
        }
    }

    private static func columnIndex(from reference: String) -> Int? {
        let letters = reference.prefix { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        return letters.uppercased().reduce(0) { $0 * 26 + Int($1.asciiValue! - Character("A").asciiValue! + 1) } - 1
    }
}

private enum XLSXTableReader {
    static func read(_ file: URL) throws -> [String: [[String: String]]] {
        guard let archive = Archive(url: file, accessMode: .read) else {
            throw NSError(domain: "XLSX", code: 3, userInfo: [NSLocalizedDescriptionKey: "标准工作簿不是有效的 XLSX 文件。"])
        }
        let entries = Array(archive)
        guard entries.count <= 4_000 else {
            throw NSError(domain: "XLSX", code: 4, userInfo: [NSLocalizedDescriptionKey: "工作簿内部文件数量异常。"])
        }
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankXLSX-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let duplicatePaths = Dictionary(grouping: entries, by: \.path).filter { $0.value.count > 1 }
        guard duplicatePaths.isEmpty else {
            throw NSError(domain: "XLSX", code: 5, userInfo: [NSLocalizedDescriptionKey: "工作簿中存在重复文件路径。"])
        }
        let entryByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        var extractedSize: UInt64 = 0
        func extractXML(_ path: String) throws -> URL {
            // XLSX relationship manifests are XML documents but use the .rels extension.
            let isXMLDocument = [".xml", ".rels"].contains { path.lowercased().hasSuffix($0) }
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                  path.hasPrefix("xl/"), isXMLDocument,
                  let entry = entryByPath[path] else {
                throw NSError(domain: "XLSX", code: 6, userInfo: [NSLocalizedDescriptionKey: "工作簿缺少必要结构文件：\(path)"])
            }
            guard entry.type == .file, entry.uncompressedSize <= 32 * 1024 * 1024 else {
                throw NSError(domain: "XLSX", code: 7, userInfo: [NSLocalizedDescriptionKey: "工作簿 XML 文件类型异常或超过 32 MB：\(path)"])
            }
            extractedSize += entry.uncompressedSize
            guard extractedSize <= 96 * 1024 * 1024 else {
                throw NSError(domain: "XLSX", code: 8, userInfo: [NSLocalizedDescriptionKey: "工作簿 XML 解压总量超过 96 MB。"])
            }
            guard let destination = QuestionBankAssetStore.url(for: path, under: temporaryRoot) else {
                throw NSError(domain: "XLSX", code: 9, userInfo: [NSLocalizedDescriptionKey: "工作簿内部路径无效：\(path)"])
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let checkedDestination = QuestionBankAssetStore.url(for: path, under: temporaryRoot) else {
                throw NSError(domain: "XLSX", code: 9, userInfo: [NSLocalizedDescriptionKey: "工作簿内部路径无效：\(path)"])
            }
            try archive.extract(entry, to: checkedDestination)
            return checkedDestination
        }

        let workbookURL = try extractXML("xl/workbook.xml")
        let relationshipsURL = try extractXML("xl/_rels/workbook.xml.rels")
        let sharedStringsPath = "xl/sharedStrings.xml"
        let shared = entryByPath[sharedStringsPath] == nil
            ? [] : try values(at: extractXML(sharedStringsPath), sharedStrings: true).sharedStrings
        let workbook = try metadata(at: workbookURL)
        let relationships = try metadata(at: relationshipsURL)
        var result: [String: [[String: String]]] = [:]
        for sheet in workbook.sheets {
            guard let target = relationships.relationships[sheet.relationshipID] else {
                throw NSError(domain: "XLSX", code: 10, userInfo: [NSLocalizedDescriptionKey: "工作表“\(sheet.name)”缺少关系映射。"])
            }
            var relative = target.replacingOccurrences(of: "\\", with: "/")
            if relative.hasPrefix("/") { relative.removeFirst() }
            if !relative.hasPrefix("xl/") { relative = "xl/" + relative }
            guard !relative.split(separator: "/").contains(".."), relative.hasPrefix("xl/worksheets/") else {
                throw NSError(domain: "XLSX", code: 11, userInfo: [NSLocalizedDescriptionKey: "工作表“\(sheet.name)”路径无效。"])
            }
            let worksheet = try values(at: extractXML(relative), sharedStrings: false)
            let decodedRows: [[Int: String]] = worksheet.rows.map { row in
                row.mapValues { cell in
                    guard cell.type == "s", let index = Int(cell.value), index >= 0, index < shared.count else {
                        return cell.value
                    }
                    return shared[index]
                }
            }
            guard let headerRow = decodedRows.firstIndex(where: { row in
                row.values.contains(where: { ["试卷ID", "模块ID", "材料ID", "题目ID", "图片资源ID"].contains($0) })
            }) else { continue }
            let headers = decodedRows[headerRow]
            let headerNames = headers.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard Set(headerNames).count == headerNames.count else {
                throw NSError(domain: "XLSX", code: 12, userInfo: [NSLocalizedDescriptionKey: "工作表“\(sheet.name)”的字段名重复。"])
            }
            result[sheet.name] = decodedRows.dropFirst(headerRow).map { row in
                var mapped: [String: String] = [:]
                for (column, name) in headers where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let value = row[column] { mapped[name] = value }
                }
                return mapped
            }
        }
        return result
    }

    private static func metadata(at url: URL) throws -> XLSXMetadataXMLParser {
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.shouldProcessNamespaces = true
        let delegate = XLSXMetadataXMLParser()
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? NSError(domain: "XLSX", code: 1) }
        return delegate
    }

    private static func values(at url: URL, sharedStrings: Bool) throws -> XLSXValuesXMLParser {
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.shouldProcessNamespaces = true
        let delegate = XLSXValuesXMLParser(sharedStringMode: sharedStrings)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? NSError(domain: "XLSX", code: 2) }
        return delegate
    }
}

private extension String {
    var cleaned: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Optional where Wrapped == String {
    var cleaned: String { (self ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
