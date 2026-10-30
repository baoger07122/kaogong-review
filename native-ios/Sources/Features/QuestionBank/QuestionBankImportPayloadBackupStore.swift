import CryptoKit
import Foundation
import SwiftData

struct QuestionBankImportPayloadBackupReference: Equatable, Sendable {
    var backupID: String
    var relativePath: String
    var manifestSHA256: String
}

private struct QuestionBankImportPayloadBackupManifest: Codable {
    struct Record: Codable {
        var compoundID: String
        var paperID: String
        var kind: String
        var stableID: String
        var payloadBase64: String
        var payloadSHA256: String
        var assetRelativePath: String?
    }

    struct Asset: Codable {
        var compoundID: String
        var originalRelativePath: String
        var backupRelativePath: String
        var sha256: String
        var byteCount: Int64
    }

    var format = "kaogong-question-bank-replacement-backup"
    var schemaVersion = 1
    var jobID: String
    var backupID: String
    var createdAt: String
    var sourcePackageSHA256: String
    var records: [Record]
    var assets: [Asset]
}

enum QuestionBankImportPayloadBackupStore {
    static func persist(
        _ rows: [QuestionBankRecord],
        sourceFileSHA256: String,
        jobID: String,
        assetRoot: URL,
        in customDirectory: URL? = nil
    ) throws -> QuestionBankImportPayloadBackupReference {
        guard !rows.isEmpty else {
            throw QuestionBankBatchPackageFailure.invalidTarget("没有可备份的现有题库 payload；本次更新已取消。")
        }
        let backupRoot = try root(customDirectory)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupID = UUID().uuidString.lowercased()
        let backupDirectory = backupRoot
            .appendingPathComponent(safeComponent(jobID), isDirectory: true)
            .appendingPathComponent(backupID, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: backupDirectory.path) else {
            throw QuestionBankBatchPackageFailure.invalidTarget("备份 ID 已存在，已取消覆盖。")
        }
        let backupAssetDirectory = backupDirectory.appendingPathComponent("assets", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: backupAssetDirectory, withIntermediateDirectories: true)
            var assets: [QuestionBankImportPayloadBackupManifest.Asset] = []
            let rowsWithAssets = rows.sorted { $0.compoundID < $1.compoundID }
                .filter { $0.assetRelativePath != nil }
            for (index, row) in rowsWithAssets.enumerated() {
                guard let originalPath = row.assetRelativePath,
                      let source = QuestionBankAssetStore.url(for: originalPath, under: assetRoot),
                      FileManager.default.fileExists(atPath: source.path) else {
                    throw QuestionBankBatchPackageFailure.invalidTarget(
                        "待替换题库图片缺失，已取消覆盖：\(row.compoundID)"
                    )
                }
                let backupRelativePath = "assets/asset-\(index)"
                let destination = backupDirectory.appendingPathComponent(backupRelativePath)
                try FileManager.default.copyItem(at: source, to: destination)
                let sourceHash = try sha256(fileAt: source)
                let copiedHash = try sha256(fileAt: destination)
                let sourceSize = try fileSize(source)
                let copiedSize = try fileSize(destination)
                guard sourceHash == copiedHash, sourceSize == copiedSize else {
                    throw QuestionBankBatchPackageFailure.invalidTarget("题库图片备份校验失败，已取消覆盖。")
                }
                assets.append(.init(
                    compoundID: row.compoundID,
                    originalRelativePath: originalPath,
                    backupRelativePath: backupRelativePath,
                    sha256: sourceHash,
                    byteCount: sourceSize
                ))
            }
            let manifest = QuestionBankImportPayloadBackupManifest(
                jobID: jobID,
                backupID: backupID,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                sourcePackageSHA256: sourceFileSHA256,
                records: rows.sorted { $0.compoundID < $1.compoundID }.map {
                    .init(
                        compoundID: $0.compoundID,
                        paperID: $0.paperID,
                        kind: $0.kind,
                        stableID: $0.stableID,
                        payloadBase64: $0.payload.base64EncodedString(),
                        payloadSHA256: sha256(data: $0.payload),
                        assetRelativePath: $0.assetRelativePath
                    )
                },
                assets: assets
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let manifestURL = backupDirectory.appendingPathComponent("manifest.json")
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)
            let relativePath = "\(safeComponent(jobID))/\(backupID)/manifest.json"
            let reference = QuestionBankImportPayloadBackupReference(
                backupID: backupID,
                relativePath: relativePath,
                manifestSHA256: sha256(data: manifestData)
            )
            try verify(reference, jobID: jobID, in: backupRoot)
            return reference
        } catch {
            try? FileManager.default.removeItem(at: backupDirectory)
            throw error
        }
    }

    static func verify(
        _ reference: QuestionBankImportPayloadBackupReference,
        jobID: String,
        in customDirectory: URL? = nil
    ) throws {
        let backupRoot = try root(customDirectory)
        guard let manifestURL = QuestionBankAssetStore.url(for: reference.relativePath, under: backupRoot) else {
            throw QuestionBankBatchPackageFailure.invalidTarget("题库备份路径无效。")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard sha256(data: manifestData) == reference.manifestSHA256 else {
            throw QuestionBankBatchPackageFailure.invalidTarget("题库备份清单校验失败，已取消覆盖。")
        }
        let manifest = try JSONDecoder().decode(QuestionBankImportPayloadBackupManifest.self, from: manifestData)
        guard manifest.format == "kaogong-question-bank-replacement-backup",
              manifest.schemaVersion == 1,
              manifest.jobID == jobID,
              manifest.backupID == reference.backupID,
              !manifest.records.isEmpty,
              Set(manifest.records.map(\.compoundID)).count == manifest.records.count,
              manifest.records.allSatisfy({
                  guard let data = Data(base64Encoded: $0.payloadBase64) else { return false }
                  return sha256(data: data) == $0.payloadSHA256
              }) else {
            throw QuestionBankBatchPackageFailure.invalidTarget("题库备份内容不完整，已取消覆盖。")
        }
        let referencedAssetKeys = Set(manifest.records.compactMap { record in
            record.assetRelativePath.map { "\(record.compoundID)|\($0)" }
        })
        let backedAssetKeys = Set(manifest.assets.map { "\($0.compoundID)|\($0.originalRelativePath)" })
        guard referencedAssetKeys == backedAssetKeys,
              backedAssetKeys.count == manifest.assets.count,
              Set(manifest.assets.map(\.backupRelativePath)).count == manifest.assets.count else {
            throw QuestionBankBatchPackageFailure.invalidTarget("题库备份的资源引用不完整，已取消覆盖。")
        }
        let backupDirectory = manifestURL.deletingLastPathComponent()
        for asset in manifest.assets {
            guard let assetURL = QuestionBankAssetStore.url(for: asset.backupRelativePath, under: backupDirectory) else {
                throw QuestionBankBatchPackageFailure.invalidTarget("题库图片备份路径无效，已取消覆盖。")
            }
            let assetSize = try fileSize(assetURL)
            let assetHash = try sha256(fileAt: assetURL)
            guard assetSize == asset.byteCount, assetHash == asset.sha256 else {
                throw QuestionBankBatchPackageFailure.invalidTarget("题库图片备份校验失败，已取消覆盖。")
            }
        }
    }

    private static func root(_ customDirectory: URL?) throws -> URL {
        if let customDirectory { return customDirectory }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appendingPathComponent("QuestionBankImportBackups", isDirectory: true)
    }

    private static func safeComponent(_ value: String) -> String {
        let component = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let result = component.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return result.isEmpty ? "unknown" : result
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? -1
    }

    private static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
