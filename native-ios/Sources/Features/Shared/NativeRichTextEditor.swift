import PhotosUI
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum RichTextToolbarMode: Equatable { case full, compact, minimal }

private enum RichTextMetrics {
    static let bodySize: CGFloat = 16
    static let heading2Size: CGFloat = 18
    static let heading1Size: CGFloat = 21
}

private enum NativeRichTextNoteFormatting {
    static let quoteKey = NSAttributedString.Key("com.kaogong.note.quote")
    static let listKey = NSAttributedString.Key("com.kaogong.note.list-item")
    static let blockKey = NSAttributedString.Key("com.kaogong.note.block")
    static let placeholder = "\u{200B}"
    static let quoteIndent: CGFloat = 22
    static let calloutInset: CGFloat = 16
    static let markerInset: CGFloat = 3

    static func isNeutralBackground(_ value: Any?) -> Bool {
        guard let color = value as? UIColor else { return false }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return max(red, green, blue) - min(red, green, blue) <= 0.06
        }
        var white: CGFloat = 0
        return color.getWhite(&white, alpha: &alpha)
    }

    static func removeNeutralQuoteBackground(in text: NSMutableAttributedString, range: NSRange) {
        text.enumerateAttribute(.backgroundColor, in: range) { value, run, _ in
            if isNeutralBackground(value) { text.removeAttribute(.backgroundColor, range: run) }
        }
    }

    static func isQuoted(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        attributes[quoteKey] as? Bool == true
    }

    static func isQuoted(_ attributed: NSAttributedString, at location: Int) -> Bool {
        guard attributed.length > 0 else { return false }
        let safeLocation = min(max(0, location), attributed.length - 1)
        return isQuoted(attributed.attributes(at: safeLocation, effectiveRange: nil))
    }

    static func block(in attributes: [NSAttributedString.Key: Any]) -> NativeRichTextNoteBlockKind? {
        if let raw = attributes[blockKey] as? String,
           let block = NativeRichTextNoteBlockKind(rawValue: raw) { return block }
        return isQuoted(attributes) ? .quote : nil
    }

    static func plainAttributes(from attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes
        result.removeValue(forKey: blockKey)
        result.removeValue(forKey: quoteKey)
        result.removeValue(forKey: listKey)
        result[.paragraphStyle] = NSParagraphStyle.default
        result.removeValue(forKey: .attachment)
        return result
    }

    static func applyBlock(_ block: NativeRichTextNoteBlockKind?, to text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        let currentStyle = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (currentStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        style.minimumLineHeight = 0
        style.maximumLineHeight = 0
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 0
        style.textLists = []
        style.tabStops = []
        text.removeAttribute(blockKey, range: range)
        text.removeAttribute(quoteKey, range: range)
        text.removeAttribute(listKey, range: range)
        if let block {
            text.addAttribute(blockKey, value: block.rawValue, range: range)
            if block.includesQuote {
                text.addAttribute(quoteKey, value: true, range: range)
            }
            style.headIndent = (block.includesQuote ? quoteIndent : 0) + (block.includesCallout ? calloutInset : 0)
            style.firstLineHeadIndent = style.headIndent
            style.tailIndent = block.includesCallout ? -calloutInset : 0
            style.paragraphSpacingBefore = block.includesCallout ? 8 : 2
            style.paragraphSpacing = block.includesCallout ? 8 : 5
            if block == .divider {
                style.minimumLineHeight = 16
                style.maximumLineHeight = 16
            }
        }
        text.addAttribute(.paragraphStyle, value: style, range: range)
    }
}

private struct NoteListMarker {
    enum Kind: Equatable {
        case bullet
        case number(Int)

        var prefix: String {
            switch self {
            case .bullet: "•\t"
            case let .number(number): "\(number).\t"
            }
        }

        var next: Kind {
            switch self {
            case .bullet: .bullet
            case let .number(number): .number(number + 1)
            }
        }
    }

    let kind: Kind
    let prefix: String

    private static let oldBullets = ["•", "◦", "▪︎", "▪", "■", "–"]
    private static let numberExpression = try? NSRegularExpression(pattern: #"^([0-9]{1,12})\.[ \t\u00a0]"#)

    static func read(in paragraph: NSAttributedString) -> Self? {
        guard paragraph.length > 0,
              paragraph.attribute(NativeRichTextNoteFormatting.listKey, at: 0, effectiveRange: nil) as? Bool == true else {
            return nil
        }
        return read(paragraph.string)
    }

    static func read(_ text: String) -> Self? {
        for symbol in oldBullets where text.hasPrefix(symbol) {
            if let gap = text.dropFirst(symbol.count).first, gap == " " || gap == "\t" || gap == "\u{00A0}" {
                return Self(kind: .bullet, prefix: symbol + String(gap))
            }
        }
        let source = text as NSString
        guard let match = numberExpression?.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
              let number = Int(source.substring(with: match.range(at: 1))) else { return nil }
        return Self(kind: .number(number), prefix: source.substring(with: match.range))
    }

    static func apply(_ kind: Kind, to paragraph: NSMutableAttributedString, oldMarker: NoteListMarker?) {
        let oldStyle = paragraph.length > 0
            ? paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            : nil
        let previousFirstIndent = oldStyle?.firstLineHeadIndent ?? 0
        let wasHanging = ((oldStyle?.headIndent ?? 0) - previousFirstIndent) >= 19
        let base = max(0, previousFirstIndent - (wasHanging ? NativeRichTextNoteFormatting.markerInset : 0))
        let offset = oldMarker?.prefix.utf16.count ?? 0
        if offset > 0 { paragraph.deleteCharacters(in: NSRange(location: 0, length: offset)) }
        let previousAttributes = paragraph.length > 0 ? paragraph.attributes(at: 0, effectiveRange: nil) : [:]
        var markerAttributes = NativeRichTextNoteFormatting.plainAttributes(from: previousAttributes)
        let size = kind == .bullet ? 14.0 : RichTextMetrics.bodySize
        let markerFont = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        markerAttributes[.font] = markerFont
        markerAttributes[.foregroundColor] = UIColor.label
        markerAttributes.removeValue(forKey: .link)
        markerAttributes.removeValue(forKey: .backgroundColor)
        markerAttributes.removeValue(forKey: .underlineStyle)
        markerAttributes.removeValue(forKey: .strikethroughStyle)
        paragraph.insert(NSAttributedString(string: kind.prefix, attributes: markerAttributes), at: 0)

        let style = (oldStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let markerWidth = (String(kind.prefix.dropLast()) as NSString).size(withAttributes: [.font: markerFont]).width
        style.firstLineHeadIndent = base + NativeRichTextNoteFormatting.markerInset
        style.headIndent = base + max(22, NativeRichTextNoteFormatting.markerInset + ceil(markerWidth) + 6)
        style.tailIndent = 0
        style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent, options: [:])]
        style.textLists = []
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 4
        let range = NSRange(location: 0, length: paragraph.length)
        paragraph.removeAttribute(NativeRichTextNoteFormatting.blockKey, range: range)
        paragraph.removeAttribute(NativeRichTextNoteFormatting.quoteKey, range: range)
        paragraph.addAttribute(NativeRichTextNoteFormatting.listKey, value: true, range: range)
        paragraph.addAttribute(.paragraphStyle, value: style, range: range)
    }
}

private enum RichTextCommandKind: Equatable {
    case bold, italic, underline, strike, indent, outdent, bullets, numbers, todos, divider
    case heading(RichTextHeading)
    case foreground(RichTextColor)
    case highlight
    case paragraphHighlight(RichTextColor)
    case border
    case quote
    case code
    case table(RichTextTable)
    case image(String, NativeRichTextInsertionTarget)
    case formula(RichTextFormula)
    case internalLink(RichTextInternalLink)
    case link(String)
    case undo, redo
}

struct RichTextInternalLink: Equatable, Identifiable {
    let collection: String
    let recordID: String
    let title: String
    var id: String { "\(collection):\(recordID)" }
    var url: URL? { URL(string: "kaogong-review://record/\(collection)/\(recordID)") }
}

private struct InternalLinkPickerRequest: Identifiable { let id = UUID() }

enum NativeRichTextTableAppearance: String, Equatable {
    case system
    case libraryContent
    case wordDetail

    fileprivate var usesHorizontalTableRules: Bool { self != .system }
    fileprivate var tableCellVerticalInset: CGFloat { self == .wordDetail ? 8 : 7 }
}

private struct PendingRichTextTableMarker {
    let marker: String
    let table: RichTextTable
}

private struct RichTextFormula: Codable, Equatable, Identifiable {
    var id = UUID()
    var preset: DataAnalysisFormulaPreset = .baseAmount
}

private enum DataAnalysisFormulaPreset: String, Codable, CaseIterable, Identifiable {
    case currentAmount = "现期量"
    case baseAmount = "基期量"
    case growthAmount = "增长量"
    case growthRate = "增长率"
    case proportion = "比重"
    case average = "平均数"
    case multiple = "倍数"
    case intervalGrowth = "间隔增长率"
    case proportionChange = "两期比重差"
    var id: String { rawValue }
    var expression: String {
        switch self {
        case .currentAmount: "现期量 = 基期量 × (1 + r)"
        case .baseAmount: "基期量 = 现期量 ÷ (1 + r)"
        case .growthAmount: "增长量 = 现期量 × r ÷ (1 + r)"
        case .growthRate: "增长率 = 增长量 ÷ 基期量"
        case .proportion: "比重 = 部分量 ÷ 整体量"
        case .average: "平均数 = 总量 ÷ 份数"
        case .multiple: "倍数 = A ÷ B"
        case .intervalGrowth: "间隔增长率 = r₁ + r₂ + r₁ × r₂"
        case .proportionChange: "两期比重差 = A ÷ B − a ÷ b"
        }
    }
}

private enum RichTextHeading: String, CaseIterable, Identifiable {
    case body = "正文", heading1 = "一级标题", heading2 = "二级标题"
    var id: String { rawValue }
    var size: CGFloat {
        self == .heading1 ? RichTextMetrics.heading1Size : self == .heading2 ? RichTextMetrics.heading2Size : RichTextMetrics.bodySize
    }
    var weight: UIFont.Weight { self == .body ? .regular : .semibold }
}

private enum RichTextColor: String, CaseIterable, Identifiable {
    case primary = "黑色", blue = "蓝色", red = "红色", green = "绿色"
    var id: String { rawValue }
    var uiColor: UIColor {
        switch self {
        case .primary: .label
        case .blue: .systemBlue
        case .red: .systemRed
        case .green: .systemGreen
        }
    }
}

private enum RichTextToolbarPage: Equatable {
    case main, format
}

private struct RichTextSelectionState: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStruckThrough = false
    var isHighlighted = false
    var isParagraphHighlighted = false
    var isQuoted = false
    var isBordered = false
    var isBulleted = false
    var isNumbered = false
    var isCode = false
    var heading: RichTextHeading = .body
    var foreground: RichTextColor = .primary
    var canUndo = false
    var canRedo = false
}

private struct RichTextKeyboardAccessoryState: Equatable {
    let selection: RichTextSelectionState
    let table: RichTextTable?
    let formula: RichTextFormula?
    let toolbarPage: RichTextToolbarPage
    let isEditing: Bool
    let showsFullTools: Bool
    let internalLinks: [RichTextInternalLink]
    let height: CGFloat
}

private struct RichTextCommand: Equatable {
    let id = UUID()
    let kind: RichTextCommandKind
    var imageCompletion: ((Result<Void, NativeRichTextEditorError>) -> Void)? = nil
    var tableCompletion: ((Result<Void, NativeRichTextEditorError>) -> Void)? = nil
    var tableEditTarget: RichTextTableEditTarget? = nil

    static func == (lhs: RichTextCommand, rhs: RichTextCommand) -> Bool {
        lhs.id == rhs.id
    }
}

struct NativeRichTextEditorSnapshot {
    let html: String
    let attributedText: NSAttributedString
    let selection: NSRange
    let documentRevision: UInt64
    let userEditRevision: UInt64

    var imageMarkers: [String] {
        var markers: [String] = []
        attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length)) { value, _, _ in
            if let image = value as? NativeImageAttachment {
                markers.append(image.marker)
            } else if let image = value as? NativeUnavailableImageAttachment {
                markers.append(image.marker)
            } else if let opaque = value as? NativeOpaqueRichTextAttachment,
                      !Self.imageMarkers(in: opaque.marker).isEmpty {
                markers.append(opaque.marker)
            }
        }
        return markers
    }

    var htmlImageMarkers: [String] {
        Self.imageMarkers(in: html)
    }

    var hasConsistentImageMarkers: Bool {
        imageMarkers == htmlImageMarkers
    }

    static func imageMarkers(in html: String) -> [String] {
        let pattern = #"\[\[NATIVE_IMAGE:[A-Za-z0-9+/=]+\]\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }
}

struct NativeRichTextImageInsertionReceipt: Equatable {
    let documentID: String?
    let sessionID: UUID
    let revision: UInt64
    let userEditRevision: UInt64
    let imageMarkers: [String]
}

enum NativeRichTextImageLimits {
    static let maximumEncodedBytes = 11 * 1024 * 1024
}

struct NativeRichTextInsertionTarget: Equatable {
    let documentID: String?
    let sessionID: UUID
    let range: NSRange
    let revision: UInt64
}

private struct RichTextTableEditTarget: Equatable {
    let documentID: String?
    let sessionID: UUID
    let attachmentInstanceID: UUID?
    let range: NSRange
    let revision: UInt64
}

private struct RichTextTableEditorRequest: Identifiable {
    let id = UUID()
    let table: RichTextTable
    let target: RichTextTableEditTarget
}

private final class NoteParagraphLayoutFragment: NSTextLayoutFragment {
    var showsPlaceholder = false

    private var paragraph: NSAttributedString? { (textElement as? NSTextParagraph)?.attributedString }

    private var drawingArea: CGRect {
        let lines = textLineFragments.reduce(CGRect.null) { $0.union($1.typographicBounds) }
        guard !lines.isNull else { return .null }
        let container = textLayoutManager?.textContainer
        let width = (container?.size.width ?? 0) - layoutFragmentFrame.minX - (container?.lineFragmentPadding ?? 0)
        let usableWidth = width.isFinite && width < 100_000 ? max(width, lines.width) : lines.width
        return CGRect(x: 0, y: lines.minY, width: max(1, usableWidth), height: max(16, lines.height))
    }

    override var renderingSurfaceBounds: CGRect {
        let area = drawingArea
        return area.isNull ? super.renderingSurfaceBounds : super.renderingSurfaceBounds.union(area.insetBy(dx: -1, dy: -8))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let area = drawingArea
        guard !area.isNull, let paragraph, paragraph.length > 0 else {
            super.draw(at: point, in: context)
            return
        }
        let attributes = paragraph.attributes(at: 0, effectiveRange: nil)
        let block = NativeRichTextNoteFormatting.block(in: attributes)
        let style = attributes[.paragraphStyle] as? NSParagraphStyle
        let frame = area.offsetBy(dx: point.x, dy: point.y)
        context.saveGState()
        if block?.includesCallout == true {
            context.setStrokeColor(UIColor.separator.cgColor)
            context.setLineWidth(0.8)
            let outline = CGRect(x: frame.minX + 0.5, y: frame.minY - 6,
                                 width: max(1, frame.width - 1), height: frame.height + 12)
            context.addPath(CGPath(roundedRect: outline, cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.strokePath()
        }
        if block?.includesQuote == true {
            let inset = block?.includesCallout == true ? NativeRichTextNoteFormatting.calloutInset : 0
            let ruleX = max(inset, (textLineFragments.first?.glyphOrigin.x ?? 0) - NativeRichTextNoteFormatting.quoteIndent)
            let quote = CGRect(x: frame.minX + ruleX, y: frame.minY + 1,
                               width: 3, height: max(4, frame.height - 2))
            context.setFillColor(UIColor.label.cgColor)
            context.fill(quote)
        }
        if block == .divider {
            context.setFillColor(UIColor.separator.cgColor)
            context.fill(CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: 0.75))
        }
        context.restoreGState()
        super.draw(at: point, in: context)

        guard showsPlaceholder, block != .divider else { return }
        let source = paragraph.string
        let list = attributes[NativeRichTextNoteFormatting.listKey] != nil ? NoteListMarker.read(source) : nil
        let text = list.map { String(source.dropFirst($0.prefix.count)) } ?? source
        guard text.replacingOccurrences(of: NativeRichTextNoteFormatting.placeholder, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let caption = list != nil ? "项目" : (block?.includesQuote == true ? "空白引用" : "")
        guard !caption.isEmpty else { return }
        UIGraphicsPushContext(context)
        (caption as NSString).draw(
            at: CGPoint(x: frame.minX + (style?.headIndent ?? 0), y: frame.minY),
            withAttributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize), .foregroundColor: UIColor.placeholderText]
        )
        UIGraphicsPopContext()
    }

    static func make(for element: NSTextElement, noteFormatting: Bool, editing: Bool) -> NSTextLayoutFragment {
        guard noteFormatting, let paragraph = element as? NSTextParagraph, paragraph.attributedString.length > 0 else {
            return NSTextLayoutFragment(textElement: element, range: nil)
        }
        let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        let hasEmptyListItem = editing && attributes[NativeRichTextNoteFormatting.listKey] != nil
            && paragraph.attributedString.string.contains(NativeRichTextNoteFormatting.placeholder)
        guard NativeRichTextNoteFormatting.block(in: attributes) != nil || hasEmptyListItem else {
            return NSTextLayoutFragment(textElement: element, range: nil)
        }
        let fragment = NoteParagraphLayoutFragment(textElement: element, range: nil)
        fragment.showsPlaceholder = editing
        return fragment
    }
}

struct NativeRichTextImageImportRequest: Equatable {
    let id: UUID
    let documentID: String?
    let sessionID: UUID
    var insertMenuDismissed = false
}

struct NativeRichTextMediaNotice: Equatable {
    let documentID: String?
    let message: String
}

enum NativeRichTextEditorError: LocalizedError {
    case editorSessionChanged
    case invalidSelection
    case imageAttachmentInvalid
    case tableTargetChanged
    case tablePayloadTooLarge

    var errorDescription: String? {
        switch self {
        case .editorSessionChanged: "笔记页面已切换，图片没有插入到其他题目。请重新打开图片选择器。"
        case .invalidSelection: "图片插入位置已失效，请重新选择插入位置后再试。"
        case .imageAttachmentInvalid: "图片无法生成附件，原笔记没有被修改。"
        case .tableTargetChanged: "附件位置已变化，当前输入仍保留。"
        case .tablePayloadTooLarge: "附件文字总量超过可保存范围，请缩短后再试。"
        }
    }
}

private enum NativeRichTextPhotoError: LocalizedError {
    case loadFailed(String)
    case noData
    case decodeFailed
    case encodeFailed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .loadFailed(let detail): "读取图片失败：\(detail)"
        case .noData: "没有读取到图片数据，笔记内容没有改变。"
        case .decodeFailed: "无法解码所选图片，笔记内容没有改变。"
        case .encodeFailed: "图片压缩失败，笔记内容没有改变。"
        case .tooLarge: "图片超过笔记附件大小限制（8 MB），请选更小的图片。"
        }
    }
}

private enum RichTextEditorAlert {
    case linkPrompt
    case imageError(String)
    case blockError(String)
}

@MainActor
struct NativeRichTextEditor: View {
    @Binding var html: String
    let minHeight: CGFloat
    var mode: RichTextToolbarMode = .full
    var documentStyle = false
    var noteFormatting = false
    var usesStabilizedInlineNoteMeasurement = false
    var tableAppearance: NativeRichTextTableAppearance = .system
    var focusOnAppear = false
    var initialSelectionOffset: Int? = nil
    var initialSelectionWidth: CGFloat? = nil
    var initialBlockCell: RichTextTable.Cell? = nil
    var preparedInitialHTML: String? = nil
    var preparedInitialAttributedText: NSAttributedString? = nil
    var editorSession: NativeRichTextEditorSession? = nil
    var editorDocumentID: String? = nil
    var editorSessionID: UUID? = nil
    var defersPhotoPickerToParent = true
    var internalLinks: [RichTextInternalLink] = []
    var onOpenInternalLink: ((RichTextInternalLink) -> Void)?
    var onFocusReady: ((UITextView) -> Void)?
    var onCaretChange: ((UITextView) -> Void)?
    @StateObject private var localEditorSession = NativeRichTextEditorSession()
    @State private var localEditorSessionID = UUID()
    @State private var command: RichTextCommand?
    @State private var activeAlert: RichTextEditorAlert?
    @State private var linkTarget = "https://"
    @State private var selectedTable: RichTextTable?
    @State private var tableEditorRequest: RichTextTableEditorRequest?
    @State private var tableEditTarget: RichTextTableEditTarget?
    @State private var pendingPhotoImportRequestID: UUID?
    @State private var selectedFormula: RichTextFormula?
    @State private var formulaEditor: RichTextFormula?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var internalLinkPicker: InternalLinkPickerRequest?
    @State private var isEditing = false
    @State private var toolbarPage: RichTextToolbarPage = .main
    @State private var selectionState = RichTextSelectionState()
    @State private var capturedPhotoTarget: NativeRichTextInsertionTarget?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var awaitingImageInsertion = false

    private var activeEditorSession: NativeRichTextEditorSession { editorSession ?? localEditorSession }
    private var activeEditorDocumentID: String? { editorDocumentID }
    private var activeEditorSessionID: UUID { editorSessionID ?? localEditorSessionID }
    private var usesDeferredPhotoPicker: Bool {
        defersPhotoPickerToParent && editorSession != nil && editorDocumentID != nil && editorSessionID != nil
    }

    private var activeAlertPresentation: Binding<Bool> {
        Binding(
            get: { activeAlert != nil },
            set: { isPresented in
                guard !isPresented, activeAlert != nil else { return }
                if case .linkPrompt? = activeAlert { activeEditorSession.setAuxiliaryPanelPresented(false) }
                activeAlert = nil
            }
        )
    }

    private var alertTitle: String {
        switch activeAlert {
        case .linkPrompt: "添加链接"
        case .blockError: "无法更新笔记附件"
        case .imageError, nil: "无法插入图片"
        }
    }

