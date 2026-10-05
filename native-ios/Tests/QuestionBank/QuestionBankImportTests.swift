import Foundation
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
