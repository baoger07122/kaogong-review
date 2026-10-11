import CryptoKit
import Foundation
import SwiftData
import ZIPFoundation

struct QuestionBankBatchPackagePaperV1: Codable, Equatable, Sendable {
    var paperID: String
    var path: String
    var sha256: String
}

struct QuestionBankBatchPackageAssetV1: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var paperID: String
    var ownerType: String
    var ownerID: String
    var role: String
    var logicalPath: String
    var entryPath: String
    var mimeType: String
    var fileName: String
    var originalPage: String
    var sha256: String
    var byteCount: Int64

    var identity: String { "\(paperID)\u{0}\(id)" }
}

struct QuestionBankBatchPackageGroupV1: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var order: Int
}

struct QuestionBankBatchPackagePaperOrderV1: Codable, Equatable, Sendable, Identifiable {
    var paperID: String
    var groupID: String?
    var order: Int

    var id: String { paperID }

    private enum CodingKeys: String, CodingKey { case paperID, groupID, order }

    init(paperID: String, groupID: String?, order: Int) {
        self.paperID = paperID
        self.groupID = groupID
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paperID = try container.decode(String.self, forKey: .paperID)
        guard container.contains(.groupID) else {
            throw DecodingError.keyNotFound(
                CodingKeys.groupID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "paperOrder.groupID 必须出现；未分组使用 null。")
            )
        }
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        order = try container.decode(Int.self, forKey: .order)
    }
}

struct QuestionBankBatchPackageOrganizationV1: Codable, Equatable, Sendable {
    var groups: [QuestionBankBatchPackageGroupV1]
    var paperOrder: [QuestionBankBatchPackagePaperOrderV1]
}

struct QuestionBankBatchPackageManifestV1: Codable, Equatable, Sendable {
    static let formatIdentifier = "kaogong-question-bank-batch"
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var operation: String
    var createdAt: String
    var papers: [QuestionBankBatchPackagePaperV1]
    var assets: [QuestionBankBatchPackageAssetV1]
    var organization: QuestionBankBatchPackageOrganizationV1

    init(
        format: String = Self.formatIdentifier,
        schemaVersion: Int = Self.currentSchemaVersion,
        operation: String = "update",
        createdAt: String,
        papers: [QuestionBankBatchPackagePaperV1],
        assets: [QuestionBankBatchPackageAssetV1],
        organization: QuestionBankBatchPackageOrganizationV1
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.operation = operation
        self.createdAt = createdAt
        self.papers = papers
        self.assets = assets
        self.organization = organization
    }
}

struct QuestionBankBatchPackagePlan: Identifiable, Sendable {
    let id = UUID()
    var manifest: QuestionBankBatchPackageManifestV1
    var paperPlans: [QuestionBankImportPlan]
    var stagingDirectory: URL?
    var sourceFileSHA256: String
    var sourceFileByteCount: Int64
    var crossPaperQuestionIDConflicts: [String: String]

    var canImport: Bool {
        stagingDirectory != nil && !paperPlans.isEmpty
            && paperPlans.allSatisfy { $0.canImport }
    }
}

struct QuestionBankBatchQuestionKey: Hashable, Sendable, Identifiable {
    let paperID: String
    let questionID: String

    var id: String {
        Data("\(paperID)\u{0}\(questionID)".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct QuestionBankBatchPaperUpdateStatus: Identifiable, Sendable {
    var paperID: String
    var title: String
    var targetFound: Bool
    var conflict: String?
    var matchingQuestionCount: Int
    var newQuestionKeys: [QuestionBankBatchQuestionKey]

    var id: String { paperID }
    var canUpdate: Bool { targetFound && conflict == nil }
}

struct QuestionBankBatchPackageUpdatePreview: Sendable {
    var papers: [QuestionBankBatchPaperUpdateStatus]

    var updatablePaperCount: Int { papers.filter(\.canUpdate).count }
    var pendingPaperCount: Int { papers.count - updatablePaperCount }
    var newQuestionCount: Int { papers.flatMap(\.newQuestionKeys).count }
}

struct QuestionBankBatchPackageCommitResult: Sendable {
    var updatedPaperCount: Int
    var updatedQuestionCount: Int
    var addedQuestionCount: Int
    var pendingPaperCount: Int
    var payloadBackupFileName: String
}

struct QuestionBankBatchPackageExportSnapshot: Sendable {
    var orderedPaperIDs: [String]
    var organization: QuestionBankOrganizationSnapshot
    var records: [QuestionBankStoredRow]
    var assetRoot: URL
}

private struct QuestionBankBatchPayloadBackupDocument: Encodable {
    struct Entry: Encodable {
        var compoundID: String
        var paperID: String
        var kind: String
        var stableID: String
        var payloadBase64: String
        var payloadSHA256: String

        init(row: QuestionBankRecord) {
            compoundID = row.compoundID
            paperID = row.paperID
            kind = row.kind
            stableID = row.stableID
            payloadBase64 = row.payload.base64EncodedString()
            payloadSHA256 = SHA256.hash(data: row.payload).map { String(format: "%02x", $0) }.joined()
        }
    }

    var format = "kaogong-question-bank-payload-backup"
    var schemaVersion = 1
    var createdAt: String
    var sourcePackageSHA256: String
    var records: [Entry]
}

enum QuestionBankBatchPackageFailure: LocalizedError {
    case invalidArchive(String)
    case invalidManifest(String)
    case invalidPaper(String)
    case invalidAsset(String)
    case unsafePath(String)
    case invalidTarget(String)
    case noEligibleUpdates

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let reason): "批量更新包无效：\(reason)"
        case .invalidManifest(let reason): "批量更新清单无效：\(reason)"
        case .invalidPaper(let reason): "批量更新中的单卷文件无效：\(reason)"
        case .invalidAsset(let reason): "批量更新图片校验失败：\(reason)"
        case .unsafePath(let path): "批量更新包包含不安全路径：\(path)"
        case .invalidTarget(let reason): "批量更新没有写入：\(reason)"
        case .noEligibleUpdates: "没有可按 paperID 精确匹配的试卷；数据未更改。"
        }
    }
}