    private var alertMessage: String {
        switch activeAlert {
        case .linkPrompt: "选中文字后添加链接；没有选中文字时会直接插入链接地址。"
        case .imageError(let message), .blockError(let message): message
        case nil: ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RichTextTextView(
                html: $html,
                command: $command,
                selectedTable: $selectedTable,
                tableEditorRequest: $tableEditorRequest,
                tableEditTarget: $tableEditTarget,
                selectedFormula: $selectedFormula,
                isEditing: $isEditing,
                selectionState: $selectionState,
                internalLinks: internalLinks,
                onOpenInternalLink: onOpenInternalLink,
                onFocusReady: onFocusReady,
                onCaretChange: onCaretChange,
                onInlineBlockError: { activeAlert = .blockError($0) },
                keyboardAccessory: AnyView(keyboardToolbar),
                keyboardAccessoryHeight: keyboardAccessoryHeight,
                keyboardAccessoryState: RichTextKeyboardAccessoryState(
                    selection: selectionState,
                    table: selectedTable,
                    formula: selectedFormula,
                    toolbarPage: toolbarPage,
                    isEditing: isEditing,
                    showsFullTools: mode == .full,
                    internalLinks: internalLinks,
                    height: keyboardAccessoryHeight
                ),
                growsWithContent: documentStyle,
                tableAppearance: tableAppearance,
                noteFormatting: noteFormatting,
                usesStabilizedInlineNoteMeasurement: usesStabilizedInlineNoteMeasurement,
                minimumContentHeight: documentStyle ? minHeight : 0,
                focusOnAppear: focusOnAppear,
                initialSelectionOffset: initialSelectionOffset,
                initialSelectionWidth: initialSelectionWidth,
                initialBlockCell: initialBlockCell,
                preparedInitialHTML: preparedInitialHTML,
                preparedInitialAttributedText: preparedInitialAttributedText,
                editorSession: activeEditorSession,
                editorDocumentID: activeEditorDocumentID,
                editorSessionID: activeEditorSessionID,
                usesLazyHTMLInitialization: editorSession != nil
            )
                .modifier(NativeDirectionalTextFieldNavigation(
                    isEnabled: !(noteFormatting && tableAppearance == .libraryContent)
                ))
                .frame(minHeight: documentStyle ? nil : minHeight, alignment: .topLeading)
                .padding(.horizontal, documentStyle ? 0 : 5)
        }
        .background(Color.primary.opacity(documentStyle ? 0 : 0.035), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius).stroke(Color.primary.opacity(documentStyle ? 0 : 0.07), lineWidth: 0.7))
        .sheet(item: $tableEditorRequest, onDismiss: {
            tableEditTarget = nil
            selectedTable = nil
            activeEditorSession.setAuxiliaryPanelPresented(false)
        }) { request in
            RichTextTableEditor(initial: request.table, appearance: tableAppearance) { updated, completion in
                command = RichTextCommand(
                    kind: .table(updated),
                    tableCompletion: completion,
                    tableEditTarget: request.target
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $formulaEditor, onDismiss: { activeEditorSession.setAuxiliaryPanelPresented(false) }) { formula in
            DataAnalysisFormulaPicker(initial: formula) { updated in
                command = RichTextCommand(kind: .formula(updated))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $internalLinkPicker, onDismiss: { activeEditorSession.setAuxiliaryPanelPresented(false) }) { _ in
            RichTextInternalLinkPicker(links: internalLinks) { link in
                command = RichTextCommand(kind: .internalLink(link))
            }
            .presentationDetents([.medium, .large])
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoLoadTask?.cancel()
            photoLoadTask = Task { @MainActor in await loadAndInsertPhoto(item) }
        }
        .onChange(of: showPhotoPicker) { _, presented in
            guard !presented else { return }
            Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                if photoItem == nil, photoLoadTask == nil {
                    if !awaitingImageInsertion {
                        if let sessionID = capturedPhotoTarget?.sessionID {
                            activeEditorSession.setMediaOperationInProgress(false, sessionID: sessionID)
                        }
                        capturedPhotoTarget = nil
                    }
                }
            }
        }
        .alert(alertTitle, isPresented: activeAlertPresentation) {
            switch activeAlert {
            case .linkPrompt:
                TextField("https://example.com", text: $linkTarget)
                    .modifier(NativeDirectionalTextFieldNavigation())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("取消", role: .cancel) {}
                Button("添加") {
                    let value = linkTarget.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    command = RichTextCommand(kind: .link(value))
                    linkTarget = "https://"
                }
            case .imageError, .blockError, nil:
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            activeEditorSession.activate(documentID: activeEditorDocumentID, sessionID: activeEditorSessionID)
        }
        .onDisappear {
            if activeEditorSession.isMediaOperationInProgress {
                activeEditorSession.cancelMediaOperation(
                    sessionID: activeEditorSessionID,
                    message: "切换题目时已取消图片插入，没有把图片写入其他题目。"
                )
            }
            photoLoadTask?.cancel()
            activeEditorSession.deactivate(sessionID: activeEditorSessionID)
        }
        .onChange(of: isEditing) { _, active in
            if !active { toolbarPage = .main }
        }
    }

    private var keyboardAccessoryHeight: CGFloat {
        58
    }

    private var keyboardToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                toolbarStrip
                    .frame(maxWidth: .infinity, alignment: .leading)
                toolbarDivider
                toolbarButton("keyboard.chevron.compact.down", label: "收起键盘") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
        .padding(.horizontal, 14)
        .padding(.top, 3)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Color.clear)
        .disabled(activeEditorSession.isInputLocked || activeEditorSession.isMediaOperationInProgress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("笔记格式栏")
    }

    @ViewBuilder private var toolbarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                formatButton(.bold, "bold", active: selectionState.isBold)
                formatButton(.underline, "underline", active: selectionState.isUnderlined)
                if mode == .full {
                    colorMenu
                    formatButton(.numbers, "list.number", active: selectionState.isNumbered, label: "有序列表")
                    formatButton(.bullets, "list.bullet", active: selectionState.isBulleted, label: "无序列表")
                    formatButton(.quote, "text.quote", active: selectionState.isQuoted, label: "引用")
                    formatButton(.border, "rectangle", active: selectionState.isBordered, label: noteFormatting ? "标注" : "边框")
                    formatButton(.indent, "increase.indent")
                    formatButton(.outdent, "decrease.indent")
                }
                formatButton(.undo, "arrow.uturn.backward", disabled: !selectionState.canUndo)
                formatButton(.redo, "arrow.uturn.forward", disabled: !selectionState.canRedo)
                if mode == .full {
                    paragraphMenu
                    insertMenu
                }
            }
        }
    }

    @MainActor
    private func openPhotoPicker() {
        guard activeEditorSession.canFinishEditing else {
            presentImageError("请先完成输入并关闭当前编辑面板，再插入图片。")
            return
        }
        guard let target = activeEditorSession.captureInsertionTarget(
            expectedDocumentID: activeEditorDocumentID,
            expectedSessionID: activeEditorSessionID
        ) else {
            presentImageError("无法确定当前笔记中的插入位置，请点选正文位置后重试。")
            return
        }
        capturedPhotoTarget = target
        activeEditorSession.setMediaOperationInProgress(true)
        showPhotoPicker = true
    }

    @MainActor
    private func loadAndInsertPhoto(_ item: PhotosPickerItem) async {
        let target = capturedPhotoTarget
        defer {
            photoItem = nil
            photoLoadTask = nil
        }
        do {
            guard let target else { throw NativeRichTextEditorError.invalidSelection }
            let sourceData: Data
            do {
                guard let loaded = try await item.loadTransferable(type: Data.self) else {
                    throw NativeRichTextPhotoError.noData
                }
                sourceData = loaded
            } catch let error as NativeRichTextEditorError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw NativeRichTextPhotoError.loadFailed(error.localizedDescription)
            }
            try Task.checkCancellation()
            guard activeEditorSession.matches(target) else {
                throw NativeRichTextEditorError.editorSessionChanged
            }
            guard sourceData.count <= 8 * 1024 * 1024 else {
                throw NativeRichTextPhotoError.tooLarge
            }
            guard let image = UIImage(data: sourceData) else {
                throw NativeRichTextPhotoError.decodeFailed
            }
            guard let compressed = image.jpegData(compressionQuality: 0.82) else {
                throw NativeRichTextPhotoError.encodeFailed
            }
            guard compressed.count <= 8 * 1024 * 1024 else {
                throw NativeRichTextPhotoError.tooLarge
            }
            let dataURL = "data:image/jpeg;base64,\(compressed.base64EncodedString())"
            guard dataURL.utf8.count <= NativeRichTextImageLimits.maximumEncodedBytes else {
                throw NativeRichTextPhotoError.tooLarge
            }
            awaitingImageInsertion = true
            command = RichTextCommand(
                kind: .image(dataURL, target),
                imageCompletion: { result in
                    self.awaitingImageInsertion = false
                    self.capturedPhotoTarget = nil
                    self.activeEditorSession.setMediaOperationInProgress(false, sessionID: target.sessionID)
                    if case .failure(let error) = result { self.presentImageError(error.localizedDescription) }
                }
            )
        } catch is CancellationError {
            capturedPhotoTarget = nil
            if let target { activeEditorSession.setMediaOperationInProgress(false, sessionID: target.sessionID) }
        } catch {
            capturedPhotoTarget = nil
            if let target { activeEditorSession.setMediaOperationInProgress(false, sessionID: target.sessionID) }
            presentImageError(error.localizedDescription)
        }
    }

    @MainActor
    private func presentImageError(_ message: String) {
        activeAlert = .imageError(message)
    }

    private var insertMenu: some View {
        Menu {
            Button {
                if usesDeferredPhotoPicker { requestParentPhotoImport() }
                else { openPhotoPicker() }
            } label: { Label("图片", systemImage: "photo") }
            Button {
                if noteFormatting && tableAppearance == .libraryContent {
                    insertInlineBlock(RichTextTable())
                    return
                }
                activeEditorSession.commitCompositionIfNeeded()
                let target: RichTextTableEditTarget?
                if selectedTable != nil {
                    target = tableEditTarget
                } else {
                    target = activeEditorSession.captureTableInsertionTarget(
                        expectedDocumentID: activeEditorDocumentID,
                        expectedSessionID: activeEditorSessionID
                    )
                }
                guard let target else { return }
                tableEditorRequest = RichTextTableEditorRequest(
                    table: selectedTable ?? RichTextTable(),
                    target: target
                )
                activeEditorSession.setAuxiliaryPanelPresented(true)
            } label: { Label("表格", systemImage: "tablecells") }
            if noteFormatting && tableAppearance == .libraryContent {
                Button {
                    insertInlineBlock(RichTextTable.flowchart())
                } label: { Label("流程图", systemImage: "point.3.connected.trianglepath.dotted") }
            }
            Button { run(.divider) } label: { Label("分割线", systemImage: "minus") }
            Button {
                activeEditorSession.setAuxiliaryPanelPresented(true)
                formulaEditor = selectedFormula ?? RichTextFormula()
            } label: { Label("公式", systemImage: "function") }
            Button {
                activeEditorSession.setAuxiliaryPanelPresented(true)
                activeAlert = .linkPrompt
            } label: { Label("网页链接", systemImage: "link") }
            if !internalLinks.isEmpty {
                Button {
                    activeEditorSession.setAuxiliaryPanelPresented(true)
                    internalLinkPicker = InternalLinkPickerRequest()
                } label: { Label("关联笔记", systemImage: "link.circle") }
            }
        } label: {
            toolbarImage("plus")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("插入")
    }

    @MainActor
    private func requestParentPhotoImport() {
        guard let requestID = activeEditorSession.requestImageImport(
            expectedDocumentID: activeEditorDocumentID,
            expectedSessionID: activeEditorSessionID
        ) else {
            presentImageError("当前已有插入操作，请完成后再试。")
            return
        }
        pendingPhotoImportRequestID = requestID
        Task { @MainActor in
            await Task.yield()
            guard pendingPhotoImportRequestID == requestID else { return }
            pendingPhotoImportRequestID = nil
            activeEditorSession.markImageImportMenuDismissed(requestID: requestID)
        }
    }

    private func insertInlineBlock(_ block: RichTextTable) {
        activeEditorSession.commitCompositionIfNeeded()
        guard !activeEditorSession.isComposingText,
              let target = activeEditorSession.captureTableInsertionTarget(
                expectedDocumentID: activeEditorDocumentID,
                expectedSessionID: activeEditorSessionID
              ) else { return }
        command = RichTextCommand(kind: .table(block), tableCompletion: { result in
            if case .failure = result { activeAlert = .blockError("插入位置已变化，请在正文里重新点选。") }
        }, tableEditTarget: target)
    }

    private var paragraphMenu: some View {
        Menu {
            ForEach(RichTextHeading.allCases) { heading in
                Button { run(.heading(heading)) } label: {
                    if selectionState.heading == heading { Label(heading.rawValue, systemImage: "checkmark") }
                    else { Text(heading.rawValue) }
                }
            }
            Divider()
            Button { run(.quote) } label: { Label("引用", systemImage: "text.quote") }
            Button { run(.bullets) } label: { Label("无序列表", systemImage: "list.bullet") }
            Button { run(.numbers) } label: { Label("有序列表", systemImage: "list.number") }
            if noteFormatting {
                Button { run(.border) } label: { Label("标注", systemImage: "rectangle") }
            }
            Button { run(.todos) } label: { Label("待办列表", systemImage: "checklist") }
            Button { run(.indent) } label: { Label("增加缩进", systemImage: "increase.indent") }
            Button { run(.outdent) } label: { Label("减少缩进", systemImage: "decrease.indent") }
        } label: {
            toolbarImage("textformat", active: selectionState.heading != .body || selectionState.isQuoted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("标题与段落")
    }

    private var colorMenu: some View {
        Menu {
            Section("文字颜色") {
            ForEach(RichTextColor.allCases) { color in
                Button {
                    command = RichTextCommand(kind: .foreground(color))
                } label: {
                    if selectionState.foreground == color { Label(color.rawValue, systemImage: "checkmark") }
                    else { Text(color.rawValue) }
                }
            }
            }
            Section("文字背景") {
                Button { run(.highlight) } label: { Label("黄色文字背景", systemImage: selectionState.isHighlighted ? "checkmark" : "highlighter") }
            }
            Section("整行背景") {
                ForEach(RichTextColor.allCases.filter { $0 != .primary }) { color in
                    Button { run(.paragraphHighlight(color)) } label: { Text(color.rawValue) }
                }
                Button("清除整行背景") { run(.paragraphHighlight(.primary)) }
            }
        } label: {
            toolbarImage("paintpalette", active: selectionState.foreground != .primary || selectionState.isHighlighted || selectionState.isParagraphHighlighted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("颜色")
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 21).padding(.horizontal, 2)
    }

    private func run(_ kind: RichTextCommandKind) {
        command = RichTextCommand(kind: kind)
    }

    private func formatButton(_ kind: RichTextCommandKind, _ image: String, active: Bool = false, disabled: Bool = false, label: String? = nil) -> some View {
        toolbarButton(image, active: active, disabled: disabled, label: label) { run(kind) }
    }

    private func toolbarButton(_ image: String, active: Bool = false, disabled: Bool = false, label: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolbarImage(image, active: active) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.3 : 1)
            .accessibilityLabel(label ?? image)
    }

    private func toolbarImage(_ image: String, active: Bool = false) -> some View {
        Image(systemName: image)
            .font(.system(size: 15, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.78))
            .frame(width: 36, height: 34)
            .background(active ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

@MainActor
final class NativeRichTextEditorSession: ObservableObject {
    typealias EndEditingHandler = (@escaping (String?) -> Void) -> Void

    @Published private(set) var isMediaOperationInProgress = false
    @Published private(set) var isAuxiliaryPanelPresented = false
    @Published private(set) var isComposingText = false
    @Published private(set) var isInputLocked = false
    @Published private(set) var mediaNotice: NativeRichTextMediaNotice?
    @Published private(set) var imageImportRequest: NativeRichTextImageImportRequest?
    @Published private(set) var imageInsertionReceipts: [NativeRichTextImageInsertionReceipt] = []
    @Published private(set) var hasUnsavedImageInsertion = false
    private var confirmedImageInsertionRevision: UInt64 = 0

    private var latestHTMLReader: (() -> String?)?
    private var latestAttributedTextReader: (() -> NSAttributedString?)?
    private var snapshotReader: (() -> NativeRichTextEditorSnapshot?)?
    private var selectionReader: (() -> NSRange?)?
    private var tableInsertionTargetReader: (() -> RichTextTableEditTarget?)?
    private var compositionCommitHandler: (() -> Void)?
    private var imageInsertionHandler: ((String, NativeRichTextInsertionTarget, @escaping (Result<Void, NativeRichTextEditorError>) -> Void) -> Void)?
    private var endEditingHandler: EndEditingHandler?
    private(set) var documentID: String?
    private(set) var sessionID: UUID?

    var canFinishEditing: Bool {
        !isMediaOperationInProgress && !isAuxiliaryPanelPresented && !isComposingText && !isInputLocked
    }

    func activate(documentID: String?, sessionID: UUID) {
        if self.sessionID != sessionID {
            isMediaOperationInProgress = false
            isAuxiliaryPanelPresented = false
            isComposingText = false
            isInputLocked = false
            imageImportRequest = nil
            imageInsertionReceipts = []
            hasUnsavedImageInsertion = false
            confirmedImageInsertionRevision = 0
        }
        self.documentID = documentID
        self.sessionID = sessionID
    }

    func deactivate(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        disconnect()
        documentID = nil
        self.sessionID = nil
        isMediaOperationInProgress = false
        isAuxiliaryPanelPresented = false
        isComposingText = false
        isInputLocked = false
        imageImportRequest = nil
        imageInsertionReceipts = []
        hasUnsavedImageInsertion = false
        confirmedImageInsertionRevision = 0
    }

    func latestHTML() -> String? { latestHTMLReader?() }
    func latestAttributedText() -> NSAttributedString? { latestAttributedTextReader?() }
    func captureSnapshot() -> NativeRichTextEditorSnapshot? { snapshotReader?() }

    func captureInsertionTarget(
        expectedDocumentID: String?,
        expectedSessionID: UUID
    ) -> NativeRichTextInsertionTarget? {
        guard documentID == expectedDocumentID,
              sessionID == expectedSessionID,
              let range = selectionReader?(),
              let revision = snapshotReader?()?.documentRevision else { return nil }
        return NativeRichTextInsertionTarget(
            documentID: documentID,
            sessionID: expectedSessionID,
            range: range,
            revision: revision
        )
    }

    fileprivate func captureTableInsertionTarget(
        expectedDocumentID: String?,
        expectedSessionID: UUID
    ) -> RichTextTableEditTarget? {
        guard documentID == expectedDocumentID, sessionID == expectedSessionID else { return nil }
        return tableInsertionTargetReader?()
    }

    func matches(_ target: NativeRichTextInsertionTarget) -> Bool {
        documentID == target.documentID && sessionID == target.sessionID
    }

    func recordSuccessfulImageInsertion(_ receipt: NativeRichTextImageInsertionReceipt) {
        guard documentID == receipt.documentID, sessionID == receipt.sessionID else { return }
        imageInsertionReceipts.append(receipt)
        hasUnsavedImageInsertion = true
    }

    func confirmImageInsertionsSaved(documentID: String?, sessionID: UUID, revision: UInt64) {
        guard self.documentID == documentID, self.sessionID == sessionID,
              let latestReceipt = imageInsertionReceipts
                .filter({ $0.documentID == documentID && $0.sessionID == sessionID })
                .max(by: { $0.revision < $1.revision }),
              latestReceipt.revision <= revision else { return }
        confirmedImageInsertionRevision = max(confirmedImageInsertionRevision, revision)
        hasUnsavedImageInsertion = latestReceipt.revision > confirmedImageInsertionRevision
    }

    func insertionReceipts(forDocumentID documentID: String?, sessionID: UUID) -> [NativeRichTextImageInsertionReceipt] {
        imageInsertionReceipts.filter { $0.documentID == documentID && $0.sessionID == sessionID }
    }

    func cancelMediaOperation(sessionID: UUID, message: String) {
        guard self.sessionID == sessionID, isMediaOperationInProgress else { return }
        mediaNotice = NativeRichTextMediaNotice(documentID: documentID, message: message)
        imageImportRequest = nil
        isMediaOperationInProgress = false
    }

    @discardableResult
    func requestImageImport(expectedDocumentID: String?, expectedSessionID: UUID) -> UUID? {
        guard documentID == expectedDocumentID,
              sessionID == expectedSessionID,
              !isMediaOperationInProgress,
              imageImportRequest == nil else { return nil }
        let request = NativeRichTextImageImportRequest(
            id: UUID(),
            documentID: documentID,
            sessionID: expectedSessionID
        )
        imageImportRequest = request
        isMediaOperationInProgress = true
        return request.id
    }

    func markImageImportMenuDismissed(requestID: UUID) {
        guard var request = imageImportRequest, request.id == requestID else { return }
        request.insertMenuDismissed = true
        imageImportRequest = request
        compositionCommitHandler?()
    }

    func commitCompositionIfNeeded() {
        compositionCommitHandler?()
    }

    func captureInsertionTarget(for request: NativeRichTextImageImportRequest) -> NativeRichTextInsertionTarget? {
        guard imageImportRequest == request,
              request.insertMenuDismissed,
              !isComposingText else { return nil }
        return captureInsertionTarget(
            expectedDocumentID: request.documentID,
            expectedSessionID: request.sessionID
        )
    }

    func insertImage(
        _ dataURL: String,
        target: NativeRichTextInsertionTarget,
        completion: @escaping (Result<Void, NativeRichTextEditorError>) -> Void
    ) {
        guard matches(target), let imageInsertionHandler else {
            completion(.failure(.editorSessionChanged))
            return
        }
        imageInsertionHandler(dataURL, target, completion)
    }

    func finishImageImport(requestID: UUID) {
        guard imageImportRequest?.id == requestID else { return }
        imageImportRequest = nil
        isMediaOperationInProgress = false
    }

    func setMediaNotice(_ message: String, documentID: String?) {
        mediaNotice = NativeRichTextMediaNotice(documentID: documentID, message: message)
    }

    func clearMediaNotice(for documentID: String?) {
        guard mediaNotice?.documentID == documentID else { return }
        mediaNotice = nil
    }

    func setMediaOperationInProgress(_ value: Bool) { isMediaOperationInProgress = value }
    func setMediaOperationInProgress(_ value: Bool, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        isMediaOperationInProgress = value
    }
    func setAuxiliaryPanelPresented(_ value: Bool) { isAuxiliaryPanelPresented = value }
    func setComposingText(_ value: Bool) {
        guard isComposingText != value else { return }
        isComposingText = value
    }
    func setInputLocked(_ value: Bool) { isInputLocked = value }

    func endEditing(_ completion: @escaping (String?) -> Void) {
        if let endEditingHandler {
            endEditingHandler(completion)
        } else {
            completion(latestHTML())
        }
    }

    fileprivate func connect(
        latestHTMLReader: @escaping () -> String?,
        latestAttributedTextReader: @escaping () -> NSAttributedString?,
        snapshotReader: @escaping () -> NativeRichTextEditorSnapshot?,
        selectionReader: @escaping () -> NSRange?,
        tableInsertionTargetReader: @escaping () -> RichTextTableEditTarget?,
        compositionCommitHandler: @escaping () -> Void,
        imageInsertionHandler: @escaping (String, NativeRichTextInsertionTarget, @escaping (Result<Void, NativeRichTextEditorError>) -> Void) -> Void,
        endEditingHandler: @escaping EndEditingHandler
    ) {
        self.latestHTMLReader = latestHTMLReader
        self.latestAttributedTextReader = latestAttributedTextReader
        self.snapshotReader = snapshotReader
        self.selectionReader = selectionReader
        self.tableInsertionTargetReader = tableInsertionTargetReader
        self.compositionCommitHandler = compositionCommitHandler
        self.imageInsertionHandler = imageInsertionHandler
        self.endEditingHandler = endEditingHandler
    }

    fileprivate func disconnect() {
        latestHTMLReader = nil
        latestAttributedTextReader = nil
        snapshotReader = nil
        selectionReader = nil
        tableInsertionTargetReader = nil
        compositionCommitHandler = nil
        imageInsertionHandler = nil
        endEditingHandler = nil
    }
}

@MainActor
struct NativeRichTextDisplay: UIViewRepresentable {
    let html: String
    var minHeight: CGFloat = 0
    var tableAppearance: NativeRichTextTableAppearance = .system
    var noteFormatting = false
    var usesStabilizedInlineNoteMeasurement = false
    var requiresPreparedSnapshot = false
    var accessibilityIdentifier: String? = nil
    var onFallback: (() -> Void)? = nil
    var onTapTextOffset: ((Int, NSAttributedString, CGFloat, RichTextTable.Cell?) -> Void)? = nil
    private var preparedSnapshot: NativeRichTextDisplayRenderResult?
    private var renderVersion: String?

    private var sizesTablesToAvailableWidth: Bool {
        tableAppearance == .wordDetail || (noteFormatting && tableAppearance == .libraryContent)
    }

    init(
        html: String,
        minHeight: CGFloat = 0,
        tableAppearance: NativeRichTextTableAppearance = .system,
        accessibilityIdentifier: String? = nil,
        noteFormatting: Bool = false,
        requiresPreparedSnapshot: Bool = false,
        onFallback: (() -> Void)? = nil,
        onTapTextOffset: ((Int, NSAttributedString, CGFloat, RichTextTable.Cell?) -> Void)? = nil
    ) {
        self.html = html
        self.minHeight = minHeight
        self.tableAppearance = tableAppearance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.noteFormatting = noteFormatting
        self.requiresPreparedSnapshot = requiresPreparedSnapshot
        self.onFallback = onFallback
        self.onTapTextOffset = onTapTextOffset
        preparedSnapshot = nil
        renderVersion = nil
    }

    init(
        html: String,
        preparedSnapshot: NativeRichTextDisplayRenderResult,
        renderVersion: String,
        minHeight: CGFloat = 0,
        tableAppearance: NativeRichTextTableAppearance = .system,
        accessibilityIdentifier: String? = nil,
        noteFormatting: Bool = false,
        requiresPreparedSnapshot: Bool = false,
        onFallback: (() -> Void)? = nil,
        onTapTextOffset: ((Int, NSAttributedString, CGFloat, RichTextTable.Cell?) -> Void)? = nil
    ) {
        self.html = html
        self.minHeight = minHeight
        self.tableAppearance = tableAppearance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.noteFormatting = noteFormatting
        self.requiresPreparedSnapshot = requiresPreparedSnapshot
        self.onFallback = onFallback
        self.onTapTextOffset = onTapTextOffset
        self.preparedSnapshot = preparedSnapshot
        self.renderVersion = renderVersion
    }

    @MainActor
    final class Coordinator: NSObject, NSTextLayoutManagerDelegate {
        var parent: NativeRichTextDisplay
        var lastHTML = ""
        var lastRenderVersion: String?
        var lastTableAppearance: NativeRichTextTableAppearance = .system
        var lastNoteFormatting = false
        var lastRequiresPreparedSnapshot = false
        var lastTableDisplayWidth: CGFloat?
        var fallbackReportedHTML: String?

        init(parent: NativeRichTextDisplay) {
            self.parent = parent
            super.init()
        }

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            NoteParagraphLayoutFragment.make(for: textElement, noteFormatting: parent.noteFormatting, editing: false)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard (!parent.requiresPreparedSnapshot || parent.preparedSnapshot != nil),
                  let view = recognizer.view as? UITextView, recognizer.state == .ended else { return }
            let point = recognizer.location(in: view)
            guard let position = view.closestPosition(to: point) else { return }
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            let snapshot = view.attributedText.map { $0.copy() as? NSAttributedString ?? $0 }
                ?? NSAttributedString(string: "")
            if parent.noteFormatting, parent.tableAppearance == .libraryContent,
               let hit = NativeTableAttachment.hitTest(point, in: view, near: offset) {
                parent.onTapTextOffset?(hit.range.location, snapshot, view.bounds.width, hit.cell)
            } else {
                parent.onTapTextOffset?(max(0, min(offset, snapshot.length)), snapshot, view.bounds.width, nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = accessibilityIdentifier
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = onTapTextOffset != nil
            && (!requiresPreparedSnapshot || preparedSnapshot != nil)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if onTapTextOffset != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false
            view.addGestureRecognizer(tap)
        }
        applyContent(to: view, coordinator: context.coordinator)
        context.coordinator.lastHTML = html
        context.coordinator.lastRenderVersion = renderVersion
        context.coordinator.lastTableAppearance = tableAppearance
        context.coordinator.lastNoteFormatting = noteFormatting
        context.coordinator.lastRequiresPreparedSnapshot = requiresPreparedSnapshot
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = accessibilityIdentifier
        view.isUserInteractionEnabled = onTapTextOffset != nil
            && (!requiresPreparedSnapshot || preparedSnapshot != nil)
        guard context.coordinator.lastHTML != html
                || context.coordinator.lastRenderVersion != renderVersion
                || context.coordinator.lastTableAppearance != tableAppearance
                || context.coordinator.lastNoteFormatting != noteFormatting
                || context.coordinator.lastRequiresPreparedSnapshot != requiresPreparedSnapshot else { return }
        applyContent(to: view, coordinator: context.coordinator)
        context.coordinator.lastHTML = html
        context.coordinator.lastRenderVersion = renderVersion
        context.coordinator.lastTableAppearance = tableAppearance
        context.coordinator.lastNoteFormatting = noteFormatting
        context.coordinator.lastRequiresPreparedSnapshot = requiresPreparedSnapshot
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        var tableWidth = max(80, floor(width))
        if tableAppearance == .wordDetail {
            tableWidth = min(tableWidth, NativeTableAttachment.defaultDisplayWidth)
        }
        if sizesTablesToAvailableWidth,
           context.coordinator.lastTableDisplayWidth != tableWidth, let content = uiView.attributedText {
            context.coordinator.lastTableDisplayWidth = tableWidth
            uiView.attributedText = NativeRichTextDisplayRenderer.applyingTableAppearance(
                to: content, appearance: tableAppearance, displayWidth: tableWidth
            )
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: 65_536))
        let height = fitting.height.isFinite ? max(minHeight, ceil(fitting.height)) : minHeight
        return CGSize(width: width, height: height)
    }

    private func applyContent(to view: UITextView, coordinator: Coordinator) {
        let rendered: NativeRichTextDisplayRenderResult
        if let preparedSnapshot {
            rendered = preparedSnapshot
        } else if requiresPreparedSnapshot {
            rendered = NativeRichTextDisplayRenderResult(
                attributedText: NSAttributedString(string: ""),
                usedSafeFallback: false
            )
        } else {
            rendered = NativeRichTextDisplayRenderer.render(
                html,
                tableAppearance: tableAppearance,
                noteFormatting: noteFormatting,
                cleanLegacyInjectedSpacing: noteFormatting
            )
        }
        let withTables = NativeRichTextDisplayRenderer.applyingTableAppearance(
            to: rendered.attributedText,
            appearance: tableAppearance,
            displayWidth: sizesTablesToAvailableWidth ? coordinator.lastTableDisplayWidth : nil
        )
        let displayed = tableAppearance == .wordDetail
            ? NativeRichTextDisplayRenderer.applyingWordDetailSpacing(to: withTables, usedSafeFallback: rendered.usedSafeFallback)
            : withTables
        view.attributedText = displayed
        view.accessibilityLabel = displayed.string
        guard rendered.usedSafeFallback, coordinator.fallbackReportedHTML != html else { return }
        coordinator.fallbackReportedHTML = html
        DispatchQueue.main.async { onFallback?() }
    }
}

@MainActor
struct NativeRichTextDisplayRenderResult {
    let attributedText: NSAttributedString
    let usedSafeFallback: Bool
}

@MainActor
enum NativeRichTextDisplayRenderer {
    private static let maximumImportedHTMLBytes = 512 * 1024

    static func render(
        _ html: String,
        tableAppearance: NativeRichTextTableAppearance = .system,
        noteFormatting: Bool = false,
        cleanLegacyInjectedSpacing: Bool = false
    ) -> NativeRichTextDisplayRenderResult {
        guard html.utf8.count <= maximumImportedHTMLBytes else {
            let result = fallback(html, tableAppearance: tableAppearance)
            return noteFormatting
                ? applyingNoteFormatting(to: result, sourceHTML: html, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
                : result
        }
        let source = tableAppearance == .wordDetail ? convertingSimpleWordTables(in: html) : html
        let attributed = applyingTableAppearance(
            to: RichTextTextView.attributed(
                from: source,
                noteFormatting: noteFormatting,
                cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing
            ),
            appearance: tableAppearance
        )
        guard source.contains("<"), attributed.string == source else {
            return NativeRichTextDisplayRenderResult(attributedText: attributed, usedSafeFallback: false)
        }
        let result = fallback(source, tableAppearance: tableAppearance)
        return noteFormatting
            ? applyingNoteFormatting(to: result, sourceHTML: html, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
            : result
    }

    private static func convertingSimpleWordTables(in html: String) -> String {
        guard let tables = NativeRichTextTablePasteParser.htmlTables(in: html), !tables.isEmpty else { return html }
        let source = NSMutableString(string: html)
        for parsed in tables.reversed() {
            let tableHTML = source.substring(with: parsed.range)
            // Keep cells with links, custom styles or other rich content in their original HTML.
            let complexTag = #"<(?!/?(?:table|thead|tbody|tfoot|tr|td|th|p|div|b|strong|br)\s*/?>)"#
            guard tableHTML.range(of: complexTag, options: [.regularExpression, .caseInsensitive]) == nil,
                  !tableHTML.contains("[[NATIVE_") else { continue }
            let table = RichTextTable(cells: parsed.cells, cellBoldRanges: parsed.boldRanges)
            guard let data = try? JSONEncoder().encode(table) else { continue }
            source.replaceCharacters(in: parsed.range, with: "<p>[[NATIVE_TABLE:\(data.base64EncodedString())]]</p>")
        }
        return source as String
    }

    static func applyingWordDetailSpacing(
        to source: NSAttributedString,
        usedSafeFallback: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let text = source.string as NSString
        RichTextTextView.enumerateParagraphRanges(in: source.string) { paragraph, contents in
            let content = text.substring(with: contents).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, content != "\u{FFFC}" else { return }

            let attributes = source.attributes(at: paragraph.location, effectiveRange: nil)
            let original = (attributes[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
            guard let style = original.mutableCopy() as? NSMutableParagraphStyle else { return }
            let font = attributes[.font] as? UIFont
            let fallbackHeading = usedSafeFallback && (font?.pointSize ?? 0) >= RichTextMetrics.heading2Size
                && font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
            let isHeading = attributes[NativeRichTextPastePolicy.semanticHeadingParagraph] != nil || fallbackHeading

            style.lineSpacing = max(style.lineSpacing, 3)
            style.paragraphSpacing = max(style.paragraphSpacing, isHeading ? 5 : 4)
            if isHeading {
                style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, 8)
            }
            result.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
        return result
    }

    static func applyingNoteFormatting(
        to result: NativeRichTextDisplayRenderResult,
        sourceHTML: String,
        cleanLegacyInjectedSpacing: Bool = false
    ) -> NativeRichTextDisplayRenderResult {
        let paragraphMetadata = RichTextTextView.alignedParagraphMetadata(
            in: sourceHTML,
            matching: result.attributedText
        )
        return NativeRichTextDisplayRenderResult(
            attributedText: RichTextTextView.applyingNoteParagraphFormatting(
                to: result.attributedText,
                sourceHTML: sourceHTML,
                cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing,
                paragraphMetadata: paragraphMetadata
            ),
            usedSafeFallback: result.usedSafeFallback
        )
    }

    static func applyingTableAppearance(
        to source: NSAttributedString,
        appearance: NativeRichTextTableAppearance,
        displayWidth: CGFloat? = nil
    ) -> NSAttributedString {
        var replacements: [(NSRange, NativeTableAttachment)] = []
        source.enumerateAttribute(.attachment, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            guard let table = value as? NativeTableAttachment else { return }
            let width = displayWidth ?? table.displayWidth
            guard table.appearance != appearance || abs(table.displayWidth - width) > 0.5 else { return }
            replacements.append((range, table.replacingAppearance(appearance, displayWidth: width)))
        }
        guard !replacements.isEmpty else { return source }
        let result = NSMutableAttributedString(attributedString: source)
        for (range, table) in replacements.reversed() {
            if appearance == .wordDetail {
                result.addAttribute(.attachment, value: table, range: range)
            } else {
                result.replaceCharacters(in: range, with: NSAttributedString(attachment: table))
            }
        }
        return result.copy() as? NSAttributedString ?? result
    }

    static func renderFallbackPreview(
        _ runs: [NativeRichTextFallbackRun],
        sourceHTML: String,
        tableAppearance: NativeRichTextTableAppearance = .system,
        noteFormatting: Bool = false,
        cleanLegacyInjectedSpacing: Bool = false
    ) -> NativeRichTextDisplayRenderResult {
        let result = fallback(runs, tableAppearance: tableAppearance)
        return noteFormatting
            ? applyingNoteFormatting(to: result, sourceHTML: sourceHTML, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
            : result
    }

    private static func fallback(
        _ html: String,
        tableAppearance: NativeRichTextTableAppearance
    ) -> NativeRichTextDisplayRenderResult {
        fallback(NativeRichTextFallbackParser.parse(html), tableAppearance: tableAppearance)
    }

    private static func fallback(
        _ runs: [NativeRichTextFallbackRun],
        tableAppearance: NativeRichTextTableAppearance
    ) -> NativeRichTextDisplayRenderResult {
        let attributed = NSMutableAttributedString(string: "")
        let font = UIFont.systemFont(ofSize: RichTextMetrics.bodySize)
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        for run in runs {
            switch run {
            case .text(let text):
                attributed.append(NSAttributedString(string: text, attributes: textAttributes))
            case .styledText(let text, let style):
                attributed.append(NSAttributedString(string: text, attributes: fallbackTextAttributes(style, baseFont: font)))
            case .image(let dataURL):
                if let attachment = NativeImageAttachment(dataURL: dataURL) {
                    attributed.append(NSAttributedString(attachment: attachment))
                } else {
                    appendFallbackPlaceholder("[图片无法显示]", to: attributed, attributes: textAttributes)
                }
            case .imageWithMarker(let dataURL, let marker):
                if let attachment = NativeImageAttachment(dataURL: dataURL, marker: marker) {
                    attributed.append(NSAttributedString(attachment: attachment))
                } else {
                    attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: "图片", marker: marker)))
                }
            case .table(let encoded):
                if let table = fallbackTable(from: encoded) {
                    attributed.append(NSAttributedString(attachment: NativeTableAttachment(table: table, appearance: tableAppearance)))
                } else {
                    appendFallbackPlaceholder("[表格无法显示]", to: attributed, attributes: textAttributes)
                }
            case .tableWithMarker(let encoded, let marker):
                if let table = fallbackTable(from: encoded) {
                    attributed.append(NSAttributedString(attachment: NativeTableAttachment(table: table, marker: marker, appearance: tableAppearance)))
                } else {
                    attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: "表格", marker: marker)))
                }
            case .formula(let encoded):
                if let formula = fallbackFormula(from: encoded) {
                    attributed.append(NSAttributedString(attachment: NativeFormulaAttachment(formula: formula)))
                } else {
                    appendFallbackPlaceholder("[公式无法显示]", to: attributed, attributes: textAttributes)
                }
            case .formulaWithMarker(let encoded, let marker):
                if let formula = fallbackFormula(from: encoded) {
                    attributed.append(NSAttributedString(attachment: NativeFormulaAttachment(formula: formula, marker: marker)))
                } else {
                    attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: "公式", marker: marker)))
                }
            case .opaque(let label, let marker):
                attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: label, marker: marker)))
            case .placeholder(let label):
                let text = label == "其余附件已省略" ? "[\(label)]" : "[\(label)无法显示]"
                appendFallbackPlaceholder(text, to: attributed, attributes: textAttributes)
            }
        }
        return NativeRichTextDisplayRenderResult(
            attributedText: attributed,
            usedSafeFallback: true
        )
    }

    static func editableAttributedText(
        from runs: [NativeRichTextFallbackRun],
        tableAppearance: NativeRichTextTableAppearance = .system
    ) -> NSAttributedString? {
        let attributed = NSMutableAttributedString(string: "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize),
            .foregroundColor: UIColor.label
        ]
        let baseFont = UIFont.systemFont(ofSize: RichTextMetrics.bodySize)
        var imagePayloadBytes = 0
        let maximumImagePayloadBytes = 8 * 1024 * 1024

        for run in runs {
            switch run {
            case .text(let text):
                attributed.append(NSAttributedString(string: text, attributes: attributes))
            case .styledText(let text, let style):
                attributed.append(NSAttributedString(string: text, attributes: fallbackTextAttributes(style, baseFont: baseFont)))
            case .imageWithMarker(let dataURL, let marker):
                imagePayloadBytes += dataURL.utf8.count
                guard imagePayloadBytes <= maximumImagePayloadBytes,
                      let attachment = NativeImageAttachment(dataURL: dataURL, marker: marker) else { return nil }
                attributed.append(NSAttributedString(attachment: attachment))
            case .tableWithMarker(let encoded, let marker):
                guard let table = fallbackTable(from: encoded) else { return nil }
                attributed.append(NSAttributedString(attachment: NativeTableAttachment(
                    table: table, marker: marker, appearance: tableAppearance
                )))
            case .formulaWithMarker(let encoded, let marker):
                guard let formula = fallbackFormula(from: encoded) else { return nil }
                attributed.append(NSAttributedString(attachment: NativeFormulaAttachment(formula: formula, marker: marker)))
            case .image, .table, .formula, .placeholder, .opaque:
                return nil
            }
        }
        return attributed.copy() as? NSAttributedString ?? attributed
    }

    static func editableNoteSnapshot(
        from runs: [NativeRichTextFallbackRun],
        sourceHTML: String,
        tableAppearance: NativeRichTextTableAppearance = .system
    ) -> NSAttributedString? {
        guard let editable = editableAttributedText(from: runs, tableAppearance: tableAppearance) else { return nil }
        let attributed = NSMutableAttributedString(attributedString: editable)
        let metadata = RichTextTextView.alignedParagraphMetadata(in: sourceHTML, matching: attributed)
        if metadata == nil, sourceHTML.localizedCaseInsensitiveContains("data-note-layout-version=") {
            return nil
        }
        RichTextTextView.applyHTMLListMarkers(from: sourceHTML, to: attributed)
        return RichTextTextView.applyingNoteParagraphFormatting(
            to: attributed,
            sourceHTML: sourceHTML,
            cleanLegacyInjectedSpacing: true,
            paragraphMetadata: metadata
        )
    }

    /// Checks that the bounded fallback parser retained every attachment in a form
    /// that the editor can render and write back without replacing it with a label.
    static func supportsLosslessEditing(_ runs: [NativeRichTextFallbackRun]) -> Bool {
        var imagePayloadBytes = 0
        let maximumImagePayloadBytes = 8 * 1024 * 1024

        for run in runs {
            switch run {
            case .text(_), .styledText(_, _):
                continue
            case .imageWithMarker(let dataURL, let marker):
                imagePayloadBytes += dataURL.utf8.count
                guard imagePayloadBytes <= maximumImagePayloadBytes,
                      NativeImageAttachment(dataURL: dataURL, marker: marker) != nil else { return false }
            case .tableWithMarker(let encoded, let marker):
                guard let table = fallbackTable(from: encoded) else { return false }
                _ = NativeTableAttachment(table: table, marker: marker)
            case .formulaWithMarker(let encoded, let marker):
                guard let formula = fallbackFormula(from: encoded) else { return false }
                _ = NativeFormulaAttachment(formula: formula, marker: marker)
            case .image, .table, .formula, .placeholder, .opaque:
                return false
            }
        }
        return true
    }

    /// The system HTML importer is the preferred editing snapshot for app-exported
    /// HTML. This guard rejects parser fallbacks, unparsed markup, unresolved native
    /// markers, and attachments that the editor cannot serialize back losslessly.
    static func supportsNativeEditingSnapshot(
        sourceHTML: String,
        rendered: NativeRichTextDisplayRenderResult
    ) -> Bool {
        guard sourceHTML.utf8.count <= maximumImportedHTMLBytes,
              !rendered.usedSafeFallback,
              rendered.attributedText.length <= 1_000_000,
              hasBalancedHTMLTags(sourceHTML),
              !containsUnparsedHTMLOrNativeMarker(rendered.attributedText.string) else { return false }

        var supportedAttachments = true
        var attachmentCount = 0
        var imagePayloadBytes = 0
        rendered.attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: rendered.attributedText.length)
        ) { value, _, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            attachmentCount += 1
            guard attachmentCount <= 64 else {
                supportedAttachments = false
                stop.pointee = true
                return
            }
            if let image = attachment as? NativeImageAttachment {
                imagePayloadBytes += image.dataURL.utf8.count
                guard imagePayloadBytes <= 8 * 1024 * 1024,
                      image.dataURL.utf8.count <= NativeRichTextImageLimits.maximumEncodedBytes else {
                    supportedAttachments = false
                    stop.pointee = true
                    return
                }
            } else if let table = attachment as? NativeTableAttachment {
                guard table.marker != nil else {
                    supportedAttachments = false
                    stop.pointee = true
                    return
                }
            } else if let formula = attachment as? NativeFormulaAttachment {
                guard formula.marker != nil else {
                    supportedAttachments = false
                    stop.pointee = true
                    return
                }
            } else {
                supportedAttachments = false
                stop.pointee = true
            }
        }
        return supportedAttachments
    }

    private static func containsUnparsedHTMLOrNativeMarker(_ text: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: #"<\s*/?\s*[A-Za-z][^>]*>|\[\[NATIVE_[^\]]*"#
        ) else { return true }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func hasBalancedHTMLTags(_ html: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: #"</?\s*([A-Za-z][A-Za-z0-9:-]*)\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else { return false }
        let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        let source = html as NSString
        var stack: [String] = []
        for match in expression.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard match.numberOfRanges > 1 else { return false }
            let tag = source.substring(with: match.range).lowercased()
            let name = source.substring(with: match.range(at: 1)).lowercased()
            if tag.hasPrefix("</") {
                guard let last = stack.popLast(), last == name else { return false }
            } else if !voidTags.contains(name), !tag.hasSuffix("/>") {
                stack.append(name)
            }
        }
        return stack.isEmpty
    }

    private static func fallbackTextAttributes(
        _ style: NativeRichTextFallbackTextStyle,
        baseFont: UIFont
    ) -> [NSAttributedString.Key: Any] {
        let headingSize = style.contains(.heading1)
            ? RichTextMetrics.heading1Size
            : (style.contains(.heading2) ? RichTextMetrics.heading2Size : baseFont.pointSize)
        let size = style.pointSize ?? headingSize
        let sizedFont = UIFont.systemFont(ofSize: size)
        var traits = sizedFont.fontDescriptor.symbolicTraits
        if style.contains(.bold) { traits.insert(.traitBold) }
        if style.contains(.italic) { traits.insert(.traitItalic) }
        let descriptor = sizedFont.fontDescriptor.withSymbolicTraits(traits) ?? sizedFont.fontDescriptor
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(descriptor: descriptor, size: size),
            .foregroundColor: UIColor.label
        ]
        if style.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let color = style.color {
            attributes[.foregroundColor] = UIColor(
                red: CGFloat((color >> 16) & 255) / 255,
                green: CGFloat((color >> 8) & 255) / 255,
                blue: CGFloat(color & 255) / 255,
                alpha: 1
            )
        }
        if let link = style.link { attributes[.link] = link }
        return attributes
    }

    private static func appendFallbackPlaceholder(
        _ value: String,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        output.append(NSAttributedString(string: value, attributes: attributes))
    }

    private static func fallbackTable(from encoded: String) -> RichTextTable? {
        guard let data = Data(base64Encoded: encoded), data.count <= 48 * 1024,
              let table = try? JSONDecoder().decode(RichTextTable.self, from: data),
              (1...16).contains(table.rowCount),
              (1...RichTextTable.maximumColumns).contains(table.columnCount),
              (!table.isFlowchart || table.columnCount == 2),
              table.cells.allSatisfy({ $0.count == table.columnCount && $0.allSatisfy { $0.utf8.count <= 512 } })
        else { return nil }
        return table
    }

    private static func fallbackFormula(from encoded: String) -> RichTextFormula? {
        guard let data = Data(base64Encoded: encoded), data.count <= 4 * 1024 else { return nil }
        return try? JSONDecoder().decode(RichTextFormula.self, from: data)
    }
}

