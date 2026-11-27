import Foundation
import SwiftData

private struct LibraryDoodlePreparedWrite: Sendable {
    let basePayload: Data
    let payload: Data
    let indexPayload: Data
    let decoded: LibraryDecodedJSONPayload?
}

@MainActor
enum LibraryDoodlePersistence {
    typealias CommitObserver = (LibraryDetailPayloadKey, LibraryDecodedJSONPayload) -> Void

    nonisolated static let flashcardDrawingsKey = "flashcardDoodleDrawings"

    @discardableResult
    static func saveSplitDrawings(
        record: StoredRecord,
        context: ModelContext,
        drawingValues: [String: String],
        onCommitted: CommitObserver? = nil
    ) async -> String? {
        guard !drawingValues.isEmpty else { return nil }
        return await saveOverlayDrawing(
            record: record, context: context, splitDrawingValues: drawingValues, onCommitted: onCommitted
        )
    }

    static func saveFlashcardDrawing(
        record: StoredRecord,
        context: ModelContext,
        diagramKey: String,
        drawingData: String
    ) async -> String? {
        await saveOverlayDrawing(record: record, context: context, flashcardDrawing: (diagramKey, drawingData))
    }

    private static func saveOverlayDrawing(
        record: StoredRecord,
        context: ModelContext,
        splitDrawingValues: [String: String]? = nil,
        flashcardDrawing: (key: String, data: String)? = nil,
        onCommitted: CommitObserver? = nil
    ) async -> String? {
        for _ in 0..<3 {
            guard record.modelContext != nil, !record.isDeleted else { return "涂鸦未保存：题目记录已不存在。" }
            let base = record.payload
            guard let write = await prepareWrite(
                base: base,
                collection: record.collection,
                splitDrawingValues: splitDrawingValues,
                flashcardDrawing: flashcardDrawing
            ) else {
                return "涂鸦数据格式无效，未保存。"
            }
            do {
                let committed = try await commit(write, to: record, in: context, onCommitted: onCommitted)
                if committed { return nil }
            } catch {
                return "涂鸦未保存：\(error.localizedDescription)"
            }
        }
        return "题目内容刚刚发生变化，涂鸦未覆盖最新内容，请重试。"
    }

    @discardableResult
    static func save(
        record: StoredRecord,
        context: ModelContext,
        drawingData: String,
        legacyPreviewCleared: Bool,
        savesPreviewTogether: Bool = false,
        onCommitted: CommitObserver? = nil
    ) async -> String? {
        for _ in 0..<3 {
            guard record.modelContext != nil, !record.isDeleted else { return "涂鸦未保存：题目记录已不存在。" }
            let base = record.payload
            guard let write = await prepareWrite(
                base: base,
                collection: record.collection,
                drawingData: drawingData,
                legacyPreviewCleared: legacyPreviewCleared,
                savesPreviewTogether: savesPreviewTogether
            ) else {
                return "涂鸦数据格式无效，未保存。"
            }
            do {
                let committed = try await commit(write, to: record, in: context, onCommitted: onCommitted)
                guard committed else { continue }
            } catch {
                return "涂鸦未保存：\(error.localizedDescription)"
            }

            guard !savesPreviewTogether, write.decoded != nil, !drawingData.isEmpty else { return nil }
            Task { @MainActor in
                await Task.yield()
                let previewBase = record.payload
                let preparedPreviewBase = previewBase == write.payload ? write.decoded : nil
                let collection = record.collection
                let previewPayload = await Task.detached(priority: .utility) {
                    let sourceObject = preparedPreviewBase?.object
                        ?? ((try? JSONSerialization.jsonObject(with: previewBase)) as? [String: Any])
                    guard var object = sourceObject,
                          object["pencilKitData"] as? String == drawingData else { return nil as LibraryDoodlePreparedWrite? }
                    let preview = PencilDrawingCompatibility.previewDataURL(encodedData: drawingData)
                    guard !preview.isEmpty else { return nil }
                    object["drawingPreview"] = preview
                    object["doodle"] = preview
                    object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
                    guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                          let indexPayload = StoredRecord.makeIndexPayload(from: object, collection: collection) else { return nil }
                    return LibraryDoodlePreparedWrite(
                        basePayload: previewBase, payload: payload, indexPayload: indexPayload,
                        decoded: LibraryDecodedJSONPayload(object: object)
                    )
                }.value
                if let previewPayload { _ = try? await commit(previewPayload, to: record, in: context) }
            }
            return nil
        }
        return "题目内容刚刚发生变化，涂鸦未覆盖最新内容，请重试。"
    }

