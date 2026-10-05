import Foundation
import SwiftData
import OSLog
import ZIPFoundation

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

struct QuestionBankImportPlan: Identifiable, Sendable {
    let id = UUID()
    var paper: QuestionBankPaper?
    var modules: [QuestionBankModule]
    var materials: [QuestionBankMaterial]
    var questions: [QuestionBankQuestion]
    var assets: [QuestionBankAsset]
    var errors: [String]
    var stagingDirectory: URL?

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

    var errorDescription: String? {
        switch self {
        case .invalidPlan:
            "导入包没有通过完整校验，未写入真题库。"
        case .duplicatePaper(let title):
            "已存在同一套试卷“\(title)”。请选择替换，或取消本次导入。"
        case .missingStagingFile(let name):
            "导入时找不到图片文件：\(name)。原有数据未更改。"
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
        guard let relativePath, !relativePath.isEmpty,
              !relativePath.contains(".."), !relativePath.hasPrefix("/") else { return nil }
        guard let root = try? root(create: false) else { return nil }
        let result = root.appendingPathComponent(relativePath).standardizedFileURL
        guard result.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
        return result
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
        assetRoot: URL? = nil
    ) throws {
        guard plan.canImport, let paper = plan.paper, let stage = plan.stagingDirectory else {
            throw QuestionBankImportFailure.invalidPlan
        }
        let duplicate = duplicatePaper(for: paper, in: records)
        if let duplicate, decision != .replaceExisting {
            throw QuestionBankImportFailure.duplicatePaper(duplicate.title ?? "未命名试卷")
        }

        let root: URL
        if let assetRoot { root = assetRoot } else { root = try QuestionBankAssetStore.root() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let generation = "\(safePathComponent(paper.id))-\(UUID().uuidString.lowercased())"
        let generationURL = root.appendingPathComponent(generation, isDirectory: true)
        let previousPaperID = duplicate?.paperID
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
                    let source = stage.appendingPathComponent(asset.path).standardizedFileURL
                    guard source.path.hasPrefix(stage.standardizedFileURL.path + "/"),
                          FileManager.default.fileExists(atPath: source.path) else {
                        throw QuestionBankImportFailure.missingStagingFile(asset.fileName)
                    }
                    let destination = generationURL.appendingPathComponent(asset.path)
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
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
            }
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: generationURL)
            throw error
        }

        for oldGeneration in oldGenerations where oldGeneration != generation {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(oldGeneration, isDirectory: true))
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