private final class RichTextKeyboardAccessoryView: UIView {
    private(set) var preferredHeight: CGFloat

    init(contentView: UIView, height: CGFloat) {
        preferredHeight = height
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    func updateHeight(_ height: CGFloat) -> Bool {
        guard abs(preferredHeight - height) > 0.5 else { return false }
        preferredHeight = height
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        return true
    }
}

@MainActor
private final class RichTextPasteTextView: UITextView {
    var onPaste: ((UITextView) -> Bool)?
    var onCopy: ((UITextView, Bool) -> Void)?
    var copyStructuredSelection: ((UITextView) -> Bool)?
    var onLayout: ((UITextView) -> Void)?
    var onBoundsChange: ((UITextView) -> Void)?
    var onBackspace: ((UITextView) -> Bool)?
    var focusOnceAttached: (() -> Void)?
    private var lastReportedBoundsSize: CGSize?

    init(pasteEnabledUsingTextLayoutManager: Bool) {
        if pasteEnabledUsingTextLayoutManager {
            let layoutManager = NSTextLayoutManager()
            let textContainer = NSTextContainer(size: .zero)
            layoutManager.textContainer = textContainer
            let contentStorage = NSTextContentStorage()
            contentStorage.addTextLayoutManager(layoutManager)
            super.init(frame: .zero, textContainer: textContainer)
        } else {
            super.init(frame: .zero, textContainer: nil)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func paste(_ sender: Any?) {
        if onPaste?(self) == true { return }
        super.paste(sender)
    }

    override func deleteBackward() {
        if onBackspace?(self) == true { return }
        super.deleteBackward()
    }

    override func copy(_ sender: Any?) {
        if copyStructuredSelection?(self) == true { return }
        onCopy?(self, false)
        super.copy(sender)
        onCopy?(self, true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
        let size = bounds.size
        if lastReportedBoundsSize != size {
            lastReportedBoundsSize = size
            onBoundsChange?(self)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, let focus = self.focusOnceAttached else { return }
            self.focusOnceAttached = nil
            focus()
        }
    }
}

@MainActor
private final class RichTextEditorHostView: UIView {
    let textView: RichTextPasteTextView

    init(textView: RichTextPasteTextView) {
        self.textView = textView
        super.init(frame: .zero)
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        textView = RichTextPasteTextView(pasteEnabledUsingTextLayoutManager: true)
        super.init(coder: coder)
        addSubview(textView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if textView.frame != bounds { textView.frame = bounds }
    }
}

@MainActor
private final class RichTextInlineBlockField: UITextView {
    var switchField: ((Int) -> Void)?
    var moveVertically: ((Int) -> Void)?
    var reportedError: String?

    override var keyCommands: [UIKeyCommand]? {
        guard markedTextRange == nil else { return super.keyCommands }
        let next = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(changeField(_:)))
        let previous = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(changeField(_:)))
        var commands = [next, previous]
        if moveVertically != nil {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(changeRow(_:))))
            commands.append(UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(changeRow(_:))))
        }
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands + (super.keyCommands ?? [])
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(changeRow(_:)) || action == #selector(changeField(_:)) {
            return markedTextRange == nil
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func changeField(_ command: UIKeyCommand) {
        switchField?(command.modifierFlags.contains(.shift) ? -1 : 1)
    }

    @objc private func changeRow(_ command: UIKeyCommand) {
        moveVertically?(command.input == UIKeyCommand.inputUpArrow ? -1 : 1)
    }
}

@MainActor
private struct RichTextTextView: UIViewRepresentable {
    @Binding var html: String
    @Binding var command: RichTextCommand?
    @Binding var selectedTable: RichTextTable?
    @Binding var tableEditorRequest: RichTextTableEditorRequest?
    @Binding var tableEditTarget: RichTextTableEditTarget?
    @Binding var selectedFormula: RichTextFormula?
    @Binding var isEditing: Bool
    @Binding var selectionState: RichTextSelectionState
    let internalLinks: [RichTextInternalLink]
    let onOpenInternalLink: ((RichTextInternalLink) -> Void)?
    let onFocusReady: ((UITextView) -> Void)?
    let onCaretChange: ((UITextView) -> Void)?
    let onInlineBlockError: (String) -> Void
    let keyboardAccessory: AnyView
    let keyboardAccessoryHeight: CGFloat
    let keyboardAccessoryState: RichTextKeyboardAccessoryState
    var growsWithContent = false
    var tableAppearance: NativeRichTextTableAppearance = .system
    var noteFormatting = false
    var usesStabilizedInlineNoteMeasurement = false
    var minimumContentHeight: CGFloat = 0
    var focusOnAppear = false
    var initialSelectionOffset: Int? = nil
    var initialSelectionWidth: CGFloat? = nil
    var initialBlockCell: RichTextTable.Cell? = nil
    var preparedInitialHTML: String? = nil
    var preparedInitialAttributedText: NSAttributedString? = nil
    var editorSession: NativeRichTextEditorSession? = nil
    var editorDocumentID: String? = nil
    var editorSessionID: UUID = UUID()
    var usesLazyHTMLInitialization = false

