import Foundation
import SwiftData

enum LibraryDoodlePersistence {
    @MainActor
    @discardableResult
    static func save(
        record: StoredRecord,
        context: ModelContext,
        drawingData: String,
        legacyPreviewCleared: Bool
    ) -> String? {
        let totalStart = ProcessInfo.processInfo.systemUptime
        let current = record.jsonObject ?? [:]
        let previousDrawing = (current["pencilKitData"] as? String)
            ?? (current["drawingData"] as? String)
            ?? ""
        let changed = previousDrawing != drawingData || legacyPreviewCleared
        guard changed else {
            LibraryPerformanceLog.mark("doodle.save.skipped-unchanged", since: totalStart)
            return nil
        }

        var updated = current
        updated["pencilKitData"] = drawingData
        updated["updatedAt"] = ISO8601DateFormatter().string(from: .now)

        if drawingData.isEmpty {
            updated.removeValue(forKey: "drawingPreview")
            updated.removeValue(forKey: "doodle")
            updated.removeValue(forKey: "drawingData")
            updated.removeValue(forKey: "drawingDataURL")
            updated.removeValue(forKey: "handNote")
        } else {
            // PencilKit data is the canonical editable value. Keep any old preview
            // until the non-blocking compatibility refresh finishes below.
            updated.removeValue(forKey: "drawingData")
            updated.removeValue(forKey: "drawingDataURL")
        }

        do {
            let payloadStart = ProcessInfo.processInfo.systemUptime
            let payload = try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys])
            LibraryPerformanceLog.mark("doodle.save.payload", since: payloadStart)
            record.replacePayload(payload)
            record.updatedAt = .now
            let contextSaveStart = ProcessInfo.processInfo.systemUptime
            try context.save()
            LibraryPerformanceLog.mark("doodle.save.context", since: contextSaveStart)
        } catch {
            return "涂鸦未保存：\(error.localizedDescription)"
        }
        LibraryPerformanceLog.mark("doodle.save.total", since: totalStart)

        guard !drawingData.isEmpty else { return nil }
        Task { @MainActor in
            await Task.yield()
            let current = record.jsonObject ?? [:]
            guard current["pencilKitData"] as? String == drawingData else { return }
            let previewStart = ProcessInfo.processInfo.systemUptime
            // Preview generation is compatibility/cache work. Keep it out of the
            // main actor so it cannot compete with the detail page after closing.
            let preview = await Task.detached(priority: .utility) {
                PencilDrawingCompatibility.previewDataURL(encodedData: drawingData)
            }.value
            LibraryPerformanceLog.mark("doodle.preview", since: previewStart)
            guard !preview.isEmpty else { return }
            var refreshed = current
            refreshed["drawingPreview"] = preview
            refreshed["doodle"] = preview
            do {
                let payload = try JSONSerialization.data(withJSONObject: refreshed, options: [.sortedKeys])
                record.replacePayload(payload)
                record.updatedAt = .now
                try context.save()
            } catch {
                // The editable PencilKit data is already saved. A preview is only
                // a compatibility/cache field, so it must not block closing.
            }
        }
        return nil
    }
}