    static func prepare(from sourceURL: URL) throws -> QuestionBankImportPlan {
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            throw PackageError("请选择 .zip 真题包；不能直接导入 Excel、文件夹或其他文件。")
        }
        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        do {
            logger.info("prepare started; package extension is ZIP")
            let localArchive = stage.appendingPathComponent("incoming.zip")
            try stageSourceArchive(from: sourceURL, to: localArchive)
            logger.info("opening ZIP from app-local staging")
            try extractArchive(at: localArchive, to: stage)
            try FileManager.default.removeItem(at: localArchive)
            let workbooks = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "xlsx" }
            guard workbooks.count == 1 else {
                throw PackageError("ZIP 根目录必须且只能包含一个 .xlsx 标准工作簿。")
            }
            logger.info("XLSX validation started")
            let tables: [String: [[String: String]]]
            do {
                tables = try XLSXTableReader.read(workbooks[0])
            } catch {
                logger.error("XLSX validation failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            var paper: QuestionBankPaper?
            var modules: [QuestionBankModule] = []
            var materials: [QuestionBankMaterial] = []
            var questions: [QuestionBankQuestion] = []
            var assets: [QuestionBankAsset] = []
            var errors: [String] = []

            do { paper = try parsePaper(tables["试卷"] ?? []) }
            catch {
                logger.error("paper sheet validation failed: \(error.localizedDescription, privacy: .public)")
                errors.append("试卷表：\(error.localizedDescription)")
            }
            do { modules = try parseModules(tables["模块"] ?? []) }
            catch {
                logger.error("module sheet validation failed: \(error.localizedDescription, privacy: .public)")
                errors.append("模块表：\(error.localizedDescription)")
            }
            do { materials = try parseMaterials(tables["材料"] ?? []) }
            catch {
                logger.error("materials sheet validation failed: \(error.localizedDescription, privacy: .public)")
                errors.append("材料表：\(error.localizedDescription)")
            }
            do { questions = try parseQuestions(tables["题目"] ?? []) }
            catch {
                logger.error("questions sheet validation failed: \(error.localizedDescription, privacy: .public)")
                errors.append("题目表：\(error.localizedDescription)")
            }
            do { assets = try parseAssets(tables["图片资源"] ?? []) }
            catch {
                logger.error("image asset sheet validation failed: \(error.localizedDescription, privacy: .public)")
                errors.append("图片资源表：\(error.localizedDescription)")
            }

            logger.info("image and cross-reference validation started")
            errors += validate(paper: paper, modules: modules, materials: materials, questions: questions,
                               assets: assets, staging: stage)
            logger.info("package validation finished; modules=\(modules.count), materials=\(materials.count), questions=\(questions.count), images=\(assets.count), errors=\(errors.count)")
            return QuestionBankImportPlan(paper: paper, modules: modules, materials: materials,
                                          questions: questions, assets: assets, errors: errors,
                                          stagingDirectory: stage)
        } catch {
            logger.error("prepare failed; staging directory will be removed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    private static func stageSourceArchive(from sourceURL: URL, to localArchive: URL) throws {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } }
        logger.info("source access started; security scope granted=\(hasSecurityScope)")

        do {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else {
                throw PackageError("所选项目是文件夹；请选择 .zip 真题包。")
            }
        } catch let error as PackageError {
            throw error
        } catch {
            throw PackageError("无法读取所选文件信息：\(error.localizedDescription)")
        }

        try requestICloudDownloadIfNeeded(for: sourceURL)
        logger.info("coordinated source copy started")
        var copyResult: Result<Void, Error>?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.copyItem(at: coordinatedURL, to: localArchive)
                copyResult = .success(())
            } catch {
                copyResult = .failure(error)
            }
        }
        if let coordinationError {
            logger.error("source coordination failed: \(coordinationError.localizedDescription, privacy: .public)")
            throw PackageError("无法从文件提供方读取真题包：\(coordinationError.localizedDescription)")
        }
        guard let copyResult else {
            throw PackageError("文件提供方没有返回可读取的真题包。")
        }
        do {
            try copyResult.get()
        } catch {
            logger.error("copy to local staging failed: \(error.localizedDescription, privacy: .public)")
            throw PackageError("无法将真题包复制到本地暂存区：\(error.localizedDescription)")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: localArchive.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount > 0 else { throw PackageError("所选 ZIP 文件为空。") }
        logger.info("coordinated local copy completed; bytes=\(byteCount)")
    }

    private static func requestICloudDownloadIfNeeded(for sourceURL: URL) throws {
        guard let values = try? sourceURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else {
            logger.info("source is not reported as an iCloud ubiquitous item; file-provider coordination will handle the read")
            return
        }

        if values.ubiquitousItemDownloadingStatus == .current {
            logger.info("iCloud source is already current on device")
            return
        }

        do {
            logger.info("requesting iCloud source download")
            try FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
        } catch {
            logger.error("iCloud download request failed: \(error.localizedDescription, privacy: .public)")
            throw PackageError("无法请求 iCloud 下载真题包：\(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            guard let values = try? sourceURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                  let status = values.ubiquitousItemDownloadingStatus else {
                logger.error("iCloud download status could not be read; continuing to coordinated file access")
                return
            }
            if status == .current {
                logger.info("iCloud source became available; status=\(String(describing: status), privacy: .public)")
                return
            }
        }
        logger.error("iCloud source did not finish downloading within 90 seconds")
        throw PackageError("iCloud 真题包尚未下载完成。请确认 iPad 网络正常后重试。")
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
            let target = stage.appendingPathComponent(path).standardizedFileURL
            guard target.path.hasPrefix(stage.standardizedFileURL.path + "/") else {
                throw PackageError("ZIP 中包含越界文件路径：\(entry.path)")
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try archive.extract(entry, to: target)
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
                                 assets: [QuestionBankAsset], staging: URL) -> [String] {
        var errors: [String] = []
        guard let paper else { return errors }
        if modules.isEmpty { errors.append("\(paper.title)：模块表至少需要一条模块记录。") }
        reportDuplicates(modules.map(\.id), label: "模块ID", paper: paper.title, errors: &errors)
        reportDuplicates(modules.map(\.sequence), label: "模块序号", paper: paper.title, errors: &errors)
        reportDuplicates(materials.map(\.id), label: "材料ID", paper: paper.title, errors: &errors)
        reportDuplicates(questions.map(\.id), label: "题目ID", paper: paper.title, errors: &errors)
        reportDuplicates(questions.map(\.number), label: "题号", paper: paper.title, errors: &errors)
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
            if module.id.isEmpty || module.title.isEmpty { errors.append("\(paper.title)：模块ID和标题不能为空。") }
            if module.paperID != paper.id { errors.append("\(paper.title)／模块“\(module.title)”：试卷ID关联不一致。") }
        }
        for material in materials {
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
            let fileURL = staging.appendingPathComponent(asset.path).standardizedFileURL
            guard fileURL.path.hasPrefix(staging.standardizedFileURL.path + "/"),
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
            let destination = temporaryRoot.appendingPathComponent(path).standardizedFileURL
            guard destination.path.hasPrefix(temporaryRoot.standardizedFileURL.path + "/") else {
                throw NSError(domain: "XLSX", code: 9, userInfo: [NSLocalizedDescriptionKey: "工作簿内部路径无效：\(path)"])
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archive.extract(entry, to: destination)
            return destination
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
