import Foundation
import SwiftData
import SwiftUI

enum QuestionBankReadingMode: String, CaseIterable, Identifiable {
    case reading
    case practice

    var id: String { rawValue }
    var title: String { self == .reading ? "看题" : "刷题" }

    func revealsAnswer(afterSelecting optionID: String?) -> Bool {
        self == .reading || optionID != nil
    }
}

enum QuestionBankPresentationMode: String, CaseIterable, Identifiable, Equatable {
    case continuous
    case single

    var id: String { rawValue }
    var title: String { self == .continuous ? "连续阅读" : "单题模式" }
    var shortTitle: String { self == .continuous ? "连续" : "单题" }
}

struct QuestionBankReaderPosition: Equatable {
    var presentationMode: QuestionBankPresentationMode
    var currentQuestionID: String?
    var splitMaterialID: String?
}

enum QuestionBankReaderTransition {
    static func switchingPresentation(
        to mode: QuestionBankPresentationMode,
        from position: QuestionBankReaderPosition
    ) -> QuestionBankReaderPosition {
        var result = position
        result.presentationMode = mode
        return result
    }

    static func selectingOverviewQuestion(
        _ questionID: String,
        materialID: String?,
        availableMaterialIDs: Set<String>,
        from position: QuestionBankReaderPosition
    ) -> QuestionBankReaderPosition {
        var result = position
        result.presentationMode = .single
        result.currentQuestionID = questionID
        if position.splitMaterialID != nil {
            result.splitMaterialID = materialID.flatMap { availableMaterialIDs.contains($0) ? $0 : nil }
        }
        return result
    }

    static func movingToQuestion(
        _ questionID: String,
        materialID: String?,
        availableMaterialIDs: Set<String>,
        from position: QuestionBankReaderPosition
    ) -> QuestionBankReaderPosition {
        var result = position
        result.currentQuestionID = questionID
        if position.splitMaterialID != nil {
            result.splitMaterialID = materialID.flatMap { availableMaterialIDs.contains($0) ? $0 : nil }
        }
        return result
    }

    static func adjacentQuestionID(
        currentID: String?,
        orderedIDs: [String],
        direction: Int
    ) -> String? {
        guard direction == -1 || direction == 1,
              let currentID,
              let index = orderedIDs.firstIndex(of: currentID) else { return nil }
        let targetIndex = index + direction
        guard orderedIDs.indices.contains(targetIndex) else { return nil }
        return orderedIDs[targetIndex]
    }

    static func displayedQuestionIDs(
        for mode: QuestionBankPresentationMode,
        currentID: String?,
        orderedIDs: [String]
    ) -> [String] {
        guard mode == .single else { return orderedIDs }
        if let currentID, orderedIDs.contains(currentID) { return [currentID] }
        return orderedIDs.first.map { [$0] } ?? []
    }

    static func ordinal(of questionID: String?, in orderedIDs: [String]) -> Int? {
        guard let questionID, let index = orderedIDs.firstIndex(of: questionID) else { return nil }
        return index + 1
    }
}

