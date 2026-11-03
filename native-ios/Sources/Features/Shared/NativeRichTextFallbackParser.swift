import Foundation

enum NativeRichTextFallbackRun: Equatable, Sendable {
    case text(String)
    case image(String)
    case table(String)
    case formula(String)
    case placeholder(String)
    case imageWithMarker(dataURL: String, marker: String)
    case tableWithMarker(encoded: String, marker: String)
    case formulaWithMarker(encoded: String, marker: String)
    case opaque(label: String, marker: String)
}

/// Bounded, Foundation-only parser used when the system HTML importer is skipped
/// or fails. It preserves native attachment markers without changing stored HTML.
enum NativeRichTextFallbackParser {
    private static let maximumScannedBytes = 8 * 1024 * 1024
    private static let maximumOutputCharacters = 10_000
    private static let maximumRegularTagBytes = 512
    private static let maximumMarkerBytes = 7 * 1024 * 1024
    private static let maximumImageDataBytes = 4 * 1024 * 1024
    private static let maximumImageTagBytes = maximumImageDataBytes + 2 * 1024
    private static let maximumTableJSONBytes = 48 * 1024
    private static let maximumFormulaJSONBytes = 4 * 1024
    private static let maximumAttachments = 32
    private static let maximumEditableDocumentBytes = 8 * 1024 * 1024
    private static let maximumEditableTextCharacters = 1_000_000
    private static let maximumEditableAttachments = 64
    private static let skippedElements: Set<String> = ["head", "style", "script"]

    private struct ScannedTag {
        let raw: String
        let endIndex: String.Index
        let byteCount: Int
    }

    private struct ScannedNativeMarker {
        let raw: String
        let kind: String
        let payload: String
        let endIndex: String.Index
        let byteCount: Int
        let isClosed: Bool
    }

    static func parse(_ html: String) -> [NativeRichTextFallbackRun] {
        guard !html.isEmpty else { return [] }
        var runs: [NativeRichTextFallbackRun] = []
        var textBuffer = String()
        var textCharacterCount = 0
        var scannedBytes = 0
        var outputCharacters = 0
        var attachmentCount = 0
        var ignoredElements: [String] = []
        var didAppendAttachmentLimit = false
        var wasTruncated = false
        var cursor = html.startIndex

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            let decoded = decodeEntities(textBuffer)
            if !decoded.isEmpty {
                runs.append(.text(decoded))
                outputCharacters += decoded.count
            }
            textBuffer.removeAll(keepingCapacity: true)
            textCharacterCount = 0
        }

        func appendText(_ value: String) {
            guard !value.isEmpty, outputCharacters + textCharacterCount < maximumOutputCharacters else {
                wasTruncated = true
                return
            }
            let remaining = maximumOutputCharacters - outputCharacters - textCharacterCount
            if value.count > remaining {
                textBuffer.append(contentsOf: value.prefix(remaining))
                textCharacterCount += remaining
                wasTruncated = true
            } else {
                textBuffer.append(contentsOf: value)
                textCharacterCount += value.count
            }
        }

        func appendAttachment(_ run: NativeRichTextFallbackRun) {
            flushText()
            guard attachmentCount < maximumAttachments else {
                if !didAppendAttachmentLimit {
                    runs.append(.placeholder("其余附件已省略"))
                    didAppendAttachmentLimit = true
                }
                return
            }
            attachmentCount += 1
            runs.append(run)
        }

        func appendPlaceholder(_ label: String) {
            appendAttachment(.placeholder(label))
        }

