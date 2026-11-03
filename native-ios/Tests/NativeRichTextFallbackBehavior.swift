import Foundation

@main
enum NativeRichTextFallbackBehavior {
    static func main() {
        verifyStyleAndScriptContentsAreSkipped()
        verifyAdjacentImageMarkersKeepTheirPositions()
        verifyTableFormulaAndMalformedAttachments()
        verifyInlineDataImageIsPreserved()
        verifyLongQuotedImageTagIsPreserved()
        verifyOversizedAndUnclosedImageTagsAreBounded()
    }

    private static func verifyStyleAndScriptContentsAreSkipped() {
        let html = "<html><head><style>.p.p1{color:red}</style><script>secret()</script></head><body><p>正文&amp;内容</p></body></html>"
        let runs = NativeRichTextFallbackParser.parse(html)
        let text = runs.compactMap { run -> String? in
            if case .text(let value) = run { return value }
            if case .placeholder(let value) = run { return value }
            return nil
        }.joined()
        precondition(text.contains("正文&内容"), "body copy should remain readable")
        precondition(!text.contains(".p.p1"), "Apple export CSS must not appear in preview text")
        precondition(!text.contains("secret()"), "script bodies must not appear in preview text")
    }

    private static func verifyAdjacentImageMarkersKeepTheirPositions() {
        let first = "data:image/png;base64,Zmlyc3Q="
        let second = "data:image/jpeg;base64,c2Vjb25k"
        let html = "A\(imageMarker(first))B\(imageMarker(second))C"
        let runs = NativeRichTextFallbackParser.parse(html)
        let imageValues = runs.compactMap { run -> String? in
            if case .image(let value) = run { return value }
            return nil
        }
        precondition(imageValues == [first, second], "both adjacent images and their order must be preserved")
        let order = runs.map { run -> String in
            switch run {
            case .text(let value): return value
            case .image: return "<image>"
            case .table: return "<table>"
            case .formula: return "<formula>"
            case .placeholder(let value): return "<\(value)>"
            }
        }
        precondition(order == ["A", "<image>", "B", "<image>", "C"], "images must stay between surrounding text")
    }

    private static func verifyTableFormulaAndMalformedAttachments() {
        let tableJSON = Data(#"{"cells":[["列一","列二"],["值一","值二"]]}"#.utf8).base64EncodedString()
        let formulaJSON = Data(#"{"preset":"增长率"}"#.utf8).base64EncodedString()
        let html = "前[[NATIVE_TABLE:\(tableJSON)]][[NATIVE_FORMULA:\(formulaJSON)]]后[[NATIVE_IMAGE:not-base64]]尾"
        let runs = NativeRichTextFallbackParser.parse(html)
        precondition(runs.contains(.table(tableJSON)), "native table marker should become a table run")
        precondition(runs.contains(.formula(formulaJSON)), "native formula marker should become a formula run")
        precondition(runs.contains(.placeholder("图片")), "malformed image data should get an explicit placeholder")
        let visibleText = runs.compactMap { run -> String? in
            if case .text(let value) = run { return value }
            if case .placeholder(let value) = run { return value }
            return nil
        }.joined()
        precondition(!visibleText.contains("not-base64"), "malformed marker payload must not leak into preview")
        precondition(visibleText.contains("前") && visibleText.contains("后") && visibleText.contains("尾"), "nearby text must survive attachment recovery")
    }

    private static func verifyInlineDataImageIsPreserved() {
        let dataURL = "data:image/png;base64,aW5saW5l"
        let html = "<p>前<img alt=\"题图 > 小图\" src=\"\(dataURL)\">后</p>"
        let runs = NativeRichTextFallbackParser.parse(html)
        precondition(runs.contains(.image(dataURL)), "inline data URI image should become an image run")
        let order = runs.map { run -> String in
            switch run {
            case .text(let value): return value
            case .image: return "<image>"
            case .table: return "<table>"
            case .formula: return "<formula>"
            case .placeholder(let value): return "<\(value)>"
            }
        }
        precondition(order == ["前", "<image>", "后\n"], "inline image should retain its surrounding text order")
    }

    private static func verifyLongQuotedImageTagIsPreserved() {
        let bytes = Data(repeating: 0xAB, count: 1_200)
        let dataURL = "data:image/png;base64,\(bytes.base64EncodedString())"
        let html = "<p>前<img alt=\"示意图 > 右侧\" src=\"\(dataURL)\">后</p>"
        precondition(html.utf8.count > 512, "fixture must exceed the regular tag budget")
        let runs = NativeRichTextFallbackParser.parse(html)
        precondition(runs.contains(.image(dataURL)), "long quoted inline data image should be preserved")
        let order = runs.map { run -> String in
            switch run {
            case .text(let value): return value
            case .image: return "<image>"
            case .table: return "<table>"
            case .formula: return "<formula>"
            case .placeholder(let value): return "<\(value)>"
            }
        }
        precondition(order == ["前", "<image>", "后\n"], "quoted greater-than characters must not end the image tag")
    }

    private static func verifyOversizedAndUnclosedImageTagsAreBounded() {
        let oversizedBytes = Data(repeating: 0xA5, count: 3_300_000)
        let oversizedDataURL = "data:image/png;base64,\(oversizedBytes.base64EncodedString())"
        let oversizedHTML = "<p>前<img alt=\"大图 > 示例\" src=\"\(oversizedDataURL)\">后</p>"
        let oversizedRuns = NativeRichTextFallbackParser.parse(oversizedHTML)
        precondition(oversizedRuns.contains(.placeholder("图片")), "oversized inline images should become placeholders")
        let oversizedVisibleText = visibleText(in: oversizedRuns)
        precondition(oversizedVisibleText.contains("前") && oversizedVisibleText.contains("后"), "closed oversized tags should preserve text on both sides")
        precondition(!oversizedVisibleText.contains(oversizedDataURL), "oversized base64 must not leak into body text")

        let unclosedDataURL = "data:image/png;base64,\(Data(repeating: 0x7F, count: 1_200).base64EncodedString())"
        let unclosedHTML = "<p>前<img alt=\"图 > 示例\" src=\"\(unclosedDataURL) 后"
        let unclosedRuns = NativeRichTextFallbackParser.parse(unclosedHTML)
        precondition(unclosedRuns.contains(.placeholder("图片")), "unclosed inline images should get a placeholder")
        let unclosedVisibleText = visibleText(in: unclosedRuns)
        precondition(unclosedVisibleText.contains("前"), "text before an unclosed tag should remain readable")
        precondition(!unclosedVisibleText.contains(unclosedDataURL), "unclosed base64 must not leak into body text")
    }

    private static func visibleText(in runs: [NativeRichTextFallbackRun]) -> String {
        runs.compactMap { run -> String? in
            if case .text(let value) = run { return value }
            if case .placeholder(let value) = run { return value }
            return nil
        }.joined()
    }

    private static func imageMarker(_ dataURL: String) -> String {
        let payload = Data(dataURL.utf8).base64EncodedString()
        return "[[NATIVE_IMAGE:\(payload)]]"
    }
}
