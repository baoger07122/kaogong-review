import Foundation

enum LibraryQuantityErrorCauseCompatibility {
    static let authorityKey = "quantityErrorCauseAuthorityVersion"

    static func isAuthoritative(in object: [String: Any]) -> Bool {
        (object[authorityKey] as? NSNumber)?.intValue == 1
    }

    static func values(in object: [String: Any]) -> [String] {
        let authoritative = isAuthoritative(in: object)
        values(
            errorCause: authoritative
                ? [object["errorCause"]]
                : [object["errorCause"], object["cause"], object["reason"]],
            weaknessTags: object["weaknessTags"],
            authoritative: authoritative
        )
    }

    static func values(errorCause: Any?, weaknessTags: Any?, authoritative: Bool) -> [String] {
        values(errorCause: [errorCause], weaknessTags: weaknessTags, authoritative: authoritative)
    }

    static func serialized(errorCause: Any?, weaknessTags: Any?, authoritative: Bool) -> String {
        values(errorCause: errorCause, weaknessTags: weaknessTags, authoritative: authoritative)
            .joined(separator: "、")
    }

    static func markAuthoritative(in object: inout [String: Any]) {
        object[authorityKey] = 1
    }

    private static func values(errorCause: [Any?], weaknessTags: Any?, authoritative: Bool) -> [String] {
        let current = errorCause.flatMap { splitValues($0) }
        let legacy = authoritative ? [] : splitValues(weaknessTags)
        var seen = Set<String>()
        return (current + legacy).filter { seen.insert($0).inserted }
    }

    private static func splitValues(_ value: Any?) -> [String] {
        let candidates: [String]
        if let values = value as? [String] {
            candidates = values
        } else if let string = value as? String {
            candidates = string.split(whereSeparator: { "、,，".contains($0) }).map(String.init)
        } else {
            candidates = []
        }
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
