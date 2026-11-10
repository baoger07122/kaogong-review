import Foundation

@main
enum LibraryRecordPerformanceBehavior {
    static func main() throws {
        try verifyFilterIndexMatchesListRules()
        try verifyVisibleRecordQueryVersions()
        try verifySwipePreviewUsesIndexThenLegacyFallback()
    }

    private static func verifyFilterIndexMatchesListRules() throws {
        let object: [String: Any] = [
            "question": "一项工程的行程变化如下",
            "status": "已掌握",
            "isDifficult": true,
            "needsReview": true,
            "knowledgePoints": ["行程问题"],
            "errorCause": "工程问题"
        ]
        let index = LibraryRecordFilterIndex(
            collection: "errors",
            storedSubject: "数量关系",
            indexObject: object,
            compatibleObject: object,
            isMockReview: false,
            sourceExamTitle: ""
        )
        guard index.matches(
            selectedTag: "难题",
            normalizedSearch: LibraryRecordFilterIndex.normalized("行程变化"),
            includesMastered: true
        ) else {
            throw Failure(description: "The cached filter index must preserve matching tags and search text.")
        }
        guard !index.matches(selectedTag: "行程问题", normalizedSearch: "", includesMastered: false) else {
            throw Failure(description: "Mastered records must stay hidden when the mastery filter is off.")
        }
        guard index.matches(selectedTag: "行程问题", normalizedSearch: "", includesMastered: true) else {
            throw Failure(description: "Knowledge point tags must remain filterable.")
        }
    }

    private static func verifyVisibleRecordQueryVersions() throws {
        let version = LibraryRecordDataVersion(
            updatedAt: Date(timeIntervalSince1970: 100),
            payloadByteCount: 800,
            indexPayloadByteCount: 160
        )
        let revision = LibraryVisibleErrorRecordRevision(
            compoundID: "errors:one",
            recordID: "one",
            collection: "errors",
            subject: "数量关系",
            module: nil,
            createdAt: Date(timeIntervalSince1970: 90),
            dataVersion: version
        )
        let query = LibraryVisibleErrorRecordQuery(
            revisions: [revision],
            collection: "errors",
            subject: "数量关系",
            module: nil,
            quantityType: "",
            reviewSource: "pending",
            sourceExamTitleRevision: 0,
            selectedTag: "难题",
            normalizedSearch: "工程",
            includesMastered: false
        )
        let unchangedQuery = LibraryVisibleErrorRecordQuery(
            revisions: [revision], collection: "errors", subject: "数量关系", module: nil,
            quantityType: "", reviewSource: "pending", sourceExamTitleRevision: 0, selectedTag: "难题",
            normalizedSearch: "工程", includesMastered: false
        )
        guard query == unchangedQuery else {
            throw Failure(description: "An unchanged filter and record version should hit the visible-ID cache.")
        }
        let changedSearch = LibraryVisibleErrorRecordQuery(
            revisions: [revision], collection: "errors", subject: "数量关系", module: nil,
            quantityType: "", reviewSource: "pending", sourceExamTitleRevision: 0, selectedTag: "难题",
            normalizedSearch: "行程", includesMastered: false
        )
        guard query != changedSearch else {
            throw Failure(description: "Changing search text must invalidate the visible-ID cache.")
        }
        let changedSourceTitle = LibraryVisibleErrorRecordQuery(
            revisions: [revision], collection: "errors", subject: "数量关系", module: nil,
            quantityType: "", reviewSource: "mock", sourceExamTitleRevision: 1,
            selectedTag: "难题", normalizedSearch: "工程", includesMastered: false
        )
        guard query != changedSourceTitle else {
            throw Failure(description: "A changed linked exam title must invalidate source-name searches.")
        }
        let changedRevision = LibraryVisibleErrorRecordRevision(
            compoundID: revision.compoundID,
            recordID: revision.recordID,
            collection: revision.collection,
            subject: revision.subject,
            module: revision.module,
            createdAt: revision.createdAt,
            dataVersion: LibraryRecordDataVersion(
                updatedAt: Date(timeIntervalSince1970: 101),
                payloadByteCount: version.payloadByteCount,
                indexPayloadByteCount: version.indexPayloadByteCount
            )
        )
        let changedRecord = LibraryVisibleErrorRecordQuery(
            revisions: [changedRevision], collection: "errors", subject: "数量关系", module: nil,
            quantityType: "", reviewSource: "pending", sourceExamTitleRevision: 0, selectedTag: "难题",
            normalizedSearch: "工程", includesMastered: false
        )
        guard query != changedRecord else {
            throw Failure(description: "A changed record version must invalidate the visible-ID cache.")
        }
    }

    private static func verifySwipePreviewUsesIndexThenLegacyFallback() throws {
        let index = try JSONSerialization.data(withJSONObject: [
            "question": "索引题干",
            "options": ["索引选项 A"]
        ])
        let fullPayload = try JSONSerialization.data(withJSONObject: [
            "question": "完整题干",
            "options": ["完整选项 A", "完整选项 B"]
        ])
        let indexedPreview = LibraryRecordSwipePreviewContent(
            subject: "数量关系", module: "行程问题", indexPayload: index, payload: fullPayload
        )
        guard indexedPreview.title == "索引题干", indexedPreview.options == ["索引选项 A"] else {
            throw Failure(description: "A valid index must provide swipe-preview fields.")
        }

        let incompleteIndex = try JSONSerialization.data(withJSONObject: ["subject": "数量关系"])
        let legacyPreview = LibraryRecordSwipePreviewContent(
            subject: "数量关系", module: nil, indexPayload: incompleteIndex, payload: fullPayload
        )
        guard legacyPreview.title == "完整题干", legacyPreview.options.count == 2 else {
            throw Failure(description: "A legacy index without preview fields must fall back to the payload.")
        }
    }

    private struct Failure: Error {
        let description: String
    }
}
