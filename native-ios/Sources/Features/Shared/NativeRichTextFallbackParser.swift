import Foundation

enum NativeRichTextFallbackRun: Equatable {
    case text(String)
    case image(String)
    case table(String)
    case formula(String)
    case placeholder(String)
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
    private static let skippedElements: Set<String> = ["head", "style", "script"]

    private struct ScannedTag {
        let raw: String
        let endIndex: String.Index
        let byteCount: Int
    }

    private struct ScannedMarker {
        let run: NativeRichTextFallbackRun?
        let placeholder: String?
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

            if html[cursor...].hasPrefix("[[NATIVE_IMAGE:")
                || html[cursor...].hasPrefix("[[NATIVE_TABLE:")
                || html[cursor...].hasPrefix("[[NATIVE_FORMULA:") {
                flushText()
                guard let marker = scanMarker(in: html, from: cursor) else {
                    appendPlaceholder("附件无法显示")
                    wasTruncated = true
                    break
                }
                scannedBytes += marker.byteCount
                cursor = marker.endIndex
                if let run = marker.run {
                    appendAttachment(run)
                } else {
                    appendPlaceholder(marker.placeholder ?? "附件无法显示")
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

    private static func scanMarker(in value: String, from start: String.Index) -> ScannedMarker? {
        let kinds: [(prefix: String, label: String)] = [
            ("[[NATIVE_IMAGE:", "图片"),
            ("[[NATIVE_TABLE:", "表格"),
            ("[[NATIVE_FORMULA:", "公式")
        ]
        guard let kind = kinds.first(where: { value[start...].hasPrefix($0.prefix) }) else { return nil }
        var cursor = start
        var byteCount = 0
        var marker = String()
        while cursor < value.endIndex, byteCount < maximumMarkerBytes {
            let character = value[cursor]
            marker.append(character)
            byteCount += String(character).utf8.count
            cursor = value.index(after: cursor)
            if marker.hasSuffix("]]" ) {
                let payloadStart = kind.prefix.count
                let payload = String(marker.dropFirst(payloadStart).dropLast(2))
                return ScannedMarker(
                    run: decodedMarkerRun(payload: payload, label: kind.label),
                    placeholder: kind.label,
                    endIndex: cursor,
                    byteCount: byteCount,
                    isClosed: true
                )
            }
        }
        return ScannedMarker(run: nil, placeholder: kind.label, endIndex: cursor, byteCount: byteCount, isClosed: false)
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