    fileprivate var usesInlineBlockEditing: Bool { noteFormatting && tableAppearance == .libraryContent }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = RichTextPasteTextView(pasteEnabledUsingTextLayoutManager: true)
        view.onPaste = { [weak coordinator = context.coordinator] textView in
            coordinator?.handlePaste(textView) ?? false
        }
        view.onCopy = { [weak coordinator = context.coordinator] textView, completed in
            coordinator?.logNoteCopy(textView, completed: completed)
        }
        view.copyStructuredSelection = { [weak coordinator = context.coordinator] textView in
            coordinator?.copyFlowchartSelection(textView) ?? false
        }
        view.delegate = context.coordinator
        view.onBackspace = { [weak coordinator = context.coordinator] textView in
            coordinator?.handleNoteBackspace(in: textView) ?? false
        }
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        view.onLayout = { [weak coordinator = context.coordinator] textView in
            coordinator?.updateNativeTableWidths(in: textView)
            coordinator?.positionInlineBlockField(in: textView)
        }
        view.onBoundsChange = { [weak coordinator = context.coordinator] textView in
            guard coordinator?.parent.noteFormatting == true else { return }
            coordinator?.parent.onCaretChange?(textView)
        }
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: RichTextMetrics.bodySize)
        view.adjustsFontForContentSizeCategory = false
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        if growsWithContent {
            view.isScrollEnabled = false
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            if let initialSelectionWidth, initialSelectionWidth.isFinite, initialSelectionWidth > 0 {
                view.textContainer.size.width = initialSelectionWidth
            }
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        view.allowsEditingTextAttributes = true
        view.inputAssistantItem.leadingBarButtonGroups = []
        view.inputAssistantItem.trailingBarButtonGroups = []
        view.keyboardDismissMode = .interactive
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let tableTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleNativeTableTap(_:)))
        tableTap.cancelsTouchesInView = usesInlineBlockEditing
        tableTap.delaysTouchesBegan = false
        tableTap.delaysTouchesEnded = false
        tableTap.delegate = context.coordinator
        view.addGestureRecognizer(tableTap)
        if usesInlineBlockEditing {
            let caretTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleNoteCaretTap(_:)))
            caretTap.cancelsTouchesInView = false
            caretTap.delegate = context.coordinator
            context.coordinator.noteCaretTap = caretTap
            view.addGestureRecognizer(caretTap)
        }
        if let preparedInitialAttributedText, preparedInitialHTML == html {
            view.attributedText = NativeRichTextDisplayRenderer.applyingTableAppearance(
                to: preparedInitialAttributedText,
                appearance: tableAppearance
            )
        } else if !usesLazyHTMLInitialization {
            view.attributedText = NativeRichTextDisplayRenderer.applyingTableAppearance(
                to: Self.attributed(from: html, noteFormatting: noteFormatting),
                appearance: tableAppearance
            )
        } else {
            view.attributedText = NSAttributedString(
                string: html,
                attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]
            )
        }
        context.coordinator.setPublishedHTML(html)
        context.coordinator.rememberManagedDocumentIdentity(
            isManaged: usesLazyHTMLInitialization,
            documentID: editorDocumentID,
            sessionID: editorSessionID
        )
        context.coordinator.updateNativeTableWidths(in: view, force: true)
        context.coordinator.connect(editorSession, to: view)
        context.coordinator.rememberSelection(view.selectedRange)
        context.coordinator.installKeyboardAccessory(
            keyboardAccessory,
            height: keyboardAccessoryHeight,
            state: keyboardAccessoryState,
            on: view
        )
        if focusOnAppear {
            let end = view.attributedText.length
            let offset = max(0, min(initialSelectionOffset ?? end, end))
            let caret = NSRange(location: offset, length: 0)
            view.selectedRange = caret
            context.coordinator.rememberSelection(caret)
            view.focusOnceAttached = { [weak coordinator = context.coordinator, weak view] in
                guard let coordinator, let view else { return }
                view.superview?.layoutIfNeeded()
                if let cell = initialBlockCell,
                   coordinator.focusInitialBlockCell(cell, offset: offset, in: view) { return }
                guard view.becomeFirstResponder() else { return }
                view.selectedRange = caret
                coordinator.rememberSelection(caret)
                view.scrollRangeToVisible(caret)
                onFocusReady?(view)
            }
        }
        if usesInlineBlockEditing { return RichTextEditorHostView(textView: view) }
        return view
    }

    private func textView(in view: UIView) -> RichTextPasteTextView? {
        (view as? RichTextEditorHostView)?.textView ?? (view as? RichTextPasteTextView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard growsWithContent, let width = proposal.width, width > 0,
              let view = textView(in: uiView) else { return nil }
        let measurementStart = ProcessInfo.processInfo.systemUptime
        let height = context.coordinator.contentHeight(
            for: view,
            width: width,
            minimum: max(42, minimumContentHeight)
        )
        if noteFormatting, editorSession != nil, context.coordinator.didMeasureHeightDuringLastRequest {
            LibraryPerformanceLog.markIfSlow("note.editor.height-measure", since: measurementStart)
        }
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ host: UIView, context: Context) {
        guard let view = textView(in: host) else { return }
        context.coordinator.parent = self
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        context.coordinator.updateKeyboardAccessory(
            keyboardAccessory,
            height: keyboardAccessoryHeight,
            state: keyboardAccessoryState,
            on: view
        )
        context.coordinator.connect(editorSession, to: view)
        let managedDocumentChanged = context.coordinator.updateManagedDocumentIdentity(
            isManaged: usesLazyHTMLInitialization,
            documentID: editorDocumentID,
            sessionID: editorSessionID
        )
        let replacingDocumentContent = usesLazyHTMLInitialization
            ? managedDocumentChanged
            : context.coordinator.lastHTML != html && !view.isFirstResponder && !context.coordinator.isEditingInlineBlock
        if usesStabilizedInlineNoteMeasurement, editorSession != nil,
           managedDocumentChanged || context.coordinator.lastHTML != html {
            LibraryPerformanceLog.event(
                "note.editor.update documentChanged=\(managedDocumentChanged) replacement=\(replacingDocumentContent) focused=\(view.isFirstResponder) bindingBytes=\(html.utf8.count) storageLength=\(view.textStorage.length) selection=\(view.selectedRange.location):\(view.selectedRange.length)"
            )
        }
        if replacingDocumentContent {
            context.coordinator.removeInlineBlockField()
            if managedDocumentChanged { view.resignFirstResponder() }
            if let preparedInitialAttributedText, preparedInitialHTML == html {
                view.attributedText = NativeRichTextDisplayRenderer.applyingTableAppearance(
                    to: preparedInitialAttributedText,
                    appearance: tableAppearance
                )
                context.coordinator.setPublishedHTML(html)
            } else if !usesLazyHTMLInitialization || managedDocumentChanged {
                view.attributedText = NativeRichTextDisplayRenderer.applyingTableAppearance(
                    to: Self.attributed(from: html, noteFormatting: noteFormatting),
                    appearance: tableAppearance
                )
                context.coordinator.setPublishedHTML(html)
            }
        }
        context.coordinator.updateNativeTableWidths(in: view, force: replacingDocumentContent)
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            let result = context.coordinator.apply(command.kind, to: view, tableEditTarget: command.tableEditTarget)
            let commandKind = command.kind
            let imageCompletion = command.imageCompletion
            let tableCompletion = command.tableCompletion
            DispatchQueue.main.async {
                self.command = nil
                if let imageCompletion {
                    imageCompletion(context.coordinator.completeImageInsertion(
                        commandKind,
                        result: result ?? .failure(NativeRichTextEditorError.imageAttachmentInvalid),
                        in: view
                    ))
                }
                if let tableCompletion {
                    tableCompletion(result ?? .failure(NativeRichTextEditorError.tableTargetChanged))
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, NSTextLayoutManagerDelegate {
        var parent: RichTextTextView
        var lastHTML = ""
        var lastCommandID: UUID?
        weak var noteCaretTap: UITapGestureRecognizer?
        var isEditingInlineBlock: Bool { inlineBlockEdit != nil }
        weak var connectedSession: NativeRichTextEditorSession?
        private var pendingEndEditingCompletion: ((String?) -> Void)?
        private var lastEditingSelection = NSRange(location: 0, length: 0)
        private var pendingPublish: DispatchWorkItem?
        private var layoutRefreshScheduled = false
        private var layoutRefreshUpdatesToolbar = false
        private var layoutRefreshUpdatesLayout = false
        private weak var pendingLayoutRefreshView: UITextView?
        private var documentRevision: UInt64 = 0
        private var userEditRevision: UInt64 = 0
        private var publishedRevision: UInt64 = 0
        private var publishedHTML = ""
        private var cachedSnapshot: NativeRichTextEditorSnapshot?
        private var lastTableWidth: CGFloat?
        private var lastMeasuredWidth: CGFloat?
        private var lastMeasuredHeight: CGFloat = 0
        private var measuredHeightNeedsRefresh = true
        private var forcedNoteHeightMeasurement: (revision: UInt64, sessionID: UUID, documentID: String)?
        private(set) var didMeasureHeightDuringLastRequest = false
        private var lastSelectionTable: RichTextTable?
        private var lastSelectionFormula: RichTextFormula?
        private var lastQueuedSelectionState: RichTextSelectionState?
        private var accessoryController: UIHostingController<AnyView>?
        private weak var accessoryContainer: RichTextKeyboardAccessoryView?
        private var lastKeyboardAccessoryState: RichTextKeyboardAccessoryState?
        private var hasManagedDocumentIdentity = false
        private var managedDocumentID: String?
        private var managedSessionID: UUID?
        private struct InlineBlockEdit {
            let target: RichTextTableEditTarget
            let cell: RichTextTable.Cell
            let field: RichTextInlineBlockField
        }
        private var inlineBlockEdit: InlineBlockEdit?
        init(parent: RichTextTextView) { self.parent = parent }

        func rememberManagedDocumentIdentity(isManaged: Bool, documentID: String?, sessionID: UUID) {
            guard isManaged else { return }
            hasManagedDocumentIdentity = true
            managedDocumentID = documentID
            managedSessionID = sessionID
        }

        func updateManagedDocumentIdentity(isManaged: Bool, documentID: String?, sessionID: UUID) -> Bool {
            guard isManaged else {
                hasManagedDocumentIdentity = false
                managedDocumentID = nil
                managedSessionID = nil
                return false
            }
            let changed = !hasManagedDocumentIdentity
                || managedDocumentID != documentID
                || managedSessionID != sessionID
            hasManagedDocumentIdentity = true
            managedDocumentID = documentID
            managedSessionID = sessionID
            return changed
        }

        private var hasPendingForcedNoteHeightMeasurement: Bool {
            guard let pending = forcedNoteHeightMeasurement else { return false }
            return pending.revision == documentRevision
                && pending.sessionID == parent.editorSessionID
                && pending.documentID == (parent.editorDocumentID ?? "")
        }

        private func carryForcedNoteHeightMeasurementForward() {
            guard let pending = forcedNoteHeightMeasurement,
                  pending.sessionID == parent.editorSessionID,
                  pending.documentID == (parent.editorDocumentID ?? "") else { return }
            forcedNoteHeightMeasurement = (documentRevision, pending.sessionID, pending.documentID)
        }

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            NoteParagraphLayoutFragment.make(for: textElement, noteFormatting: parent.noteFormatting, editing: true)
        }

        func setPublishedHTML(_ html: String) {
            if lastHTML != html {
                documentRevision &+= 1
                forcedNoteHeightMeasurement = nil
            }
            lastHTML = html
            publishedHTML = html
            publishedRevision = documentRevision
            cachedSnapshot = nil
            measuredHeightNeedsRefresh = true
        }

        func contentHeight(for view: UITextView, width: CGFloat, minimum: CGFloat) -> CGFloat {
            didMeasureHeightDuringLastRequest = false
            let normalizedWidth = floor(width * 2) / 2
            if parent.usesStabilizedInlineNoteMeasurement {
                if let lastMeasuredWidth,
                   abs(lastMeasuredWidth - normalizedWidth) <= 0.5,
                   !measuredHeightNeedsRefresh {
                    return max(minimum, lastMeasuredHeight)
                }
                ensureCurrentNoteLayout(view)
                let size = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
                didMeasureHeightDuringLastRequest = true
                lastMeasuredWidth = normalizedWidth
                let fittedHeight = size.height.isFinite ? ceil(size.height) : minimum
                let caret = view.caretRect(for: view.endOfDocument)
                let caretHeight = !caret.isNull && caret.maxY.isFinite
                    ? ceil(caret.maxY + view.textContainerInset.bottom + 2)
                    : minimum
                lastMeasuredHeight = max(minimum, max(fittedHeight, caretHeight))
                measuredHeightNeedsRefresh = false
                if hasPendingForcedNoteHeightMeasurement { forcedNoteHeightMeasurement = nil }
                if parent.editorSession != nil {
                    LibraryPerformanceLog.event(
                        "note.editor.height revision=\(documentRevision) edit=\(userEditRevision) length=\(view.textStorage.length) selection=\(view.selectedRange.location):\(view.selectedRange.length) width=\(normalizedWidth) fit=\(Int(fittedHeight)) caret=\(Int(caretHeight)) result=\(Int(lastMeasuredHeight))"
                    )
                }
                return lastMeasuredHeight
            }

            if parent.noteFormatting, hasPendingForcedNoteHeightMeasurement {
                let size = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
                didMeasureHeightDuringLastRequest = true
                lastMeasuredWidth = normalizedWidth
                lastMeasuredHeight = max(minimum, size.height.isFinite ? ceil(size.height) : minimum)
                measuredHeightNeedsRefresh = false
                forcedNoteHeightMeasurement = nil
                return lastMeasuredHeight
            }
            if parent.noteFormatting,
               let lastMeasuredWidth,
               abs(lastMeasuredWidth - normalizedWidth) <= 0.5 {
                if !measuredHeightNeedsRefresh {
                    return max(minimum, lastMeasuredHeight)
                }
                if let usedHeight = view.textLayoutManager?.usageBoundsForTextContainer.height,
                   usedHeight.isFinite, usedHeight > 0 {
                    lastMeasuredHeight = max(minimum, ceil(usedHeight))
                    measuredHeightNeedsRefresh = false
                    return lastMeasuredHeight
                }
            }

            let size = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            didMeasureHeightDuringLastRequest = true
            lastMeasuredWidth = normalizedWidth
            lastMeasuredHeight = max(minimum, size.height.isFinite ? ceil(size.height) : minimum)
            measuredHeightNeedsRefresh = false
            return lastMeasuredHeight
        }

        private func ensureCurrentNoteLayout(_ view: UITextView) {
            guard let textLayoutManager = view.textLayoutManager,
                  let textContentManager = textLayoutManager.textContentManager else { return }
            textLayoutManager.ensureLayout(for: textContentManager.documentRange)
        }

        private func updateCachedNoteHeightFromTextKit(_ view: UITextView) -> Bool {
            guard parent.noteFormatting,
                  let lastMeasuredWidth,
                  view.bounds.width.isFinite,
                  abs(lastMeasuredWidth - floor(view.bounds.width * 2) / 2) <= 0.5 else { return false }
            guard parent.usesStabilizedInlineNoteMeasurement else {
                guard let usedHeight = view.textLayoutManager?.usageBoundsForTextContainer.height,
                      usedHeight.isFinite, usedHeight > 0 else { return false }
                let updatedHeight = max(parent.minimumContentHeight, ceil(usedHeight))
                measuredHeightNeedsRefresh = false
                guard abs(updatedHeight - lastMeasuredHeight) > 0.5 else { return false }
                lastMeasuredHeight = updatedHeight
                return true
            }
            ensureCurrentNoteLayout(view)
            let size = view.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude))
            guard size.height.isFinite, size.height > 0 else { return false }
            let caret = view.caretRect(for: view.endOfDocument)
            let caretHeight = !caret.isNull && caret.maxY.isFinite
                ? ceil(caret.maxY + view.textContainerInset.bottom + 2)
                : parent.minimumContentHeight
            let updatedHeight = max(parent.minimumContentHeight, max(ceil(size.height), caretHeight))
            measuredHeightNeedsRefresh = false
            guard abs(updatedHeight - lastMeasuredHeight) > 0.5 else { return false }
            lastMeasuredHeight = updatedHeight
            return true
        }

        func connect(_ session: NativeRichTextEditorSession?, to view: UITextView) {
            if connectedSession !== session {
                connectedSession?.disconnect()
                forcedNoteHeightMeasurement = nil
            }
            connectedSession = session
            guard let session else { return }
            session.connect(
                latestHTMLReader: { [weak self, weak view] in
                    guard let self, let view else { return nil }
                    return self.publishNow(view)
                },
                latestAttributedTextReader: { [weak self, weak view] in
                    guard let self, let view else { return nil }
                    return self.snapshotNow(view).attributedText
                },
                snapshotReader: { [weak self, weak view] in
                    guard let self, let view else { return nil }
                    let snapshot = self.snapshotNow(view)
                    self.publish(snapshot.html)
                    return snapshot
                },
                selectionReader: { [weak self, weak view] in
                    guard let self, let view else { return nil }
                    let selection = self.validSelection(self.lastEditingSelection, in: view)
                        ? self.lastEditingSelection
                        : view.selectedRange
                    self.rememberSelection(selection)
                    return selection
                },
                tableInsertionTargetReader: { [weak self, weak view] in
                    guard let self, let view else { return nil }
                    let selected = self.validSelection(self.lastEditingSelection, in: view)
                        ? self.lastEditingSelection
                        : view.selectedRange
                    return RichTextTableEditTarget(
                        documentID: self.parent.editorDocumentID,
                        sessionID: self.parent.editorSessionID,
                        attachmentInstanceID: nil,
                        range: selected,
                        revision: self.documentRevision
                    )
                },
                compositionCommitHandler: { [weak self, weak view] in
                    guard let self, let view else { return }
                    if self.inlineBlockEdit != nil {
                        _ = self.commitInlineBlockField(in: view)
                        return
                    }
                    guard view.markedTextRange != nil else { return }
                    let revisionBeforeCommit = self.documentRevision
                    view.unmarkText()
                    let composing = view.markedTextRange != nil
                    self.connectedSession?.setComposingText(composing)
                    self.rememberSelection(view.selectedRange)
                    self.scheduleLayoutAndToolbarRefresh(
                        view,
                        updatesToolbar: !composing,
                        updatesLayout: self.parent.noteFormatting || !composing
                    )
                    if !composing, self.documentRevision == revisionBeforeCommit { self.schedulePublish(view) }
                },
                imageInsertionHandler: { [weak self] dataURL, target, completion in
                    guard let self else {
                        completion(.failure(.editorSessionChanged))
                        return
                    }
                    self.parent.command = RichTextCommand(
                        kind: .image(dataURL, target),
                        imageCompletion: completion
                    )
                },
                endEditingHandler: { [weak self, weak view] completion in
                    guard let self, let view else { completion(nil); return }
                    guard self.closeInlineBlockField(in: view) else { completion(nil); return }
                    if view.isFirstResponder {
                        self.pendingEndEditingCompletion = completion
                        if !view.resignFirstResponder() {
                            self.pendingEndEditingCompletion = nil
                            completion(self.publishNow(view))
                        }
                    } else {
                        completion(self.publishNow(view))
                    }
                }
            )
        }

        func installKeyboardAccessory(
            _ content: AnyView,
            height: CGFloat,
            state: RichTextKeyboardAccessoryState,
            on textView: UITextView
        ) {
            let controller = UIHostingController(rootView: content)
            controller.view.backgroundColor = .clear
            let container = RichTextKeyboardAccessoryView(contentView: controller.view, height: height)
            accessoryController = controller
            accessoryContainer = container
            lastKeyboardAccessoryState = state
            textView.inputAccessoryView = container
        }

        func updateKeyboardAccessory(
            _ content: AnyView,
            height: CGFloat,
            state: RichTextKeyboardAccessoryState,
            on textView: UITextView
        ) {
            guard lastKeyboardAccessoryState != state else { return }
            lastKeyboardAccessoryState = state
            accessoryController?.rootView = content
            if accessoryContainer?.updateHeight(height) == true, textView.isFirstResponder {
                textView.reloadInputViews()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            if textView is RichTextInlineBlockField {
                connectedSession?.setComposingText(textView.markedTextRange != nil)
                return
            }
            userEditRevision &+= 1
            let isComposing = textView.markedTextRange != nil
            connectedSession?.setComposingText(isComposing)
            if parent.usesStabilizedInlineNoteMeasurement, parent.editorSession != nil {
                LibraryPerformanceLog.event(
                    "note.editor.change length=\(textView.textStorage.length) selection=\(textView.selectedRange.location):\(textView.selectedRange.length) revision=\(documentRevision) edit=\(userEditRevision) composing=\(isComposing) locked=\(connectedSession?.isInputLocked == true)"
                )
            }
            if parent.noteFormatting {
                measuredHeightNeedsRefresh = true
            }
            scheduleLayoutAndToolbarRefresh(
                textView,
                updatesToolbar: !isComposing,
                updatesLayout: !isComposing || parent.noteFormatting
            )
            if isComposing {
                documentRevision &+= 1
                cachedSnapshot = nil
                pendingPublish?.cancel()
                pendingPublish = nil
            } else {
                if parent.noteFormatting { parent.onCaretChange?(textView) }
                schedulePublish(textView)
            }
            carryForcedNoteHeightMeasurementForward()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !(textView is RichTextInlineBlockField) else { return }
            rememberSelection(textView.selectedRange)
            scheduleLayoutAndToolbarRefresh(textView, updatesToolbar: true, updatesLayout: false)
            if parent.noteFormatting { parent.onCaretChange?(textView) }
            DispatchQueue.main.async { self.parent.isEditing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView is RichTextInlineBlockField {
                guard let edit = inlineBlockEdit, edit.field === textView,
                      let host = textView.superview as? RichTextEditorHostView else { return }
                _ = closeInlineBlockField(in: host.textView)
                return
            }
            // The document still owns the keyboard while a cell is taking focus.
            guard inlineBlockEdit == nil else { return }
            let latestHTML = publishNow(textView)
            let completion = pendingEndEditingCompletion
            pendingEndEditingCompletion = nil
            connectedSession?.setComposingText(false)
            DispatchQueue.main.async { [weak textView] in
                if self.inlineBlockEdit == nil, textView?.isFirstResponder != true { self.parent.isEditing = false }
                completion?(latestHTML)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView is RichTextInlineBlockField {
                let isComposing = textView.markedTextRange != nil
                connectedSession?.setComposingText(isComposing)
                if !isComposing { parent.onCaretChange?(textView) }
                return
            }
            guard inlineBlockEdit == nil else { return }
            let isComposing = textView.markedTextRange != nil
            connectedSession?.setComposingText(isComposing)
            guard !isComposing else { return }
            rememberSelection(textView.selectedRange)
            let tableMatch = tableAttachment(near: textView.selectedRange, view: textView)
            let table = tableMatch?.attachment.table
            let formula = formulaAttachment(near: textView.selectedRange, view: textView)?.attachment.formula
            let tableTarget = tableMatch.map { makeTableEditTarget(for: $0.attachment, range: $0.range) }
            if lastSelectionTable != table || lastSelectionFormula != formula {
                lastSelectionTable = table
                lastSelectionFormula = formula
                DispatchQueue.main.async {
                    if self.parent.selectedTable != table { self.parent.selectedTable = table }
                    if self.parent.tableEditTarget != tableTarget { self.parent.tableEditTarget = tableTarget }
                    if self.parent.selectedFormula != formula { self.parent.selectedFormula = formula }
                }
            } else if parent.tableEditTarget != tableTarget {
                DispatchQueue.main.async { self.parent.tableEditTarget = tableTarget }
            }
            if parent.noteFormatting { parent.onCaretChange?(textView) }
            scheduleLayoutAndToolbarRefresh(textView, updatesToolbar: true, updatesLayout: false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let isLocked = connectedSession?.isInputLocked == true
            if textView is RichTextInlineBlockField { return !isLocked }
            guard closeInlineBlockField(in: textView) else { return false }
            if parent.usesStabilizedInlineNoteMeasurement, parent.editorSession != nil {
                let action = text.isEmpty ? "delete" : (text == "\n" ? "newline" : "insert")
                LibraryPerformanceLog.event(
                    "note.editor.input action=\(action) range=\(range.location):\(range.length) insertLength=\(text.utf16.count) storageLength=\(textView.textStorage.length) selection=\(textView.selectedRange.location):\(textView.selectedRange.length) revision=\(documentRevision) edit=\(userEditRevision) locked=\(isLocked)"
                )
            }
            guard !isLocked else { return false }
            if textView.markedTextRange != nil { return true }
            if parent.noteFormatting {
                if text.isEmpty, textView.selectedRange.length == 0,
                   NSMaxRange(range) == textView.selectedRange.location, handleNoteBackspace(in: textView) { return false }
                if text == "\n", handleNoteReturn(in: textView, range: range) { return false }
            }
            if text.isEmpty, range.length == 1, removeEmptyListPrefixBeforeBackspace(in: textView, range: range) {
                return false
            }
            guard text == "\n" else { return true }
            let source = textView.text as NSString
            let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard (!parent.noteFormatting || line.hasPrefix("☐ ")),
                  let list = listPrefix(in: line) else { return true }
            let prefix = list.next
            let content = String(line.dropFirst(list.current.count))
            if content.isEmpty {
                textView.textStorage.replaceCharacters(in: lineRange, with: "\n")
                textView.selectedRange = NSRange(location: lineRange.location + 1, length: 0)
            } else {
                textView.textStorage.replaceCharacters(in: range, with: "\n" + prefix)
                textView.selectedRange = NSRange(location: range.location + prefix.utf16.count + 1, length: 0)
            }
            scheduleLayoutAndToolbarRefresh(textView, updatesToolbar: true)
            schedulePublish(textView)
            return false
        }

        private func listPrefix(in line: String) -> (current: String, next: String)? {
            if let marker = NoteListMarker.read(line) {
                if marker.kind == .bullet { return (marker.prefix, marker.prefix) }
                let next = marker.kind.next.prefix.replacingOccurrences(of: "\t", with: " ")
                return (marker.prefix, next)
            }
            if line.hasPrefix("☐ ") { return ("☐ ", "☐ ") }
            return nil
        }

        private enum NoteParagraphCommand: Equatable {
            case bullets, numbers, quote, callout
        }

        private func noteParagraphRange(in view: UITextView, selection: NSRange) -> NSRange {
            let source = view.textStorage.string as NSString
            if selection.location == source.length, selection.length == 0,
               source.length == 0 || [10, 13, 0x2029].contains(source.character(at: source.length - 1)) {
                return selection
            }
            return source.paragraphRange(for: selection)
        }

        private func noteTextWithoutPlaceholder(_ text: String) -> String {
            text.replacingOccurrences(of: NativeRichTextNoteFormatting.placeholder, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func noteAttributes(
            in text: NSAttributedString, view: UITextView, after marker: NoteListMarker? = nil
        ) -> [NSAttributedString.Key: Any] {
            let offset = marker?.prefix.utf16.count ?? 0
            return offset < text.length ? text.attributes(at: offset, effectiveRange: nil) : view.typingAttributes
        }

        private func addNotePlaceholder(to text: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]) {
            let insertion = NSAttributedString(
                string: NativeRichTextNoteFormatting.placeholder,
                attributes: NativeRichTextNoteFormatting.plainAttributes(from: attributes)
            )
            text.insert(insertion, at: 0)
        }

        private func clearNoteBlock(
            in text: NSMutableAttributedString,
            marker: NoteListMarker?,
            remainingBlock: NativeRichTextNoteBlockKind? = nil,
            attributes: [NSAttributedString.Key: Any]
        ) {
            if let marker { text.deleteCharacters(in: NSRange(location: 0, length: marker.prefix.utf16.count)) }
            let placeholder = NativeRichTextNoteFormatting.placeholder
            if text.string.contains(placeholder) {
                text.mutableString.replaceOccurrences(
                    of: placeholder, with: "", options: [], range: NSRange(location: 0, length: text.length)
                )
            }
            if remainingBlock != nil, noteTextWithoutPlaceholder(text.string).isEmpty {
                addNotePlaceholder(to: text, attributes: attributes)
            }
            NativeRichTextNoteFormatting.applyBlock(remainingBlock, to: text, range: NSRange(location: 0, length: text.length))
        }

        private func editNoteParagraphs(_ command: NoteParagraphCommand, view: UITextView, selection: NSRange) {
            let target = noteParagraphRange(in: view, selection: selection)
            let source = view.textStorage.attributedSubstring(from: target)
            var paragraphs: [NSAttributedString] = []
            RichTextTextView.enumerateParagraphRanges(in: source.string) { range, _ in
                paragraphs.append(source.attributedSubstring(from: range))
            }
            if paragraphs.isEmpty { paragraphs = [source] }
            let removesList = paragraphs.allSatisfy { paragraph in
                guard let kind = NoteListMarker.read(in: paragraph)?.kind else { return false }
                if command == .bullets { return kind == .bullet }
                if command == .numbers, case .number = kind { return true }
                return false
            }
            let replacement = NSMutableAttributedString(string: "")
            var oldPrefixLength = 0
            var newPrefixLength = 0
            for (index, paragraph) in paragraphs.enumerated() {
                let marker = NoteListMarker.read(in: paragraph)
                let attributes = noteAttributes(in: paragraph, view: view, after: marker)
                let block = NativeRichTextNoteFormatting.block(in: attributes)
                var containsAttachment = false
                paragraph.enumerateAttribute(.attachment, in: NSRange(location: 0, length: paragraph.length)) { value, _, stop in
                    if value != nil { containsAttachment = true; stop.pointee = true }
                }
                guard !containsAttachment, block != .divider else { replacement.append(paragraph); continue }
                let updated = NSMutableAttributedString(attributedString: paragraph)
                var prefixLength = 0
                switch command {
                case .bullets, .numbers:
                    if removesList {
                        clearNoteBlock(in: updated, marker: marker, attributes: attributes)
                    } else {
                        if block != nil { clearNoteBlock(in: updated, marker: marker, attributes: attributes) }
                        let currentMarker = block == nil ? marker : nil
                        let body = currentMarker.map { String(updated.string.dropFirst($0.prefix.count)) } ?? updated.string
                        if noteTextWithoutPlaceholder(body).isEmpty, !body.contains(NativeRichTextNoteFormatting.placeholder) {
                            let offset = currentMarker?.prefix.utf16.count ?? 0
                            let empty = NSMutableAttributedString(string: "")
                            addNotePlaceholder(to: empty, attributes: attributes)
                            updated.insert(empty, at: offset)
                        }
                        let kind: NoteListMarker.Kind = command == .bullets ? .bullet : .number(index + 1)
                        NoteListMarker.apply(kind, to: updated, oldMarker: currentMarker)
                        prefixLength = kind.prefix.utf16.count
                    }
                case .quote:
                    let next: NativeRichTextNoteBlockKind? = switch block {
                    case .quote: nil
                    case .callout: .calloutQuote
                    case .calloutQuote: .callout
                    default: .quote
                    }
                    clearNoteBlock(in: updated, marker: marker, remainingBlock: next, attributes: attributes)
                case .callout:
                    let next: NativeRichTextNoteBlockKind? = switch block {
                    case .callout: nil
                    case .quote: .calloutQuote
                    case .calloutQuote: .quote
                    default: .callout
                    }
                    clearNoteBlock(in: updated, marker: marker, remainingBlock: next, attributes: attributes)
                }
                if index == 0 {
                    oldPrefixLength = marker?.prefix.utf16.count ?? 0
                    newPrefixLength = prefixLength
                }
                replacement.append(updated)
            }
            let newSelection: NSRange
            if selection.length == 0 {
                let offset = max(0, selection.location - target.location - oldPrefixLength) + newPrefixLength
                newSelection = NSRange(location: target.location + min(offset, replacement.length), length: 0)
            } else {
                newSelection = NSRange(location: target.location, length: replacement.length)
            }
            _ = commitNoteEdit(replacement, in: target, selection: newSelection, view: view)
        }

        private func insertNoteDivider(in view: UITextView, selection: NSRange) {
            let range = noteParagraphRange(in: view, selection: selection)
            let paragraph = view.textStorage.attributedSubstring(from: range)
            let attributes = NativeRichTextNoteFormatting.plainAttributes(from: noteAttributes(in: paragraph, view: view))
            let marker = NoteListMarker.read(in: paragraph)
            let content = marker.map { String(paragraph.string.dropFirst($0.prefix.count)) } ?? paragraph.string
            let target = noteTextWithoutPlaceholder(content).isEmpty
                ? range : NSRange(location: NSMaxRange(range), length: 0)
            let divider = NSMutableAttributedString(string: "\(NativeRichTextNoteFormatting.placeholder)\n", attributes: attributes)
            NativeRichTextNoteFormatting.applyBlock(.divider, to: divider, range: NSRange(location: 0, length: divider.length))
            if target.location > range.location, paragraph.string.last?.isNewline != true {
                divider.insert(NSAttributedString(string: "\n", attributes: noteAttributes(in: paragraph, view: view)), at: 0)
            }
            _ = commitNoteEdit(
                divider, in: target, selection: NSRange(location: target.location + divider.length, length: 0),
                view: view, typingAttributes: attributes
            )
        }

        fileprivate func handleNoteBackspace(in view: UITextView) -> Bool {
            guard parent.noteFormatting, view.markedTextRange == nil,
                  connectedSession?.isInputLocked != true, inlineBlockEdit == nil,
                  view.selectedRange.length == 0 else { return false }
            let caret = view.selectedRange.location
            let range = noteParagraphRange(in: view, selection: view.selectedRange)
            let text = NSMutableAttributedString(attributedString: view.textStorage.attributedSubstring(from: range))
            let marker = NoteListMarker.read(in: text)
            let attributes = noteAttributes(in: text, view: view, after: marker)
            let block = text.length > 0 ? NativeRichTextNoteFormatting.block(in: attributes) : nil
            let bodyStart = range.location + (marker?.prefix.utf16.count ?? 0)
            let body = String(text.string.dropFirst(marker?.prefix.count ?? 0))
            if marker != nil || block != nil,
               caret <= bodyStart || noteTextWithoutPlaceholder(body).isEmpty {
                if block == .divider {
                    return commitNoteEdit(NSAttributedString(string: ""), in: range, selection: NSRange(location: range.location, length: 0),
                                          view: view, typingAttributes: NativeRichTextNoteFormatting.plainAttributes(from: attributes))
                }
                let remaining: NativeRichTextNoteBlockKind? = block == .calloutQuote ? .callout : nil
                clearNoteBlock(in: text, marker: marker, remainingBlock: remaining, attributes: attributes)
                return commitNoteEdit(
                    text, in: range, selection: NSRange(location: range.location, length: 0), view: view,
                    typingAttributes: remaining == nil && text.length == 0
                        ? NativeRichTextNoteFormatting.plainAttributes(from: attributes) : nil
                )
            }
            guard caret == range.location, caret > 0 else { return false }
            let previous = noteParagraphRange(in: view, selection: NSRange(location: caret - 1, length: 1))
            let previousAttributes = view.textStorage.attributes(at: previous.location, effectiveRange: nil)
            guard NativeRichTextNoteFormatting.block(in: previousAttributes) == .divider else { return false }
            return commitNoteEdit(NSAttributedString(string: ""), in: previous,
                                  selection: NSRange(location: previous.location, length: 0), view: view,
                                  typingAttributes: NativeRichTextNoteFormatting.plainAttributes(from: attributes))
        }

        private func handleNoteReturn(in view: UITextView, range: NSRange) -> Bool {
            let paragraphRange = noteParagraphRange(in: view, selection: NSRange(location: range.location, length: 0))
            guard paragraphRange.length > 0, NSMaxRange(range) <= NSMaxRange(paragraphRange) else { return false }
            let paragraph = view.textStorage.attributedSubstring(from: paragraphRange)
            let marker = NoteListMarker.read(in: paragraph)
            let attributes = noteAttributes(in: paragraph, view: view, after: marker)
            let block = NativeRichTextNoteFormatting.block(in: attributes)
            guard marker != nil || (block != nil && block != .divider) else { return false }
            let prefixLength = marker?.prefix.utf16.count ?? 0
            let plain = NativeRichTextNoteFormatting.plainAttributes(from: attributes)
            if noteTextWithoutPlaceholder(String(paragraph.string.dropFirst(marker?.prefix.count ?? 0))).isEmpty {
                let cleared = NSMutableAttributedString(attributedString: paragraph)
                clearNoteBlock(in: cleared, marker: marker, attributes: attributes)
                return commitNoteEdit(cleared, in: paragraphRange,
                                      selection: NSRange(location: paragraphRange.location, length: 0),
                                      view: view, typingAttributes: plain)
            }

            let start = max(prefixLength, range.location - paragraphRange.location)
            let end = max(start, NSMaxRange(range) - paragraphRange.location)
            let first = NSMutableAttributedString(attributedString: paragraph.attributedSubstring(from: NSRange(location: 0, length: start)))
            let second = NSMutableAttributedString(attributedString: paragraph.attributedSubstring(from: NSRange(location: end, length: paragraph.length - end)))
            first.append(NSAttributedString(string: "\n", attributes: attributes))
            let nextPrefix: Int
            if let marker {
                if noteTextWithoutPlaceholder(second.string).isEmpty, !second.string.contains(NativeRichTextNoteFormatting.placeholder) {
                    addNotePlaceholder(to: second, attributes: attributes)
                }
                if let style = attributes[.paragraphStyle], second.length > 0 {
                    second.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: second.length))
                }
                NoteListMarker.apply(marker.kind.next, to: second, oldMarker: nil)
                nextPrefix = marker.kind.next.prefix.utf16.count
            } else {
                clearNoteBlock(in: second, marker: nil, attributes: attributes)
                nextPrefix = 0
            }
            let caret = paragraphRange.location + first.length + nextPrefix
            first.append(second)
            var target = paragraphRange
            if case let .number(number)? = marker?.kind {
                let source = view.textStorage.string as NSString
                let indent = (attributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent
                var expected = number + 1
                while NSMaxRange(target) < source.length {
                    let nextRange = source.paragraphRange(for: NSRange(location: NSMaxRange(target), length: 0))
                    let next = NSMutableAttributedString(attributedString: view.textStorage.attributedSubstring(from: nextRange))
                    guard let nextMarker = NoteListMarker.read(in: next), nextMarker.kind == .number(expected),
                          (next.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent == indent else { break }
                    expected += 1
                    NoteListMarker.apply(.number(expected), to: next, oldMarker: nextMarker)
                    first.append(next)
                    target.length += nextRange.length
                }
            }
            return commitNoteEdit(first, in: target,
                                  selection: NSRange(location: caret, length: 0), view: view,
                                  typingAttributes: marker == nil ? plain : nil)
        }

        @discardableResult
        private func commitNoteEdit(
            _ replacement: NSAttributedString, in target: NSRange, selection: NSRange, view: UITextView,
            typingAttributes: [NSAttributedString.Key: Any]? = nil
        ) -> Bool {
            guard replaceAttributed(replacement, in: target, view: view, preservesSelection: true) else { return false }
            userEditRevision &+= 1
            view.selectedRange = selection
            if let typingAttributes { view.typingAttributes = typingAttributes }
            else if selection.length == 0, selection.location < view.textStorage.length {
                view.typingAttributes = view.textStorage.attributes(at: selection.location, effectiveRange: nil)
            } else if selection.length == 0 {
                view.typingAttributes = NativeRichTextNoteFormatting.plainAttributes(from: view.typingAttributes)
            }
            rememberSelection(selection)
            return true
        }

        private func removeEmptyListPrefixBeforeBackspace(in view: UITextView, range: NSRange) -> Bool {
            let source = view.text as NSString
            let caret = range.location + range.length
            let lineRange = source.lineRange(for: NSRange(location: caret, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let list = listPrefix(in: line), line == list.current, caret == lineRange.location + list.current.utf16.count else { return false }
            view.textStorage.replaceCharacters(in: NSRange(location: lineRange.location, length: list.current.utf16.count), with: "")
            view.selectedRange = NSRange(location: lineRange.location, length: 0)
            scheduleLayoutAndToolbarRefresh(view, updatesToolbar: true)
            schedulePublish(view)
            return true
        }

        @discardableResult
        private func replaceAttributed(
            _ replacement: NSAttributedString, in range: NSRange, view: UITextView, preservesSelection: Bool = false
        ) -> Bool {
            NativeRichTextPastePolicy.replace(
                replacement,
                in: range,
                of: view.textStorage,
                undoManager: view.undoManager,
                onReplacement: { [weak self, weak view] replacementRange, replacedText in
                    guard let self, let view else { return }
                    if !preservesSelection || !self.validSelection(view.selectedRange, in: view) {
                        view.selectedRange = NSRange(location: replacementRange.location + replacedText.length, length: 0)
                    }
                    if self.parent.noteFormatting {
                        self.measuredHeightNeedsRefresh = true
                        self.forcedNoteHeightMeasurement = (
                            self.documentRevision &+ 1,
                            self.parent.editorSessionID,
                            self.parent.editorDocumentID ?? ""
                        )
                    }
                    self.scheduleLayoutAndToolbarRefresh(view, updatesToolbar: true)
                    self.schedulePublish(view)
                }
            )
        }

        func handlePaste(_ textView: UITextView) -> Bool {
            guard connectedSession?.isInputLocked != true, closeInlineBlockField(in: textView) else { return true }
            guard textView.markedTextRange == nil else { return false }
            let range = textView.selectedRange
            if parent.noteFormatting {
                LibraryPerformanceLog.event(
                    "note.paste.begin id=\(LibraryPerformanceLog.shortIdentifier(parent.editorDocumentID ?? "")) revision=\(documentRevision) location=\(range.location) length=\(range.length)"
                )
            }
            guard range.location >= 0,
                  range.length >= 0,
                  NSMaxRange(range) <= textView.attributedText.length else {
                if parent.noteFormatting { LibraryPerformanceLog.event("note.paste.invalid-range revision=\(documentRevision)") }
                return false
            }

            guard let replacement = preparedClipboardText() else {
                if parent.noteFormatting { LibraryPerformanceLog.event("note.paste.system-fallback revision=\(documentRevision)") }
                return false
            }
            let prepared: NSAttributedString
            if parent.noteFormatting {
                let noteFormatted = RichTextTextView.applyingNoteInsertionParagraphContext(
                    replacement,
                    from: textView,
                    replacing: range
                )
                prepared = noteFormatted
            } else {
                prepared = NativeRichTextPastePolicy.compactParagraphSpacing(in: replacement)
            }
            replaceAttributed(prepared, in: range, view: textView)
            if containsNativeTableAttachment(prepared) {
                updateNativeTableWidths(in: textView, force: true)
            }
            if parent.noteFormatting {
                LibraryPerformanceLog.event("note.paste.applied revision=\(documentRevision) insertedLength=\(prepared.length)")
            }
            return true
        }

        func logNoteCopy(_ textView: UITextView, completed: Bool) {
            guard parent.noteFormatting else { return }
            let range = textView.selectedRange
            let isValid = validSelection(range, in: textView)
            LibraryPerformanceLog.event(
                "note.copy.\(completed ? "completed" : "begin") id=\(LibraryPerformanceLog.shortIdentifier(parent.editorDocumentID ?? "")) revision=\(documentRevision) valid=\(isValid) location=\(range.location) length=\(range.length)"
            )
        }

        private func containsNativeTableAttachment(_ attributed: NSAttributedString) -> Bool {
            guard attributed.length > 0 else { return false }
            var found = false
            attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
                if value is NativeTableAttachment {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        private func normalizeResidualMarkdownBold(in value: NSMutableAttributedString) {
            guard value.length > 0 else { return }
            let source = value.string as NSString
            var pairs: [(open: NSRange, close: NSRange, content: NSRange)] = []

            func isEscaped(at location: Int) -> Bool {
                var cursor = location - 1
                var slashCount = 0
                while cursor >= 0, source.character(at: cursor) == 92 {
                    slashCount += 1
                    cursor -= 1
                }
                return slashCount % 2 == 1
            }

            func isTripleMarker(_ range: NSRange) -> Bool {
                let before = range.location > 0 && source.character(at: range.location - 1) == 42
                let after = NSMaxRange(range) < source.length && source.character(at: NSMaxRange(range)) == 42
                return before || after
            }

            func isWhitespace(at location: Int) -> Bool {
                guard location >= 0, location < source.length else { return true }
                return source.substring(with: NSRange(location: location, length: 1))
                    .rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            }

            func isCodeOrLink(_ range: NSRange) -> Bool {
                var protected = false
                value.enumerateAttributes(in: range) { attributes, _, stop in
                    let font = attributes[.font] as? UIFont
                    if attributes[.link] != nil
                        || attributes[.attachment] != nil
                        || font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true {
                        protected = true
                        stop.pointee = true
                    }
                }
                return protected
            }

            var paragraphCursor = 0
            while paragraphCursor < source.length {
                var paragraphStart = 0
                var paragraphEnd = 0
                var contentsEnd = 0
                source.getParagraphStart(
                    &paragraphStart,
                    end: &paragraphEnd,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: paragraphCursor, length: 0)
                )
                guard paragraphEnd > paragraphCursor else { break }
                let contentEnd = max(paragraphStart, contentsEnd)
                var cursor = paragraphStart
                while cursor + 1 < contentEnd {
                    let open = source.range(of: "**", options: [], range: NSRange(location: cursor, length: contentEnd - cursor))
                    guard open.location != NSNotFound else { break }
                    let openRange = NSRange(location: open.location, length: 2)
                    guard !isEscaped(at: openRange.location), !isTripleMarker(openRange),
                          !isWhitespace(at: NSMaxRange(openRange)), !isCodeOrLink(openRange) else {
                        cursor = NSMaxRange(openRange)
                        continue
                    }

                    var closeCursor = NSMaxRange(openRange)
                    var acceptedClose: NSRange?
                    while closeCursor + 1 < contentEnd {
                        let close = source.range(
                            of: "**",
                            options: [],
                            range: NSRange(location: closeCursor, length: contentEnd - closeCursor)
                        )
                        guard close.location != NSNotFound else { break }
                        let closeRange = NSRange(location: close.location, length: 2)
                        if !isEscaped(at: closeRange.location), !isTripleMarker(closeRange),
                           !isWhitespace(at: closeRange.location - 1), !isCodeOrLink(closeRange) {
                            acceptedClose = closeRange
                            break
                        }
                        closeCursor = NSMaxRange(closeRange)
                    }
                    guard let closeRange = acceptedClose,
                          closeRange.location > NSMaxRange(openRange) else {
                        cursor = NSMaxRange(openRange)
                        continue
                    }
                    pairs.append((
                        open: openRange,
                        close: closeRange,
                        content: NSRange(location: NSMaxRange(openRange), length: closeRange.location - NSMaxRange(openRange))
                    ))
                    cursor = NSMaxRange(closeRange)
                }
                paragraphCursor = paragraphEnd
            }

            for pair in pairs.reversed() {
                var fontUpdates: [(NSRange, UIFont)] = []
                value.enumerateAttribute(.font, in: pair.content) { attribute, range, _ in
                    let font = attribute as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
                    var traits = font.fontDescriptor.symbolicTraits
                    traits.insert(.traitBold)
                    let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
                    fontUpdates.append((range, UIFont(descriptor: descriptor, size: font.pointSize)))
                }
                for (range, font) in fontUpdates { value.addAttribute(.font, value: font, range: range) }
                value.deleteCharacters(in: pair.close)
                value.deleteCharacters(in: pair.open)
            }
        }

        private func preparedClipboardText() -> NSAttributedString? {
            let pasteboard = UIPasteboard.general
            let richCandidates: [(String, NSAttributedString.DocumentType)] = [
                ("com.apple.flat-rtfd", .rtfd),
                (UTType.rtfd.identifier, .rtfd),
                (UTType.rtf.identifier, .rtf),
                (UTType.html.identifier, .html)
            ]
            let plainTypes = [
                UTType.utf8PlainText.identifier,
                UTType.plainText.identifier,
                UTType.text.identifier
            ]

            for item in pasteboard.items {
                let plainText = plainTypes.compactMap { type in
                    item[type].flatMap(Self.stringRepresentation)
                }.first

                if let htmlValue = item[UTType.html.identifier],
                   let html = Self.stringRepresentation(htmlValue),
                   html.contains("[[NATIVE_TABLE:"),
                   let imported = Self.attributedRepresentation(htmlValue, documentType: .html) {
                    return finalizedRichPaste(imported, plainText: plainText, htmlData: nil, sourceHTML: html, htmlIsPrimary: true)
                }

                if let htmlValue = item[UTType.html.identifier],
                   let html = Self.stringRepresentation(htmlValue),
                   NativeRichTextTablePasteParser.containsHTMLTable(html) {
                    if let tables = NativeRichTextTablePasteParser.htmlTables(in: html), !tables.isEmpty,
                       let richTablePaste = prepareHTMLTablePaste(html, tables: tables, plainText: plainText) {
                        return richTablePaste
                    }
                    if let plainText { return plainTextPaste(plainText) }
                    if let imported = Self.attributedRepresentation(htmlValue, documentType: .html) {
                        return finalizedRichPaste(
                            imported,
                            plainText: nil,
                            htmlData: Self.dataRepresentation(htmlValue),
                            sourceHTML: html,
                            htmlIsPrimary: true
                        )
                    }
                }

                if let plainText {
                    let normalized = NativeRichTextTablePasteParser.normalizeLineEndings(plainText)
                    let tables = NativeRichTextTablePasteParser.markdownTables(in: normalized)
                    if !tables.isEmpty {
                        let richRepresentation = [
                            ("com.apple.flat-rtfd", NSAttributedString.DocumentType.rtfd),
                            (UTType.rtfd.identifier, .rtfd),
                            (UTType.rtf.identifier, .rtf)
                        ].compactMap { type, documentType in
                            item[type].flatMap { Self.attributedRepresentation($0, documentType: documentType) }
                        }.first
                        if let richRepresentation,
                           richRepresentation.string == plainText,
                           let enriched = replacingMarkdownTables(
                            tables,
                            in: normalizedAttributedLineEndings(richRepresentation)
                           ) {
                            return finalizedRichPaste(
                                enriched,
                                plainText: plainText,
                                htmlData: nil,
                                sourceHTML: item[UTType.html.identifier].flatMap(Self.stringRepresentation)
                            )
                        }
                        return markdownTablePaste(normalized, tables: tables)
                    }
                }

                for (type, documentType) in richCandidates {
                    guard let raw = item[type],
                          let imported = Self.attributedRepresentation(raw, documentType: documentType) else { continue }
                    let htmlValue = item[UTType.html.identifier]
                    let clipboardHTML = htmlValue.flatMap(Self.stringRepresentation)
                    let primary = NSMutableAttributedString(attributedString: imported)
                    if let plainText {
                        NativeRichTextPastePolicy.removeOnlyProvenBoundaryNewlines(from: primary, matching: plainText)
                    }
                    var companionHTML = htmlValue.flatMap { Self.attributedRepresentation($0, documentType: .html) }
                    if let plainText, let companion = companionHTML {
                        let normalized = NSMutableAttributedString(attributedString: companion)
                        NativeRichTextPastePolicy.removeOnlyProvenBoundaryNewlines(from: normalized, matching: plainText)
                        companionHTML = normalized
                    }

                    let alignedCompanion = documentType != .html
                        && companionHTML.map { clipboardRepresentationsMatch(primary, $0) } == true
                    if documentType == .html {
                        return finalizedRichPaste(
                            primary,
                            plainText: plainText,
                            htmlData: Self.dataRepresentation(raw),
                            sourceHTML: clipboardHTML,
                            htmlIsPrimary: true
                        )
                    }
                    if alignedCompanion, let companionHTML {
                        let attachments = clipboardAttachmentRanges(in: primary)
                        if attachments.isEmpty {
                            return finalizedRichPaste(
                                companionHTML,
                                plainText: plainText,
                                htmlData: nil,
                                sourceHTML: clipboardHTML,
                                htmlIsPrimary: true
                            )
                        }
                        return finalizedRichPaste(
                            primary,
                            plainText: plainText,
                            htmlData: nil,
                            sourceHTML: clipboardHTML,
                            companionHTML: companionHTML
                        )
                    }
                    return finalizedRichPaste(
                        primary,
                        plainText: plainText,
                        htmlData: nil
                    )
                }

                guard let plainText else { continue }
                if let markdownHTML = NativeRichTextMarkdown.htmlIfMarkdown(plainText) {
                    return finalizedRichPaste(
                        RichTextTextView.attributed(from: markdownHTML, noteFormatting: parent.noteFormatting),
                        plainText: plainText,
                        htmlData: nil,
                        sourceHTML: markdownHTML,
                        htmlIsPrimary: true
                    )
                }
                return plainTextPaste(plainText)
            }
            return nil
        }

        private func clipboardRepresentationsMatch(
            _ primary: NSAttributedString,
            _ companion: NSAttributedString
        ) -> Bool {
            let primaryText = NativeRichTextTablePasteParser.normalizeLineEndings(primary.string)
            let companionText = NativeRichTextTablePasteParser.normalizeLineEndings(companion.string)
            guard primaryText == companionText,
                  RichTextTextView.paragraphContents(in: primary) == RichTextTextView.paragraphContents(in: companion) else { return false }

            let primaryAttachments = clipboardAttachmentRanges(in: primary)
            let companionAttachments = clipboardAttachmentRanges(in: companion)
            guard primaryAttachments.count == companionAttachments.count else { return false }
            for (left, right) in zip(primaryAttachments, companionAttachments) {
                guard left.range == right.range else { return false }
                switch (left.attachment, right.attachment) {
                case let (lhs as NativeImageAttachment, rhs as NativeImageAttachment):
                    guard lhs.marker == rhs.marker else { return false }
                case let (lhs as NativeUnavailableImageAttachment, rhs as NativeUnavailableImageAttachment):
                    guard lhs.marker == rhs.marker else { return false }
                case let (lhs as NativeTableAttachment, rhs as NativeTableAttachment):
                    guard lhs.table == rhs.table else { return false }
                case let (lhs as NativeFormulaAttachment, rhs as NativeFormulaAttachment):
                    guard lhs.formula == rhs.formula else { return false }
                case let (lhs as NativeOpaqueRichTextAttachment, rhs as NativeOpaqueRichTextAttachment):
                    guard lhs.marker == rhs.marker else { return false }
                default:
                    guard left.attachment.fileType == right.attachment.fileType,
                          let leftData = left.attachment.fileWrapper?.regularFileContents,
                          let rightData = right.attachment.fileWrapper?.regularFileContents,
                          leftData == rightData else { return false }
                }
            }
            return true
        }

        private func clipboardAttachmentRanges(
            in value: NSAttributedString
        ) -> [(range: NSRange, attachment: NSTextAttachment)] {
            guard value.length > 0 else { return [] }
            var result: [(NSRange, NSTextAttachment)] = []
            value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { item, range, _ in
                guard let attachment = item as? NSTextAttachment else { return }
                result.append((range, attachment))
            }
            return result
        }

        private func finalizedRichPaste(
            _ source: NSAttributedString,
            plainText: String?,
            htmlData: Data?,
            sourceHTML: String? = nil,
            companionHTML: NSAttributedString? = nil,
            htmlIsPrimary: Bool = false
        ) -> NSAttributedString {
            let richText = NSMutableAttributedString(attributedString: source)
            RichTextTextView.restoreNativeTables(in: richText)
            if let plainText {
                NativeRichTextPastePolicy.removeOnlyProvenBoundaryNewlines(from: richText, matching: plainText)
            }
            let plainTextMatchesPrimary = plainText.map {
                NativeRichTextTablePasteParser.normalizeLineEndings(richText.string)
                    == NativeRichTextTablePasteParser.normalizeLineEndings($0)
            } ?? false
            let markdownMarkup = plainTextMatchesPrimary
                ? plainText.flatMap(NativeRichTextMarkdown.htmlIfMarkdown)
                : nil
            let markup = sourceHTML
                ?? htmlData.flatMap { String(data: $0, encoding: .utf8) }
                ?? markdownMarkup
            var paragraphMetadata: [NativeRichTextNoteParagraphHTMLMetadata?]?
            var headingSizes: [String: [CGFloat]] = [:]
            var markupMatchesPrimary = htmlIsPrimary
            if let markup, htmlIsPrimary {
                paragraphMetadata = RichTextTextView.alignedParagraphMetadata(in: markup, matching: richText)
                headingSizes = RichTextTextView.semanticHeadingSizes(in: markup, matching: richText)
            } else if let markup, let companionHTML {
                let companion = NSMutableAttributedString(attributedString: companionHTML)
                if let plainText {
                    NativeRichTextPastePolicy.removeOnlyProvenBoundaryNewlines(from: companion, matching: plainText)
                }
                let companionMetadata = RichTextTextView.alignedParagraphMetadata(in: markup, matching: companion)
                if clipboardRepresentationsMatch(richText, companion),
                   RichTextTextView.applyingCompanionParagraphStyles(
                    from: companion,
                    to: richText,
                    paragraphMetadata: companionMetadata
                ) {
                    paragraphMetadata = companionMetadata
                    headingSizes = RichTextTextView.semanticHeadingSizes(in: markup, matching: companion)
                    markupMatchesPrimary = true
                }
            }
            if headingSizes.isEmpty, markupMatchesPrimary, let markup, let data = markup.data(using: .utf8) {
                headingSizes = RichTextTextView.semanticHeadingSizes(in: data)
            } else if headingSizes.isEmpty, let htmlData {
                headingSizes = RichTextTextView.semanticHeadingSizes(in: htmlData)
            }
            if !parent.noteFormatting {
                RichTextTextView.markSourceParagraphSemantics(
                    in: richText,
                    metadata: paragraphMetadata,
                    semanticHeadingSizes: headingSizes
                )
            }
            normalizeResidualMarkdownBold(in: richText)
            RichTextTextView.normalizePastedFonts(in: richText, semanticHeadingSizes: headingSizes)
            if parent.noteFormatting {
                if let markup { RichTextTextView.applyHTMLListMarkers(from: markup, to: richText) }
                let styled = RichTextTextView.applyingNoteParagraphFormatting(
                    to: richText,
                    sourceHTML: markup,
                    paragraphMetadata: paragraphMetadata
                )
                richText.setAttributedString(RichTextTextView.normalizingPastedNoteParagraphs(
                    in: styled,
                    hasStructuredParagraphs: RichTextTextView.hasStructuredParagraphs(in: styled),
                    paragraphMetadata: paragraphMetadata
                ))
            }
            return NativeRichTextDisplayRenderer.applyingTableAppearance(
                to: richText,
                appearance: parent.tableAppearance
            )
        }

        private func plainTextPaste(_ text: String) -> NSAttributedString {
            if parent.noteFormatting,
               let markdownHTML = NativeRichTextMarkdown.htmlIfMarkdown(text) {
                let styled = RichTextTextView.attributed(from: markdownHTML, noteFormatting: true)
                let metadata = RichTextTextView.alignedParagraphMetadata(in: markdownHTML, matching: styled)
                return RichTextTextView.normalizingPastedNoteParagraphs(
                    in: styled,
                    hasStructuredParagraphs: RichTextTextView.hasStructuredParagraphs(in: styled),
                    paragraphMetadata: metadata
                )
            }
            let plain = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize),
                    .foregroundColor: UIColor.label
                ]
            )
            guard parent.noteFormatting else {
                let explicitParagraphs = NSMutableAttributedString(attributedString: plain)
                RichTextTextView.markConfirmedPlainTextParagraphs(in: explicitParagraphs)
                return explicitParagraphs
            }
            let styled = RichTextTextView.applyingNoteParagraphFormatting(to: plain, sourceHTML: nil)
            return RichTextTextView.normalizingPastedNoteParagraphs(in: styled, hasStructuredParagraphs: false)
        }

        private func prepareHTMLTablePaste(
            _ html: String,
            tables: [NativeRichTextPastedTable],
            plainText: String?
        ) -> NSAttributedString? {
            let source = NSMutableString(string: html)
            var pending: [PendingRichTextTableMarker] = []
            for parsed in tables.reversed() {
                guard parsed.range.location >= 0,
                      NSMaxRange(parsed.range) <= source.length else { return nil }
                let marker = "NATIVE_TABLE_PASTE_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                source.replaceCharacters(in: parsed.range, with: "<p>\(marker)</p>")
                pending.append(PendingRichTextTableMarker(
                    marker: marker,
                    table: RichTextTable(cells: parsed.cells, cellBoldRanges: parsed.boldRanges)
                ))
            }
            let imported = RichTextTextView.attributed(from: source as String, noteFormatting: parent.noteFormatting)
            let richText = NSMutableAttributedString(attributedString: imported)
            RichTextTextView.restoreNativeTables(in: richText)
            for item in pending {
                let search = richText.string as NSString
                let range = search.range(of: item.marker)
                guard range.location != NSNotFound else { return nil }
                richText.replaceCharacters(in: range, with: NSAttributedString(attachment: NativeTableAttachment(table: item.table)))
            }
            if let plainText {
                NativeRichTextPastePolicy.removeOnlyProvenBoundaryNewlines(from: richText, matching: plainText)
            }
            RichTextTextView.normalizePastedFonts(in: richText, semanticHeadingSizes: RichTextTextView.semanticHeadingSizes(in: Data(html.utf8)))
            if parent.noteFormatting {
                RichTextTextView.applyHTMLListMarkers(from: html, to: richText)
                let metadata = RichTextTextView.alignedParagraphMetadata(in: html, matching: richText)
                let styled = RichTextTextView.applyingNoteParagraphFormatting(
                    to: richText,
                    sourceHTML: html,
                    paragraphMetadata: metadata
                )
                richText.setAttributedString(RichTextTextView.normalizingPastedNoteParagraphs(
                    in: styled,
                    hasStructuredParagraphs: RichTextTextView.hasStructuredParagraphs(in: styled),
                    paragraphMetadata: metadata
                ))
            }
            return NativeRichTextDisplayRenderer.applyingTableAppearance(
                to: richText,
                appearance: parent.tableAppearance
            )
        }

        private func normalizedAttributedLineEndings(_ source: NSAttributedString) -> NSAttributedString {
            let normalized = NSMutableAttributedString(attributedString: source)
            let original = source.string as NSString
            var replacements: [(NSRange, [NSAttributedString.Key: Any])] = []
            var location = 0
            while location < original.length {
                let character = original.character(at: location)
                if character == 13 {
                    let length = location + 1 < original.length && original.character(at: location + 1) == 10 ? 2 : 1
                    replacements.append((NSRange(location: location, length: length), source.attributes(at: location, effectiveRange: nil)))
                    location += length
                } else {
                    location += 1
                }
            }
            for (range, attributes) in replacements.reversed() {
                normalized.replaceCharacters(in: range, with: "\n")
                normalized.setAttributes(attributes, range: NSRange(location: range.location, length: 1))
            }
            return normalized
        }

        private func markdownTablePaste(_ text: String, tables: [NativeRichTextPastedTable]) -> NSAttributedString {
            let output = NSMutableAttributedString(string: "")
            var cursor = 0
            for parsed in tables {
                guard parsed.range.location >= cursor, NSMaxRange(parsed.range) <= (text as NSString).length else { continue }
                let prefixRange = NSRange(location: cursor, length: parsed.range.location - cursor)
                if prefixRange.length > 0 {
                    let prefix = (text as NSString).substring(with: prefixRange)
                    output.append(formattedTextSegment(prefix))
                }
                output.append(NSAttributedString(attachment: NativeTableAttachment(
                    table: RichTextTable(cells: parsed.cells, cellBoldRanges: parsed.boldRanges),
                    appearance: parent.tableAppearance
                )))
                cursor = NSMaxRange(parsed.range)
            }
            let fullLength = (text as NSString).length
            if cursor < fullLength {
                output.append(formattedTextSegment((text as NSString).substring(from: cursor)))
            }
            if output.length == 0 { return plainTextPaste(text) }
            return output
        }

        private func replacingMarkdownTables(
            _ tables: [NativeRichTextPastedTable],
            in source: NSAttributedString
        ) -> NSAttributedString? {
            let result = NSMutableAttributedString(attributedString: source)
            guard tables.allSatisfy({ $0.range.location >= 0 && NSMaxRange($0.range) <= result.length }) else { return nil }
            for parsed in tables.reversed() {
                result.replaceCharacters(
                    in: parsed.range,
                    with: NSAttributedString(attachment: NativeTableAttachment(
                        table: RichTextTable(cells: parsed.cells, cellBoldRanges: parsed.boldRanges),
                        appearance: parent.tableAppearance
                    ))
                )
            }
            return result
        }

        private func formattedTextSegment(_ text: String) -> NSAttributedString {
            guard let markdownHTML = NativeRichTextMarkdown.htmlIfMarkdown(text) else { return plainTextPaste(text) }
            return RichTextTextView.attributed(from: markdownHTML, noteFormatting: parent.noteFormatting)
        }

        private static func dataRepresentation(_ value: Any) -> Data? {
            if let data = value as? Data { return data }
            if let data = value as? NSData { return data as Data }
            if let string = value as? String { return string.data(using: .utf8) }
            return nil
        }

        private static func stringRepresentation(_ value: Any) -> String? {
            if let string = value as? String { return string }
            guard let data = dataRepresentation(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func attributedRepresentation(
            _ value: Any,
            documentType: NSAttributedString.DocumentType
        ) -> NSAttributedString? {
            if let attributed = value as? NSAttributedString {
                return attributed.copy() as? NSAttributedString ?? attributed
            }
            guard let data = dataRepresentation(value), data.count <= 8 * 1024 * 1024,
                  let imported = try? NSMutableAttributedString(
                    data: data,
                    options: [.documentType: documentType],
                    documentAttributes: nil
                  ), imported.length > 0 else { return nil }
            return imported
        }

        func apply(
            _ command: RichTextCommandKind,
            to view: UITextView,
            tableEditTarget: RichTextTableEditTarget? = nil
        ) -> Result<Void, NativeRichTextEditorError>? {
            guard closeInlineBlockField(in: view) else { return .failure(.tableTargetChanged) }
            let revisionBeforeCommand = documentRevision
            let range: NSRange
            if case .image(_, let target) = command {
                guard connectedSession?.matches(target) == true else {
                    return .failure(NativeRichTextEditorError.editorSessionChanged)
                }
                guard validSelection(target.range, in: view) else {
                    return .failure(NativeRichTextEditorError.invalidSelection)
                }
                range = target.range
            } else {
                range = validSelection(lastEditingSelection, in: view) ? lastEditingSelection : view.selectedRange
            }
            if !view.isFirstResponder { view.becomeFirstResponder() }
            view.selectedRange = range
            var restoreSelection = true
            var imageResult: Result<Void, NativeRichTextEditorError>?
            var tableResult: Result<Void, NativeRichTextEditorError>?
            switch command {
            case .bold: toggleFontTrait(.traitBold, view: view, range: range)
            case .italic: toggleFontTrait(.traitItalic, view: view, range: range)
            case .underline: toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, view: view, range: range)
            case .strike: toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, view: view, range: range)
            case let .heading(level): applyHeading(level, view: view, range: range)
            case let .foreground(color): applyAttribute(.foregroundColor, value: color.uiColor, view: view, range: range)
            case .highlight: toggleAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), view: view, range: range)
            case let .paragraphHighlight(color): toggleParagraphHighlight(color, view: view, range: range)
            case .quote:
                if parent.noteFormatting { editNoteParagraphs(.quote, view: view, selection: range); restoreSelection = false }
                else { toggleQuote(view: view, range: range) }
            case .border:
                if parent.noteFormatting { editNoteParagraphs(.callout, view: view, selection: range); restoreSelection = false }
                else { toggleBorder(view: view, range: range) }
            case .code: toggleCode(view: view, range: range)
            case .indent: changeIndent(18, view: view, range: range)
            case .outdent: changeIndent(-18, view: view, range: range)
            case .bullets:
                if parent.noteFormatting { editNoteParagraphs(.bullets, view: view, selection: range) }
                else { toggleParagraphPrefixes("• ", view: view, range: range) }
                restoreSelection = false
            case .numbers:
                if parent.noteFormatting { editNoteParagraphs(.numbers, view: view, selection: range) }
                else { numberParagraphs(view: view, range: range) }
                restoreSelection = false
            case .todos: toggleParagraphPrefixes("☐ ", view: view, range: range); restoreSelection = false
            case .divider:
                if parent.noteFormatting { insertNoteDivider(in: view, selection: range) }
                else { insertDivider(view: view, range: range) }
                restoreSelection = false
            case let .table(table):
                let result = upsertTable(table, view: view, target: tableEditTarget)
                tableResult = result
                if case .success = result, parent.usesInlineBlockEditing,
                   tableEditTarget?.attachmentInstanceID == nil, let target = parent.tableEditTarget {
                    DispatchQueue.main.async { [weak self, weak view] in
                        guard let self, let view else { return }
                        self.editInlineBlock(at: target, cell: .init(row: 0, column: 0), in: view)
                    }
                }
                restoreSelection = false
            case let .image(dataURL, target):
                imageResult = insertImage(dataURL, target: target, view: view)
                restoreSelection = false
            case let .formula(formula): upsertFormula(formula, view: view, range: range); restoreSelection = false
            case let .internalLink(link): insertInternalLink(link, view: view, range: range); restoreSelection = false
            case let .link(target): addLink(target, view: view, range: range); restoreSelection = false
            case .undo: view.undoManager?.undo(); restoreSelection = false
            case .redo: view.undoManager?.redo(); restoreSelection = false
            }
            if restoreSelection { view.selectedRange = range }
            rememberSelection(view.selectedRange)
            scheduleLayoutAndToolbarRefresh(view, updatesToolbar: true)
            if let imageResult {
                return imageResult
            }
            if let tableResult {
                if case .success = tableResult { _ = publishNow(view) }
                return tableResult
            }
            if documentRevision == revisionBeforeCommand { schedulePublish(view) }
            return nil
        }

        func rememberSelection(_ range: NSRange) {
            lastEditingSelection = range
        }

        private func validSelection(_ range: NSRange, in view: UITextView) -> Bool {
            range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= view.textStorage.length
        }

        private func addLink(_ target: String, view: UITextView, range: NSRange) {
            guard let url = URL(string: target) else { return }
            if range.length == 0 {
                let insertion = NSAttributedString(
                    string: target,
                    attributes: [.link: url, .font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]
                )
                view.textStorage.insert(insertion, at: range.location)
                view.selectedRange = NSRange(location: range.location + insertion.length, length: 0)
            } else {
                view.textStorage.addAttribute(.link, value: url, range: range)
            }
        }

        private func insertInternalLink(_ link: RichTextInternalLink, view: UITextView, range: NSRange) {
            guard let url = link.url else { return }
            let insertion = NSAttributedString(
                string: link.title,
                attributes: [
                    .link: url,
                    .font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize, weight: .medium),
                    .foregroundColor: UIColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            )
            replaceAttributed(insertion, in: range, view: view)
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            guard URL.scheme == "kaogong-review", URL.host == "record" else { return true }
            let parts = URL.pathComponents.filter { $0 != "/" }
            guard parts.count == 2,
                  let link = parent.internalLinks.first(where: { $0.collection == parts[0] && $0.recordID == parts[1] })
            else { return false }
            parent.onOpenInternalLink?(link)
            return false
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith textAttachment: NSTextAttachment,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            guard let tableAttachment = textAttachment as? NativeTableAttachment else { return true }
            if !parent.usesInlineBlockEditing { openTableEditor(tableAttachment, range: characterRange) }
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.usesInlineBlockEditing, let body = gestureRecognizer.view as? UITextView else { return true }
            let point = gestureRecognizer.location(in: body)
            let hitsBlock = NativeTableAttachment.hitTest(point, in: body) != nil
            return gestureRecognizer === noteCaretTap ? !hitsBlock : hitsBlock
        }

        @objc func handleNoteCaretTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view as? UITextView,
                  connectedSession?.isInputLocked != true, view.markedTextRange == nil else { return }
            let point = recognizer.location(in: view)
            let editRevision = userEditRevision
            let sessionID = parent.editorSessionID
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, view.window != nil,
                      self.parent.editorSessionID == sessionID, self.userEditRevision == editRevision,
                      self.connectedSession?.isInputLocked != true, view.markedTextRange == nil,
                      view.selectedRange.length == 0,
                      self.closeInlineBlockField(in: view),
                      view.becomeFirstResponder(),
                      let position = view.closestPosition(to: point),
                      let range = view.textRange(from: position, to: position) else { return }
                view.selectedTextRange = range
                self.rememberSelection(view.selectedRange)
                self.parent.onCaretChange?(view)
            }
        }

        @objc func handleNativeTableTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view as? UITextView else { return }
            let point = recognizer.location(in: view)
            if parent.usesInlineBlockEditing {
                guard let hit = NativeTableAttachment.hitTest(point, in: view) else { return }
                editInlineBlock(
                    at: makeTableEditTarget(for: hit.attachment, range: hit.range),
                    cell: hit.cell, in: view, caretNear: point
                )
            } else if let match = tableAttachment(at: point, in: view) {
                openTableEditor(match.attachment, range: match.range)
            }
        }

        func focusInitialBlockCell(_ cell: RichTextTable.Cell, offset: Int, in body: UITextView) -> Bool {
            guard parent.usesInlineBlockEditing, (0..<body.textStorage.length).contains(offset),
                  let attachment = body.textStorage.attribute(.attachment, at: offset, effectiveRange: nil) as? NativeTableAttachment
            else { return false }
            let target = makeTableEditTarget(for: attachment, range: NSRange(location: offset, length: 1))
            editInlineBlock(at: target, cell: cell, in: body)
            return inlineBlockEdit?.field.isFirstResponder == true
        }

        private func inlineAttachment(
            at target: RichTextTableEditTarget, in body: UITextView
        ) -> NativeTableAttachment? {
            guard target.documentID == parent.editorDocumentID,
                  target.sessionID == parent.editorSessionID,
                  let attachmentID = target.attachmentInstanceID,
                  target.range.location < body.textStorage.length,
                  validSelection(target.range, in: body),
                  let attachment = body.textStorage.attribute(.attachment, at: target.range.location, effectiveRange: nil) as? NativeTableAttachment,
                  attachment.instanceID == attachmentID else { return nil }
            return attachment
        }

        func positionInlineBlockField(in body: UITextView) {
            guard let edit = inlineBlockEdit,
                  let host = edit.field.superview,
                  let attachment = inlineAttachment(at: edit.target, in: body),
                  let blockFrame = attachment.frame(in: body, at: edit.target.range.location),
                  let fieldFrame = attachment.frame(for: edit.cell) else { return }
            let bodyFrame = fieldFrame.offsetBy(dx: blockFrame.minX, dy: blockFrame.minY)
            let frame = body.convert(bodyFrame, to: host)
            if edit.field.frame != frame { edit.field.frame = frame }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if let body = scrollView as? RichTextPasteTextView {
                positionInlineBlockField(in: body)
            }
        }

        private func editInlineBlock(
            at target: RichTextTableEditTarget,
            cell: RichTextTable.Cell,
            in body: UITextView,
            caretNear point: CGPoint? = nil
        ) {
            guard connectedSession?.isInputLocked != true,
                  let host = body.superview as? RichTextEditorHostView else { return }
            if let existing = inlineBlockEdit, existing.target.attachmentInstanceID == target.attachmentInstanceID,
               existing.cell == cell {
                existing.field.becomeFirstResponder()
                return
            }
            guard closeInlineBlockField(in: body),
                  let attachment = inlineAttachment(at: target, in: body),
                  attachment.table.contains(cell),
                  attachment.frame(for: cell) != nil else { return }

            let field = RichTextInlineBlockField(frame: .zero, textContainer: nil)
            let isFlowchart = attachment.table.isFlowchart
            field.isScrollEnabled = true
            field.textContainer.lineFragmentPadding = 0
            field.textContainerInset = isFlowchart ? .zero : UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
            field.textContainer.lineBreakMode = .byWordWrapping
            field.font = .systemFont(
                ofSize: isFlowchart ? (cell.column == 0 ? 15 : 13) : 12,
                weight: (isFlowchart ? cell.column == 0 : cell.row == 0) ? .semibold : .regular
            )
            field.textAlignment = isFlowchart ? .center : .natural
            field.textColor = isFlowchart && cell.column == 1 ? .secondaryLabel : .label
            let content = attachment.content(for: cell)
            if content.length > 0 { field.attributedText = content }
            field.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.16, green: 0.21, blue: 0.28, alpha: 1)
                    : UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)
            }
            field.layer.borderWidth = 1
            field.layer.borderColor = UIColor.systemBlue.cgColor
            field.layer.cornerRadius = 3
            field.accessibilityLabel = isFlowchart
                ? "第 \(cell.row + 1) 步\(cell.column == 0 ? "标题" : "说明")"
                : "第 \(cell.row + 1) 行第 \(cell.column + 1) 列"
            field.inputAccessoryView = inlineBlockToolbar(for: attachment.table, cell: cell, body: body)
            field.switchField = { [weak self, weak body] direction in
                guard let self, let body else { return }
                self.switchInlineBlockField(direction: direction, in: body)
            }
            if !isFlowchart {
                field.moveVertically = { [weak self, weak body] offset in
                    guard let self, let body else { return }
                    self.moveInlineBlockRow(by: offset, in: body)
                }
            }

            inlineBlockEdit = InlineBlockEdit(target: target, cell: cell, field: field)
            host.addSubview(field)
            positionInlineBlockField(in: body)
            field.delegate = self
            guard field.becomeFirstResponder() else {
                removeInlineBlockField()
                return
            }
            if let point,
               let position = field.closestPosition(to: field.convert(point, from: body)),
               let range = field.textRange(from: position, to: position) {
                field.selectedTextRange = range
            } else {
                let end = NSRange(location: field.textStorage.length, length: 0)
                field.selectedRange = end
                field.scrollRangeToVisible(end)
            }
            if body.isScrollEnabled { body.scrollRectToVisible(body.convert(field.frame, from: host), animated: false) }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, field.isFirstResponder else { return }
                self.parent.isEditing = true
            }
            parent.onCaretChange?(field)
        }

        private func inlineBlockToolbar(
            for table: RichTextTable, cell: RichTextTable.Cell, body: UITextView
        ) -> UIToolbar {
            let structureItems: [(RichTextTable.StructureAction, String, String)] = table.isFlowchart
                ? [(.addRow, "增加步骤", "plus"), (.removeRow, "删除步骤", "minus"),
                   (.moveUp, "上移步骤", "arrow.up"), (.moveDown, "下移步骤", "arrow.down")]
                : [(.addRow, "增加行", "plus.rectangle.on.rectangle"), (.removeRow, "删除行", "minus.rectangle"),
                   (.addColumn, "增加列", "rectangle.split.3x1"), (.removeColumn, "删除列", "rectangle.split.2x1")]
            let actions = structureItems.map { action, title, symbol in
                UIAction(
                    title: title, image: UIImage(systemName: symbol), attributes: table.canApply(action, at: cell) ? [] : .disabled
                ) { [weak self, weak body] _ in
                    guard let self, let body else { return }
                    self.applyInlineStructureAction(action, in: body)
                }
            }
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: body.bounds.width, height: 44))
            bar.autoresizingMask = [.flexibleWidth]
            let menu = UIBarButtonItem(
                title: table.isFlowchart ? "流程图操作" : "表格操作",
                image: nil, primaryAction: nil, menu: UIMenu(children: actions)
            )
            let done = UIAction(title: table.isFlowchart ? "完成步骤输入" : "完成单元格") { [weak self, weak body] _ in
                guard let self, let body else { return }
                self.returnToBody(in: body)
            }
            let spacing = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            var items = [menu, spacing]
            if !table.isFlowchart {
                items += [
                    inlineVerticalNavigationButton(table: table, cell: cell, offset: -1, body: body),
                    inlineVerticalNavigationButton(table: table, cell: cell, offset: 1, body: body),
                    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
                ]
            }
            items.append(UIBarButtonItem(title: done.title, image: nil, primaryAction: done, menu: nil))
            bar.items = items
            return bar
        }

        private func inlineVerticalNavigationButton(
            table: RichTextTable, cell: RichTextTable.Cell, offset: Int, body: UITextView
        ) -> UIBarButtonItem {
            let caption = offset < 0 ? "上一行单元格" : "下一行单元格"
            let symbol = offset < 0 ? "chevron.up" : "chevron.down"
            let destination = RichTextTable.Cell(row: cell.row + offset, column: cell.column)
            let action = UIAction(title: caption, image: UIImage(systemName: symbol)) { [weak self, weak body] _ in
                guard let self, let body, self.inlineBlockEdit?.cell == cell else { return }
                self.moveInlineBlockRow(by: offset, in: body)
            }
            let button = UIBarButtonItem(title: nil, image: action.image, primaryAction: action, menu: nil)
            button.accessibilityLabel = caption
            button.isEnabled = table.contains(destination)
            return button
        }

        private func moveInlineBlockRow(by offset: Int, in body: UITextView) {
            guard let edit = inlineBlockEdit, let attachment = inlineAttachment(at: edit.target, in: body) else { return }
            let destination = RichTextTable.Cell(row: edit.cell.row + offset, column: edit.cell.column)
            guard attachment.table.contains(destination) else { return }
            editInlineBlock(at: edit.target, cell: destination, in: body)
        }

        private func switchInlineBlockField(direction: Int, in body: UITextView) {
            guard let edit = inlineBlockEdit, let attachment = inlineAttachment(at: edit.target, in: body) else { return }
            let fields = attachment.table.cells.indices.flatMap { row in
                attachment.table.cells[row].indices.map { RichTextTable.Cell(row: row, column: $0) }
            }
            guard let index = fields.firstIndex(of: edit.cell) else { return }
            let destination = index + direction
            if fields.indices.contains(destination) {
                editInlineBlock(at: edit.target, cell: fields[destination], in: body)
            } else {
                returnToBody(in: body)
            }
        }

        private func returnToBody(in body: UITextView) {
            guard let edit = inlineBlockEdit, closeInlineBlockField(in: body) else { return }
            let source = body.textStorage.string as NSString
            var offset = min(NSMaxRange(edit.target.range), source.length)
            if offset < source.length, source.character(at: offset) == 10 { offset += 1 }
            let range = NSRange(location: offset, length: 0)
            body.selectedRange = range
            rememberSelection(range)
            body.becomeFirstResponder()
        }

        private func applyInlineStructureAction(_ action: RichTextTable.StructureAction, in body: UITextView) {
            guard connectedSession?.isInputLocked != true,
                  let edit = inlineBlockEdit, closeInlineBlockField(in: body),
                  let attachment = inlineAttachment(at: edit.target, in: body) else { return }
            var table = attachment.table
            guard let destination = table.apply(action, at: edit.cell) else { return }
            if case .failure(let error) = upsertTable(table, view: body, target: edit.target) {
                parent.onInlineBlockError(error.localizedDescription)
                editInlineBlock(at: edit.target, cell: edit.cell, in: body)
                return
            }
            userEditRevision &+= 1
            editInlineBlock(at: edit.target, cell: destination, in: body)
        }

        @discardableResult
        private func commitInlineBlockField(in body: UITextView) -> Bool {
            guard let edit = inlineBlockEdit else { return true }
            if edit.field.markedTextRange != nil { edit.field.unmarkText() }
            guard edit.field.markedTextRange == nil else {
                connectedSession?.setComposingText(true)
                return false
            }
            let text = edit.field.text ?? ""
            guard let attachment = inlineAttachment(at: edit.target, in: body), attachment.table.contains(edit.cell) else {
                return reportInlineBlockFailure("附件位置已变化，当前输入仍在原位。", edit: edit)
            }
            var table = attachment.table
            if table.cells[edit.cell.row][edit.cell.column] != text {
                guard text.utf8.count <= RichTextTable.maximumCellBytes else {
                    return reportInlineBlockFailure("此格文字过长，请缩短后再保存。", edit: edit)
                }
                table.replaceText(at: edit.cell, with: text)
                if case .failure(let error) = upsertTable(table, view: body, target: edit.target) {
                    return reportInlineBlockFailure(error.localizedDescription, edit: edit)
                }
                userEditRevision &+= 1
            }
            edit.field.layer.borderColor = UIColor.systemBlue.cgColor
            edit.field.reportedError = nil
            connectedSession?.setComposingText(false)
            return true
        }

        private func reportInlineBlockFailure(_ message: String, edit: InlineBlockEdit) -> Bool {
            connectedSession?.setComposingText(true)
            edit.field.layer.borderColor = UIColor.systemRed.cgColor
            if edit.field.reportedError != message {
                edit.field.reportedError = message
                DispatchQueue.main.async { [weak self, weak field = edit.field] in
                    guard let self, let field, self.inlineBlockEdit?.field === field else { return }
                    self.parent.onInlineBlockError(message)
                }
            }
            return false
        }

        private func closeInlineBlockField(in body: UITextView) -> Bool {
            guard inlineBlockEdit != nil else { return true }
            guard commitInlineBlockField(in: body) else { return false }
            removeInlineBlockField()
            return true
        }

        func removeInlineBlockField() {
            guard let edit = inlineBlockEdit else { return }
            inlineBlockEdit = nil
            edit.field.delegate = nil
            edit.field.resignFirstResponder()
            edit.field.removeFromSuperview()
            connectedSession?.setComposingText(false)
        }

        func copyFlowchartSelection(_ view: UITextView) -> Bool {
            let range = view.selectedRange
            guard range.length > 0, validSelection(range, in: view) else { return false }
            let selected = view.textStorage.attributedSubstring(from: range)
            let plainText = NSMutableString(string: selected.string)
            var containsFlowchart = false
            var replacements: [(NSRange, String)] = []
            selected.enumerateAttribute(.attachment, in: NSRange(location: 0, length: selected.length)) { value, range, _ in
                guard let attachment = value as? NSTextAttachment else { return }
                if let block = attachment as? NativeTableAttachment {
                    containsFlowchart = containsFlowchart || block.table.isFlowchart
                    replacements.append((range, block.table.plainText()))
                } else {
                    replacements.append((range, ""))
                }
            }
            guard containsFlowchart else { return false }
            for (range, text) in replacements.reversed() { plainText.replaceCharacters(in: range, with: text) }
            let html = RichTextTextView.html(from: selected, noteFormatting: parent.noteFormatting)
            UIPasteboard.general.items = [[
                UTType.utf8PlainText.identifier: plainText as String,
                UTType.html.identifier: Data(html.utf8)
            ]]
            return true
        }

        private func openTableEditor(_ attachment: NativeTableAttachment, range: NSRange) {
            parent.selectedTable = attachment.table
            let target = makeTableEditTarget(for: attachment, range: range)
            parent.tableEditTarget = target
            parent.tableEditorRequest = RichTextTableEditorRequest(table: attachment.table, target: target)
            parent.editorSession?.setAuxiliaryPanelPresented(true)
        }

        private func makeTableEditTarget(for attachment: NativeTableAttachment, range: NSRange) -> RichTextTableEditTarget {
            RichTextTableEditTarget(
                documentID: parent.editorDocumentID,
                sessionID: parent.editorSessionID,
                attachmentInstanceID: attachment.instanceID,
                range: range,
                revision: documentRevision
            )
        }

        func updateNativeTableWidths(in textView: UITextView, force: Bool = false) {
            let proposedWidth = availableTableWidth(in: textView)
            guard proposedWidth.isFinite, proposedWidth > 0,
                  textView.textStorage.length > 0 else { return }
            if !force, let lastTableWidth, abs(proposedWidth - lastTableWidth) <= 0.5 { return }
            lastTableWidth = proposedWidth
            let updateStart = ProcessInfo.processInfo.systemUptime
            var updatedRanges: [NSRange] = []
            textView.textStorage.enumerateAttribute(
                .attachment,
                in: NSRange(location: 0, length: textView.textStorage.length)
            ) { value, range, _ in
                guard let attachment = value as? NativeTableAttachment,
                      attachment.updateDisplayWidth(proposedWidth) else { return }
                updatedRanges.append(range)
            }
            guard !updatedRanges.isEmpty else {
                if parent.noteFormatting, parent.editorSession != nil {
                    LibraryPerformanceLog.markIfSlow("note.editor.table-width-update", since: updateStart)
                }
                return
            }
            textView.textStorage.beginEditing()
            for range in updatedRanges {
                textView.textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
            }
            textView.textStorage.endEditing()
            measuredHeightNeedsRefresh = true
            textView.invalidateIntrinsicContentSize()
            textView.setNeedsLayout()
            if parent.noteFormatting, parent.editorSession != nil {
                LibraryPerformanceLog.markIfSlow("note.editor.table-width-update", since: updateStart)
            }
        }

        private func availableTableWidth(in textView: UITextView) -> CGFloat {
            let viewportWidth = textView.bounds.width
                - textView.textContainerInset.left
                - textView.textContainerInset.right
            let padding = textView.textContainer.lineFragmentPadding * 2
            let availableViewportWidth = viewportWidth - padding
            let configuredWidth = textView.textContainer.size.width - padding
            guard configuredWidth.isFinite, configuredWidth > 0 else { return max(1, availableViewportWidth) }
            return max(1, min(availableViewportWidth, configuredWidth))
        }

        private func tableAttachment(at point: CGPoint, in view: UITextView) -> (attachment: NativeTableAttachment, range: NSRange)? {
            guard view.textStorage.length > 0 else { return nil }
            guard let closestPosition = view.closestPosition(to: point) else { return nil }
            let closestOffset = view.offset(from: view.beginningOfDocument, to: closestPosition)
            for character in [closestOffset, closestOffset - 1] where character >= 0 && character < view.textStorage.length {
                var range = NSRange()
                guard let attachment = view.textStorage.attribute(.attachment, at: character, effectiveRange: &range) as? NativeTableAttachment,
                      let start = view.position(from: view.beginningOfDocument, offset: character),
                      let end = view.position(from: start, offset: 1),
                      let textRange = view.textRange(from: start, to: end) else { continue }
                if view.firstRect(for: textRange).insetBy(dx: -3, dy: -3).contains(point) {
                    return (attachment, range)
                }
            }
            return nil
        }

        private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, view: UITextView, range: NSRange) {
            let base = font(at: range.location, view: view)
            if range.length == 0 {
                var traits = base.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
                applyAttribute(.font, value: UIFont(descriptor: descriptor, size: base.pointSize), view: view, range: range)
                return
            }
            let remove = allRuns(in: range, view: view) { attributes in
                (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(trait) == true
            }
            view.textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
                var traits = font.fontDescriptor.symbolicTraits
                if remove { traits.remove(trait) } else { traits.insert(trait) }
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
                view.textStorage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
            }
        }

        private func toggleAttribute(_ key: NSAttributedString.Key, value: Any, view: UITextView, range: NSRange) {
            if range.length == 0 {
                var attributes = view.typingAttributes
                if attributes[key] == nil { attributes[key] = value } else { attributes.removeValue(forKey: key) }
                view.typingAttributes = attributes
            } else if allRuns(in: range, view: view, predicate: { $0[key] != nil }) { view.textStorage.removeAttribute(key, range: range) }
            else { view.textStorage.addAttribute(key, value: value, range: range) }
        }

        private func applyAttribute(_ key: NSAttributedString.Key, value: Any, view: UITextView, range: NSRange) {
            if range.length == 0 { var attributes = view.typingAttributes; attributes[key] = value; view.typingAttributes = attributes }
            else { view.textStorage.addAttribute(key, value: value, range: range) }
        }

        private func font(at location: Int, view: UITextView) -> UIFont {
            guard view.attributedText.length > 0 else { return .systemFont(ofSize: RichTextMetrics.bodySize) }
            return view.attributedText.attribute(.font, at: min(location, view.attributedText.length - 1), effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
        }

        private func changeIndent(_ delta: CGFloat, view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            view.textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, subrange, _ in
                let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                if parent.noteFormatting,
                   view.textStorage.attribute(NativeRichTextNoteFormatting.listKey, at: subrange.location, effectiveRange: nil) != nil {
                    let first = max(NativeRichTextNoteFormatting.markerInset, style.firstLineHeadIndent + delta)
                    style.headIndent += first - style.firstLineHeadIndent
                    style.firstLineHeadIndent = first
                    style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent, options: [:])]
                } else {
                    style.headIndent = max(0, style.headIndent + delta)
                    style.firstLineHeadIndent = max(0, style.firstLineHeadIndent + delta)
                }
                view.textStorage.addAttribute(.paragraphStyle, value: style, range: subrange)
            }
        }

        private func applyHeading(_ level: RichTextHeading, view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let font = UIFont.systemFont(ofSize: level.size, weight: level.weight)
            applyAttribute(.font, value: font, view: view, range: paragraphRange)
        }

        private func toggleQuote(view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let current: NSParagraphStyle? = if view.attributedText.length > 0 {
                view.attributedText.attribute(.paragraphStyle, at: min(paragraphRange.location, view.attributedText.length - 1), effectiveRange: nil) as? NSParagraphStyle
            } else {
                view.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            }
            let isQuoted = (current?.headIndent ?? 0) >= 22
            let style = current?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent = isQuoted ? 0 : 24
            style.firstLineHeadIndent = isQuoted ? 0 : 24
            style.paragraphSpacing = isQuoted ? 0 : 5
            applyAttribute(.paragraphStyle, value: style, view: view, range: paragraphRange)
            updateQuoteMarkers(removing: isQuoted, style: style, view: view, paragraphRange: paragraphRange)
            if paragraphRange.length == 0 {
                var attributes = view.typingAttributes
                if isQuoted { attributes.removeValue(forKey: .foregroundColor) }
                else { attributes[.foregroundColor] = UIColor.secondaryLabel }
                view.typingAttributes = attributes
            } else if isQuoted {
                view.textStorage.removeAttribute(.foregroundColor, range: paragraphRange)
            } else {
                view.textStorage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: paragraphRange)
            }
        }

        private func toggleParagraphHighlight(_ color: RichTextColor, view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            if color == .primary {
                if paragraphRange.length == 0 {
                    var attributes = view.typingAttributes
                    attributes.removeValue(forKey: .backgroundColor)
                    view.typingAttributes = attributes
                } else {
                    view.textStorage.removeAttribute(.backgroundColor, range: paragraphRange)
                }
            } else {
                applyAttribute(.backgroundColor, value: color.uiColor.withAlphaComponent(0.14), view: view, range: paragraphRange)
            }
        }

        private func toggleBorder(view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let current = paragraphStyle(at: paragraphRange.location, view: view)
            let style = current.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let isBordered = abs(style.headIndent - 10) < 0.5 && abs(style.tailIndent + 10) < 0.5
            if isBordered {
                style.headIndent = 0
                style.firstLineHeadIndent = 0
                style.tailIndent = 0
                view.textStorage.removeAttribute(.backgroundColor, range: paragraphRange)
            } else {
                style.headIndent = 10
                style.firstLineHeadIndent = 10
                style.tailIndent = -10
                style.paragraphSpacing = max(style.paragraphSpacing, 6)
                view.textStorage.addAttribute(.backgroundColor, value: UIColor.secondarySystemBackground.withAlphaComponent(0.72), range: paragraphRange)
            }
            applyAttribute(.paragraphStyle, value: style, view: view, range: paragraphRange)
        }

        private func updateQuoteMarkers(removing: Bool, style: NSParagraphStyle, view: UITextView, paragraphRange: NSRange) {
            let source = view.text as NSString
            var lineRanges: [NSRange] = []
            var cursor = paragraphRange.location
            let upperBound = NSMaxRange(paragraphRange)
            while cursor < upperBound {
                let line = source.lineRange(for: NSRange(location: cursor, length: 0))
                lineRanges.append(line)
                cursor = max(cursor + 1, NSMaxRange(line))
            }
            let marker = "│ "
            for lineRange in lineRanges.reversed() {
                let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if removing, line.hasPrefix(marker) {
                    view.textStorage.deleteCharacters(in: NSRange(location: lineRange.location, length: marker.utf16.count))
                } else if !removing, !line.hasPrefix(marker) {
                    view.textStorage.insert(
                        NSAttributedString(
                            string: marker,
                            attributes: [
                                .font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize),
                                .foregroundColor: UIColor.tertiaryLabel,
                                .paragraphStyle: style
                            ]
                        ),
                        at: lineRange.location
                    )
                }
            }
        }

        private func paragraphStyle(at location: Int, view: UITextView) -> NSParagraphStyle {
            guard view.attributedText.length > 0 else {
                return view.typingAttributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            }
            return view.attributedText.attribute(.paragraphStyle, at: min(location, view.attributedText.length - 1), effectiveRange: nil) as? NSParagraphStyle
                ?? NSParagraphStyle.default
        }

        private func toggleCode(view: UITextView, range: NSRange) {
            let target = range.length == 0 ? NSRange(location: range.location, length: 0) : range
            let current = font(at: range.location, view: view)
            let isMonospaced = current.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
            let font = isMonospaced
                ? UIFont.systemFont(ofSize: RichTextMetrics.bodySize)
                : UIFont.monospacedSystemFont(ofSize: RichTextMetrics.bodySize, weight: .regular)
            applyAttribute(.font, value: font, view: view, range: target)
            if isMonospaced {
                if target.length > 0 { view.textStorage.removeAttribute(.backgroundColor, range: target) }
                else { var attributes = view.typingAttributes; attributes.removeValue(forKey: .backgroundColor); view.typingAttributes = attributes }
            } else {
                applyAttribute(.backgroundColor, value: UIColor.secondarySystemFill, view: view, range: target)
            }
        }

        private func toggleParagraphPrefixes(_ prefix: String, view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let lines = (view.text as NSString).substring(with: paragraphRange).split(separator: "\n", omittingEmptySubsequences: false)
            let allActive = lines.allSatisfy { String($0).hasPrefix(prefix) }
            let replacement = lines.map { line -> String in
                let raw = stripListPrefix(from: String(line))
                return allActive ? raw : prefix + raw
            }.joined(separator: "\n")
            replaceParagraphs(replacement, originalRange: paragraphRange, selection: range, insertedPrefixLength: allActive ? 0 : prefix.utf16.count, view: view)
        }

        private func numberParagraphs(view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let lines = (view.text as NSString).substring(with: paragraphRange).split(separator: "\n", omittingEmptySubsequences: false)
            let allActive = lines.allSatisfy { String($0).range(of: #"^\d+\.\s"#, options: .regularExpression) != nil }
            let replacement = lines.enumerated().map { index, line in
                let raw = stripListPrefix(from: String(line))
                return allActive ? raw : "\(index + 1). \(raw)"
            }.joined(separator: "\n")
            replaceParagraphs(replacement, originalRange: paragraphRange, selection: range, insertedPrefixLength: allActive ? 0 : 3, view: view)
        }

        private func stripListPrefix(from line: String) -> String {
            if let prefix = listPrefix(in: line)?.current { return String(line.dropFirst(prefix.count)) }
            return line
        }

        private func replaceParagraphs(_ replacement: String, originalRange: NSRange, selection: NSRange, insertedPrefixLength: Int, view: UITextView) {
            let attributes = view.typingAttributes.merging([.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]) { current, _ in current }
            replaceAttributed(NSAttributedString(string: replacement, attributes: attributes), in: originalRange, view: view)
            if selection.length == 0 {
                let relative = max(0, selection.location - originalRange.location)
                view.selectedRange = NSRange(location: min(originalRange.location + relative + insertedPrefixLength, view.textStorage.length), length: 0)
            } else {
                view.selectedRange = NSRange(location: originalRange.location, length: replacement.utf16.count)
            }
        }

        private func insertDivider(view: UITextView, range: NSRange) {
            let insertion = NSAttributedString(
                string: "\n────────────────\n",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.separator
                ]
            )
            view.textStorage.replaceCharacters(in: range, with: insertion)
            view.selectedRange = NSRange(location: range.location + insertion.length, length: 0)
            view.typingAttributes = [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize), .foregroundColor: UIColor.label]
        }

        private func upsertTable(
            _ table: RichTextTable,
            view: UITextView,
            target: RichTextTableEditTarget?
        ) -> Result<Void, NativeRichTextEditorError> {
            guard let target,
                  target.sessionID == parent.editorSessionID,
                  target.documentID == parent.editorDocumentID else {
                return .failure(.editorSessionChanged)
            }
            if parent.usesInlineBlockEditing {
                guard let encoded = try? JSONEncoder().encode(table), encoded.count <= 48 * 1024 else {
                    return .failure(.tablePayloadTooLarge)
                }
            }
            let availableWidth = availableTableWidth(in: view)
            let attachment = NativeTableAttachment(
                table: table,
                instanceID: target.attachmentInstanceID ?? UUID(),
                displayWidth: availableWidth,
                appearance: parent.tableAppearance
            )
            let replacement = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            if let attachmentID = target.attachmentInstanceID {
                var matches: [NSRange] = []
                view.textStorage.enumerateAttribute(
                    .attachment,
                    in: NSRange(location: 0, length: view.textStorage.length)
                ) { value, range, _ in
                    guard let existing = value as? NativeTableAttachment,
                          existing.instanceID == attachmentID else { return }
                    matches.append(range)
                }
                guard matches.count == 1, let existingRange = matches.first,
                      replaceAttributed(replacement, in: existingRange, view: view, preservesSelection: parent.usesInlineBlockEditing) else {
                    return .failure(.tableTargetChanged)
                }
                updateNativeTableWidths(in: view, force: true)
                parent.tableEditTarget = RichTextTableEditTarget(
                    documentID: target.documentID,
                    sessionID: target.sessionID,
                    attachmentInstanceID: attachment.instanceID,
                    range: existingRange,
                    revision: documentRevision
                )
            } else {
                guard target.revision == documentRevision,
                      validSelection(target.range, in: view) else {
                    return .failure(.tableTargetChanged)
                }
                let newline = NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)])
                var blockOffset = target.range.location
                if parent.usesInlineBlockEditing {
                    let source = view.textStorage.string as NSString
                    if blockOffset > 0, source.character(at: blockOffset - 1) != 10 {
                        replacement.insert(newline, at: 0)
                        blockOffset += 1
                    }
                }
                replacement.append(newline)
                guard replaceAttributed(replacement, in: target.range, view: view) else {
                    return .failure(.tableTargetChanged)
                }
                updateNativeTableWidths(in: view, force: true)
                parent.tableEditTarget = RichTextTableEditTarget(
                    documentID: target.documentID,
                    sessionID: target.sessionID,
                    attachmentInstanceID: attachment.instanceID,
                    range: NSRange(location: blockOffset, length: 1),
                    revision: documentRevision
                )
            }
            parent.selectedTable = table
            return .success(())
        }

        private func insertImage(
            _ dataURL: String,
            target: NativeRichTextInsertionTarget,
            view: UITextView
        ) -> Result<Void, NativeRichTextEditorError> {
            guard connectedSession?.matches(target) == true else {
                return .failure(NativeRichTextEditorError.editorSessionChanged)
            }
            guard target.revision == documentRevision,
                  validSelection(target.range, in: view) else {
                return .failure(NativeRichTextEditorError.invalidSelection)
            }
            guard let attachment = NativeImageAttachment(dataURL: dataURL) else {
                return .failure(NativeRichTextEditorError.imageAttachmentInvalid)
            }
            let replacement = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            replacement.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]))
            guard replaceAttributed(replacement, in: target.range, view: view) else {
                return .failure(NativeRichTextEditorError.invalidSelection)
            }
            return .success(())
        }

        private func upsertFormula(_ formula: RichTextFormula, view: UITextView, range: NSRange) {
            let replacement = NSAttributedString(attachment: NativeFormulaAttachment(formula: formula))
            if let existing = formulaAttachment(near: range, view: view), existing.attachment.formula.id == formula.id {
                replaceAttributed(replacement, in: existing.range, view: view)
            } else {
                let value = NSMutableAttributedString(attributedString: replacement)
                value.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]))
                replaceAttributed(value, in: range, view: view)
            }
            parent.selectedFormula = formula
        }

        private func tableAttachment(near range: NSRange, view: UITextView) -> (attachment: NativeTableAttachment, range: NSRange)? {
            let storage = view.textStorage
            for location in [range.location, range.location - 1] where location >= 0 && location < storage.length {
                var effective = NSRange()
                if let attachment = storage.attribute(.attachment, at: location, effectiveRange: &effective) as? NativeTableAttachment {
                    return (attachment, effective)
                }
            }
            return nil
        }

        private func formulaAttachment(near range: NSRange, view: UITextView) -> (attachment: NativeFormulaAttachment, range: NSRange)? {
            let storage = view.textStorage
            for location in [range.location, range.location - 1] where location >= 0 && location < storage.length {
                var effective = NSRange()
                if let attachment = storage.attribute(.attachment, at: location, effectiveRange: &effective) as? NativeFormulaAttachment {
                    return (attachment, effective)
                }
            }
            return nil
        }

        private func schedulePublish(_ view: UITextView) {
            documentRevision &+= 1
            cachedSnapshot = nil
            pendingPublish?.cancel()
            let work = DispatchWorkItem { [weak self, weak view] in
                guard let self, let view else { return }
                _ = self.publishNow(view)
            }
            pendingPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        private func publishNow(_ view: UITextView) -> String {
            pendingPublish?.cancel()
            pendingPublish = nil
            let html = currentHTML(view)
            publish(html)
            return html
        }

        private func snapshotNow(_ view: UITextView) -> NativeRichTextEditorSnapshot {
            let liveSelection = view.selectedRange
            let selection = validSelection(liveSelection, in: view)
                ? liveSelection
                : lastEditingSelection
            if let cachedSnapshot, cachedSnapshot.documentRevision == documentRevision {
                return NativeRichTextEditorSnapshot(
                    html: cachedSnapshot.html,
                    attributedText: cachedSnapshot.attributedText,
                    selection: selection,
                    documentRevision: documentRevision,
                    userEditRevision: userEditRevision
                )
            }

            let snapshotStart = ProcessInfo.processInfo.systemUptime
            let html = currentHTML(view)
            let attributedText = view.attributedText.copy() as? NSAttributedString
                ?? NSAttributedString(string: view.text ?? "")
            let snapshot = NativeRichTextEditorSnapshot(
                html: html,
                attributedText: attributedText,
                selection: selection,
                documentRevision: documentRevision,
                userEditRevision: userEditRevision
            )
            cachedSnapshot = snapshot
            if parent.noteFormatting, parent.editorSession != nil {
                LibraryPerformanceLog.markIfSlow("note.editor.rich-text-snapshot", since: snapshotStart)
            }
            return snapshot
        }

        func completeImageInsertion(
            _ command: RichTextCommandKind,
            result: Result<Void, NativeRichTextEditorError>,
            in view: UITextView
        ) -> Result<Void, NativeRichTextEditorError> {
            guard case .image(let dataURL, let target) = command else { return result }
            guard case .success = result else { return result }
            guard parent.editorSession != nil,
                  parent.editorDocumentID == target.documentID,
                  parent.editorSessionID == target.sessionID,
                  connectedSession?.matches(target) == true else {
                return .failure(.editorSessionChanged)
            }

            let snapshot = snapshotNow(view)
            let expectedMarker = "[[NATIVE_IMAGE:\(Data(dataURL.utf8).base64EncodedString())]]"
            guard snapshot.documentRevision > target.revision,
                  snapshot.hasConsistentImageMarkers,
                  snapshot.imageMarkers.contains(expectedMarker) else {
                return .failure(.imageAttachmentInvalid)
            }
            publish(snapshot.html)
            connectedSession?.recordSuccessfulImageInsertion(
                NativeRichTextImageInsertionReceipt(
                    documentID: target.documentID,
                    sessionID: target.sessionID,
                    revision: snapshot.documentRevision,
                    userEditRevision: snapshot.userEditRevision,
                    imageMarkers: snapshot.imageMarkers
                )
            )
            return .success(())
        }

        private func currentHTML(_ view: UITextView) -> String {
            guard publishedRevision != documentRevision else { return publishedHTML }
            let htmlStart = ProcessInfo.processInfo.systemUptime
            let html = RichTextTextView.html(from: view.attributedText, noteFormatting: parent.noteFormatting)
            if parent.noteFormatting, parent.editorSession != nil {
                LibraryPerformanceLog.markIfSlow("note.editor.html-export", since: htmlStart)
            }
            publishedHTML = html
            publishedRevision = documentRevision
            return html
        }

        private func publish(_ html: String) {
            guard html != lastHTML else { return }
            lastHTML = html
            parent.html = html
        }

        private func scheduleLayoutAndToolbarRefresh(
            _ view: UITextView,
            updatesToolbar: Bool,
            updatesLayout: Bool = true
        ) {
            pendingLayoutRefreshView = view
            layoutRefreshUpdatesToolbar = layoutRefreshUpdatesToolbar || updatesToolbar
            layoutRefreshUpdatesLayout = layoutRefreshUpdatesLayout || updatesLayout
            guard !layoutRefreshScheduled else { return }
            layoutRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layoutRefreshScheduled = false
                let shouldUpdateToolbar = self.layoutRefreshUpdatesToolbar
                let shouldUpdateLayout = self.layoutRefreshUpdatesLayout
                self.layoutRefreshUpdatesToolbar = false
                self.layoutRefreshUpdatesLayout = false
                guard let view = self.pendingLayoutRefreshView else { return }
                self.pendingLayoutRefreshView = nil
                let refreshStart = ProcessInfo.processInfo.systemUptime
                if shouldUpdateLayout {
                    if self.parent.noteFormatting, self.hasPendingForcedNoteHeightMeasurement {
                        view.invalidateIntrinsicContentSize()
                    } else if !self.parent.noteFormatting || self.updateCachedNoteHeightFromTextKit(view) {
                        view.invalidateIntrinsicContentSize()
                    }
                }
                if shouldUpdateToolbar, view.markedTextRange == nil {
                    self.publishSelectionState(view)
                }
                if self.parent.noteFormatting, self.parent.editorSession != nil {
                    LibraryPerformanceLog.markIfSlow("note.editor.layout-toolbar-refresh", since: refreshStart)
                }
            }
        }

        private func publishSelectionState(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let toolbarUpdateStart = ProcessInfo.processInfo.systemUptime
            defer {
                if parent.noteFormatting, parent.editorSession != nil {
                    LibraryPerformanceLog.markIfSlow("note.editor.format-toolbar-update", since: toolbarUpdateStart)
                }
            }
            let range = view.selectedRange
            let stateRange: NSRange = if parent.noteFormatting,
                range.length > 4096,
                range.location >= 0,
                range.location < view.attributedText.length {
                NSRange(location: range.location, length: 1)
            } else {
                range
            }
            let attributes = attributesForCaretOrSelection(range, view: view)
            let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
            let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
            let foreground = attributes[.foregroundColor] as? UIColor
            let currentLine: String = {
                let source = view.text as NSString
                guard source.length > 0 else { return "" }
                let location = min(range.location, source.length)
                let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
                return source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            }()
            let heading: RichTextHeading = if everyAttribute(in: stateRange, view: view, predicate: { (($0[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize) >= 20 }) {
                .heading1
            } else if everyAttribute(in: stateRange, view: view, predicate: {
                let size = ($0[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize
                return size >= 17 && size < 20
            }) {
                .heading2
            } else {
                .body
            }
            let listKind = !parent.noteFormatting || attributes[NativeRichTextNoteFormatting.listKey] as? Bool == true
                ? NoteListMarker.read(currentLine)?.kind : nil
            let isNumbered: Bool
            if case .number? = listKind { isNumbered = true } else { isNumbered = false }
            let state = RichTextSelectionState(
                isBold: everyAttribute(in: stateRange, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true },
                isItalic: everyAttribute(in: stateRange, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true },
                isUnderlined: everyAttribute(in: stateRange, view: view) { ($0[.underlineStyle] as? Int ?? 0) != 0 },
                isStruckThrough: everyAttribute(in: stateRange, view: view) { ($0[.strikethroughStyle] as? Int ?? 0) != 0 },
                isHighlighted: everyAttribute(in: stateRange, view: view) { $0[.backgroundColor] != nil },
                isParagraphHighlighted: paragraph.map { _ in
                    return self.everyAttribute(in: stateRange, view: view) { $0[.backgroundColor] != nil }
                } ?? false,
                isQuoted: everyAttribute(in: stateRange, view: view) {
                    if parent.noteFormatting { return NativeRichTextNoteFormatting.block(in: $0)?.includesQuote == true }
                    return NativeRichTextNoteFormatting.isQuoted($0) || (($0[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0) >= 22
                },
                isBordered: parent.noteFormatting
                    ? NativeRichTextNoteFormatting.block(in: attributes)?.includesCallout == true
                    : abs((paragraph?.headIndent ?? 0) - 10) < 0.5 && abs((paragraph?.tailIndent ?? 0) + 10) < 0.5,
                isBulleted: listKind == .bullet,
                isNumbered: isNumbered,
                isCode: everyAttribute(in: stateRange, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true },
                heading: heading,
                foreground: RichTextColor.allCases.first(where: { foreground?.isEqual($0.uiColor) == true }) ?? .primary,
                canUndo: view.undoManager?.canUndo == true,
                canRedo: view.undoManager?.canRedo == true
            )
            guard state != parent.selectionState, state != lastQueuedSelectionState else { return }
            lastQueuedSelectionState = state
            DispatchQueue.main.async {
                guard self.parent.selectionState != state else { return }
                if self.parent.noteFormatting && !UIAccessibility.isReduceMotionEnabled {
                    withAnimation(.easeOut(duration: 0.14)) { self.parent.selectionState = state }
                } else {
                    self.parent.selectionState = state
                }
            }
        }

        private func attributesForCaretOrSelection(_ range: NSRange, view: UITextView) -> [NSAttributedString.Key: Any] {
            if range.length == 0 { return view.typingAttributes }
            guard view.attributedText.length > 0 else { return view.typingAttributes }
            return view.attributedText.attributes(at: min(range.location, view.attributedText.length - 1), effectiveRange: nil)
        }

        private func everyAttribute(
            in range: NSRange,
            view: UITextView,
            predicate: ([NSAttributedString.Key: Any]) -> Bool
        ) -> Bool {
            if range.length == 0 { return predicate(view.typingAttributes) }
            return allRuns(in: range, view: view, predicate: predicate)
        }

        private func allRuns(
            in range: NSRange,
            view: UITextView,
            predicate: ([NSAttributedString.Key: Any]) -> Bool
        ) -> Bool {
            guard range.length > 0 else { return predicate(view.typingAttributes) }
            var matches = true
            view.attributedText.enumerateAttributes(in: range) { attributes, _, stop in
                if !predicate(attributes) { matches = false; stop.pointee = true }
            }
            return matches
        }
    }

    fileprivate static func attributed(
        from value: String,
        noteFormatting: Bool = false,
        cleanLegacyInjectedSpacing: Bool = false
    ) -> NSAttributedString {
        let noteSource = noteFormatting
            ? value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\u{2028}", options: .regularExpression)
            : value
        let markup = !noteSource.contains("<") ? (NativeRichTextMarkdown.htmlIfMarkdown(noteSource) ?? noteSource) : noteSource
        let source = noteFormatting
            ? markup.replacingOccurrences(
                of: #"(?i)<hr\b[^>]*>"#,
                with: "<p data-note-block=\"divider\">\(NativeRichTextNoteFormatting.placeholder)</p>",
                options: .regularExpression
            )
            : markup
        if source.contains("<"), let data = source.data(using: .utf8), let result = try? NSMutableAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil
        ) {
            restoreNativeTables(in: result)
            let headings = semanticHeadingSizes(in: data)
            normalizeFonts(in: result, semanticHeadingSizes: headings)
            let metadata = alignedParagraphMetadata(in: source, matching: result)
            markSourceParagraphSemantics(in: result, metadata: metadata, semanticHeadingSizes: headings)
            guard noteFormatting else { return result }
            applyHTMLListMarkers(from: source, to: result)
            return applyingNoteParagraphFormatting(
                to: result,
                sourceHTML: source,
                cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing,
                paragraphMetadata: metadata
            )
        }
        let plain = NSAttributedString(string: noteSource, attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)])
        return noteFormatting
            ? applyingNoteParagraphFormatting(to: plain, sourceHTML: source, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
            : plain
    }

    fileprivate static func applyingNoteParagraphFormatting(
        to source: NSAttributedString,
        sourceHTML: String?,
        cleanLegacyInjectedSpacing: Bool = false,
        paragraphMetadata: [NativeRichTextNoteParagraphHTMLMetadata?]? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)

        // Older note quotes stored a visible marker. Remove it only when both the
        // old 24 pt indent and the marker are present, so ordinary text is untouched.
        var legacyRanges: [NSRange] = []
        enumerateParagraphRanges(in: result.string) { paragraphRange, contentsRange in
            guard paragraphRange.location < result.length,
                  let style = result.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle,
                  style.headIndent >= 22,
                  contentsRange.length >= 2,
                  (result.string as NSString).substring(with: NSRange(location: contentsRange.location, length: 2)) == "│ " else { return }
            legacyRanges.append(paragraphRange)
        }
        for oldRange in legacyRanges.reversed() {
            guard oldRange.location < result.length else { continue }
            var paragraphRange = (result.string as NSString).paragraphRange(for: NSRange(location: oldRange.location, length: 0))
            result.deleteCharacters(in: NSRange(location: paragraphRange.location, length: 2))
            paragraphRange = (result.string as NSString).paragraphRange(for: NSRange(location: paragraphRange.location, length: 0))
            guard result.length > 0, paragraphRange.length > 0 else { continue }
            let style = (result.attribute(.paragraphStyle, at: min(paragraphRange.location, max(0, result.length - 1)), effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent = NativeRichTextNoteFormatting.quoteIndent
            style.firstLineHeadIndent = style.headIndent
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            result.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
        }

        let hasSavedBlockMetadata = paragraphMetadata?.allSatisfy { $0?.isListItem != nil } == true
        if !hasSavedBlockMetadata, let sourceHTML,
           let expression = try? NSRegularExpression(pattern: #"(?is)<blockquote\b[^>]*>(.*?)</blockquote\s*>"#) {
            let sourceNSString = sourceHTML as NSString
            let matches = expression.matches(in: sourceHTML, range: NSRange(location: 0, length: sourceNSString.length))
            var searchLocation = 0
            var sourceCursor = 0
            for match in matches where match.numberOfRanges > 1 {
                if match.range.location > sourceCursor {
                    let prefixHTML = sourceNSString.substring(with: NSRange(location: sourceCursor, length: match.range.location - sourceCursor))
                    if let prefixText = plainTextFromHTMLFragment(prefixHTML) {
                        searchLocation = min(result.length, searchLocation + prefixText.utf16.count)
                    }
                }
                sourceCursor = NSMaxRange(match.range)
                let innerHTML = sourceNSString.substring(with: match.range(at: 1))
                guard let quotedText = plainTextFromHTMLFragment(innerHTML)?.trimmingCharacters(in: .newlines) else { continue }
                guard !quotedText.isEmpty, searchLocation <= result.length else { continue }
                let fullText = result.string as NSString
                let found = fullText.range(of: quotedText, options: [], range: NSRange(location: searchLocation, length: fullText.length - searchLocation))
                guard found.location != NSNotFound else { continue }
                markQuotedParagraphs(in: result, intersecting: found)
                searchLocation = NSMaxRange(found)
            }
        }

        let sourceText = result.string as NSString
        var paragraphRanges: [NSRange] = []
        var paragraphStyles: [NativeRichTextNoteParagraphHTMLStyle] = []
        var paragraphQuotes: [Bool] = []
        var paragraphContent: [Bool] = []
        enumerateParagraphRanges(in: result.string) { paragraphRange, contentsRange in
            guard paragraphRange.length > 0, paragraphRange.location < result.length else { return }
            let quoted = NativeRichTextNoteFormatting.isQuoted(result, at: paragraphRange.location)
            let attributes = result.attributes(at: paragraphRange.location, effectiveRange: nil)
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            let fontSize = (attributes[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize
            let content = sourceText.substring(with: contentsRange).trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphRanges.append(paragraphRange)
            paragraphStyles.append(NativeRichTextNoteParagraphHTMLStyle(
                spacingBefore: Double(paragraphStyle.paragraphSpacingBefore),
                spacingAfter: Double(paragraphStyle.paragraphSpacing),
                lineSpacing: Double(paragraphStyle.lineSpacing),
                fontSize: Double(fontSize),
                firstLineHeadIndent: Double(paragraphStyle.firstLineHeadIndent),
                headIndent: Double(paragraphStyle.headIndent),
                tailIndent: Double(paragraphStyle.tailIndent)
            ))
            paragraphQuotes.append(quoted)
            paragraphContent.append(!content.isEmpty)
        }
        let metadataRows: [NativeRichTextNoteParagraphHTMLMetadata?]
        if let paragraphMetadata, paragraphMetadata.count == paragraphRanges.count {
            metadataRows = paragraphMetadata
        } else {
            metadataRows = Array(repeating: nil, count: paragraphRanges.count)
        }
        let hasVersionedLayout = metadataRows.contains { $0?.versionedLayout != nil }
        let savedIndents: [NativeRichTextNoteParagraphHTMLIndent?]
        if let paragraphMetadata,
           paragraphMetadata.count == paragraphRanges.count,
           let sourceHTML {
            savedIndents = NativeRichTextNoteParagraphHTMLPolicy.indents(in: sourceHTML)
        } else {
            savedIndents = []
        }
        let useSavedIndents = savedIndents.count == paragraphRanges.count
        let normalizedStyles = cleanLegacyInjectedSpacing && !hasVersionedLayout
            ? NativeRichTextNoteParagraphHTMLPolicy.removingLegacyInjectedSpacing(
                from: paragraphStyles,
                isQuoted: paragraphQuotes,
                hasContent: paragraphContent
            )
            : paragraphStyles
        for index in paragraphRanges.indices.reversed() {
            let paragraphRange = paragraphRanges[index]
            guard paragraphRange.location < result.length else { continue }
            let quoted = metadataRows[index]?.blockKind?.includesQuote ?? paragraphQuotes[index]
            let cleaned = normalizedStyles[index]
            let style = (result.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            if let saved = metadataRows[index]?.versionedLayout {
                style.paragraphSpacingBefore = CGFloat(saved.spacingBefore)
                style.paragraphSpacing = CGFloat(saved.spacingAfter)
                style.lineSpacing = CGFloat(saved.lineSpacing)
                style.minimumLineHeight = 0
                style.maximumLineHeight = 0
                style.lineHeightMultiple = 0
                style.firstLineHeadIndent = CGFloat(saved.firstLineHeadIndent)
                style.headIndent = CGFloat(saved.headIndent)
                style.tailIndent = CGFloat(saved.tailIndent)
            } else {
                style.paragraphSpacingBefore = CGFloat(cleaned.spacingBefore)
                style.paragraphSpacing = CGFloat(cleaned.spacingAfter)
                style.lineSpacing = CGFloat(cleaned.lineSpacing)
                if let spacing = metadataRows[index]?.cssSpacing {
                    style.paragraphSpacingBefore = CGFloat(spacing.before)
                    style.paragraphSpacing = CGFloat(spacing.after)
                }
            }
            if metadataRows[index]?.versionedLayout == nil,
               useSavedIndents,
               index < savedIndents.count,
               let indent = savedIndents[index] {
                style.firstLineHeadIndent = CGFloat(indent.firstLineHeadIndent)
                style.headIndent = CGFloat(indent.headIndent)
                style.tailIndent = CGFloat(indent.tailIndent)
            }
            if quoted {
                style.headIndent = max(style.headIndent, NativeRichTextNoteFormatting.quoteIndent)
                style.firstLineHeadIndent = max(style.firstLineHeadIndent, NativeRichTextNoteFormatting.quoteIndent)
                style.paragraphSpacing = max(style.paragraphSpacing, 5)
                result.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
                NativeRichTextNoteFormatting.removeNeutralQuoteBackground(in: result, range: paragraphRange)
            } else {
                result.removeAttribute(NativeRichTextNoteFormatting.quoteKey, range: paragraphRange)
            }
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            let attributes = result.attributes(at: paragraphRange.location, effectiveRange: nil)
            let content = sourceText.substring(with: paragraphRange)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            var block = metadataRows[index]?.blockKind ?? NativeRichTextNoteFormatting.block(in: attributes)
            if block == nil {
                if trimmed.hasPrefix("────────"), trimmed.allSatisfy({ $0 == "─" }) {
                    block = .divider
                } else if metadataRows[index]?.isListItem == nil,
                          abs(style.headIndent - 10) < 0.5, abs(style.tailIndent + 10) < 0.5 {
                    block = .callout
                }
            }
            if let block {
                if block != .divider && trimmed.isEmpty {
                    result.insert(NSAttributedString(string: NativeRichTextNoteFormatting.placeholder, attributes: attributes),
                                  at: paragraphRange.location)
                    NativeRichTextNoteFormatting.applyBlock(
                        block, to: result, range: NSRange(location: paragraphRange.location, length: paragraphRange.length + 1)
                    )
                } else if block == .divider {
                    let newline = String(content.reversed().prefix(while: \.isNewline).reversed())
                    let isDividerContent = trimmed.allSatisfy { $0 == "─" || $0 == "\u{200B}" }
                    guard isDividerContent else {
                        NativeRichTextNoteFormatting.applyBlock(nil, to: result, range: paragraphRange)
                        continue
                    }
                    let replacement = NSAttributedString(string: NativeRichTextNoteFormatting.placeholder + newline, attributes: attributes)
                    result.replaceCharacters(in: paragraphRange, with: replacement)
                    NativeRichTextNoteFormatting.applyBlock(
                        block, to: result, range: NSRange(location: paragraphRange.location, length: replacement.length)
                    )
                } else {
                    NativeRichTextNoteFormatting.applyBlock(block, to: result, range: paragraphRange)
                }
            } else if metadataRows[index]?.isListItem != false,
                      let marker = NoteListMarker.read(content)
                        ?? (attributes[NativeRichTextNoteFormatting.listKey] != nil && content.hasPrefix("- ")
                            ? NoteListMarker(kind: .bullet, prefix: "- ") : nil) {
                let paragraph = NSMutableAttributedString(attributedString: result.attributedSubstring(from: paragraphRange))
                let body = content.dropFirst(marker.prefix.count)
                if body.allSatisfy(\.isWhitespace) {
                    var bodyAttributes = attributes
                    bodyAttributes[.font] = UIFont.systemFont(ofSize: RichTextMetrics.bodySize)
                    paragraph.insert(
                        NSAttributedString(string: NativeRichTextNoteFormatting.placeholder, attributes: bodyAttributes),
                        at: marker.prefix.utf16.count
                    )
                }
                NoteListMarker.apply(marker.kind, to: paragraph, oldMarker: marker)
                result.replaceCharacters(in: paragraphRange, with: paragraph)
            }
        }
        return result.copy() as? NSAttributedString ?? result
    }

    fileprivate static func normalizingPastedNoteParagraphs(
        in source: NSAttributedString,
        hasStructuredParagraphs: Bool = false,
        paragraphMetadata: [NativeRichTextNoteParagraphHTMLMetadata?]? = nil
    ) -> NSAttributedString {
        guard source.length > 0 else { return source.copy() as? NSAttributedString ?? source }
        let result = NSMutableAttributedString(attributedString: source)
        var paragraphRanges: [NSRange] = []
        var paragraphStyles: [NativeRichTextNoteParagraphHTMLStyle] = []
        var paragraphContent: [Bool] = []
        var paragraphQuotes: [Bool] = []
        var paragraphLists: [Bool] = []
        var preservesParagraphLayout: [Bool] = []
        let text = result.string as NSString
        enumerateParagraphRanges(in: result.string) { paragraphRange, contentsRange in
            guard paragraphRange.location < result.length else { return }
            let attributes = result.attributes(at: paragraphRange.location, effectiveRange: nil)
            let style = attributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            let contents = text.substring(with: contentsRange).trimmingCharacters(in: .whitespacesAndNewlines)
            var hasAttachment = false
            result.enumerateAttribute(.attachment, in: paragraphRange) { attachment, _, stop in
                if attachment != nil {
                    hasAttachment = true
                    stop.pointee = true
                }
            }
            paragraphRanges.append(paragraphRange)
            paragraphStyles.append(NativeRichTextNoteParagraphHTMLStyle(
                spacingBefore: Double(style.paragraphSpacingBefore),
                spacingAfter: Double(style.paragraphSpacing),
                lineSpacing: Double(style.lineSpacing),
                fontSize: Double((attributes[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize),
                firstLineHeadIndent: Double(style.firstLineHeadIndent),
                headIndent: Double(style.headIndent),
                tailIndent: Double(style.tailIndent)
            ))
            paragraphContent.append(!contents.isEmpty)
            paragraphQuotes.append(NativeRichTextNoteFormatting.isQuoted(attributes))
            paragraphLists.append(attributes[NativeRichTextNoteFormatting.listKey] as? Bool == true)
            preservesParagraphLayout.append(hasAttachment || NativeRichTextNoteFormatting.block(in: attributes) != nil)
        }

        let metadataRows: [NativeRichTextNoteParagraphHTMLMetadata?]
        if let paragraphMetadata, paragraphMetadata.count == paragraphRanges.count {
            metadataRows = paragraphMetadata
        } else {
            metadataRows = Array(repeating: nil, count: paragraphRanges.count)
        }
        let normalized = NativeRichTextNoteParagraphHTMLPolicy.normalizingPastedStyles(
            paragraphStyles,
            hasContent: paragraphContent,
            isQuoted: paragraphQuotes,
            isList: paragraphLists,
            preservesParagraphLayout: preservesParagraphLayout,
            metadata: metadataRows,
            hasStructuredParagraphs: hasStructuredParagraphs
        )
        for index in paragraphRanges.indices {
            guard paragraphContent[index], !preservesParagraphLayout[index], paragraphRanges[index].location < result.length else { continue }
            let style = (result.attribute(.paragraphStyle, at: paragraphRanges[index].location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.minimumLineHeight = 0
            style.maximumLineHeight = 0
            style.lineHeightMultiple = 0
            style.paragraphSpacingBefore = CGFloat(normalized[index].spacingBefore)
            style.paragraphSpacing = CGFloat(normalized[index].spacingAfter)
            style.lineSpacing = CGFloat(normalized[index].lineSpacing)
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRanges[index])
        }
        return result.copy() as? NSAttributedString ?? result
    }

    fileprivate static func applyHTMLListMarkers(from html: String, to value: NSMutableAttributedString) {
        guard value.length > 0 else { return }
        let items = NativeRichTextNoteListHTMLPolicy.items(in: html)
        guard !items.isEmpty else { return }
        var searchLocation = 0

        for item in items {
            guard let decoded = plainTextFromListItemHTML(item.contentHTML) else { continue }
            let needle = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            let currentSource = value.string as NSString
            let start = min(searchLocation, currentSource.length)
            let found = currentSource.range(of: needle, options: [], range: NSRange(location: start, length: currentSource.length - start))
            guard found.location != NSNotFound else { continue }

            let beforeInsertion = value.string as NSString
            var paragraphRange = beforeInsertion.paragraphRange(for: NSRange(location: found.location, length: 0))
            guard paragraphRange.location < value.length else { continue }
            let paragraphText = beforeInsertion.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedMarker = item.marker.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasMarker = ["•", "◦", "▪", "▪︎", "■", "–", "-"].contains(expectedMarker)
                ? paragraphText.range(of: #"^[•◦▪︎■–-]\s+"#, options: .regularExpression) != nil
                : paragraphText.hasPrefix(expectedMarker)
                    && (paragraphText.dropFirst(expectedMarker.count).first.map(\.isWhitespace) ?? true)
            if !hasMarker {
                let markerAttributes = value.attributes(at: found.location, effectiveRange: nil)
                value.insert(NSAttributedString(string: item.marker, attributes: markerAttributes), at: found.location)
                paragraphRange.length += item.marker.utf16.count
            }

            let styleLocation = min(paragraphRange.location, max(0, value.length - 1))
            let style = (value.attribute(.paragraphStyle, at: styleLocation, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent = CGFloat(item.firstLineHeadIndent)
            style.headIndent = CGFloat(item.headIndent)
            value.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            value.addAttribute(NativeRichTextNoteFormatting.listKey, value: true, range: paragraphRange)
            searchLocation = min(value.length, found.location + needle.utf16.count + (hasMarker ? 0 : item.marker.utf16.count))
        }
    }

    private static func plainTextFromListItemHTML(_ html: String) -> String? {
        let runs = NativeRichTextFallbackParser.parse(html)
        guard !runs.isEmpty else { return nil }
        var text = ""
        for run in runs {
            switch run {
            case .text(let value), .styledText(let value, _):
                text += value
            default:
                return nil
            }
        }
        return text
    }

    fileprivate static func applyingNoteInsertionParagraphContext(
        _ source: NSAttributedString,
        from textView: UITextView,
        replacing range: NSRange
    ) -> NSAttributedString {
        guard source.length > 0,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= textView.attributedText.length else { return source }
        let targetText = textView.attributedText.string as NSString
        guard targetText.length > 0 else { return source }

        typealias ParagraphContext = (style: NSParagraphStyle?, block: NativeRichTextNoteBlockKind?, hasPrefix: Bool, hasSuffix: Bool)
        func paragraphContext(at location: Int) -> ParagraphContext {
            let probe = min(max(0, location), targetText.length - 1)
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            targetText.getParagraphStart(&paragraphStart, end: &paragraphEnd, contentsEnd: &contentsEnd, for: NSRange(location: probe, length: 0))
            let safeLocation = min(location, targetText.length)
            let hasPrefix = safeLocation > paragraphStart
                && targetText.substring(with: NSRange(location: paragraphStart, length: safeLocation - paragraphStart)).contains { $0 != "\n" && $0 != "\r" }
            let hasSuffix = safeLocation < contentsEnd
            let attributes = textView.attributedText.attributes(at: probe, effectiveRange: nil)
            return (
                attributes[.paragraphStyle] as? NSParagraphStyle,
                NativeRichTextNoteFormatting.block(in: attributes),
                hasPrefix,
                hasSuffix
            )
        }

        let startContext = paragraphContext(at: range.location)
        let endContext = paragraphContext(at: NSMaxRange(range))
        var paragraphs: [NSRange] = []
        enumerateParagraphRanges(in: source.string) { paragraphRange, _ in
            paragraphs.append(paragraphRange)
        }
        guard paragraphs.count > 0 else { return source }
        let result = NSMutableAttributedString(attributedString: source)

        func apply(_ context: ParagraphContext, to paragraphRange: NSRange) {
            guard paragraphRange.length > 0, paragraphRange.location < result.length,
                  context.hasPrefix || context.hasSuffix else { return }
            if let style = context.style {
                result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            }
            if let block = context.block {
                result.addAttribute(NativeRichTextNoteFormatting.blockKey, value: block.rawValue, range: paragraphRange)
            } else {
                result.removeAttribute(NativeRichTextNoteFormatting.blockKey, range: paragraphRange)
            }
            if context.block?.includesQuote == true {
                result.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
            } else {
                result.removeAttribute(NativeRichTextNoteFormatting.quoteKey, range: paragraphRange)
            }
        }

        let firstRange = paragraphs.first
        let lastRange = paragraphs.last
        if let firstRange, startContext.hasPrefix {
            apply(startContext, to: firstRange)
        }
        if let lastRange, lastRange != firstRange, endContext.hasSuffix {
            apply(endContext, to: lastRange)
        }
        return result.copy() as? NSAttributedString ?? result
    }

    private static func plainTextFromHTMLFragment(_ html: String) -> String? {
        let wrapperTags = try? NSRegularExpression(pattern: #"(?is)</?(html|head|body)\b[^>]*>|<meta\b[^>]*>|<!doctype[^>]*>"#)
        let nonContentTags = try? NSRegularExpression(pattern: #"(?is)<(style|script)\b[^>]*>.*?</\1\s*>"#)
        let source = html as NSString
        let withoutStyles = nonContentTags?.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: source.length),
            withTemplate: ""
        ) ?? html
        let withoutStylesSource = withoutStyles as NSString
        let cleaned = wrapperTags?.stringByReplacingMatches(
            in: withoutStyles,
            range: NSRange(location: 0, length: withoutStylesSource.length),
            withTemplate: ""
        ) ?? withoutStyles
        let wrapped = "<html><head><meta charset=\"utf-8\"></head><body>\(cleaned)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let fragment = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else { return nil }
        return fragment.string
    }

    private static func markQuotedParagraphs(in value: NSMutableAttributedString, intersecting range: NSRange) {
        guard range.location >= 0, range.length > 0, range.location < value.length else { return }
        let nsText = value.string as NSString
        let limit = min(NSMaxRange(range), nsText.length)
        var cursor = range.location
        while cursor < limit {
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: cursor, length: 0))
            guard paragraphRange.length > 0, paragraphRange.location < value.length else { break }
            let style = (value.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent = 12
            style.firstLineHeadIndent = 12
            value.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            value.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
            cursor = NSMaxRange(paragraphRange)
        }
    }

    fileprivate static func enumerateParagraphRanges(
        in value: String,
        _ body: (NSRange, NSRange) -> Void
    ) {
        let source = value as NSString
        var cursor = 0
        while cursor < source.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            source.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            guard end > cursor else { break }
            body(NSRange(location: start, length: end - start), NSRange(location: start, length: max(0, contentsEnd - start)))
            cursor = end
        }
    }

    fileprivate static func paragraphContents(in value: NSAttributedString) -> [String] {
        var paragraphs: [String] = []
        let source = value.string as NSString
        enumerateParagraphRanges(in: value.string) { _, contentsRange in
            guard contentsRange.location >= 0, NSMaxRange(contentsRange) <= source.length else { return }
            paragraphs.append(source.substring(with: contentsRange))
        }
        return paragraphs
    }

    fileprivate static func hasStructuredParagraphs(in value: NSAttributedString) -> Bool {
        paragraphContents(in: value).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count >= 2
    }

    fileprivate static func alignedParagraphMetadata(
        in html: String,
        matching value: NSAttributedString
    ) -> [NativeRichTextNoteParagraphHTMLMetadata?]? {
        let metadata = NativeRichTextNoteParagraphHTMLPolicy.metadata(in: html)
        guard !metadata.isEmpty, metadata.count == paragraphContents(in: value).count else { return nil }
        return metadata.map { Optional($0) }
    }

    fileprivate static func semanticHeadingSizes(
        in html: String,
        matching value: NSAttributedString
    ) -> [String: [CGFloat]] {
        let metadata = NativeRichTextNoteParagraphHTMLPolicy.metadata(in: html)
        let paragraphs = paragraphContents(in: value)
        guard metadata.count == paragraphs.count else { return [:] }
        var result: [String: [CGFloat]] = [:]
        for (paragraph, row) in zip(paragraphs, metadata) {
            let size: CGFloat?
            if row.headingLevel == 1 { size = RichTextMetrics.heading1Size }
            else if let level = row.headingLevel, (2...6).contains(level) { size = RichTextMetrics.heading2Size }
            else { size = nil }
            guard let size else { continue }
            let key = semanticHeadingKey(paragraph)
            guard !key.isEmpty else { continue }
            result[key, default: []].append(size)
        }
        return result
    }

    fileprivate static func markSourceParagraphSemantics(
        in value: NSMutableAttributedString,
        metadata: [NativeRichTextNoteParagraphHTMLMetadata?]?,
        semanticHeadingSizes: [String: [CGFloat]]
    ) {
        guard value.length > 0 else { return }
        var ranges: [NSRange] = []
        enumerateParagraphRanges(in: value.string) { range, _ in ranges.append(range) }
        guard !ranges.isEmpty else { return }
        if let metadata, metadata.count != ranges.count { return }
        let sourceConfirmsParagraphs = metadata?.count == ranges.count

        var remainingHeadingSizes = semanticHeadingSizes
        for index in ranges.indices {
            let range = ranges[index]
            guard range.location < value.length else { continue }
            let row = metadata?[index]
            if sourceConfirmsParagraphs {
                value.addAttribute(
                    NativeRichTextPastePolicy.confirmedNaturalParagraph,
                    value: true,
                    range: range
                )
            }
            if row?.hasExplicitSpacing == true {
                value.addAttribute(
                    NativeRichTextPastePolicy.explicitParagraphSpacing,
                    value: true,
                    range: range
                )
            }

            let paragraphText = (value.string as NSString).substring(with: range)
            let key = semanticHeadingKey(paragraphText)
            let semanticSize: CGFloat? = {
                guard var sizes = remainingHeadingSizes[key], !sizes.isEmpty else { return nil }
                let size = sizes.removeFirst()
                remainingHeadingSizes[key] = sizes
                return size
            }()
            let headingLevel = row?.headingLevel
                ?? semanticSize.map { $0 >= 20.5 ? 1 : ($0 >= 17.5 ? 2 : 0) }
            if let headingLevel, headingLevel > 0 {
                value.addAttribute(
                    NativeRichTextPastePolicy.semanticHeadingParagraph,
                    value: headingLevel,
                    range: range
                )
            }
        }
    }

    fileprivate static func markConfirmedPlainTextParagraphs(in value: NSMutableAttributedString) {
        guard value.length > 0 else { return }
        enumerateParagraphRanges(in: value.string) { range, _ in
            guard range.location < value.length else { return }
            value.addAttribute(
                NativeRichTextPastePolicy.confirmedNaturalParagraph,
                value: true,
                range: range
            )
        }
    }

    fileprivate static func applyingCompanionParagraphStyles(
        from companion: NSAttributedString,
        to primary: NSMutableAttributedString,
        paragraphMetadata: [NativeRichTextNoteParagraphHTMLMetadata?]?
    ) -> Bool {
        let companionParagraphs = paragraphContents(in: companion)
        let primaryParagraphs = paragraphContents(in: primary)
        guard NativeRichTextNoteParagraphHTMLPolicy.paragraphsMatch(primaryParagraphs, companionParagraphs) else { return false }
        let metadata: [NativeRichTextNoteParagraphHTMLMetadata?]
        if let paragraphMetadata, paragraphMetadata.count == primaryParagraphs.count {
            metadata = paragraphMetadata
        } else {
            metadata = Array(repeating: nil, count: primaryParagraphs.count)
        }

        var primaryRanges: [NSRange] = []
        var companionRanges: [NSRange] = []
        enumerateParagraphRanges(in: primary.string) { range, _ in primaryRanges.append(range) }
        enumerateParagraphRanges(in: companion.string) { range, _ in companionRanges.append(range) }
        guard primaryRanges.count == companionRanges.count else { return false }

        for index in primaryRanges.indices {
            let targetRange = primaryRanges[index]
            let sourceRange = companionRanges[index]
            guard targetRange.location < primary.length, sourceRange.location < companion.length else { continue }
            let targetStyle = (primary.attribute(.paragraphStyle, at: targetRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let sourceStyle = companion.attribute(.paragraphStyle, at: sourceRange.location, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
            if let saved = metadata[index]?.versionedLayout {
                targetStyle.paragraphSpacingBefore = CGFloat(saved.spacingBefore)
                targetStyle.paragraphSpacing = CGFloat(saved.spacingAfter)
                targetStyle.lineSpacing = CGFloat(saved.lineSpacing)
                targetStyle.firstLineHeadIndent = CGFloat(saved.firstLineHeadIndent)
                targetStyle.headIndent = CGFloat(saved.headIndent)
                targetStyle.tailIndent = CGFloat(saved.tailIndent)
            } else {
                if let spacing = metadata[index]?.cssSpacing {
                    targetStyle.paragraphSpacingBefore = CGFloat(spacing.before)
                    targetStyle.paragraphSpacing = CGFloat(spacing.after)
                } else if metadata[index]?.hasExplicitSpacing == true {
                    targetStyle.paragraphSpacingBefore = sourceStyle.paragraphSpacingBefore
                    targetStyle.paragraphSpacing = sourceStyle.paragraphSpacing
                } else {
                    targetStyle.paragraphSpacingBefore = max(targetStyle.paragraphSpacingBefore, sourceStyle.paragraphSpacingBefore)
                    targetStyle.paragraphSpacing = max(targetStyle.paragraphSpacing, sourceStyle.paragraphSpacing)
                }
                if sourceStyle.lineSpacing > 0.01 {
                    targetStyle.lineSpacing = sourceStyle.lineSpacing
                }
            }
            primary.addAttribute(.paragraphStyle, value: targetStyle, range: targetRange)
        }
        return true
    }

    private static func html(from value: NSAttributedString, noteFormatting: Bool = false) -> String {
        let serializable = NSMutableAttributedString(attributedString: value)
        var replacements: [(NSRange, String)] = []
        serializable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: serializable.length)) { attribute, range, _ in
            if let table = attribute as? NativeTableAttachment, let marker = table.marker { replacements.append((range, marker)) }
            else if let image = attribute as? NativeImageAttachment { replacements.append((range, image.marker)) }
            else if let image = attribute as? NativeUnavailableImageAttachment { replacements.append((range, image.marker)) }
            else if let opaque = attribute as? NativeOpaqueRichTextAttachment { replacements.append((range, opaque.marker)) }
            else if let formula = attribute as? NativeFormulaAttachment, let marker = formula.marker { replacements.append((range, marker)) }
        }
        for (range, marker) in replacements.reversed() { serializable.replaceCharacters(in: range, with: marker) }
        if noteFormatting { return noteHTML(from: serializable) }
        guard serializable.length > 0, let data = try? serializable.data(from: NSRange(location: 0, length: serializable.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return "" }
        return htmlWithSourceParagraphSemantics(String(data: data, encoding: .utf8) ?? value.string, from: value)
    }

    private static func htmlWithSourceParagraphSemantics(_ html: String, from value: NSAttributedString) -> String {
        guard value.length > 0,
              let expression = try? NSRegularExpression(pattern: #"(?is)<(p|h[1-6])\b[^>]*>"#) else { return html }
        var paragraphRanges: [NSRange] = []
        enumerateParagraphRanges(in: value.string) { range, _ in paragraphRanges.append(range) }
        let source = html as NSString
        let matches = expression.matches(in: html, range: NSRange(location: 0, length: source.length))
        guard matches.count == paragraphRanges.count else { return html }
        let output = NSMutableString(string: html)
        for index in matches.indices.reversed() {
            let match = matches[index]
            let range = paragraphRanges[index]
            guard range.location < value.length else { continue }
            let tag = source.substring(with: match.range)
            let attributes = value.attributes(at: range.location, effectiveRange: nil)
            var additions = ""
            if let heading = (attributes[NativeRichTextPastePolicy.semanticHeadingParagraph] as? NSNumber)?.intValue,
               (1...6).contains(heading),
               !tag.contains("data-native-rich-text-heading-level=") {
                additions += " data-native-rich-text-heading-level=\"\(heading)\""
            }
            if (attributes[NativeRichTextPastePolicy.explicitParagraphSpacing] as? NSNumber)?.boolValue == true,
               !tag.contains("data-native-rich-text-explicit-spacing=") {
                additions += " data-native-rich-text-explicit-spacing=\"1\""
            }
            guard !additions.isEmpty, let close = tag.lastIndex(of: ">") else { continue }
            let updatedTag = String(tag[..<close]) + additions + ">"
            output.replaceCharacters(in: match.range, with: updatedTag)
        }
        return output as String
    }

    private static func noteHTML(from value: NSAttributedString) -> String {
        guard value.length > 0 else { return "" }
        let source = value.string as NSString
        var output = ""
        var cursor = 0
        var isInsideQuote = false
        while cursor < source.length {
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            source.getParagraphStart(&paragraphStart, end: &paragraphEnd, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            guard paragraphEnd > cursor else { break }
            let paragraphRange = NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart)
            let contentRange = NSRange(location: paragraphStart, length: max(0, contentsEnd - paragraphStart))
            let paragraphAttributes = value.attributes(at: paragraphStart, effectiveRange: nil)
            let block = NativeRichTextNoteFormatting.block(in: paragraphAttributes)
            let quoted = block?.includesQuote == true
            let paragraphStyle = paragraphAttributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            let paragraphFontSize = (paragraphAttributes[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize
            let headingLevel = noteHeadingLevel(in: value, range: contentRange)
            var body: String
            if contentRange.length == 0 {
                body = "<p><br></p>"
            } else {
                let fragment = value.attributedSubstring(from: contentRange)
                let inner = noteInlineHTML(from: fragment)
                if inner.isEmpty {
                    body = "<p><br></p>"
                } else if let headingLevel {
                    body = "<h\(headingLevel)>\(inner)</h\(headingLevel)>"
                } else {
                    body = "<p>\(inner)</p>"
                }
            }
            body = NativeRichTextNoteParagraphHTMLPolicy.applying(
                NativeRichTextNoteParagraphHTMLStyle(
                    spacingBefore: Double(paragraphStyle.paragraphSpacingBefore),
                    spacingAfter: Double(paragraphStyle.paragraphSpacing),
                    lineSpacing: Double(paragraphStyle.lineSpacing),
                    fontSize: Double(paragraphFontSize),
                    firstLineHeadIndent: Double(paragraphStyle.firstLineHeadIndent),
                    headIndent: Double(paragraphStyle.headIndent),
                    tailIndent: Double(paragraphStyle.tailIndent)
                ),
                to: body,
                blockKind: block,
                isListItem: paragraphAttributes[NativeRichTextNoteFormatting.listKey] as? Bool == true
            )
            if quoted && !isInsideQuote { output += "<blockquote>" }
            if !quoted && isInsideQuote { output += "</blockquote>" }
            output += body
            isInsideQuote = quoted
            cursor = NSMaxRange(paragraphRange)
        }
        if isInsideQuote { output += "</blockquote>" }
        return output
    }

    private static func noteHeadingLevel(in value: NSAttributedString, range: NSRange) -> Int? {
        guard range.length > 0 else { return nil }
        var level: Int?
        var isUniformHeading = true
        value.enumerateAttribute(.font, in: range) { attribute, _, stop in
            let size = (attribute as? UIFont)?.pointSize ?? RichTextMetrics.bodySize
            let currentLevel: Int?
            if size >= 20 { currentLevel = 1 }
            else if size >= 17 { currentLevel = 2 }
            else { currentLevel = nil }
            guard let currentLevel else {
                isUniformHeading = false
                stop.pointee = true
                return
            }
            if let level, level != currentLevel {
                isUniformHeading = false
                stop.pointee = true
            } else {
                level = currentLevel
            }
        }
        return isUniformHeading ? level : nil
    }

    private static func noteInlineHTML(from fragment: NSAttributedString) -> String {
        guard fragment.length > 0 else { return "" }
        var output = ""
        let source = fragment.string as NSString
        var pendingRange: NSRange?
        var pendingStyle: NativeRichTextNoteInlineHTMLStyle?

        func appendPendingRun() {
            guard let range = pendingRange, let style = pendingStyle,
                  range.location >= 0, NSMaxRange(range) <= source.length else { return }
            let text = source.substring(with: range)
            let preservesLeadingSpace = range.location == 0
                || (range.location > 0 && source.character(at: range.location - 1) == 32)
            let preservesTrailingSpace = NSMaxRange(range) == source.length
                || (NSMaxRange(range) < source.length && source.character(at: NSMaxRange(range)) == 32)
            let escaped = NativeRichTextNoteInlineHTMLPolicy.escapingText(
                text,
                preservingSpaces: true,
                preserveLeadingSpace: preservesLeadingSpace,
                preserveTrailingSpace: preservesTrailingSpace
            )
            output += NativeRichTextNoteInlineHTMLPolicy.applying(style, to: escaped)
        }

        fragment.enumerateAttributes(in: NSRange(location: 0, length: fragment.length)) { attributes, range, _ in
            let font = attributes[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let link: String? = {
                guard let value = attributes[.link] else { return nil }
                if let url = value as? URL { return url.absoluteString }
                if let url = value as? NSURL { return url.absoluteString }
                return value as? String
            }()
            let style = NativeRichTextNoteInlineHTMLStyle(
                bold: traits.contains(.traitBold),
                italic: traits.contains(.traitItalic),
                underlined: (attributes[.underlineStyle] as? Int ?? 0) != 0,
                fontSize: font.flatMap { abs(Double($0.pointSize) - 16) > 0.5 ? Double($0.pointSize) : nil },
                colorHex: (attributes[.foregroundColor] as? UIColor).flatMap(noteHTMLColorHex),
                link: link
            )

            if pendingStyle == style, let previousRange = pendingRange, NSMaxRange(previousRange) == range.location {
                pendingRange = NSRange(location: previousRange.location, length: previousRange.length + range.length)
            } else {
                appendPendingRun()
                pendingStyle = style
                pendingRange = range
            }
        }
        appendPendingRun()
        return output
    }

    private static func noteHTMLColorHex(_ color: UIColor) -> String? {
        if color.isEqual(UIColor.label) { return nil }
        let resolved = color.resolvedColor(with: .current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            guard resolved.getWhite(&white, alpha: &alpha) else { return nil }
            red = white
            green = white
            blue = white
        }
        guard alpha > 0.01 else { return nil }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    private static func restoreNativeTables(in value: NSMutableAttributedString) {
        let pattern = #"\[\[NATIVE_TABLE:([A-Za-z0-9+/=]+)\]\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let text = value.string as NSString
        for match in expression.matches(in: value.string, range: NSRange(location: 0, length: text.length)).reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let encoded = text.substring(with: match.range(at: 1))
            let marker = text.substring(with: match.range)
            guard encoded.utf8.count <= 64 * 1024,
                  let data = Data(base64Encoded: encoded),
                  let table = try? JSONDecoder().decode(RichTextTable.self, from: data),
                  !table.isFlowchart || ((1...RichTextTable.maximumRows).contains(table.rowCount)
                    && table.cells.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.utf8.count <= RichTextTable.maximumCellBytes } }))
            else { continue }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: NativeTableAttachment(table: table, marker: marker)))
        }
        let imagePattern = #"\[\[NATIVE_IMAGE:([A-Za-z0-9+/=]+)\]\]"#
        guard let imageExpression = try? NSRegularExpression(pattern: imagePattern) else { return }
        let updatedText = value.string as NSString
        for match in imageExpression.matches(in: value.string, range: NSRange(location: 0, length: updatedText.length)).reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let encoded = updatedText.substring(with: match.range(at: 1))
            let marker = updatedText.substring(with: match.range)
            let replacement: NSTextAttachment
            if encoded.utf8.count <= NativeRichTextImageLimits.maximumEncodedBytes,
               let data = Data(base64Encoded: encoded),
               let dataURL = String(data: data, encoding: .utf8),
               let attachment = NativeImageAttachment(dataURL: dataURL, marker: marker) {
                replacement = attachment
            } else {
                replacement = NativeUnavailableImageAttachment(marker: marker)
            }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: replacement))
        }
        let formulaPattern = #"\[\[NATIVE_FORMULA:([A-Za-z0-9+/=]+)\]\]"#
        guard let formulaExpression = try? NSRegularExpression(pattern: formulaPattern) else { return }
        let formulaText = value.string as NSString
        for match in formulaExpression.matches(in: value.string, range: NSRange(location: 0, length: formulaText.length)).reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let encoded = formulaText.substring(with: match.range(at: 1))
            let marker = formulaText.substring(with: match.range)
            guard encoded.utf8.count <= 8 * 1024,
                  let data = Data(base64Encoded: encoded),
                  let formula = try? JSONDecoder().decode(RichTextFormula.self, from: data) else { continue }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: NativeFormulaAttachment(formula: formula, marker: marker)))
        }

        let opaquePattern = #"\[\[NATIVE_[A-Z0-9_]+:[^\]]{0,7168000}\]\]"#
        guard let opaqueExpression = try? NSRegularExpression(pattern: opaquePattern) else { return }
        let opaqueText = value.string as NSString
        for match in opaqueExpression.matches(in: value.string, range: NSRange(location: 0, length: opaqueText.length)).reversed() {
            let marker = opaqueText.substring(with: match.range)
            let kind = marker.dropFirst(2).split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            let label: String
            switch kind {
            case "NATIVE_IMAGE", "NATIVE_RAW_HTML": label = "图片"
            case "NATIVE_TABLE": label = "表格"
            case "NATIVE_FORMULA": label = "公式"
            default: label = "附件"
            }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: label, marker: marker)))
        }
    }

    private static func normalizeFonts(
        in value: NSMutableAttributedString,
        semanticHeadingSizes: [String: [CGFloat]] = [:]
    ) {
        normalizePastedFonts(in: value, semanticHeadingSizes: semanticHeadingSizes)
    }

    private static func semanticHeadingSizes(in data: Data) -> [String: [CGFloat]] {
        guard let html = String(data: data, encoding: .utf8),
              let expression = try? NSRegularExpression(pattern: #"(?is)<h([1-6])\b[^>]*>(.*?)</h\1\s*>"#) else { return [:] }
        let source = html as NSString
        let matches = expression.matches(in: html, range: NSRange(location: 0, length: source.length)).prefix(32)
        var result: [String: [CGFloat]] = [:]
        for match in matches {
            guard match.numberOfRanges > 2 else { continue }
            let innerHTML = source.substring(with: match.range(at: 2))
            guard innerHTML.utf8.count <= 16 * 1024,
                  let fragmentData = "<html><head><meta charset=\"utf-8\"></head><body>\(innerHTML)</body></html>".data(using: .utf8),
                  let fragment = try? NSAttributedString(
                    data: fragmentData,
                    options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: nil
                  ) else { continue }
            let level = source.substring(with: match.range(at: 1))
            let size = level == "1" ? RichTextMetrics.heading1Size : RichTextMetrics.heading2Size
            for paragraph in fragment.string.components(separatedBy: .newlines) {
                let key = semanticHeadingKey(paragraph)
                guard !key.isEmpty else { continue }
                result[key, default: []].append(size)
            }
        }
        if let paragraphExpression = try? NSRegularExpression(pattern: #"(?is)<p\b([^>]*)>(.*?)</p\s*>"#),
           let sizeExpression = try? NSRegularExpression(pattern: #"(?i)font-size\s*:\s*(21|18)(?:\.0+)?\s*pt\b"#) {
            for match in paragraphExpression.matches(in: html, range: NSRange(location: 0, length: source.length)).prefix(64) {
                guard match.numberOfRanges > 2 else { continue }
                let paragraphHTML = source.substring(with: match.range)
                let paragraphNSString = paragraphHTML as NSString
                guard let sizeMatch = sizeExpression.firstMatch(
                    in: paragraphHTML,
                    range: NSRange(location: 0, length: paragraphNSString.length)
                ), sizeMatch.numberOfRanges > 1,
                let sizeValue = Int(paragraphNSString.substring(with: sizeMatch.range(at: 1))) else { continue }
                let innerHTML = source.substring(with: match.range(at: 2))
                guard innerHTML.utf8.count <= 16 * 1024,
                      let fragmentData = "<html><head><meta charset=\"utf-8\"></head><body>\(innerHTML)</body></html>".data(using: .utf8),
                      let fragment = try? NSAttributedString(
                        data: fragmentData,
                        options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                        documentAttributes: nil
                      ) else { continue }
                let size = sizeValue == 21 ? RichTextMetrics.heading1Size : RichTextMetrics.heading2Size
                for paragraph in fragment.string.components(separatedBy: .newlines) {
                    let key = semanticHeadingKey(paragraph)
                    guard !key.isEmpty else { continue }
                    result[key, default: []].append(size)
                }
            }
        }
        return result
    }

    private static func semanticHeadingKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizePastedFonts(
        in value: NSMutableAttributedString,
        semanticHeadingSizes: [String: [CGFloat]] = [:]
    ) {
        guard value.length > 0 else { return }

        let text = value.string
        var remainingHeadingSizes = semanticHeadingSizes
        var updates: [(NSRange, UIFont)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { substring, range, _, _ in
            guard let substring else { return }
            let visibleText = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visibleText.isEmpty else { return }

            let paragraphRange = NSRange(range, in: text)
            let headingKey = semanticHeadingKey(visibleText)
            let headingSize: CGFloat? = {
                guard var sizes = remainingHeadingSizes[headingKey], !sizes.isEmpty else { return nil }
                let size = sizes.removeFirst()
                remainingHeadingSizes[headingKey] = sizes
                return size
            }()

            value.enumerateAttribute(.font, in: paragraphRange) { attribute, fontRange, _ in
                let source = attribute as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
                let size = headingSize ?? RichTextMetrics.bodySize
                let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(source.fontDescriptor.symbolicTraits)
                    ?? UIFont.systemFont(ofSize: size).fontDescriptor
                updates.append((fontRange, UIFont(descriptor: descriptor, size: size)))
            }
        }
        for (range, font) in updates {
            value.addAttribute(.font, value: font, range: range)
        }
    }
}

private final class NativeTableAttachment: NSTextAttachment, NSCopying {
    static let defaultDisplayWidth: CGFloat = 440

    let table: RichTextTable
    let instanceID: UUID
    let appearance: NativeRichTextTableAppearance
    private let originalMarker: String?
    private(set) var displayWidth: CGFloat
    private var fieldFrames: [[CGRect]] = []

    init(
        table: RichTextTable,
        marker: String? = nil,
        instanceID: UUID = UUID(),
        displayWidth: CGFloat = defaultDisplayWidth,
        appearance: NativeRichTextTableAppearance = .system
    ) {
        var normalizedTable = table
        normalizedTable.normalizeBoldRanges()
        self.table = normalizedTable
        self.instanceID = instanceID
        self.appearance = appearance
        originalMarker = normalizedTable == table ? marker : nil
        self.displayWidth = max(80, displayWidth)
        super.init(data: nil, ofType: "com.kaogong.native-table")
        redraw()
    }

    required init?(coder: NSCoder) { nil }

    func copy(with zone: NSZone? = nil) -> Any {
        NativeTableAttachment(table: table, marker: originalMarker, instanceID: instanceID, displayWidth: displayWidth, appearance: appearance)
    }

    func replacingAppearance(
        _ appearance: NativeRichTextTableAppearance, displayWidth: CGFloat
    ) -> NativeTableAttachment {
        NativeTableAttachment(table: table, marker: originalMarker, instanceID: instanceID, displayWidth: displayWidth, appearance: appearance)
    }

    @discardableResult
    func updateDisplayWidth(_ width: CGFloat) -> Bool {
        let updatedWidth = max(80, floor(width))
        guard updatedWidth.isFinite, abs(updatedWidth - displayWidth) > 0.5 else { return false }
        displayWidth = updatedWidth
        redraw()
        return true
    }

    @MainActor
    static func hitTest(
        _ point: CGPoint, in view: UITextView, near offset: Int? = nil
    ) -> (attachment: NativeTableAttachment, range: NSRange, cell: RichTextTable.Cell)? {
        let closest = offset ?? view.closestPosition(to: point).map {
            view.offset(from: view.beginningOfDocument, to: $0)
        }
        guard let closest else { return nil }
        for character in [closest, closest - 1, closest - 2, closest + 1]
            where (0..<view.textStorage.length).contains(character) {
            guard let attachment = view.textStorage.attribute(.attachment, at: character, effectiveRange: nil) as? NativeTableAttachment,
                  let frame = attachment.frame(in: view, at: character),
                  let cell = attachment.cell(at: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
            else { continue }
            return (attachment, NSRange(location: character, length: 1), cell)
        }
        return nil
    }

    @MainActor
    func frame(in view: UITextView, at offset: Int) -> CGRect? {
        guard let start = view.position(from: view.beginningOfDocument, offset: offset),
              let end = view.position(from: start, offset: 1),
              let range = view.textRange(from: start, to: end) else { return nil }
        let rect = view.firstRect(for: range)
        guard !rect.isNull, !rect.isInfinite, rect.width > 0 else { return nil }
        return CGRect(
            x: rect.minX, y: rect.minY + max(0, (rect.height - bounds.height) / 2),
            width: bounds.width, height: bounds.height
        )
    }

    func frame(for cell: RichTextTable.Cell) -> CGRect? {
        guard fieldFrames.indices.contains(cell.row), fieldFrames[cell.row].indices.contains(cell.column) else { return nil }
        return fieldFrames[cell.row][cell.column]
    }

    func cell(at point: CGPoint) -> RichTextTable.Cell? {
        for (row, fields) in fieldFrames.enumerated() {
            if let column = fields.firstIndex(where: { $0.contains(point) }) {
                return RichTextTable.Cell(row: row, column: column)
            }
        }
        return nil
    }

    func content(for cell: RichTextTable.Cell) -> NSAttributedString {
        if table.isFlowchart {
            return Self.flowText(table.cells[cell.row][cell.column], title: cell.column == 0)
        }
        return Self.cellAttributedString(table, row: cell.row, column: cell.column, appearance: appearance)
    }

    private func redraw() {
        let height: CGFloat
        if table.isFlowchart, table.columnCount == 2, table.cells.allSatisfy({ $0.count == 2 }) {
            let (flowHeight, frames, flowImage) = Self.renderFlowchart(table, width: displayWidth)
            height = flowHeight
            fieldFrames = frames
            image = flowImage
        } else {
            let layout = Self.layout(table, width: displayWidth, appearance: appearance)
            height = layout.rowHeights.reduce(0, +)
            var y: CGFloat = 0
            fieldFrames = layout.rowHeights.map { rowHeight in
                var x: CGFloat = 0
                let fields = layout.columnWidths.map { columnWidth in
                    let frame = CGRect(x: x, y: y, width: columnWidth, height: rowHeight)
                    x += columnWidth
                    return frame
                }
                y += rowHeight
                return fields
            }
            image = Self.render(table, layout: layout, width: displayWidth, appearance: appearance)
        }
        bounds = CGRect(x: 0, y: -4, width: displayWidth, height: max(1, height))
    }

    private static func renderFlowchart(
        _ table: RichTextTable, width: CGFloat
    ) -> (CGFloat, [[CGRect]], UIImage) {
        let inset: CGFloat = 10
        let gap: CGFloat = 24
        let textWidth = max(1, width - inset * 2)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        var rows: [[CGRect]] = []
        var y: CGFloat = inset
        for (index, step) in table.cells.enumerated() {
            let title = flowText(step[0].isEmpty ? "步骤 \(index + 1)" : step[0], title: true)
            let detail = flowText(step[1], title: false)
            let titleHeight = max(20, ceil(title.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: options, context: nil
            ).height))
            let detailHeight = max(20, ceil(detail.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: options, context: nil
            ).height))
            let first = CGRect(x: inset, y: y, width: textWidth, height: titleHeight)
            let second = CGRect(x: inset, y: first.maxY + 4, width: textWidth, height: detailHeight)
            rows.append([first, second])
            y = second.maxY + inset + gap + inset
        }
        let height = y - gap - inset
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(format.scale, 4096 / max(height, width))
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            for (index, fields) in rows.enumerated() {
                let first = fields[0], second = fields[1]
                let card = CGRect(x: 0, y: first.minY - inset, width: width, height: second.maxY - first.minY + inset * 2)
                UIColor.systemGray6.setFill()
                UIBezierPath(roundedRect: card, cornerRadius: 12).fill()
                let step = table.cells[index]
                flowText(step[0].isEmpty ? "步骤 \(index + 1)" : step[0], title: true)
                    .draw(with: first, options: options, context: nil)
                flowText(step[1], title: false).draw(with: second, options: options, context: nil)
                if index + 1 < rows.count {
                    flowText("↓", title: false).draw(
                        with: CGRect(x: 0, y: card.maxY + 3, width: width, height: gap),
                        options: options, context: nil
                    )
                }
            }
        }
        return (height, rows, rendered)
    }

    private static func flowText(_ text: String, title: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: title ? 15 : 13, weight: title ? .semibold : .regular),
            .foregroundColor: title ? UIColor.label : UIColor.secondaryLabel,
            .paragraphStyle: paragraph
        ])
    }

    var marker: String? {
        if let originalMarker { return originalMarker }
        var normalizedTable = table
        normalizedTable.normalizeBoldRanges()
        guard let data = try? JSONEncoder().encode(normalizedTable) else { return nil }
        return "[[NATIVE_TABLE:\(data.base64EncodedString())]]"
    }

    private struct TableLayout {
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
    }

    private static func layout(
        _ table: RichTextTable,
        width: CGFloat,
        appearance: NativeRichTextTableAppearance
    ) -> TableLayout {
        let columns = max(1, table.columnCount)
        let desiredColumnWidths = (0..<columns).map { column in
            let natural = table.cells.indices.compactMap { rowIndex -> CGFloat? in
                guard table.cells[rowIndex].indices.contains(column) else { return nil }
                let measured = cellAttributedString(table, row: rowIndex, column: column, appearance: appearance).size().width
                    + (appearance.usesHorizontalTableRules ? 14 : 18)
                return min(220, max(72, measured))
            }.max() ?? 96
            return natural
        }
        let totalWidth = desiredColumnWidths.reduce(0, +)
        var columnWidths = desiredColumnWidths
        if totalWidth < width {
            let addition = (width - totalWidth) / CGFloat(columns)
            columnWidths = columnWidths.map { $0 + addition }
        } else if totalWidth > width, totalWidth > 0 {
            let scale = width / totalWidth
            let minimumColumnWidth = min(36, width / CGFloat(columns))
            columnWidths = columnWidths.map { max(minimumColumnWidth, $0 * scale) }
            let overflow = columnWidths.reduce(0, +) - width
            let flexibleWidth = columnWidths.reduce(0) { $0 + max(0, $1 - minimumColumnWidth) }
            if overflow > 0, flexibleWidth > 0 {
                columnWidths = columnWidths.map {
                    $0 - overflow * max(0, $0 - minimumColumnWidth) / flexibleWidth
                }
            }
        }
        let rowHeights = table.cells.enumerated().map { rowIndex, row in
            row.enumerated().map { column, _ in
                let columnWidth = columnWidths[min(column, columnWidths.count - 1)]
                let attributed = cellAttributedString(table, row: rowIndex, column: column, appearance: appearance)
                let rect = attributed.boundingRect(
                    with: CGSize(width: max(1, columnWidth - 14), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let contentHeight = CGFloat(ceil(rect.height))
                if appearance.usesHorizontalTableRules {
                    let minimumRowHeight: CGFloat = appearance == .wordDetail ? 36 : 34
                    return max(minimumRowHeight, contentHeight + 2 * appearance.tableCellVerticalInset)
                }
                return max(20, contentHeight)
            }.max() ?? CGFloat(20)
        }
        return TableLayout(columnWidths: columnWidths, rowHeights: rowHeights)
    }

    private static func render(
        _ table: RichTextTable,
        layout: TableLayout,
        width: CGFloat,
        appearance: NativeRichTextTableAppearance
    ) -> UIImage {
        let height = layout.rowHeights.reduce(0, +)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            let libraryStyle = appearance.usesHorizontalTableRules
            let ink = libraryStyle
                ? UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
                : UIColor.label
            (libraryStyle ? UIColor.white : UIColor.secondarySystemBackground).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var rowOrigins: [CGFloat] = [0]
            for rowHeight in layout.rowHeights { rowOrigins.append((rowOrigins.last ?? 0) + rowHeight) }
            if !libraryStyle, let headerRow = table.cells.indices.first {
                UIColor.tertiarySystemGroupedBackground.setFill()
                context.cgContext.fill(CGRect(x: 0, y: rowOrigins[headerRow], width: width, height: layout.rowHeights[headerRow]))
            }
            var columnOrigins: [CGFloat] = [0]
            for columnWidth in layout.columnWidths { columnOrigins.append((columnOrigins.last ?? 0) + columnWidth) }
            if libraryStyle {
                context.cgContext.setFillColor(
                    UIColor(red: 150.0 / 255.0, green: 150.0 / 255.0, blue: 156.0 / 255.0, alpha: 1).cgColor
                )
                for y in rowOrigins.dropFirst().dropLast() {
                    context.cgContext.fill(CGRect(x: 0, y: y, width: width, height: 1))
                }
            } else {
                UIColor.separator.setStroke()
                context.cgContext.setLineWidth(1)
                for y in rowOrigins {
                    context.cgContext.move(to: CGPoint(x: 0, y: y)); context.cgContext.addLine(to: CGPoint(x: width, y: y))
                }
                for x in columnOrigins {
                    context.cgContext.move(to: CGPoint(x: x, y: 0)); context.cgContext.addLine(to: CGPoint(x: x, y: height))
                }
                context.cgContext.strokePath()
            }
            for (rowIndex, row) in table.cells.enumerated() {
                for (columnIndex, _) in row.enumerated() {
                    guard columnIndex < layout.columnWidths.count, rowIndex < layout.rowHeights.count else { continue }
                    let topInset = appearance.tableCellVerticalInset
                    let bottomInset = libraryStyle ? topInset : 3
                    let rect = CGRect(
                        x: columnOrigins[columnIndex] + 7,
                        y: rowOrigins[rowIndex] + topInset,
                        width: max(1, layout.columnWidths[columnIndex] - 14),
                        height: max(20, layout.rowHeights[rowIndex] - topInset - bottomInset)
                    )
                    cellAttributedString(table, row: rowIndex, column: columnIndex, appearance: appearance, foreground: ink).draw(
                        with: rect,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                }
            }
        }
    }

    private static func cellAttributedString(
        _ table: RichTextTable,
        row: Int,
        column: Int,
        appearance: NativeRichTextTableAppearance,
        foreground: UIColor? = nil
    ) -> NSAttributedString {
        guard table.cells.indices.contains(row), table.cells[row].indices.contains(column) else {
            return NSAttributedString(string: "")
        }
        let isHeader = row == 0
        let fontSize: CGFloat = appearance == .wordDetail ? 13 : 12
        let font = UIFont.systemFont(ofSize: fontSize, weight: isHeader ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        if appearance == .wordDetail { paragraph.lineSpacing = 2 }
        let ink = foreground ?? (appearance.usesHorizontalTableRules
            ? UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
            : UIColor.label)
        let value = NSMutableAttributedString(
            string: table.cells[row][column],
            attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        )
        for range in table.cellBoldRanges ?? [] where range.row == row && range.column == column {
            guard range.length > 0,
                  range.location >= 0,
                  range.location <= value.length,
                  range.length <= value.length - range.location else { continue }
            value.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize, weight: .bold), range: NSRange(location: range.location, length: range.length))
        }
        return value
    }
}

private final class NativeImageAttachment: NSTextAttachment {
    let dataURL: String
    private let originalMarker: String?

    init?(dataURL: String, marker: String? = nil) {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard encoded.utf8.count <= NativeRichTextImageLimits.maximumEncodedBytes,
              let data = Data(base64Encoded: encoded),
              data.count <= 8 * 1024 * 1024,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else { return nil }
        let source = UIImage(cgImage: thumbnail)
        self.dataURL = dataURL
        originalMarker = marker
        super.init(data: nil, ofType: "com.kaogong.native-image")
        image = source
        let maxWidth: CGFloat = 420
        let scale = min(1, maxWidth / max(1, source.size.width))
        bounds = CGRect(x: 0, y: -4, width: source.size.width * scale, height: source.size.height * scale)
    }

    required init?(coder: NSCoder) { nil }

    var marker: String {
        if let originalMarker { return originalMarker }
        return "[[NATIVE_IMAGE:\(Data(dataURL.utf8).base64EncodedString())]]"
    }
}

private final class NativeUnavailableImageAttachment: NSTextAttachment {
    let marker: String

    init(marker: String) {
        self.marker = marker
        super.init(data: nil, ofType: "com.kaogong.native-image-placeholder")
        let size = CGSize(width: 38, height: 28)
        image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).fill()
            let symbol = UIImage(systemName: "photo")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 8, y: 4, width: 22, height: 20))
            context.cgContext.setStrokeColor(UIColor.separator.cgColor)
            context.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), width: 1)
        }
        bounds = CGRect(x: 0, y: -3, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) { nil }
}