enum QuestionBankBatchPackageImporter {
    private static let maximumEntryCount = 4_000
    private static let maximumEntryBytes: UInt64 = 30 * 1024 * 1024
    private static let maximumArchiveBytes: UInt64 = 250 * 1024 * 1024

    static func containsManifest(at url: URL) -> Bool {
        guard let archive = Archive(url: url, accessMode: .read) else { return false }
        return archive.first(where: { $0.path == "manifest.json" && $0.type == .file }) != nil
    }

    static func prepare(
        from sourceURL: URL,
        onProgress: @escaping @Sendable (QuestionBankImportPhase) -> Void = { _ in }
    ) throws -> QuestionBankBatchPackagePlan {
        guard sourceURL.isFileURL else {
            throw QuestionBankBatchPackageFailure.invalidArchive("请选择本地 ZIP 文件。")
        }
        let stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankBatchImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stageRoot, withIntermediateDirectories: true)
        do {
            onProgress(.parsing)
            let extractedFiles = try extract(sourceURL, to: stageRoot)
            try Task.checkCancellation()
            guard let manifestURL = QuestionBankAssetStore.url(for: "manifest.json", under: stageRoot),
                  FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw QuestionBankBatchPackageFailure.invalidArchive("ZIP 根目录缺少 manifest.json。")
            }
            let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            let manifest: QuestionBankBatchPackageManifestV1
            do {
                manifest = try JSONDecoder().decode(QuestionBankBatchPackageManifestV1.self, from: manifestData)
            } catch {
                throw QuestionBankBatchPackageFailure.invalidManifest(error.localizedDescription)
            }
            try validateManifest(manifest)
            let expectedPaths = Set(["manifest.json"] + manifest.papers.map(\.path) + manifest.assets.map(\.entryPath))
            guard extractedFiles == expectedPaths else {
                let extra = extractedFiles.subtracting(expectedPaths).sorted().first
                let missing = expectedPaths.subtracting(extractedFiles).sorted().first
                throw QuestionBankBatchPackageFailure.invalidArchive(
                    extra.map { "存在未在清单声明的文件 \($0)。" }
                        ?? "清单引用的文件不存在：\(missing ?? "未知文件")。"
                )
            }
            onProgress(.validatingImages)

