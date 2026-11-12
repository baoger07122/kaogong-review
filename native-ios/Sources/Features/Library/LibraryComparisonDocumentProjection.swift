import Foundation

enum LibraryComparisonDocumentProjection {
    private struct Term {
        let name: String
        let meaning: String
        let coreFocus: String
        let contextExample: String
        let contextFocus: String
        let quickDecision: String
    }

    static func storedOrProjected(in object: [String: Any], category: WordCategory) -> String {
        if object.keys.contains("comparisonDocument") {
            return object["comparisonDocument"] as? String ?? ""
        }
        guard category.isComparison else { return "" }
        return project(
            category: category,
            commonMeaning: richValue(object["commonMeaning"]),
            terms: terms(from: object["compareWords"]),
            context: richValue(object["idiomComparisonContext"]),
            judgmentHint: richValue(firstValue(in: object, keys: ["judgmentHint", "content", "meaning"])),
            coreDifference: richValue(firstValue(in: object, keys: ["compareNote", "coreDifference"]))
        )
    }

    static func wordContent(in object: [String: Any], category: WordCategory) -> String {
        if category.isComparison { return storedOrProjected(in: object, category: category) }
        return richValue(firstValue(in: object, keys: ["meaning", "content", "judgmentHint"]))
    }

    static func project(draft: LibraryRecordDraft) -> String {
        let category = WordCategory(rawValue: draft.type) ?? .idiomDefinition
        guard category.isComparison else { return "" }
        if !draft.original.isEmpty, !draft.original.keys.contains("comparisonDocument") {
            return storedOrProjected(in: draft.original, category: category)
        }
        let terms = draft.wordCompareTerms.map {
            Term(
                name: $0.name,
                meaning: $0.meaning,
                coreFocus: $0.coreFocus ?? "",
                contextExample: $0.contextExample ?? "",
                contextFocus: $0.contextFocus ?? "",
                quickDecision: $0.quickDecision ?? ""
            )
        }
        return project(
            category: category,
            commonMeaning: richValue(draft.commonMeaning),
            terms: terms,
            context: richValue(draft.idiomComparisonContext),
            judgmentHint: richValue(draft.content),
            coreDifference: richValue(draft.compareNote)
        )
    }

    private static func project(
        category: WordCategory,
        commonMeaning: String,
        terms: [Term],
        context: String,
        judgmentHint: String,
        coreDifference: String
    ) -> String {
        var output = ""
        appendSection("共同语义", body: commonMeaning, to: &output)

        let hasMeaningRows = terms.contains { !$0.meaning.isEmpty || !$0.coreFocus.isEmpty }
        if hasMeaningRows {
            let firstColumn = category == .idiomComparison ? "成语" : "词语"
            var rows = [[firstColumn, "词义", "核心侧重"]]
            rows.append(contentsOf: terms.filter { !$0.meaning.isEmpty || !$0.coreFocus.isEmpty }.map {
                [$0.name, $0.meaning, $0.coreFocus]
            })
            output += "<h2>词义区别</h2>" + tableHTML(rows)
        }

        let hasContextRows = terms.contains { !$0.contextExample.isEmpty || !$0.contextFocus.isEmpty }
        if !context.isEmpty || hasContextRows {
            appendSection("同一情境下的具体区别", body: context.isEmpty ? "" : "<strong>统一情境：</strong>\(context)", to: &output)
            if hasContextRows {
                let firstColumn = category == .idiomComparison ? "成语" : "词语"
                var rows = [[firstColumn, "具体情境", "核心含义"]]
                rows.append(contentsOf: terms.filter { !$0.contextExample.isEmpty || !$0.contextFocus.isEmpty }.map {
                    [$0.name, $0.contextExample, $0.contextFocus]
                })
                output += tableHTML(rows)
            }
        }

        let decisionTerms = terms.filter { !$0.quickDecision.isEmpty }
        if !decisionTerms.isEmpty {
            let firstColumn = category == .idiomComparison ? "成语" : "词语"
            var rows = [[firstColumn, "判断提示"]]
            rows.append(contentsOf: decisionTerms.map { [$0.name, $0.quickDecision] })
            output += "<h2>一眼判断</h2>" + tableHTML(rows)
        }
        appendSection("判断提示", body: judgmentHint, to: &output)
        appendSection("核心区别", body: coreDifference, to: &output)
        return output
    }

    private static func terms(from value: Any?) -> [Term] {
        guard let values = value as? [[String: Any]] else { return [] }
        return values.compactMap { item in
            let name = item["name"] as? String ?? ""
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Term(
                name: name,
                meaning: richValue(item["meaning"]),
                coreFocus: richValue(firstValue(in: item, keys: ["coreFocus", "focus"])),
                contextExample: richValue(item["contextExample"]),
                contextFocus: richValue(item["contextFocus"]),
                quickDecision: richValue(firstValue(in: item, keys: ["quickDecision", "decision"]))
            )
        }
    }

    private static func appendSection(_ title: String, body: String, to output: inout String) {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        output += "<h2>\(escape(title))</h2><p>\(body)</p>"
    }

    private static func tableHTML(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        var html = "<table>"
        for (rowIndex, row) in rows.enumerated() {
            let tag = rowIndex == 0 ? "th" : "td"
            html += "<tr>"
            for cell in row { html += "<\(tag)>\(richValue(cell))</\(tag)>" }
            html += "</tr>"
        }
        return html + "</table>"
    }

    private static func richValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            if trimmed.contains("[[NATIVE_") { return string }
            if trimmed.range(of: #"(?is)<(?:[a-z][a-z0-9]*)(?:\s|>)"#, options: .regularExpression) != nil {
                return string
            }
            if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
               let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return LegacyRichTextConverter.html(from: blocks)
            }
            if let markdown = NativeRichTextMarkdown.htmlIfMarkdown(string) { return markdown }
            return escape(string).replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "<br>")
        }
        return LegacyRichTextConverter.html(from: value)
    }

    private static func firstValue(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key], !(value is NSNull) {
                if let string = value as? String, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                return value
            }
        }
        return nil
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
