import Foundation

enum LibraryQuantityErrorCauseCompatibility {
    static let authorityKey = "quantityErrorCauseAuthorityVersion"

    static func isAuthoritative(in object: [String: Any]) -> Bool {
        (object[authorityKey] as? NSNumber)?.intValue == 1
    }

    static func values(in object: [String: Any]) -> [String] {
        let authoritative = isAuthoritative(in: object)
        let causes = values(
            errorCause: authoritative
                ? [object["errorCause"]]
                : [object["errorCause"], object["cause"], object["reason"]],
            weaknessTags: object["weaknessTags"],
            authoritative: authoritative
        )
        return LibraryDataAnalysisCauseLayout.mergingTrapLines(into: causes, from: object)
    }

    static func values(errorCause: Any?, weaknessTags: Any?, authoritative: Bool) -> [String] {
        values(errorCause: [errorCause], weaknessTags: weaknessTags, authoritative: authoritative)
    }

    static func serialized(errorCause: Any?, weaknessTags: Any?, authoritative: Bool) -> String {
        values(errorCause: errorCause, weaknessTags: weaknessTags, authoritative: authoritative)
            .joined(separator: "\n")
    }

    static func markAuthoritative(in object: inout [String: Any]) {
        object[authorityKey] = 1
    }

    private static func values(errorCause: [Any?], weaknessTags: Any?, authoritative: Bool) -> [String] {
        let current = errorCause.flatMap {
            splitValues($0, splitLegacySeparators: !authoritative, legacySeparators: "、")
        }
        let legacy = authoritative
            ? []
            : splitValues(weaknessTags, splitLegacySeparators: true, legacySeparators: "、,，")
        var seen = Set<String>()
        return (current + legacy).filter { seen.insert($0).inserted }
    }

    private static func splitValues(
        _ value: Any?,
        splitLegacySeparators: Bool,
        legacySeparators: String
    ) -> [String] {
        let candidates: [String]
        if let values = value as? [String] {
            candidates = values.flatMap { $0.components(separatedBy: .newlines) }
        } else if let string = value as? String {
            let lines = string.components(separatedBy: .newlines)
            candidates = splitLegacySeparators
                ? lines.flatMap { line in line.split(whereSeparator: { legacySeparators.contains($0) }).map(String.init) }
                : lines
        } else {
            candidates = []
        }
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