            var paperPlans: [QuestionBankImportPlan] = []
            var imageByteTotal: Int64 = 0
            for (index, paperEntry) in manifest.papers.enumerated() {
                try Task.checkCancellation()
                guard let paperURL = QuestionBankAssetStore.url(for: paperEntry.path, under: stageRoot),
                      FileManager.default.fileExists(atPath: paperURL.path) else {
                    throw QuestionBankBatchPackageFailure.invalidPaper("缺少 \(paperEntry.path)。")
                }
                let paperData = try Data(contentsOf: paperURL, options: [.mappedIfSafe])
                guard sha256(paperData) == paperEntry.sha256 else {
                    throw QuestionBankBatchPackageFailure.invalidPaper("\(paperEntry.path) 的 SHA-256 不匹配。")
                }
                guard Int64(paperData.count) <= QuestionBankPackageImporter.maxJSONFileBytes else {
                    throw QuestionBankBatchPackageFailure.invalidPaper("\(paperEntry.path) 超过 64 MiB。")
                }
                let document: QuestionBankImportJSONV1
                do {
                    document = try JSONDecoder().decode(QuestionBankImportJSONV1.self, from: paperData)
                } catch {
                    throw QuestionBankBatchPackageFailure.invalidPaper("\(paperEntry.path)：\(error.localizedDescription)")
                }
                guard document.paper.id == paperEntry.paperID else {
                    throw QuestionBankBatchPackageFailure.invalidPaper(
                        "\(paperEntry.path) 的 paper.id 与 manifest.paperID 不一致。"
                    )
                }
                guard document.assets.isEmpty else {
                    throw QuestionBankBatchPackageFailure.invalidPaper(
                        "\(paperEntry.path) 的 assets 必须为空；资源元数据只能放在根清单。"
                    )
                }
                guard document.paper.source != "" else {
                    throw QuestionBankBatchPackageFailure.invalidPaper("\(paperEntry.path) 缺少 paper.source。")
                }
                let sequenceValues = document.modules.map(\.sequence)
                guard sequenceValues == sequenceValues.sorted() else {
                    throw QuestionBankBatchPackageFailure.invalidPaper(
                        "\(paperEntry.path) 的 modules 数组必须按 sequence 升序排列。"
                    )
                }
                let questionNumbers = document.questions.map(\.number)
                if !questionNumbers.isEmpty,
                   questionNumbers != Array(1...questionNumbers.count) {
                    throw QuestionBankBatchPackageFailure.invalidPaper(
                        "\(paperEntry.path) 的 questions.number 必须从 1 连续递增，且数组顺序一致。"
                    )
                }

                let paperAssets = manifest.assets.filter { $0.paperID == paperEntry.paperID }
                var assets: [QuestionBankAsset] = []
                var paperImageByteCount: Int64 = 0
                var paperLargestImageByteCount: Int64 = 0
                let paperStage = stageRoot.appendingPathComponent(
                    "prepared-\(String(format: "%04d", index + 1))",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: paperStage, withIntermediateDirectories: true)
                for assetEntry in paperAssets {
                    try Task.checkCancellation()
                    guard let source = QuestionBankAssetStore.url(for: assetEntry.entryPath, under: stageRoot),
                          FileManager.default.fileExists(atPath: source.path) else {
                        throw QuestionBankBatchPackageFailure.invalidAsset("\(assetEntry.entryPath) 不存在。")
                    }
                    let data = try Data(contentsOf: source, options: [.mappedIfSafe])
                    guard Int64(data.count) == assetEntry.byteCount,
                          sha256(data) == assetEntry.sha256 else {
                        throw QuestionBankBatchPackageFailure.invalidAsset(
                            "\(assetEntry.fileName) 的字节数或 SHA-256 不匹配。"
                        )
                    }
                    imageByteTotal += Int64(data.count)
                    guard data.count <= QuestionBankPackageImporter.maxJSONImageBytes,
                          imageByteTotal <= QuestionBankPackageImporter.maxJSONImagesTotalBytes else {
                        throw QuestionBankBatchPackageFailure.invalidAsset("图片超过单张 16 MiB 或整包 48 MiB 上限。")
                    }
                    paperImageByteCount += Int64(data.count)
                    paperLargestImageByteCount = max(paperLargestImageByteCount, Int64(data.count))
                    guard let destination = QuestionBankAssetStore.url(for: assetEntry.logicalPath, under: paperStage) else {
                        throw QuestionBankBatchPackageFailure.unsafePath(assetEntry.logicalPath)
                    }
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: destination, options: .atomic)
                    assets.append(QuestionBankAsset(
                        id: assetEntry.id,
                        paperID: assetEntry.paperID,
                        ownerType: assetEntry.ownerType,
                        ownerID: assetEntry.ownerID,
                        role: assetEntry.role,
                        path: assetEntry.logicalPath,
                        mimeType: assetEntry.mimeType,
                        fileName: assetEntry.fileName,
                        originalPage: assetEntry.originalPage
                    ))
                }
                var errors = try QuestionBankPackageImporter.validate(
                    paper: document.paper,
                    modules: document.modules,
                    materials: document.materials,
                    questions: document.questions,
                    assets: assets,
                    staging: paperStage
                )
                errors += QuestionBankPackageImporter.validateSourceProvenance(
                    sourcePapers: document.sourcePapers ?? [],
                    materials: document.materials,
                    questions: document.questions
                )
                paperPlans.append(QuestionBankImportPlan(
                    paper: document.paper,
                    modules: document.modules,
                    materials: document.materials,
                    questions: document.questions,
                    assets: assets,
                    errors: errors,
                    stagingDirectory: paperStage,
                    batchMetadata: document.batch,
                    sourceFileSHA256: paperEntry.sha256,
                    sourcePapers: document.sourcePapers ?? [],
                    sourceFileFormat: "batch-json",
                    sourceFileByteCount: Int64(paperData.count),
                    decodedImageByteCount: paperImageByteCount,
                    largestDecodedImageByteCount: paperLargestImageByteCount
                ))
            }

            onProgress(.preparingPreview)
            var questionIDPaperIDs: [String: Set<String>] = [:]
            for plan in paperPlans {
                let paperID = plan.paper?.id ?? ""
                for question in plan.questions {
                    questionIDPaperIDs[question.id, default: []].insert(paperID)
                }
            }
            var conflictByPaper: [String: String] = [:]
            for (questionID, paperIDs) in questionIDPaperIDs where paperIDs.count > 1 {
                for paperID in paperIDs {
                    conflictByPaper[paperID] = "questionID \(questionID) 在包内多个 paperID 中重复，需先修复稳定 ID。"
                }
            }
            let sourceByteCount = try fileSize(at: sourceURL)
            let sourceHash = try sha256(fileAt: sourceURL)
            return QuestionBankBatchPackagePlan(
                manifest: manifest,
                paperPlans: paperPlans,
                stagingDirectory: stageRoot,
                sourceFileSHA256: sourceHash,
                sourceFileByteCount: sourceByteCount,
                crossPaperQuestionIDConflicts: conflictByPaper
            )
        } catch {
            try? FileManager.default.removeItem(at: stageRoot)
            throw error
        }
    }

    static func cleanup(_ plan: QuestionBankBatchPackagePlan) {
        guard let stage = plan.stagingDirectory else { return }
        try? FileManager.default.removeItem(at: stage)
    }

    private static func extract(_ source: URL, to stage: URL) throws -> Set<String> {
        guard let archive = Archive(url: source, accessMode: .read) else {
            throw QuestionBankBatchPackageFailure.invalidArchive("无法打开 ZIP 文件。")
        }
        let entries = Array(archive)
        guard entries.count <= maximumEntryCount else {
            throw QuestionBankBatchPackageFailure.invalidArchive("ZIP 内部文件数量超过 \(maximumEntryCount)。")
        }
        var seenPaths = Set<String>()
        var extractedFiles = Set<String>()
        var expandedBytes: UInt64 = 0
        for entry in entries {
            try Task.checkCancellation()
            let path = entry.path
            let normalizedPath = entry.type == .directory ? path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : path
            guard isSafeRelativePath(normalizedPath) else {
                throw QuestionBankBatchPackageFailure.unsafePath(path)
            }
            let canonicalPath = normalizedPath.lowercased()
            guard seenPaths.insert(canonicalPath).inserted else {
                throw QuestionBankBatchPackageFailure.invalidArchive("ZIP 中存在重复或大小写冲突路径 \(path)。")
            }
            if entry.type == .directory {
                guard normalizedPath == "papers" || normalizedPath == "assets" else {
                    throw QuestionBankBatchPackageFailure.unsafePath(path)
                }
                continue
            }
            guard entry.type == .file else {
                throw QuestionBankBatchPackageFailure.invalidArchive("ZIP 中只允许普通文件与目录：\(path)。")
            }
            guard entry.uncompressedSize <= maximumEntryBytes else {
                throw QuestionBankBatchPackageFailure.invalidArchive("文件 \(path) 超过 30 MiB。")
            }
            expandedBytes += entry.uncompressedSize
            guard expandedBytes <= maximumArchiveBytes else {
                throw QuestionBankBatchPackageFailure.invalidArchive("ZIP 解压总量超过 250 MiB。")
            }
            let allowedPath = normalizedPath == "manifest.json"
                || normalizedPath.hasPrefix("papers/")
                || normalizedPath.hasPrefix("assets/")
            guard allowedPath else {
                throw QuestionBankBatchPackageFailure.invalidArchive("ZIP 中存在未允许的文件 \(path)。")
            }
            guard let target = QuestionBankAssetStore.url(for: normalizedPath, under: stage) else {
                throw QuestionBankBatchPackageFailure.unsafePath(path)
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let checkedTarget = QuestionBankAssetStore.url(for: normalizedPath, under: stage) else {
                throw QuestionBankBatchPackageFailure.unsafePath(path)
            }
            do {
                try archive.extract(entry, to: checkedTarget)
            } catch {
                throw QuestionBankBatchPackageFailure.invalidArchive("无法解压 \(path)：\(error.localizedDescription)")
            }
            extractedFiles.insert(normalizedPath)
        }
        return extractedFiles
    }

    private static func validateManifest(_ manifest: QuestionBankBatchPackageManifestV1) throws {
        guard manifest.format == QuestionBankBatchPackageManifestV1.formatIdentifier else {
            throw QuestionBankBatchPackageFailure.invalidManifest("format 必须为 kaogong-question-bank-batch。")
        }
        guard manifest.schemaVersion == QuestionBankBatchPackageManifestV1.currentSchemaVersion else {
            throw QuestionBankBatchPackageFailure.invalidManifest("暂不支持 schemaVersion \(manifest.schemaVersion)。")
        }
        guard manifest.operation == "update" else {
            throw QuestionBankBatchPackageFailure.invalidManifest("operation 只能为 update。")
        }
        guard isRFC3339UTC(manifest.createdAt) else {
            throw QuestionBankBatchPackageFailure.invalidManifest("createdAt 必须是 RFC3339 UTC 时间。")
        }
        guard !manifest.papers.isEmpty else {
            throw QuestionBankBatchPackageFailure.invalidManifest("papers 不能为空。")
        }
        let paperIDs = manifest.papers.map(\.paperID)
        guard paperIDs.allSatisfy({ !$0.isEmpty }), Set(paperIDs).count == paperIDs.count else {
            throw QuestionBankBatchPackageFailure.invalidManifest("paperID 必须非空且唯一。")
        }
        let paperPaths = manifest.papers.map(\.path)
        guard Set(paperPaths).count == paperPaths.count,
              manifest.papers.allSatisfy({
                  isSafeRelativePath($0.path) && $0.path.hasPrefix("papers/")
                      && $0.path.lowercased().hasSuffix(".json")
                      && isSHA256($0.sha256)
              }) else {
            throw QuestionBankBatchPackageFailure.invalidManifest("paper path 必须是唯一安全的 papers/*.json，sha256 必须为小写 64 位十六进制。")
        }

        let groupIDs = manifest.organization.groups.map(\.id)
        guard groupIDs.allSatisfy({ !$0.isEmpty }), Set(groupIDs).count == groupIDs.count,
              manifest.organization.groups.allSatisfy({ !$0.name.trimmedNonempty.isEmpty && $0.order >= 0 }),
              Set(manifest.organization.groups.map(\.order)).count == manifest.organization.groups.count,
              manifest.organization.groups.map(\.order).sorted() == Array(0..<manifest.organization.groups.count) else {
            throw QuestionBankBatchPackageFailure.invalidManifest("organization.groups 的 id、name、order 无效。")
        }
        let knownGroupIDs = Set(groupIDs)
        let packagePaperIDs = Set(paperIDs)
        let paperOrder = manifest.organization.paperOrder
        guard paperOrder.count == paperIDs.count,
              Set(paperOrder.map(\.paperID)) == packagePaperIDs,
              paperOrder.allSatisfy({ row in
                  row.order >= 0 && (row.groupID == nil || knownGroupIDs.contains(row.groupID ?? ""))
              }) else {
            throw QuestionBankBatchPackageFailure.invalidManifest("organization.paperOrder 必须恰好枚举包中每套试卷一次，groupID 必须有效或显式 null。")
        }
        let orderGroups = Dictionary(grouping: paperOrder, by: { $0.groupID ?? "" })
        for rows in orderGroups.values {
            guard Set(rows.map(\.order)).count == rows.count,
                  rows.map(\.order).sorted() == Array(0..<rows.count) else {
                throw QuestionBankBatchPackageFailure.invalidManifest("每个分组内 paperOrder.order 必须从 0 连续且唯一。")
            }
        }

        let assetKeys = manifest.assets.map(\.identity)
        let logicalPaths = manifest.assets.map { "\($0.paperID)\u{0}\($0.logicalPath)" }
        guard Set(assetKeys).count == assetKeys.count,
              Set(logicalPaths).count == logicalPaths.count else {
            throw QuestionBankBatchPackageFailure.invalidManifest("每卷 asset id 和 logicalPath 必须唯一。")
        }
        for asset in manifest.assets {
            let extensionName = URL(fileURLWithPath: asset.fileName).pathExtension.lowercased()
            let mime = asset.mimeType.lowercased()
            let isPNG = extensionName == "png" && mime == "image/png"
            let isJPEG = ["jpg", "jpeg"].contains(extensionName) && ["image/jpeg", "image/jpg"].contains(mime)
            guard packagePaperIDs.contains(asset.paperID),
                  !asset.id.isEmpty, !asset.ownerID.isEmpty,
                  ["material", "question", "option"].contains(asset.ownerType),
                  isSafeAssetLogicalPath(asset.logicalPath),
                  asset.fileName == URL(fileURLWithPath: asset.logicalPath).lastPathComponent,
                  isSHA256(asset.sha256), asset.sha256 == asset.sha256.lowercased(),
                  asset.byteCount > 0, asset.byteCount <= Int64(QuestionBankPackageImporter.maxJSONImageBytes),
                  (isPNG || isJPEG),
                  asset.entryPath == "assets/\(asset.sha256).\(extensionName)",
                  isSafeRelativePath(asset.entryPath) else {
                throw QuestionBankBatchPackageFailure.invalidManifest("asset \(asset.id) 的路径、图片类型、SHA 或字节数无效。")
            }
        }
    }

    private static func isSafeAssetLogicalPath(_ path: String) -> Bool {
        guard isSafeRelativePath(path) else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0] == "assets"
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func isRFC3339UTC(_ value: String) -> Bool {
        guard value.hasSuffix("Z") else { return false }
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds]
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if formatter.date(from: value) != nil { return true }
        }
        return false
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}