private final class NativeOpaqueRichTextAttachment: NSTextAttachment {
    let label: String
    let marker: String

    init(label: String, marker: String) {
        self.label = label
        self.marker = marker
        super.init(data: nil, ofType: "com.kaogong.native-opaque-attachment")
        let width: CGFloat = 72
        let size = CGSize(width: width, height: 28)
        image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).fill()
            UIImage(systemName: "paperclip")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 6, y: 7, width: 14, height: 14))
            ("\(label)已保留" as NSString).draw(
                in: CGRect(x: 23, y: 7, width: width - 27, height: 15),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.secondaryLabel]
            )
            context.cgContext.setStrokeColor(UIColor.separator.cgColor)
            context.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), width: 1)
        }
        bounds = CGRect(x: 0, y: -3, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) { nil }
}

private final class NativeFormulaAttachment: NSTextAttachment {
    let formula: RichTextFormula
    private let originalMarker: String?

    init(formula: RichTextFormula, marker: String? = nil) {
        self.formula = formula
        originalMarker = marker
        super.init(data: nil, ofType: "com.kaogong.data-analysis-formula")
        let text = formula.preset.expression
        let font = UIFont.systemFont(ofSize: 14, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        let width = min(430, max(190, textWidth + 28))
        let textBounds = (text as NSString).boundingRect(
            with: CGSize(width: width - 28, height: 100),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let size = CGSize(width: width, height: max(42, ceil(textBounds.height) + 20))
        image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.withAlphaComponent(0.08).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10).fill()
            (text as NSString).draw(
                in: CGRect(x: 14, y: 10, width: width - 28, height: size.height - 20),
                withAttributes: attributes
            )
            context.cgContext.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.18).cgColor)
            context.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), width: 1)
        }
        bounds = CGRect(x: 0, y: -10, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) { nil }

    var marker: String? {
        if let originalMarker { return originalMarker }
        guard let data = try? JSONEncoder().encode(formula) else { return nil }
        return "[[NATIVE_FORMULA:\(data.base64EncodedString())]]"
    }
}

