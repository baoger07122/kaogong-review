import Foundation

@main
enum LibraryPreparedWriteBehavior {
    static func main() async throws {
        let coordinator = LibraryPayloadDecodeCoordinator()
        let updatedAt = Date(timeIntervalSince1970: 1)
        // This size is intentionally above the regular decoded-cache limit.
        let question = String(repeating: "甲", count: 200_000)
        let object = ["question": question]
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let key = LibraryPayloadDecodeKey(
            recordID: "errors:a", updatedAt: updatedAt, payloadByteCount: bytes.count, source: "payload"
        )
        await coordinator.rememberPreparedWrite(
            recordID: key.recordID, updatedAt: updatedAt, payload: bytes,
            decoded: LibraryDecodedJSONPayload(object: ["question": question, "preparedMarker": true])
        )
        let prepared = await coordinator.decode(key: key, payload: bytes, priority: .userInitiated)
        precondition(prepared?.object["question"] as? String == question)
        precondition(prepared?.object["preparedMarker"] as? Bool == true)

        let replacement = String(repeating: "乙", count: 200_000)
        let sameSize = try JSONSerialization.data(withJSONObject: ["question": replacement])
        precondition(sameSize.count == bytes.count)
        let decoded = await coordinator.decode(key: key, payload: sameSize, priority: .userInitiated)
        precondition(decoded?.object["question"] as? String == replacement)
        precondition(decoded?.object["preparedMarker"] == nil)

        let otherRecord = LibraryPayloadDecodeKey(
            recordID: "errors:b", updatedAt: updatedAt, payloadByteCount: bytes.count, source: "payload"
        )
        let isolated = await coordinator.decode(key: otherRecord, payload: bytes, priority: .userInitiated)
        precondition(isolated?.object["preparedMarker"] == nil)
    }
}