@MainActor
enum QuestionBankBatchPackageRepository {
    static func updatePreview(
        for package: QuestionBankBatchPackagePlan,
        records: [QuestionBankRecord]
    ) -> QuestionBankBatchPackageUpdatePreview {
        var questionIDsByPaper: [String: Set<String>] = [:]
        for plan in package.paperPlans {
            let paperID = plan.paper?.id ?? ""
            for question in plan.questions {
                questionIDsByPaper[paperID, default: []].insert(question.id)
            }
        }
        var paperIDsByQuestion: [String: Set<String>] = [:]
        for (paperID, ids) in questionIDsByPaper {
            for id in ids { paperIDsByQuestion[id, default: []].insert(paperID) }
        }
        let duplicatedQuestionIDs = Set(paperIDsByQuestion.compactMap { id, paperIDs in
            paperIDs.count > 1 ? id : nil
        })

        let statuses = package.paperPlans.map { plan in
            let paperID = plan.paper?.id ?? ""
            let title = plan.paper?.title ?? paperID
            if let conflict = package.crossPaperQuestionIDConflicts[paperID] {
                return QuestionBankBatchPaperUpdateStatus(
                    paperID: paperID, title: title, targetFound: false, conflict: conflict,
                    matchingQuestionCount: 0, newQuestionKeys: []
                )
            }
            let paperRows = records.filter { $0.paperID == paperID }
            let paperMatches = paperRows.filter {
                $0.kind == QuestionBankRepository.paperKind && $0.stableID == paperID
            }
            guard paperMatches.count == 1 else {
                let sameStableIDElsewhere = records.contains {
                    $0.kind == QuestionBankRepository.paperKind && $0.stableID == paperID && $0.paperID != paperID
                }
                return QuestionBankBatchPaperUpdateStatus(
                    paperID: paperID, title: title, targetFound: false,
                    conflict: sameStableIDElsewhere ? "paperID 在本机指向不同试卷记录。" : nil,
                    matchingQuestionCount: 0, newQuestionKeys: []
                )
            }

            var conflict: String?
            for question in plan.questions where duplicatedQuestionIDs.contains(question.id) {
                conflict = "questionID \(question.id) 在包内多个 paperID 中重复。"
                break
            }
            let incomingEntities = [(QuestionBankRepository.moduleKind, plan.modules.map(\.id)),
                                    (QuestionBankRepository.materialKind, plan.materials.map(\.id)),
                                    (QuestionBankRepository.questionKind, plan.questions.map(\.id)),
                                    (QuestionBankRepository.assetKind, plan.assets.map(\.id))]
            for (kind, ids) in incomingEntities where conflict == nil {
                for id in ids {
                    if paperRows.contains(where: { $0.stableID == id && $0.kind != kind }) {
                        conflict = "本机 \(id) 已用于另一种题库实体。"
                        break
                    }
                }
            }
            if conflict == nil {
                for question in plan.questions {
                    if records.contains(where: {
                        $0.kind == QuestionBankRepository.questionKind
                            && $0.stableID == question.id && $0.paperID != paperID
                    }) {
                        conflict = "questionID \(question.id) 已属于另一套试卷。"
                        break
                    }
                }
            }
            let localQuestionIDs = Set(paperRows.filter { $0.kind == QuestionBankRepository.questionKind }.map(\.stableID))
            let newKeys = conflict == nil
                ? plan.questions.filter { !localQuestionIDs.contains($0.id) }
                    .map { QuestionBankBatchQuestionKey(paperID: paperID, questionID: $0.id) }
                : []
            return QuestionBankBatchPaperUpdateStatus(
                paperID: paperID,
                title: title,
                targetFound: true,
                conflict: conflict,
                matchingQuestionCount: plan.questions.count - newKeys.count,
                newQuestionKeys: newKeys
            )
        }
        return QuestionBankBatchPackageUpdatePreview(papers: statuses)
    }

