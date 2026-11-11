import Foundation
import SwiftData

private struct LibraryDoodlePreparedWrite: Sendable {
    let basePayload: Data
    let payload: Data
    let indexPayload: Data
    let changed: Bool
}

@MainActor
enum LibraryDoodlePersistence {
    @discardableResult
    static func saveSplitDrawings(
        record: StoredRecord,
        context: ModelContext,
        drawingValues: [String: String]
    ) async -> String? {
        guard !drawingValues.isEmpty else { return nil }
        for _ in 0..<3 {
            let base = record.payload
            guard let write = await prepareWrite(base: base, collection: record.collection, splitDrawingValues: drawingValues) else {
                return "涂鸦数据格式无效，未保存。"
            }
            guard record.payload == write.basePayload else { continue }
            guard write.changed else { return nil }
            record.replacePayload(write.payload, indexPayload: write.indexPayload)
            record.updatedAt = .now
            do {
                try context.save()
                return nil
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
        legacyPreviewCleared: Bool
    ) async -> String? {
        for _ in 0..<3 {
            let base = record.payload
            guard let write = await prepareWrite(
                base: base,
                collection: record.collection,
                drawingData: drawingData,
                legacyPreviewCleared: legacyPreviewCleared
            ) else {
                return "涂鸦数据格式无效，未保存。"
            }
            guard record.payload == write.basePayload else { continue }
            guard write.changed else { return nil }
            record.replacePayload(write.payload, indexPayload: write.indexPayload)
            record.updatedAt = .now
            do {
                try context.save()
            } catch {
                return "涂鸦未保存：\(error.localizedDescription)"
            }

            guard !drawingData.isEmpty else { return nil }
            Task { @MainActor in
                await Task.yield()
                let previewBase = record.payload
                let collection = record.collection
                let previewPayload = await Task.detached(priority: .utility) {
                    guard var object = (try? JSONSerialization.jsonObject(with: previewBase)) as? [String: Any],
                          object["pencilKitData"] as? String == drawingData else { return nil as LibraryDoodlePreparedWrite? }
                    let preview = PencilDrawingCompatibility.previewDataURL(encodedData: drawingData)
                    guard !preview.isEmpty else { return nil }
                    object["drawingPreview"] = preview
                    object["doodle"] = preview
                    object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
                    guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                          let indexPayload = StoredRecord.makeIndexPayload(from: payload, collection: collection) else { return nil }
                    return LibraryDoodlePreparedWrite(basePayload: previewBase, payload: payload, indexPayload: indexPayload, changed: true)
                }.value
                guard let previewPayload,
                      record.payload == previewPayload.basePayload else { return }
                record.replacePayload(previewPayload.payload, indexPayload: previewPayload.indexPayload)
                record.updatedAt = .now
                try? context.save()
            }
            return nil
        }
        return "题目内容刚刚发生变化，涂鸦未覆盖最新内容，请重试。"
    }

    private static func prepareWrite(
        base: Data,
        collection: String,
        drawingData: String? = nil,
        legacyPreviewCleared: Bool = false,
        splitDrawingValues: [String: String]? = nil
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
            if let drawingData {
                let previous = (object["pencilKitData"] as? String) ?? (object["drawingData"] as? String) ?? ""
                changed = changed || previous != drawingData || legacyPreviewCleared
                guard changed else {
                    return LibraryDoodlePreparedWrite(basePayload: base, payload: base, indexPayload: base, changed: false)
                }
                object["pencilKitData"] = drawingData
                if drawingData.isEmpty {
                    for key in ["drawingPreview", "doodle", "drawingData", "drawingDataURL", "handNote"] { object.removeValue(forKey: key) }
                } else {
                    object.removeValue(forKey: "drawingData")
                    object.removeValue(forKey: "drawingDataURL")
                }
            }
            guard changed else {
                return LibraryDoodlePreparedWrite(basePayload: base, payload: base, indexPayload: base, changed: false)
            }
            object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            guard JSONSerialization.isValidJSONObject(object),
                  let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let indexPayload = StoredRecord.makeIndexPayload(from: payload, collection: collection) else { return nil }
            return LibraryDoodlePreparedWrite(basePayload: base, payload: payload, indexPayload: indexPayload, changed: true)
        }.value
    }
}