private struct DataAnalysisFormulaPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var formula: RichTextFormula
    let onSave: (RichTextFormula) -> Void

    init(initial: RichTextFormula, onSave: @escaping (RichTextFormula) -> Void) {
        _formula = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List(DataAnalysisFormulaPreset.allCases) { preset in
                Button {
                    formula.preset = preset
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: formula.preset == preset ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(formula.preset == preset ? AppTheme.accent : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.rawValue).font(AppTheme.cardTitleFont).foregroundStyle(.primary)
                            Text(preset.expression).font(AppTheme.inputFont).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("资料分析公式")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("保存") { onSave(formula); dismiss() }
                    .buttonStyle(NativePrimaryButtonStyle())
                    .frame(maxWidth: 210)
                    .padding(14)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

private struct RichTextInternalLinkPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let links: [RichTextInternalLink]
    let onSelect: (RichTextInternalLink) -> Void

    private var filteredLinks: [RichTextInternalLink] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return links }
        return links.filter { $0.title.localizedCaseInsensitiveContains(value) }
    }

    var body: some View {
        NavigationStack {
            List(filteredLinks) { link in
                Button {
                    onSelect(link)
                    dismiss()
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: link.collection == "errors" ? "exclamationmark.circle" : "note.text")
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(2)
                            Text(link.collection == "errors" ? "错题" : "笔记")
                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "搜索笔记或错题")
            .navigationTitle("插入站内链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

private struct RichTextTableEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var table: RichTextTable
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedCell: Int?
    let appearance: NativeRichTextTableAppearance
    let onSave: (RichTextTable, @escaping (Result<Void, NativeRichTextEditorError>) -> Void) -> Void

    init(
        initial: RichTextTable,
        appearance: NativeRichTextTableAppearance,
        onSave: @escaping (RichTextTable, @escaping (Result<Void, NativeRichTextEditorError>) -> Void) -> Void
    ) {
        _table = State(initialValue: initial)
        self.appearance = appearance
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            tableFields
            .navigationTitle("编辑表格")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        tableButton("增加行", "plus.rectangle.on.rectangle") { addRow() }
                        tableButton("删除行", "minus.rectangle") { removeRow() }
                        tableButton("增加列", "rectangle.split.3x1") { addColumn() }
                        tableButton("删除列", "rectangle.split.2x1") { removeColumn() }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 320, alignment: .leading)
                    }
                    Button(action: save) {
                        if isSaving {
                            Label("正在保存…", systemImage: "hourglass")
                        } else {
                            Text("保存")
                        }
                    }
                        .buttonStyle(NativePrimaryButtonStyle())
                        .frame(maxWidth: 210)
                        .disabled(isSaving)
                }
                .padding(14)
                .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .disabled(isSaving)
                }
            }
        }
    }

    private var tableFields: some View {
        Group {
            if appearance == .libraryContent {
                GeometryReader { proxy in
                    let availableWidth = max(0, proxy.size.width - 32)
                    let columnWidth = max(108, availableWidth / CGFloat(max(1, table.columnCount)))
                    documentTableFields(columnWidth: columnWidth)
                }
                .background(Color.white)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(table.cells.indices, id: \.self) { row in
                            HStack(spacing: 7) {
                                ForEach(table.cells[row].indices, id: \.self) { column in
                                    TextField("内容", text: cellBinding(row: row, column: column))
                                        .font(AppTheme.inputFont)
                                        .textFieldStyle(NativeTextFieldStyle())
                                        .frame(width: 130)
                                        .focused($focusedCell, equals: row * 8 + column)
                                        .disabled(isSaving)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func documentTableFields(columnWidth: CGFloat) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(table.cells.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(table.cells[row].indices, id: \.self) { column in
                            TextField("内容", text: cellBinding(row: row, column: column), axis: .vertical)
                                .font(.system(size: 12, weight: row == 0 ? .semibold : .regular))
                                .textFieldStyle(.plain)
                                .lineLimit(1...)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 7)
                                .frame(width: columnWidth, alignment: .leading)
                                .frame(minHeight: 34, alignment: .topLeading)
                                .focused($focusedCell, equals: row * 8 + column)
                                .disabled(isSaving)
                        }
                    }
                    if row < table.rowCount - 1 {
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.32))
                            .frame(height: 0.5)
                    }
                }
            }
            .frame(width: columnWidth * CGFloat(max(1, table.columnCount)), alignment: .leading)
            .padding(16)
        }
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding {
            guard table.cells.indices.contains(row), table.cells[row].indices.contains(column) else { return "" }
            return table.cells[row][column]
        } set: { value in
            guard table.cells.indices.contains(row), table.cells[row].indices.contains(column) else { return }
            table.cells[row][column] = value
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        focusedCell = nil
        Task { @MainActor in
            await Task.yield()
            onSave(table) { result in
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func addRow() {
        guard table.rowCount < 12 else { return }
        table.cells.append(Array(repeating: "", count: max(1, table.columnCount)))
    }

    private func removeRow() {
        guard table.rowCount > 1 else { return }
        table.cells.removeLast()
    }

    private func addColumn() {
        guard table.columnCount < 8 else { return }
        for row in table.cells.indices { table.cells[row].append("") }
    }

    private func removeColumn() {
        guard table.columnCount > 1 else { return }
        for row in table.cells.indices { table.cells[row].removeLast() }
    }

    private func tableButton(_ title: String, _ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: image).font(AppTheme.auxiliaryFont).frame(maxWidth: .infinity) }
            .buttonStyle(NativeSecondaryButtonStyle())
            .disabled(isSaving)
    }
}