    static func commit(
        _ package: QuestionBankBatchPackagePlan,
        confirmedNewQuestionKeys: Set<QuestionBankBatchQuestionKey>,
        records: [QuestionBankRecord],
        context: ModelContext,
        assetRoot: URL? = nil
    ) throws -> QuestionBankBatchPackageCommitResult {
        guard package.canImport else {
            throw QuestionBankBatchPackageFailure.invalidTarget("批量包没有通过全部结构与图片校验。")
        }
        let preview = updatePreview(for: package, records: records)
        guard preview.updatablePaperCount > 0 else {
            throw QuestionBankBatchPackageFailure.noEligibleUpdates
        }

        let root = try assetRoot ?? QuestionBankAssetStore.root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var stagedGenerations: [URL] = []
        var oldGenerations = Set<String>()
        var rowsToApply: [QuestionBankStoredRow] = []
        var updatedPaperCount = 0
        var updatedQuestionCount = 0
        var addedQuestionCount = 0
        let existingByCompoundID = Dictionary(
            records.map { ($0.compoundID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        do {
            for (index, plan) in package.paperPlans.enumerated() {
                guard index < preview.papers.count else { continue }
                let status = preview.papers[index]
                guard status.canUpdate, let paper = plan.paper,
                      let stage = plan.stagingDirectory else { continue }
                let confirmedKeys = Set(confirmedNewQuestionKeys.filter { $0.paperID == paper.id })
                let newQuestionIDs = Set(status.newQuestionKeys
                    .filter(confirmedKeys.contains)
                    .map(\.questionID))
                let existingQuestionIDs = Set(plan.questions.map(\.id))
                    .subtracting(Set(status.newQuestionKeys.map(\.questionID)))
                let includedQuestionIDs = existingQuestionIDs.union(newQuestionIDs)

                let generation = "\(QuestionBankRepository.safePathComponent(paper.id))-\(UUID().uuidString.lowercased())"
                let allRows = try QuestionBankRepository.makeRows(from: plan, generation: generation)
                let includedMaterials = Set(plan.materials.map(\.id))
                let includedRows = allRows.filter { row in
                    switch row.kind {
                    case QuestionBankRepository.paperKind,
                         QuestionBankRepository.moduleKind,
                         QuestionBankRepository.materialKind:
                        return true
                    case QuestionBankRepository.questionKind:
                        return includedQuestionIDs.contains(row.stableID)
                    case QuestionBankRepository.assetKind:
                        guard let asset = plan.assets.first(where: { $0.id == row.stableID }) else { return false }
                        if asset.ownerType == "material" { return includedMaterials.contains(asset.ownerID) }
                        return includedQuestionIDs.contains(asset.ownerID)
                    default:
                        return false
                    }
                }
                let assetsByID = Dictionary(plan.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let includedAssetIDs = Set(includedRows.filter { $0.kind == QuestionBankRepository.assetKind }.map(\.stableID))
                let generationURL = QuestionBankAssetStore.url(for: generation, under: root)
                if !includedAssetIDs.isEmpty {
                    guard let generationURL else {
                        throw QuestionBankBatchPackageFailure.unsafePath(generation)
                    }
                    try FileManager.default.createDirectory(at: generationURL, withIntermediateDirectories: true)
                    stagedGenerations.append(generationURL)
                    for assetID in includedAssetIDs {
                        guard let asset = assetsByID[assetID] else {
                            throw QuestionBankBatchPackageFailure.invalidTarget("缺少图片资源记录：\(assetID)。")
                        }
                        guard let source = QuestionBankAssetStore.url(for: asset.path, under: stage),
                              FileManager.default.fileExists(atPath: source.path) else {
                            throw QuestionBankImportFailure.missingStagingFile(asset.fileName)
                        }
                        guard let destination = QuestionBankAssetStore.url(for: "\(generation)/\(asset.path)", under: root) else {
                            throw QuestionBankBatchPackageFailure.unsafePath(asset.path)
                        }
                        try FileManager.default.createDirectory(
                            at: destination.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try FileManager.default.copyItem(at: source, to: destination)
                    }
                }

                let localRows = records.filter { $0.paperID == paper.id }
                oldGenerations.formUnion(localRows.compactMap { row in
                    guard row.kind == QuestionBankRepository.assetKind, let path = row.assetRelativePath else { return nil }
                    return path.split(separator: "/").first.map(String.init)
                })
                for var row in includedRows {
                    if let old = existingByCompoundID[row.compoundID] {
                        guard old.paperID == row.paperID, old.kind == row.kind, old.stableID == row.stableID else {
                            throw QuestionBankBatchPackageFailure.invalidTarget("发现实体 ID 与本机记录冲突。")
                        }
                        row.payload = try mergedPayload(
                            incoming: row.payload,
                            existing: old.payload,
                            kind: row.kind
                        )
                        if row.kind == QuestionBankRepository.questionKind,
                           let question = try? JSONDecoder().decode(QuestionBankQuestion.self, from: row.payload) {
                            row.searchText = ([String(question.number), question.stem]
                                + question.options.map(\.text)
                                + (question.knowledgePoints ?? [])
                                + (question.weaknessTags ?? [])).joined(separator: " ")
                            updatedQuestionCount += 1
                        }
                    } else if row.kind == QuestionBankRepository.questionKind {
                        addedQuestionCount += 1
                    }
                    rowsToApply.append(row)
                }
                if !includedRows.isEmpty { updatedPaperCount += 1 }
            }
            guard !rowsToApply.isEmpty else {
                throw QuestionBankBatchPackageFailure.noEligibleUpdates
            }
            let finalRowsByID = Dictionary(rowsToApply.map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
            let existingRowsToUpdate = records.filter { finalRowsByID[$0.compoundID] != nil }
            let payloadBackupURL = try persistPayloadBackup(
                existingRowsToUpdate,
                sourcePackageSHA256: package.sourceFileSHA256
            )
            do {
                try context.transaction {
                    for row in finalRowsByID.values {
                        if let existing = existingByCompoundID[row.compoundID] {
                            existing.update(from: row)
                        } else {
                            context.insert(row.makeRecord())
                        }
                    }
                }
            } catch {
                context.rollback()
                throw error
            }

            let referencedGenerations = Set(
                records.filter { $0.kind == QuestionBankRepository.assetKind }
                    .compactMap { $0.assetRelativePath?.split(separator: "/").first.map(String.init) }
                    + finalRowsByID.values.filter { $0.kind == QuestionBankRepository.assetKind }
                        .compactMap { $0.assetRelativePath?.split(separator: "/").first.map(String.init) }
            )
            for generation in oldGenerations.subtracting(referencedGenerations) {
                if let url = QuestionBankAssetStore.url(for: generation, under: root) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            return QuestionBankBatchPackageCommitResult(
                updatedPaperCount: updatedPaperCount,
                updatedQuestionCount: updatedQuestionCount,
                addedQuestionCount: addedQuestionCount,
                pendingPaperCount: preview.pendingPaperCount,
                payloadBackupFileName: payloadBackupURL.lastPathComponent
            )
        } catch {
            for generation in stagedGenerations {
                try? FileManager.default.removeItem(at: generation)
            }
            throw error
        }
    }

    private static func mergedPayload(incoming: Data, existing: Data, kind: String) throws -> Data {
        guard let oldObject = try JSONSerialization.jsonObject(with: existing) as? [String: Any],
              let newObject = try JSONSerialization.jsonObject(with: incoming) as? [String: Any] else {
            throw QuestionBankBatchPackageFailure.invalidTarget("题库 payload 无法解析；未写入数据。")
        }
        var merged = oldObject
        for (key, value) in newObject {
            merged[key] = value
        }
        if kind == QuestionBankRepository.questionKind {
            for key in ["isDifficult", "needsReview", "knowledgePoints", "weaknessTags"] {
                if let localValue = oldObject[key] {
                    merged[key] = localValue
                } else {
                    merged.removeValue(forKey: key)
                }
            }
        }
        return try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    private static func persistPayloadBackup(
        _ rows: [QuestionBankRecord],
        sourcePackageSHA256: String
    ) throws -> URL {
        guard !rows.isEmpty else {
            throw QuestionBankBatchPackageFailure.invalidTarget("没有可备份的现有题库 payload；本次更新已取消。")
        }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let backupDirectory = applicationSupport.appendingPathComponent(
            "QuestionBankBatchBackups",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let target = backupDirectory.appendingPathComponent("latest-payload-backup.json")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let document = QuestionBankBatchPayloadBackupDocument(
            createdAt: formatter.string(from: Date()),
            sourcePackageSHA256: sourcePackageSHA256,
            records: rows.sorted { $0.compoundID < $1.compoundID }
                .map { QuestionBankBatchPayloadBackupDocument.Entry(row: $0) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: target, options: .atomic)
        return target
    }
}

enum QuestionBankBatchPackageExporter {
    @MainActor
    static func makeSnapshot(
        records: [QuestionBankRecord],
        organizationStore: QuestionBankOrganizationStore
    ) throws -> QuestionBankBatchPackageExportSnapshot {
        let allPaperIDs = QuestionBankHomeIndex(records: records).papers.map(\.id)
        let organization = organizationStore.exportOrganization(for: allPaperIDs)
        var exportedPlacements = organization.placements
        var ungroupedOrder = exportedPlacements.filter { $0.groupID == nil }.count
        let alreadyOrdered = Set(exportedPlacements.map(\.paperID))
        for paperID in allPaperIDs where !alreadyOrdered.contains(paperID) {
            exportedPlacements.append(QuestionBankPaperPlacement(
                paperID: paperID,
                groupID: nil,
                order: ungroupedOrder
            ))
            ungroupedOrder += 1
        }
        var exportedOrganization = organization
        exportedOrganization.placements = exportedPlacements
        let orderedPaperIDs = exportedPlacements.sorted { left, right in
            let leftGroupOrder = left.groupID.flatMap { id in organization.groups.firstIndex(where: { $0.id == id }) } ?? Int.max
            let rightGroupOrder = right.groupID.flatMap { id in organization.groups.firstIndex(where: { $0.id == id }) } ?? Int.max
            if leftGroupOrder != rightGroupOrder { return leftGroupOrder < rightGroupOrder }
            if left.order != right.order { return left.order < right.order }
            return left.paperID < right.paperID
        }.map(\.paperID)
        guard !orderedPaperIDs.isEmpty else {
            throw QuestionBankBatchPackageFailure.invalidTarget("当前没有可导出的试卷。")
        }
        let rows = records.map { row in
            QuestionBankStoredRow(
                compoundID: row.compoundID,
                paperID: row.paperID,
                kind: row.kind,
                stableID: row.stableID,
                moduleID: row.moduleID,
                questionNumber: row.questionNumber,
                sequence: row.sequence,
                year: row.year,
                examType: row.examType,
                normalizedPaperKey: row.normalizedPaperKey,
                title: row.title,
                searchText: row.searchText,
                payload: row.payload,
                assetRelativePath: row.assetRelativePath
            )
        }
        return QuestionBankBatchPackageExportSnapshot(
            orderedPaperIDs: orderedPaperIDs,
            organization: exportedOrganization,
            records: rows,
            assetRoot: try QuestionBankAssetStore.root(create: false)
        )
    }

    static func export(snapshot: QuestionBankBatchPackageExportSnapshot) throws -> URL {
        let orderedPaperIDs = snapshot.orderedPaperIDs
        let organization = snapshot.organization
        let exportedPlacements = organization.placements
        let recordsByPaper = Dictionary(grouping: snapshot.records, by: \.paperID)
        let stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankBatchExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stageRoot.appendingPathComponent("papers", isDirectory: true),
                                               withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stageRoot.appendingPathComponent("assets", isDirectory: true),
                                               withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageRoot) }

        var paperEntries: [QuestionBankBatchPackagePaperV1] = []
        var assetEntries: [QuestionBankBatchPackageAssetV1] = []
        var binaryFiles: [String: Data] = [:]
        let assetRoot = snapshot.assetRoot
        var decodedImageByteCount: Int64 = 0
        var paperJSONByteCount: Int64 = 0

        for (index, paperID) in orderedPaperIDs.enumerated() {
            guard let rows = recordsByPaper[paperID],
                  let paperRow = rows.first(where: { $0.kind == QuestionBankRepository.paperKind }),
                  var paperObject = jsonObject(paperRow.payload) else {
                throw QuestionBankBatchPackageFailure.invalidPaper("试卷 \(paperID) 缺少有效的试卷 payload。")
            }
            let modules = try jsonObjects(rows.filter { $0.kind == QuestionBankRepository.moduleKind }, label: "模块")
                .sorted {
                    if $0.0.sequence != $1.0.sequence { return ($0.0.sequence ?? Int.max) < ($1.0.sequence ?? Int.max) }
                    return $0.0.stableID < $1.0.stableID
                }
                .map { $0.1 }
            let materials = try jsonObjects(rows.filter { $0.kind == QuestionBankRepository.materialKind }, label: "材料")
                .sorted { $0.0.stableID < $1.0.stableID }
                .map { $0.1 }
            let questions = try jsonObjects(rows.filter { $0.kind == QuestionBankRepository.questionKind }, label: "题目")
                .sorted {
                    if $0.0.questionNumber != $1.0.questionNumber {
                        return ($0.0.questionNumber ?? Int.max) < ($1.0.questionNumber ?? Int.max)
                    }
                    return $0.0.stableID < $1.0.stableID
                }
                .map { $0.1 }

            var sourcePapers: Any?
            if let value = paperObject.removeValue(forKey: "sourcePapers") { sourcePapers = value }
            for assetRow in rows where assetRow.kind == QuestionBankRepository.assetKind {
                guard let asset = try? JSONDecoder().decode(QuestionBankAsset.self, from: assetRow.payload),
                      let relativePath = assetRow.assetRelativePath,
                      let source = QuestionBankAssetStore.url(for: relativePath, under: assetRoot),
                      FileManager.default.fileExists(atPath: source.path) else {
                    throw QuestionBankBatchPackageFailure.invalidAsset("本机资源 \(assetRow.stableID) 缺失。")
                }
                let data = try Data(contentsOf: source, options: [.mappedIfSafe])
                decodedImageByteCount += Int64(data.count)
                guard Int64(data.count) <= Int64(QuestionBankPackageImporter.maxJSONImageBytes),
                      decodedImageByteCount <= Int64(QuestionBankPackageImporter.maxJSONImagesTotalBytes) else {
                    throw QuestionBankBatchPackageFailure.invalidAsset("导出图片超过单张 16 MiB 或整包 48 MiB 上限。")
                }
                let digest = sha256(data)
                let ext = URL(fileURLWithPath: asset.fileName).pathExtension.lowercased()
                guard isValidImage(data, mimeType: asset.mimeType, fileExtension: ext),
                      ["png", "jpg", "jpeg"].contains(ext) else {
                    throw QuestionBankBatchPackageFailure.invalidAsset("\(asset.fileName) 不是有效 PNG/JPEG。")
                }
                let entryPath = "assets/\(digest).\(ext)"
                if let prior = binaryFiles[entryPath], prior != data {
                    throw QuestionBankBatchPackageFailure.invalidAsset("SHA-256 冲突，无法安全打包。")
                }
                binaryFiles[entryPath] = data
                assetEntries.append(QuestionBankBatchPackageAssetV1(
                    id: asset.id,
                    paperID: paperID,
                    ownerType: asset.ownerType,
                    ownerID: asset.ownerID,
                    role: asset.role,
                    logicalPath: asset.path,
                    entryPath: entryPath,
                    mimeType: asset.mimeType,
                    fileName: asset.fileName,
                    originalPage: asset.originalPage,
                    sha256: digest,
                    byteCount: Int64(data.count)
                ))
            }

            var json: [String: Any] = [
                "format": QuestionBankImportJSONV1.formatIdentifier,
                "schemaVersion": QuestionBankImportJSONV1.currentSchemaVersion,
                "paper": paperObject,
                "modules": modules,
                "materials": materials,
                "questions": questions,
                "assets": []
            ]
            if let sourcePapers { json["sourcePapers"] = sourcePapers }
            let paperData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            paperJSONByteCount += Int64(paperData.count)
            guard Int64(paperData.count) <= 30 * 1024 * 1024,
                  paperJSONByteCount + decodedImageByteCount <= 250 * 1024 * 1024 else {
                throw QuestionBankBatchPackageFailure.invalidPaper("批量 ZIP 内容超过单文件 30 MiB 或展开总量 250 MiB 上限。")
            }
            let path = "papers/\(String(format: "%04d", index + 1)).json"
            guard let destination = QuestionBankAssetStore.url(for: path, under: stageRoot) else {
                throw QuestionBankBatchPackageFailure.unsafePath(path)
            }
            try paperData.write(to: destination, options: .atomic)
            paperEntries.append(QuestionBankBatchPackagePaperV1(
                paperID: paperID, path: path, sha256: sha256(paperData)
            ))
        }

        for (path, data) in binaryFiles {
            guard let destination = QuestionBankAssetStore.url(for: path, under: stageRoot) else {
                throw QuestionBankBatchPackageFailure.unsafePath(path)
            }
            try data.write(to: destination, options: .atomic)
        }
        let exportedPaperIDs = Set(paperEntries.map(\.paperID))
        let groupIDsUsed = Set(exportedPlacements
            .filter { exportedPaperIDs.contains($0.paperID) }
            .compactMap(\.groupID))
        let groupEntries = organization.groups.filter { groupIDsUsed.contains($0.id) }.enumerated().map { index, group in
            QuestionBankBatchPackageGroupV1(id: group.id, name: group.name, order: index)
        }
        var nextOrderByGroup: [String: Int] = [:]
        var nextUngroupedPaperOrder = 0
        let placementByID = Dictionary(exportedPlacements.map { ($0.paperID, $0) }, uniquingKeysWith: { first, _ in first })
        let paperOrderEntries = orderedPaperIDs.filter(exportedPaperIDs.contains).compactMap { paperID -> QuestionBankBatchPackagePaperOrderV1? in
            guard let placement = placementByID[paperID] else { return nil }
            let order: Int
            if let groupID = placement.groupID {
                order = nextOrderByGroup[groupID, default: 0]
                nextOrderByGroup[groupID] = order + 1
            } else {
                order = nextUngroupedPaperOrder
                nextUngroupedPaperOrder += 1
            }
            return QuestionBankBatchPackagePaperOrderV1(
                paperID: paperID,
                groupID: placement.groupID,
                order: order
            )
        }
        let packageOrganization = QuestionBankBatchPackageOrganizationV1(
            groups: groupEntries,
            paperOrder: paperOrderEntries
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let manifest = QuestionBankBatchPackageManifestV1(
            createdAt: formatter.string(from: Date()),
            papers: paperEntries,
            assets: assetEntries,
            organization: packageOrganization
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        guard Int64(manifestData.count) <= 30 * 1024 * 1024,
              paperEntries.count + binaryFiles.count + 1 <= 4_000,
              paperJSONByteCount + decodedImageByteCount + Int64(manifestData.count) <= 250 * 1024 * 1024 else {
            throw QuestionBankBatchPackageFailure.invalidArchive("批量 ZIP 超过清单、文件数或展开总量上限。")
        }
        let manifestURL = stageRoot.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaogong-question-bank-batch-\(UUID().uuidString).zip")
        do {
            guard let archive = Archive(url: archiveURL, accessMode: .create) else {
                throw QuestionBankBatchPackageFailure.invalidArchive("无法创建批量 ZIP 文件。")
            }
            let files = try allFiles(under: stageRoot)
            for file in files {
                let relativePath = String(file.path.dropFirst(stageRoot.path.count + 1))
                    .replacingOccurrences(of: "\\", with: "/")
                let isImage = relativePath.hasPrefix("assets/")
                try archive.addEntry(
                    with: relativePath,
                    relativeTo: stageRoot,
                    compressionMethod: isImage ? .none : .deflate
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: archiveURL)
            throw error
        }
        return archiveURL
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func jsonObjects(
        _ rows: [QuestionBankStoredRow],
        label: String
    ) throws -> [(QuestionBankStoredRow, [String: Any])] {
        try rows.map { row in
            guard let object = jsonObject(row.payload) else {
                throw QuestionBankBatchPackageFailure.invalidPaper("\(label) \(row.stableID) 的 payload 无法解析。")
            }
            return (row, object)
        }
    }

    private static func allFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw QuestionBankBatchPackageFailure.unsafePath(url.lastPathComponent)
            }
            if values.isDirectory != true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func isValidImage(_ data: Data, mimeType: String, fileExtension: String) -> Bool {
        let bytes = [UInt8](data.prefix(8))
        if mimeType.lowercased() == "image/png" && fileExtension == "png" {
            return bytes.count == 8 && bytes == [137, 80, 78, 71, 13, 10, 26, 10]
        }
        if ["image/jpeg", "image/jpg"].contains(mimeType.lowercased())
            && ["jpg", "jpeg"].contains(fileExtension) {
            return data.count >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff
        }
        return false
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
