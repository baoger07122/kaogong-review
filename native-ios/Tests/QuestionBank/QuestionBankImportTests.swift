import Foundation
import CryptoKit
import SwiftData
import XCTest
@testable import KaogongReviewNative

@MainActor
final class QuestionBankImportTests: XCTestCase {
    func testValidationPackageImportsAtomicallyAndPersistsAcrossContainerReopen() throws {
        try assertInvalidPackagesAreRejectedWithoutLeavingTemporaryFiles()
        let packageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/QuestionBank/2019-national-exam-city-7q.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path), "Validation ZIP fixture should be checked in alongside the app sources.")

        let plan = try QuestionBankPackageImporter.prepare(from: packageURL)
        defer { QuestionBankPackageImporter.cleanup(plan) }
        XCTAssertTrue(plan.errors.isEmpty, plan.errors.joined(separator: "\n"))
        XCTAssertTrue(plan.canImport)
        XCTAssertEqual(plan.modules.count, 5)
        XCTAssertEqual(plan.questions.count, 7)
        XCTAssertEqual(plan.assets.count, 6)

        let q71 = try XCTUnwrap(plan.questions.first { $0.number == 71 })
        XCTAssertEqual(q71.stemImageAssetID, "q-2019-071-full-figure")
        XCTAssertEqual(q71.options.map(\.text), ["A", "B", "C", "D"])
        XCTAssertTrue(q71.options.allSatisfy { $0.imageAssetID.isEmpty })
        let q71Figure = try XCTUnwrap(plan.assets.first { $0.id == q71.stemImageAssetID })
        XCTAssertEqual(q71Figure.role, "题干整图")
        let q71FigureURL = try XCTUnwrap(plan.stagingDirectory).appendingPathComponent(q71Figure.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: q71FigureURL.path))

        let dataQuestions = plan.questions.filter { (111...115).contains($0.number) }
        XCTAssertEqual(dataQuestions.count, 5)
        XCTAssertEqual(Set(dataQuestions.map(\.materialID)), ["m-2019-drugs-111-115"])
        XCTAssertTrue(dataQuestions.allSatisfy { !$0.stem.isEmpty })
        let q114 = try XCTUnwrap(dataQuestions.first { $0.number == 114 })
        XCTAssertEqual(q114.options.map(\.text), ["A", "B", "C", "D"])
        XCTAssertEqual(q114.options.map(\.imageAssetID).filter { !$0.isEmpty }.count, 4)
        XCTAssertEqual(plan.assets.filter { $0.ownerID == q114.id }.count, 4)
        XCTAssertFalse(plan.materials.contains { $0.text.contains("五、资料分析") })
        XCTAssertFalse(q114.stem.contains("五、资料分析"))

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let storeURL = temporaryRoot.appendingPathComponent("QuestionBank.store")
        let assetRoot = temporaryRoot.appendingPathComponent("assets", isDirectory: true)

        do {
            // Create the database with the exact old production schema first.
            let legacyContainer = try makeLegacyContainer(storeURL: storeURL)
            let legacyPayload = try JSONSerialization.data(withJSONObject: ["id": "existing-exam", "name": "旧套卷成绩"])
            legacyContainer.mainContext.insert(
                StoredRecord(collection: "exams", recordID: "existing-exam", payload: legacyPayload)
            )
            try legacyContainer.mainContext.save()
        }

        do {
            // Opening the expanded schema must migrate additively and retain the old exam row.
            let container = try makeContainer(storeURL: storeURL)
            let context = container.mainContext
            XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).first?.recordID, "existing-exam")

            try QuestionBankRepository.commit(plan, decision: .add, records: [], context: context, assetRoot: assetRoot)
            var imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).first?.recordID, "existing-exam")

            let duplicate = try XCTUnwrap(QuestionBankRepository.duplicatePaper(for: XCTUnwrap(plan.paper), in: imported))
            XCTAssertEqual(duplicate.stableID, plan.paper?.id)
            XCTAssertThrowsError(try QuestionBankRepository.commit(
                plan, decision: .add, records: imported, context: context, assetRoot: assetRoot
            ))
            XCTAssertEqual(try context.fetch(FetchDescriptor<QuestionBankRecord>())
                .filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)

            var invalidPlan = plan
            invalidPlan.errors.append("测试缺图：必须拒绝提交")
            XCTAssertThrowsError(try QuestionBankRepository.commit(
                invalidPlan, decision: .replaceExisting, records: imported, context: context, assetRoot: assetRoot
            ))
            imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)

            try QuestionBankRepository.commit(plan, decision: .replaceExisting, records: imported, context: context, assetRoot: assetRoot)
            imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
            let q114Assets = imported.filter { $0.kind == QuestionBankRepository.assetKind && $0.stableID.hasPrefix("q-2019-114-option-") }
            XCTAssertEqual(q114Assets.count, 4)
            for asset in q114Assets {
                let localURL = try XCTUnwrap(asset.assetRelativePath.map { assetRoot.appendingPathComponent($0) })
                XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path), "Missing imported image: \(asset.title ?? asset.stableID)")
            }
            try context.save()
        }

        // A fresh container models closing and reopening the app against the same store.
        let reopened = try makeContainer(storeURL: storeURL)
        let persisted = try reopened.mainContext.fetch(FetchDescriptor<QuestionBankRecord>())
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.moduleKind }.count, 5)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<StoredRecord>()).first?.recordID, "existing-exam")
    }

    func testJSONV1PreservesVerifiedQuestionsAndPersistsWithoutBase64Payloads() throws {
        let zipURL = validationPackageURL()
        let sourcePlan = try QuestionBankPackageImporter.prepare(from: zipURL)
        defer { QuestionBankPackageImporter.cleanup(sourcePlan) }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankJSONImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let jsonURL = try writeJSON(makeJSONDocument(from: sourcePlan), to: temporaryRoot, name: "validation.json")
        let plan = try QuestionBankPackageImporter.prepare(from: jsonURL, source: .pickerCopy, onProgress: { _ in })
        defer { QuestionBankPackageImporter.cleanup(plan) }

        XCTAssertTrue(plan.errors.isEmpty, plan.errors.joined(separator: "\n"))
        XCTAssertTrue(plan.canImport)
        XCTAssertEqual(plan.paper?.id, sourcePlan.paper?.id)
        XCTAssertEqual(plan.modules.map(\.id), sourcePlan.modules.map(\.id))
        XCTAssertEqual(plan.materials.map(\.id), sourcePlan.materials.map(\.id))
        XCTAssertEqual(plan.questions.map(\.id), sourcePlan.questions.map(\.id))
        XCTAssertEqual(plan.assets.map(\.id), sourcePlan.assets.map(\.id))
        for asset in plan.assets {
            let importedBytes = try Data(contentsOf: XCTUnwrap(plan.stagingDirectory).appendingPathComponent(asset.path))
            let originalBytes = try Data(contentsOf: XCTUnwrap(sourcePlan.stagingDirectory).appendingPathComponent(asset.path))
            XCTAssertEqual(importedBytes, originalBytes, "JSON import must preserve source image bytes for \(asset.fileName).")
        }

        let filesOpenInPlan = try QuestionBankPackageImporter.prepare(
            from: jsonURL, source: .filesOpenIn, onProgress: { _ in }
        )
        defer { QuestionBankPackageImporter.cleanup(filesOpenInPlan) }
        XCTAssertTrue(filesOpenInPlan.errors.isEmpty, filesOpenInPlan.errors.joined(separator: "\n"))
        XCTAssertEqual(filesOpenInPlan.questions.map(\.id), plan.questions.map(\.id))

        let q71 = try XCTUnwrap(plan.questions.first { $0.number == 71 })
        XCTAssertEqual(q71.stemImageAssetID, "q-2019-071-full-figure")
        let q71Asset = try XCTUnwrap(plan.assets.first { $0.id == q71.stemImageAssetID })
        let jsonStagingDirectory = try XCTUnwrap(plan.stagingDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonStagingDirectory.appendingPathComponent(q71Asset.path).path))

        let sharedMaterialQuestions = plan.questions.filter { (111...115).contains($0.number) }
        XCTAssertEqual(Set(sharedMaterialQuestions.map(\.materialID)), ["m-2019-drugs-111-115"])
        let q114 = try XCTUnwrap(plan.questions.first { $0.number == 114 })
        XCTAssertEqual(q114.options.map(\.imageAssetID).filter { !$0.isEmpty }.count, 4)
        XCTAssertEqual(plan.assets.filter { $0.ownerID == q114.id }.count, 4)

        let storeURL = temporaryRoot.appendingPathComponent("QuestionBank.store")
        let assetRoot = temporaryRoot.appendingPathComponent("assets", isDirectory: true)
        do {
            let container = try makeContainer(storeURL: storeURL)
            let context = container.mainContext
            try QuestionBankRepository.commit(plan, decision: .add, records: [], context: context, assetRoot: assetRoot)
            var imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            let imageRecord = try XCTUnwrap(imported.first { $0.kind == QuestionBankRepository.assetKind })
            let imagePayload = String(decoding: imageRecord.payload, as: UTF8.self)
            XCTAssertFalse(imagePayload.contains("dataBase64"))
            XCTAssertFalse(imagePayload.contains("AABAA"), "Asset records must store metadata, never encoded image bytes.")

            XCTAssertThrowsError(try QuestionBankRepository.commit(
                plan, decision: .add, records: imported, context: context, assetRoot: assetRoot
            ))
            imported = try context.fetch(FetchDescriptor<QuestionBankRecord>())
            XCTAssertEqual(imported.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
            try context.save()
        }

        let reopened = try makeContainer(storeURL: storeURL)
        let persisted = try reopened.mainContext.fetch(FetchDescriptor<QuestionBankRecord>())
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.paperKind }.count, 1)
        XCTAssertEqual(persisted.filter { $0.kind == QuestionBankRepository.questionKind }.count, 7)
        let persistedQ114Assets = persisted.filter {
            $0.kind == QuestionBankRepository.assetKind && $0.stableID.hasPrefix("q-2019-114-option-")
        }
        XCTAssertEqual(persistedQ114Assets.count, 4)
        for asset in persistedQ114Assets {
            let path = try XCTUnwrap(asset.assetRelativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: assetRoot.appendingPathComponent(path).path))
        }
    }

    func testJSONV1RejectsWrongFormatSchemaAndInvalidImageData() throws {
        let sourcePlan = try QuestionBankPackageImporter.prepare(from: validationPackageURL())
        defer { QuestionBankPackageImporter.cleanup(sourcePlan) }
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankJSONRejectedTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let original = try makeJSONDocument(from: sourcePlan)
        let q71AssetIndex = try XCTUnwrap(original.assets.firstIndex { $0.id == "q-2019-071-full-figure" })
        let q71FileName = original.assets[q71AssetIndex].fileName

        var unsupportedSchema = original
        unsupportedSchema.schemaVersion = 2
        let schemaURL = try writeJSON(unsupportedSchema, to: temporaryRoot, name: "schema-v2.json")
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: schemaURL)) {
            XCTAssertTrue($0.localizedDescription.contains("schemaVersion=2"), $0.localizedDescription)
        }

        let backupURL = temporaryRoot.appendingPathComponent("backup.json")
        try JSONSerialization.data(withJSONObject: ["dataVersion": 1, "records": []]).write(to: backupURL)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: backupURL)) {
            XCTAssertTrue($0.localizedDescription.contains("备份 JSON"), $0.localizedDescription)
        }

        var invalidBase64 = original
        invalidBase64.assets[q71AssetIndex].dataBase64 = "%%%"
        try assertJSONPlanContainsError(invalidBase64, directory: temporaryRoot, name: "bad-base64.json",
                                        matching: "不是有效的纯 Base64", context: q71FileName)

        var invalidHash = original
        invalidHash.assets[q71AssetIndex].sha256 = String(repeating: "0", count: 64)
        try assertJSONPlanContainsError(invalidHash, directory: temporaryRoot, name: "bad-hash.json",
                                        matching: "sha256 与图片原始字节不匹配", context: q71FileName)

        var oversizedImage = original
        let maxEncodedLength = ((QuestionBankPackageImporter.maxJSONImageBytes + 2) / 3) * 4
        oversizedImage.assets[q71AssetIndex].dataBase64 = String(repeating: "A", count: maxEncodedLength + 4)
        try assertJSONPlanContainsError(oversizedImage, directory: temporaryRoot, name: "oversized-image.json",
                                        matching: "超过 16 MiB 单图上限", context: "第71题")

        var missingID = original
        missingID.assets[q71AssetIndex].id = ""
        try assertJSONPlanContainsError(missingID, directory: temporaryRoot, name: "missing-id.json",
                                        matching: "图片资源ID不能为空", context: "第71题")

        let missingIDFieldURL = try writeJSONRemovingField(original, directory: temporaryRoot,
            name: "missing-id-field.json", collection: "assets", index: q71AssetIndex, field: "id")
        try assertJSONFileContainsError(missingIDFieldURL, matching: "图片资源ID不能为空", context: q71FileName)

        let q71QuestionIndex = try XCTUnwrap(original.questions.firstIndex { $0.number == 71 })
        let missingQuestionIDFieldURL = try writeJSONRemovingField(original, directory: temporaryRoot,
            name: "missing-question-id-field.json", collection: "questions", index: q71QuestionIndex, field: "id")
        try assertJSONFileContainsError(missingQuestionIDFieldURL, matching: "题目ID不能为空", context: "第71题")

        var brokenAssociation = original
        brokenAssociation.assets[q71AssetIndex].ownerID = "question-does-not-exist"
        try assertJSONPlanContainsError(brokenAssociation, directory: temporaryRoot, name: "broken-link.json",
                                        matching: "所属记录或用途关联不匹配", context: "第71题")
    }

    private func assertInvalidPackagesAreRejectedWithoutLeavingTemporaryFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankRejectedPackageTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let stagingRoot = FileManager.default.temporaryDirectory
        let previousStaging = Set(try FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("QuestionBankImport-") })

        let spreadsheetURL = temporaryRoot.appendingPathComponent("not-a-package.xlsx")
        try Data("not a ZIP".utf8).write(to: spreadsheetURL)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: spreadsheetURL)) {
            XCTAssertTrue($0.localizedDescription.contains(".zip"), $0.localizedDescription)
        }

        let folderURL = temporaryRoot.appendingPathComponent("folder.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: folderURL)) {
            XCTAssertTrue($0.localizedDescription.contains("文件夹"), $0.localizedDescription)
        }

        let brokenArchiveURL = temporaryRoot.appendingPathComponent("broken.zip")
        try Data("not a ZIP".utf8).write(to: brokenArchiveURL)
        XCTAssertThrowsError(try QuestionBankPackageImporter.prepare(from: brokenArchiveURL)) {
            XCTAssertTrue($0.localizedDescription.contains("有效 ZIP"), $0.localizedDescription)
        }
        let remainingStaging = Set(try FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("QuestionBankImport-") })
        XCTAssertEqual(remainingStaging, previousStaging, "Rejected packages must not leave temporary staging directories.")
    }

    private func validationPackageURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/QuestionBank/2019-national-exam-city-7q.zip")
    }

    private func makeJSONDocument(from plan: QuestionBankImportPlan) throws -> QuestionBankImportJSONV1 {
        let staging = try XCTUnwrap(plan.stagingDirectory)
        let assets = try plan.assets.map { asset -> QuestionBankJSONAssetV1 in
            let data = try Data(contentsOf: staging.appendingPathComponent(asset.path))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return QuestionBankJSONAssetV1(id: asset.id, paperID: asset.paperID,
                ownerType: asset.ownerType, ownerID: asset.ownerID, role: asset.role,
                path: asset.path, mimeType: asset.mimeType, fileName: asset.fileName,
                originalPage: asset.originalPage, dataBase64: data.base64EncodedString(), sha256: digest)
        }
        return QuestionBankImportJSONV1(paper: try XCTUnwrap(plan.paper), modules: plan.modules,
            materials: plan.materials, questions: plan.questions, assets: assets)
    }

    private func writeJSON(_ document: QuestionBankImportJSONV1, to directory: URL, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        return url
    }

    private func assertJSONPlanContainsError(_ document: QuestionBankImportJSONV1, directory: URL,
        name: String, matching phrase: String, context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try writeJSON(document, to: directory, name: name)
        try assertJSONFileContainsError(url, matching: phrase, context: context, file: file, line: line)
    }

    private func writeJSONRemovingField(_ document: QuestionBankImportJSONV1, directory: URL,
        name: String, collection: String, index: Int, field: String) throws -> URL {
        let encoded = try JSONEncoder().encode(document)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var rows = try XCTUnwrap(root[collection] as? [[String: Any]])
        var row = try XCTUnwrap(index < rows.count ? rows[index] : nil)
        row.removeValue(forKey: field)
        rows[index] = row
        root[collection] = rows
        let url = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: root).write(to: url, options: .atomic)
        return url
    }

    private func assertJSONFileContainsError(_ url: URL, matching phrase: String, context: String,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let plan = try QuestionBankPackageImporter.prepare(from: url)
        defer { QuestionBankPackageImporter.cleanup(plan) }
        XCTAssertFalse(plan.canImport)
        XCTAssertTrue(plan.errors.contains { $0.contains(phrase) && $0.contains(context) },
            "Expected error containing ‘\(phrase)’ and ‘\(context)’; got: \(plan.errors)", file: file, line: line)
    }

    private func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema([StoredRecord.self, QuestionBankRecord.self])
        let configuration = ModelConfiguration(
            "QuestionBankImportTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeLegacyContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema([StoredRecord.self])
        let configuration = ModelConfiguration(
            "QuestionBankImportTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