    private static func commit(
        _ write: LibraryDoodlePreparedWrite,
        to record: StoredRecord,
        in context: ModelContext,
        onCommitted: CommitObserver? = nil
    ) async throws -> Bool {
        guard record.modelContext != nil, !record.isDeleted, record.payload == write.basePayload else { return false }
        guard let decoded = write.decoded else { return true }
        let updatedAt = Date.now
        if record.collection == "errors" {
            await LibraryPayloadDecodeCoordinator.shared.rememberPreparedWrite(
                recordID: record.compoundID, updatedAt: updatedAt, payload: write.payload, decoded: decoded
            )
        }
        guard record.modelContext != nil, !record.isDeleted, record.payload == write.basePayload else { return false }
        let previousKey = LibraryDetailPayloadKey(record: record)
        let previousIndex = record.indexPayload
        let previousVersion = record.updatedAt
        record.replacePayload(write.payload, indexPayload: write.indexPayload)
        record.updatedAt = updatedAt
        do {
            try context.save()
        } catch {
            record.replacePayload(write.basePayload, indexPayload: previousIndex)
            record.updatedAt = previousVersion
            throw error
        }
        onCommitted?(previousKey, decoded)
        return true
    }

    private static func prepareWrite(
        base: Data,
        collection: String,
        drawingData: String? = nil,
        legacyPreviewCleared: Bool = false,
        savesPreviewTogether: Bool = false,
        splitDrawingValues: [String: String]? = nil,
        flashcardDrawing: (key: String, data: String)? = nil
    ) async -> LibraryDoodlePreparedWrite? {
        await Task.detached(priority: .userInitiated) {
            guard var object = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any] else { return nil }
            var changed = false
            if let splitDrawingValues {
                var storedByLayout = object["splitDoodleDrawings"] as? [String: Any] ?? [:]
                for (storageKey, value) in splitDrawingValues {
                    let parts = storageKey.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
                    guard parts.count == 2,
                          LibraryDoodleLayoutDirection(rawValue: parts[0]) != nil,
                          let pane = LibraryDoodlePane(rawValue: parts[1]) else { continue }
                    let layout = parts[0]
                    var storedByPane = storedByLayout[layout] as? [String: Any] ?? [:]
                    let oldValue = storedByPane[pane.rawValue] as? String ?? ""
                    guard oldValue != value else { continue }
                    changed = true
                    if value.isEmpty { storedByPane.removeValue(forKey: pane.rawValue) }
                    else { storedByPane[pane.rawValue] = value }
                    if storedByPane.isEmpty { storedByLayout.removeValue(forKey: layout) }
                    else { storedByLayout[layout] = storedByPane }
                }
                if changed {
                    if storedByLayout.isEmpty { object.removeValue(forKey: "splitDoodleDrawings") }
                    else { object["splitDoodleDrawings"] = storedByLayout }
                }
            }
            if let flashcardDrawing {
                let storageKey = LibraryDoodlePersistence.flashcardDrawingsKey
                var drawings = (object[storageKey] as? [String: String]) ?? [:]
                if (drawings[flashcardDrawing.key] ?? "") != flashcardDrawing.data {
                    drawings[flashcardDrawing.key] = flashcardDrawing.data.isEmpty ? nil : flashcardDrawing.data
                    object[storageKey] = drawings.isEmpty ? nil : drawings
                    changed = true
                }
            }
            if let drawingData {
                let previous = (object["pencilKitData"] as? String) ?? (object["drawingData"] as? String) ?? ""
                changed = changed || previous != drawingData || legacyPreviewCleared
                guard changed else {
                    return LibraryDoodlePreparedWrite(basePayload: base, payload: base, indexPayload: base, decoded: nil)
                }
                object["pencilKitData"] = drawingData
                if drawingData.isEmpty {
                    for key in ["drawingPreview", "doodle", "drawingData", "drawingDataURL", "handNote"] { object.removeValue(forKey: key) }
                } else {
                    object.removeValue(forKey: "drawingData")
                    object.removeValue(forKey: "drawingDataURL")
                    if savesPreviewTogether {
                        let preview = PencilDrawingCompatibility.previewDataURL(encodedData: drawingData)
                        if !preview.isEmpty {
                            object["drawingPreview"] = preview
                            object["doodle"] = preview
                        }
                    }
                }
            }
            guard changed else {
                return LibraryDoodlePreparedWrite(basePayload: base, payload: base, indexPayload: base, decoded: nil)
            }
            object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            guard JSONSerialization.isValidJSONObject(object),
                  let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let indexPayload = StoredRecord.makeIndexPayload(from: object, collection: collection) else { return nil }
            return LibraryDoodlePreparedWrite(
                basePayload: base, payload: payload, indexPayload: indexPayload,
                decoded: LibraryDecodedJSONPayload(object: object)
            )
        }.value
    }
}