        while cursor < html.endIndex, scannedBytes < maximumScannedBytes, outputCharacters + textCharacterCount < maximumOutputCharacters {
            if !ignoredElements.isEmpty {
                if html[cursor] == "<", let scannedTag = scanTag(in: html, from: cursor) {
                    cursor = scannedTag.endIndex
                    scannedBytes += scannedTag.byteCount
                    guard let tag = parseTag(scannedTag.raw) else { continue }
                    if tag.isClosing, ignoredElements.last == tag.name {
                        ignoredElements.removeLast()
                    } else if !tag.isClosing, !tag.isSelfClosing, skippedElements.contains(tag.name) {
                        ignoredElements.append(tag.name)
                    }
                    continue
                }
                let character = html[cursor]
                scannedBytes += String(character).utf8.count
                cursor = html.index(after: cursor)
                continue
            }

            if html[cursor...].hasPrefix("[[NATIVE_") {
                flushText()
                guard let marker = scanNativeMarker(in: html, from: cursor) else {
                    appendPlaceholder("附件无法显示")
                    wasTruncated = true
                    break
                }
                scannedBytes += marker.byteCount
                cursor = marker.endIndex
                if let run = previewRun(for: marker) {
                    appendAttachment(run)
                } else {
                    appendPlaceholder(markerLabel(for: marker.kind))
                }
                if !marker.isClosed {
                    wasTruncated = true
                    break
                }
                continue
            }

            if html[cursor] == "<" {
                if let scannedTag = scanTag(in: html, from: cursor) {
                    scannedBytes += scannedTag.byteCount
                    cursor = scannedTag.endIndex
                    guard let tag = parseTag(scannedTag.raw) else { continue }
                    if !tag.isClosing, !tag.isSelfClosing, skippedElements.contains(tag.name) {
                        flushText()
                        ignoredElements.append(tag.name)
                    } else if tag.name == "img", !tag.isClosing {
                        let source = imageSource(in: tag.raw)
                        if let source, let parsed = validatedImageDataURL(source) {
                            appendAttachment(.image(parsed))
                        } else {
                            appendPlaceholder("图片")
                        }
                    } else if isLineBreakTag(tag) {
                        if (textBuffer.last ?? "\0") != "\n" { appendText("\n") }
                    }
                    continue
                }

                if isImageTagStart(in: html, at: cursor) {
                    if let skipped = skipTag(in: html, from: cursor, maximumBytes: maximumScannedBytes - scannedBytes) {
                        cursor = skipped.endIndex
                        scannedBytes += skipped.byteCount
                        appendPlaceholder("图片")
                        continue
                    } else {
                        appendPlaceholder("图片")
                        wasTruncated = true
                        break
                    }
                }

                if isLikelyTagStart(in: html, at: cursor) {
                    appendPlaceholder("内容")
                    wasTruncated = true
                    break
                }

                scannedBytes += 1
                appendText("<")
                cursor = html.index(after: cursor)
                continue
            }

            let character = html[cursor]
            let byteCount = String(character).utf8.count
            scannedBytes += byteCount
            cursor = html.index(after: cursor)
            appendText(String(character))
        }

