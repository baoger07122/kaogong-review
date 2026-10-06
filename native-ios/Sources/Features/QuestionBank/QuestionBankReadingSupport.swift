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