enum QuestionBankSelectedOptionsStorage {
    static func decode(_ value: String) -> [String: String] {
        guard let data = value.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func encode(_ selections: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(selections),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
}

struct QuestionBankDoodleToolbarTarget: Equatable {
    let questionID: String
    let questionNumber: Int
    let materialID: String?

    static func resolve(
        visibleQuestionID: String?,
        questions: [QuestionBankQuestion],
        materialIDs: Set<String>
    ) -> QuestionBankDoodleToolbarTarget? {
        guard let visibleQuestionID,
              let question = questions.first(where: { $0.id == visibleQuestionID }) else { return nil }
        let materialID = !question.materialID.isEmpty && materialIDs.contains(question.materialID)
            ? question.materialID : nil
        return QuestionBankDoodleToolbarTarget(
            questionID: question.id, questionNumber: question.number, materialID: materialID
        )
    }
}

enum QuestionBankSplitOrientation: Equatable {
    case landscape
    case portrait
}

enum QuestionBankSplitLayout {
    static let minimumQuestionPaneWidth: CGFloat = 420
    static let landscapeSplitMinimumWidth: CGFloat = 960

    static func orientation(width: CGFloat, height: CGFloat) -> QuestionBankSplitOrientation {
        width >= landscapeSplitMinimumWidth && width > height ? .landscape : .portrait
    }

    static func materialWidth(totalWidth: CGFloat) -> CGFloat {
        min(totalWidth * 0.555, totalWidth - minimumQuestionPaneWidth - 1)
    }

    static func materialHeight(totalHeight: CGFloat) -> CGFloat {
        min(max(totalHeight * 0.55, 300), max(totalHeight - 260, 0))
    }
}

enum QuestionBankOptionDisplay {
    static func text(for option: QuestionBankOption) -> String? {
        let text = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != option.id else { return nil }
        return text
    }
}

enum QuestionBankDoodleScope: Equatable {
    case question(String)
    case material(String)

    fileprivate var kind: String {
        switch self {
        case .question: "question"
        case .material: "material"
        }
    }

    fileprivate var stableID: String {
        switch self {
        case .question(let id), .material(let id): id
        }
    }
}

enum QuestionBankDoodleRepository {
    static let collection = "keyvalue"
    static let recordIDPrefix = "question_bank_doodle_v1_"

    static func recordID(paperID: String, scope: QuestionBankDoodleScope) -> String {
        let identity = "\(paperID)\u{0}\(scope.kind)\u{0}\(scope.stableID)"
        let encoded = Data(identity.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return recordIDPrefix + encoded
    }

    static func isDoodleRecordID(_ recordID: String?) -> Bool {
        recordID?.hasPrefix(recordIDPrefix) == true
    }

    static func drawingData(recordID: String, context: ModelContext) throws -> String {
        let descriptor = descriptor(for: recordID)
        guard let record = try context.fetch(descriptor).first else { return "" }
        guard let object = record.jsonObject,
              object["format"] as? String == recordIDPrefix,
              let data = object["pencilKitData"] as? String else {
            throw QuestionBankDoodleError.invalidSavedDrawing
        }
        return data
    }

    @MainActor
    @discardableResult
    static func save(
        recordID: String,
        drawingData: String,
        context: ModelContext
    ) -> String? {
        do {
            let descriptor = descriptor(for: recordID)
            let existing = try context.fetch(descriptor).first
            if drawingData.isEmpty {
                guard let existing else { return nil }
                context.delete(existing)
                try context.save()
                return nil
            }
            if let existing,
               existing.jsonObject?["pencilKitData"] as? String == drawingData {
                return nil
            }

            let now = Date()
            let object: [String: Any] = [
                "id": recordID,
                "key": recordID,
                "format": recordIDPrefix,
                "pencilKitData": drawingData,
                "updatedAt": ISO8601DateFormatter().string(from: now)
            ]
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = now
            } else {
                context.insert(StoredRecord(
                    collection: collection,
                    recordID: recordID,
                    payload: payload,
                    subject: "真题涂鸦",
                    createdAt: now,
                    updatedAt: now
                ))
            }
            try context.save()
            return nil
        } catch {
            return "涂鸦未保存：\(error.localizedDescription)"
        }
    }

    private static func descriptor(for recordID: String) -> FetchDescriptor<StoredRecord> {
        let collectionName = Self.collection
        return FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == collectionName && $0.recordID == recordID }
        )
    }
}

enum QuestionBankDoodleError: LocalizedError {
    case invalidSavedDrawing

    var errorDescription: String? {
        "已保存的真题涂鸦记录格式无效，原记录未修改。"
    }
}

struct QuestionBankDoodleAutosaveObserver: View {
    @ObservedObject private var session: LibraryDoodleSession
    @ObservedObject private var canvas: LibraryDoodleCanvasState
    private let context: ModelContext

    init(session: LibraryDoodleSession, context: ModelContext) {
        _session = ObservedObject(wrappedValue: session)
        _canvas = ObservedObject(wrappedValue: session.canvas)
        self.context = context
    }

    var body: some View {
        Color.clear
            .onChange(of: canvas.drawingData) { _, drawingData in
                guard session.isPresented,
                      let recordID = session.targetRecordID,
                      QuestionBankDoodleRepository.isDoodleRecordID(recordID) else { return }
                session.saveError = QuestionBankDoodleRepository.save(
                    recordID: recordID,
                    drawingData: drawingData,
                    context: context
                )
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