enum LegacyRichTextConverter {
    static func html(from value: Any) -> String {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["),
               let data = trimmed.data(using: .utf8),
               let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return html(fromBlocks: blocks)
            }
            return text
        }
        if let blocks = value as? [[String: Any]] { return html(fromBlocks: blocks) }
        return ""
    }

    private static func html(fromBlocks blocks: [[String: Any]]) -> String {
        var output = ""
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            let type = block["type"] as? String ?? "text"
            let content = inline(block)
            let indent = max(0, block["indent"] as? Int ?? 0)
            let style = indent > 0 ? " style=\"padding-left:\(indent * 24)px\"" : ""
            switch type {
            case "heading1", "heading2", "heading3", "heading4":
                let level = type == "heading1" ? 1 : 2
                output += "<h\(level)\(style)>\(content)</h\(level)>"
            case "bulletList", "orderedList":
                let tag = type == "bulletList" ? "ul" : "ol"
                output += "<\(tag)\(style)>"
                while index < blocks.count, (blocks[index]["type"] as? String) == type {
                    output += "<li>\(inline(blocks[index]))</li>"
                    index += 1
                }
                output += "</\(tag)>"
                index -= 1
            case "quote": output += "<blockquote\(style)>\(content)</blockquote>"
            case "divider": output += "<p style=\"color:#999;font-size:10px\">────────────────</p>"
            case "code": output += "<pre><code>\(escape(block["content"] as? String ?? ""))</code></pre>"
            case "todo":
                let checked = block["checked"] as? Bool == true ? "☑" : "☐"
                output += "<p\(style)>\(checked) \(content)</p>"
            case "callout": output += "<blockquote\(style)>\(escape(block["emoji"] as? String ?? "💡")) \(content)</blockquote>"
            case "table":
                output += "<table>"
                for row in block["tableData"] as? [[Any]] ?? [] {
                    output += "<tr>" + row.map { "<td>\(escape(String(describing: $0)))</td>" }.joined() + "</tr>"
                }
                output += "</table>"
            case "image":
                let image = block["imgData"] as? [String: Any] ?? [:]
                output += "<img src=\"\(escape(image["src"] as? String ?? ""))\" alt=\"\(escape(image["alt"] as? String ?? ""))\">"
            case "toggle":
                output += "<p\(style)>▸ \(content)</p>"
                if let children = block["children"] as? [[String: Any]] { output += html(fromBlocks: children) }
            default: output += "<p\(style)>\(content.isEmpty ? "<br>" : content)</p>"
            }
            index += 1
        }
        return output
    }

    private static func inline(_ block: [String: Any]) -> String {
        if let html = block["html"] as? String, !html.isEmpty { return html }
        return escape(block["content"] as? String ?? "").replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