        if cursor < html.endIndex || scannedBytes >= maximumScannedBytes || wasTruncated {
            wasTruncated = true
        }
        flushText()
        if wasTruncated {
            runs.append(.text("\n…（预览已截断，原内容仍保留）"))
        }
        return runs
    }

    /// Returns nil unless the whole document and every retained attachment fit the
    /// editing limits. Unlike the preview parser, this path never truncates text.
    static func parseForEditing(_ html: String) -> [NativeRichTextFallbackRun]? {
        guard html.utf8.count <= maximumEditableDocumentBytes else { return nil }
        var runs: [NativeRichTextFallbackRun] = []
        var textBuffer = String()
        var bufferedCharacters = 0
        var outputCharacters = 0
        var attachmentCount = 0
        var ignoredElements: [String] = []
        var cursor = html.startIndex

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            let decoded = decodeEntities(textBuffer)
            if !decoded.isEmpty {
                runs.append(.text(decoded))
                outputCharacters += decoded.count
            }
            textBuffer.removeAll(keepingCapacity: true)
            bufferedCharacters = 0
        }

        func appendText(_ value: String) -> Bool {
            guard outputCharacters + bufferedCharacters + value.count <= maximumEditableTextCharacters else {
                return false
            }
            textBuffer.append(value)
            bufferedCharacters += value.count
            return true
        }

        func appendAttachment(_ run: NativeRichTextFallbackRun) -> Bool {
            guard attachmentCount < maximumEditableAttachments else { return false }
            flushText()
            attachmentCount += 1
            runs.append(run)
            return true
        }

        while cursor < html.endIndex {
            if !ignoredElements.isEmpty {
                if html[cursor] == "<", let tag = scanTag(in: html, from: cursor) {
                    cursor = tag.endIndex
                    guard let parsed = parseTag(tag.raw) else { continue }
                    if parsed.isClosing, ignoredElements.last == parsed.name {
                        ignoredElements.removeLast()
                    } else if !parsed.isClosing, !parsed.isSelfClosing, skippedElements.contains(parsed.name) {
                        ignoredElements.append(parsed.name)
                    }
                    continue
                }
                cursor = html.index(after: cursor)
                continue
            }

            if html[cursor...].hasPrefix("[[NATIVE_") {
                flushText()
                guard let marker = scanNativeMarker(in: html, from: cursor), marker.isClosed else { return nil }
                cursor = marker.endIndex
                let run: NativeRichTextFallbackRun
                switch marker.kind {
                case "NATIVE_IMAGE":
                    if let decoded = decodedMarkerRun(payload: marker.payload, label: "图片"),
                       case .image(let dataURL) = decoded {
                        run = .imageWithMarker(dataURL: dataURL, marker: marker.raw)
                    } else {
                        run = .opaque(label: "图片", marker: marker.raw)
                    }
                case "NATIVE_TABLE":
                    if let data = Data(base64Encoded: marker.payload), data.count <= maximumTableJSONBytes {
                        run = .tableWithMarker(encoded: marker.payload, marker: marker.raw)
                    } else {
                        run = .opaque(label: "表格", marker: marker.raw)
                    }
                case "NATIVE_FORMULA":
                    if let data = Data(base64Encoded: marker.payload), data.count <= maximumFormulaJSONBytes {
                        run = .formulaWithMarker(encoded: marker.payload, marker: marker.raw)
                    } else {
                        run = .opaque(label: "公式", marker: marker.raw)
                    }
                default:
                    run = .opaque(label: markerLabel(for: marker.kind), marker: marker.raw)
                }
                guard appendAttachment(run) else { return nil }
                continue
            }

            if html[cursor] == "<" {
                if let tag = scanTag(in: html, from: cursor) {
                    cursor = tag.endIndex
                    guard let parsed = parseTag(tag.raw) else { continue }
                    if !parsed.isClosing, !parsed.isSelfClosing, skippedElements.contains(parsed.name) {
                        flushText()
                        ignoredElements.append(parsed.name)
                    } else if parsed.name == "img", !parsed.isClosing {
                        let run: NativeRichTextFallbackRun
                        if let source = imageSource(in: parsed.raw), let dataURL = validatedImageDataURL(source) {
                            let payload = Data(dataURL.utf8).base64EncodedString()
                            run = .imageWithMarker(
                                dataURL: dataURL,
                                marker: "[[NATIVE_IMAGE:\(payload)]]"
                            )
                        } else {
                            let payload = Data(parsed.raw.utf8).base64EncodedString()
                            run = .opaque(label: "图片", marker: "[[NATIVE_RAW_HTML:\(payload)]]")
                        }
                        guard appendAttachment(run) else { return nil }
                    } else if isLineBreakTag(parsed) {
                        if (textBuffer.last ?? "\0") != "\n", !appendText("\n") { return nil }
                    }
                    continue
                }

                if isImageTagStart(in: html, at: cursor) || isLikelyTagStart(in: html, at: cursor) {
                    return nil
                }
                if !appendText("<") { return nil }
                cursor = html.index(after: cursor)
                continue
            }

            let character = html[cursor]
            cursor = html.index(after: cursor)
            if !appendText(String(character)) { return nil }
        }

        guard ignoredElements.isEmpty else { return nil }
        flushText()
        guard outputCharacters <= maximumEditableTextCharacters else { return nil }
        return runs
    }

    private static func scanTag(in value: String, from start: String.Index) -> ScannedTag? {
        guard value[start] == "<" else { return nil }
        var cursor = start
        var byteCount = 0
        var activeQuote: Character?
        let maximumBytes = isImageTagStart(in: value, at: start) ? maximumImageTagBytes : maximumRegularTagBytes
        while cursor < value.endIndex, byteCount < maximumBytes {
            let character = value[cursor]
            byteCount += String(character).utf8.count
            cursor = value.index(after: cursor)
            if let quote = activeQuote {
                if character == quote { activeQuote = nil }
            } else if character == "\"" || character == "'" {
                activeQuote = character
            } else if character == ">" {
                return ScannedTag(raw: String(value[start..<cursor]), endIndex: cursor, byteCount: byteCount)
            }
        }
        return nil
    }

    private static func skipTag(in value: String, from start: String.Index, maximumBytes: Int) -> ScannedTag? {
        guard maximumBytes > 0, value[start] == "<" else { return nil }
        var cursor = start
        var byteCount = 0
        var activeQuote: Character?
        while cursor < value.endIndex, byteCount < maximumBytes {
            let character = value[cursor]
            byteCount += String(character).utf8.count
            cursor = value.index(after: cursor)
            if let quote = activeQuote {
                if character == quote { activeQuote = nil }
            } else if character == "\"" || character == "'" {
                activeQuote = character
            } else if character == ">" {
                return ScannedTag(raw: "", endIndex: cursor, byteCount: byteCount)
            }
        }
        return nil
    }

    private static func isImageTagStart(in value: String, at start: String.Index) -> Bool {
        guard value[start...].prefix(4).lowercased() == "<img",
              let afterName = value.index(start, offsetBy: 4, limitedBy: value.endIndex)
        else { return false }
        if afterName == value.endIndex { return true }
        let boundary = value[afterName]
        return boundary.isWhitespace || boundary == ">" || boundary == "/"
    }

    private static func isLikelyTagStart(in value: String, at start: String.Index) -> Bool {
        let next = value.index(after: start)
        guard next < value.endIndex else { return false }
        let character = value[next]
        return character.isLetter || character == "!" || character == "?" || character == "/"
    }

    private static func parseTag(_ raw: String) -> (name: String, isClosing: Bool, isSelfClosing: Bool, raw: String)? {
        guard raw.first == "<", raw.last == ">" else { return nil }
        var body = raw.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.first != "!", body.first != "?" else { return nil }
        let isClosing = body.first == "/"
        if isClosing { body.removeFirst() }
        let isSelfClosing = body.last == "/"
        let name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()
        guard !name.isEmpty else { return nil }
        return (name, isClosing, isSelfClosing, raw)
    }

    private static func isLineBreakTag(_ tag: (name: String, isClosing: Bool, isSelfClosing: Bool, raw: String)) -> Bool {
        if ["br", "hr"].contains(tag.name) { return true }
        return tag.isClosing && ["p", "div", "li", "tr", "blockquote", "pre"].contains(tag.name)
    }

    private static func scanNativeMarker(in value: String, from start: String.Index) -> ScannedNativeMarker? {
        guard value[start...].hasPrefix("[[NATIVE_") else { return nil }
        var cursor = start
        var byteCount = 0
        var marker = String()
        while cursor < value.endIndex, byteCount < maximumMarkerBytes {
            let character = value[cursor]
            marker.append(character)
            byteCount += String(character).utf8.count
            cursor = value.index(after: cursor)
            guard marker.hasSuffix("]]" ) else { continue }
            let body = marker.dropFirst(2).dropLast(2)
            guard let separator = body.firstIndex(of: ":") else {
                return ScannedNativeMarker(
                    raw: marker,
                    kind: "NATIVE_UNKNOWN",
                    payload: "",
                    endIndex: cursor,
                    byteCount: byteCount,
                    isClosed: true
                )
            }
            return ScannedNativeMarker(
                raw: marker,
                kind: String(body[..<separator]),
                payload: String(body[body.index(after: separator)...]),
                endIndex: cursor,
                byteCount: byteCount,
                isClosed: true
            )
        }
        let body = marker.dropFirst(min(2, marker.count))
        let kind = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "NATIVE_UNKNOWN"
        let payload = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
        return ScannedNativeMarker(
            raw: marker,
            kind: kind,
            payload: payload,
            endIndex: cursor,
            byteCount: byteCount,
            isClosed: false
        )
    }

    private static func previewRun(for marker: ScannedNativeMarker) -> NativeRichTextFallbackRun? {
        guard marker.isClosed else { return nil }
        switch marker.kind {
        case "NATIVE_IMAGE": decodedMarkerRun(payload: marker.payload, label: "图片")
        case "NATIVE_TABLE": decodedMarkerRun(payload: marker.payload, label: "表格")
        case "NATIVE_FORMULA": decodedMarkerRun(payload: marker.payload, label: "公式")
        default: nil
        }
    }

    private static func markerLabel(for kind: String) -> String {
        switch kind {
        case "NATIVE_IMAGE", "NATIVE_RAW_HTML": "图片"
        case "NATIVE_TABLE": "表格"
        case "NATIVE_FORMULA": "公式"
        default: "附件"
        }
    }

    private static func decodedMarkerRun(payload: String, label: String) -> NativeRichTextFallbackRun? {
        guard let data = Data(base64Encoded: payload) else { return nil }
        switch label {
        case "图片":
            guard data.count <= maximumImageDataBytes,
                  let dataURL = String(data: data, encoding: .utf8),
                  let validated = validatedImageDataURL(dataURL)
            else { return nil }
            return .image(validated)
        case "表格":
            guard data.count <= maximumTableJSONBytes else { return nil }
            return .table(payload)
        case "公式":
            guard data.count <= maximumFormulaJSONBytes else { return nil }
            return .formula(payload)
        default:
            return nil
        }
    }

    private static func imageSource(in tag: String) -> String? {
        let pattern = #"(?i)\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: tag) else { continue }
            return decodeEntities(String(tag[range]))
        }
        return nil
    }

    private static func validatedImageDataURL(_ value: String) -> String? {
        guard value.utf8.count <= maximumImageDataBytes,
              let comma = value.firstIndex(of: ",")
        else { return nil }
        let header = value[..<comma].lowercased()
        guard header.hasPrefix("data:image/"), header.contains(";base64") else { return nil }
        let encoded = value[value.index(after: comma)...]
        guard let bytes = Data(base64Encoded: String(encoded)), bytes.count <= maximumImageDataBytes else { return nil }
        return value
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
