import Foundation

enum LibraryReviewSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case real = "real"
    case mock = "mock"
    case pending = "pending"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .real: "真题复盘"
        case .mock: "模拟题复盘"
        case .pending: "待确认"
        }
    }

    static func explicitValue(in object: [String: Any]) -> LibraryReviewSource? {
        for key in ["reviewSource", "examType", "paperType", "sourceType"] {
            if let value = object[key] as? String, let source = explicitValue(value) { return source }
        }
        return nil
    }

    static func explicitValue(_ rawValue: String) -> LibraryReviewSource? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "real", "true", "past", "真题", "历年真题", "真题卷": .real
        case "mock", "simulation", "simulated", "模拟", "模拟题", "模拟卷": .mock
        case "pending", "unknown", "unclassified", "未分类", "未确认", "待确认": .pending
        default: nil
        }
    }
}

enum LibraryReviewSourcePolicy {
    static func classify(
        collection: String,
        object: [String: Any],
        linkedExamObject: [String: Any]? = nil
    ) -> LibraryReviewSource {
        if collection == "words" { return .pending }

        let explicit = LibraryReviewSource.explicitValue(in: object)
        if let explicit, explicit == .mock || explicit == .pending { return explicit }

        let linked = linkedExamObject.flatMap { LibraryReviewSource.explicitValue(in: $0) }
        if linked == .mock { return .mock }
        if let explicit { return explicit }
        if let linked { return linked }

        if collection == "errors",
           let paperID = object["questionBankPaperID"] as? String,
           !paperID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .real
        }
        if ["errors", "notes", "stickies"].contains(collection) { return .real }
        return .pending
    }
}

final class ReviewSourceMetadataCache {
    static let shared = ReviewSourceMetadataCache()

    private final class Entry {
        let payloadHash: Int
        let fields: NSDictionary

        init(payloadHash: Int, fields: NSDictionary) {
            self.payloadHash = payloadHash
            self.fields = fields
        }
    }

    private let cache = NSCache<NSString, Entry>()
    private let keys: Set<String> = [
        "reviewSource", "examType", "paperType", "sourceType", "sourceExamId", "questionBankPaperID"
    ]

    private init() {}

    func fields(for compoundID: String, payload: Data) -> [String: Any] {
        let key = compoundID as NSString
        let payloadHash = payload.hashValue
        if let cached = cache.object(forKey: key), cached.payloadHash == payloadHash {
            return cached.fields as? [String: Any] ?? [:]
        }
        let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        let values = object.filter { keys.contains($0.key) }
        cache.setObject(Entry(payloadHash: payloadHash, fields: NSDictionary(dictionary: values)), forKey: key)
        return values
    }

    func removeAll() { cache.removeAllObjects() }
}
