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

    static func isQuoted(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        attributes[quoteKey] as? Bool == true
    }

    static func isQuoted(_ attributed: NSAttributedString, at location: Int) -> Bool {
        guard attributed.length > 0 else { return false }
        let safeLocation = min(max(0, location), attributed.length - 1)
        return isQuoted(attributed.attributes(at: safeLocation, effectiveRange: nil))
    }
}

private enum RichTextCommandKind: Equatable {
    case bold, italic, underline, strike, indent, outdent, numbers, todos, divider
    case bullets(RichTextBulletStyle)
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

private enum RichTextBulletStyle: String, CaseIterable, Identifiable {
    case filled = "实心圆点"
    case hollow = "空心圆点"
    case square = "方块"
    case dash = "短横线"
    var id: String { rawValue }
    var prefix: String {
        switch self {
        case .filled: "• "
        case .hollow: "◦ "
        case .square: "▪︎ "
        case .dash: "– "
        }
    }
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

private final class NoteQuoteLayoutFragment: NSTextLayoutFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let paragraph = textElement as? NSTextParagraph,
              NativeRichTextNoteFormatting.isQuoted(paragraph.attributedString, at: 0),
              let first = textLineFragments.first,
              let last = textLineFragments.last else { return }
        let lineRects = textLineFragments.map(\.typographicBounds).filter { !$0.isNull && !$0.isEmpty }
        guard let top = lineRects.map(\.minY).min(), let bottom = lineRects.map(\.maxY).max() else { return }
        let x = point.x + first.glyphOrigin.x - 10
        let rect = CGRect(x: x, y: point.y + top - 2, width: 2, height: max(4, bottom - top + 4))
        context.saveGState()
        context.setFillColor(UIColor.systemGray4.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 1, cornerHeight: 1, transform: nil))
        context.fillPath()
        context.restoreGState()
        _ = last
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

    var errorDescription: String? {
        switch self {
        case .editorSessionChanged: "笔记页面已切换，图片没有插入到其他题目。请重新打开图片选择器。"
        case .invalidSelection: "图片插入位置已失效，请重新选择插入位置后再试。"
        case .imageAttachmentInvalid: "图片无法生成附件，原笔记没有被修改。"
        case .tableTargetChanged: "表格位置已变化，当前输入仍保留。"
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
}

@MainActor
struct NativeRichTextEditor: View {
    @Binding var html: String
    let minHeight: CGFloat
    var mode: RichTextToolbarMode = .full
    var documentStyle = false
    var noteFormatting = false
    var tableAppearance: NativeRichTextTableAppearance = .system
    var focusOnAppear = false
    var initialSelectionOffset: Int? = nil
    var initialSelectionWidth: CGFloat? = nil
    var preparedInitialHTML: String? = nil
    var preparedInitialAttributedText: NSAttributedString? = nil
    var editorSession: NativeRichTextEditorSession? = nil
    var editorDocumentID: String? = nil
    var editorSessionID: UUID? = nil
    var defersPhotoPickerToParent = true
    var internalLinks: [RichTextInternalLink] = []
    var onOpenInternalLink: ((RichTextInternalLink) -> Void)?
    var onFocusReady: ((UITextView) -> Void)?
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
        if case .linkPrompt? = activeAlert { return "添加链接" }
        return "无法插入图片"
    }

    private var alertMessage: String {
        switch activeAlert {
        case .linkPrompt: "选中文字后添加链接；没有选中文字时会直接插入链接地址。"
        case .imageError(let message): message
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
                minimumContentHeight: documentStyle ? minHeight : 0,
                focusOnAppear: focusOnAppear,
                initialSelectionOffset: initialSelectionOffset,
                initialSelectionWidth: initialSelectionWidth,
                preparedInitialHTML: preparedInitialHTML,
                preparedInitialAttributedText: preparedInitialAttributedText,
                editorSession: activeEditorSession,
                editorDocumentID: activeEditorDocumentID,
                editorSessionID: activeEditorSessionID,
                usesLazyHTMLInitialization: editorSession != nil
            )
                .modifier(NativeDirectionalTextFieldNavigation())
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
            RichTextTableEditor(initial: request.table) { updated, completion in
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
                        capturedPhotoTarget = nil
                        activeEditorSession.setMediaOperationInProgress(false)
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
            case .imageError(_), nil:
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
                    formatButton(.numbers, "list.number", active: selectionState.isNumbered)
                    bulletMenu
                    formatButton(.quote, "text.quote", active: selectionState.isQuoted)
                    formatButton(.border, "rectangle", active: selectionState.isBordered)
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
                    self.activeEditorSession.setMediaOperationInProgress(false)
                    if case .failure(let error) = result { self.presentImageError(error.localizedDescription) }
                }
            )
        } catch is CancellationError {
            capturedPhotoTarget = nil
            activeEditorSession.setMediaOperationInProgress(false)
        } catch {
            capturedPhotoTarget = nil
            activeEditorSession.setMediaOperationInProgress(false)
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
            Button { run(.bullets(.filled)) } label: { Label("项目列表", systemImage: "list.bullet") }
            Button { run(.numbers) } label: { Label("编号列表", systemImage: "list.number") }
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

    private var bulletMenu: some View {
        Menu {
            ForEach(RichTextBulletStyle.allCases) { style in
                Button { run(.bullets(style)) } label: { Text("\(style.prefix)\(style.rawValue)") }
            }
        } label: {
            toolbarImage("list.bullet", active: selectionState.isBulleted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("无序列表")
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 21).padding(.horizontal, 2)
    }

    private func run(_ kind: RichTextCommandKind) {
        command = RichTextCommand(kind: kind)
    }

    private func formatButton(_ kind: RichTextCommandKind, _ image: String, active: Bool = false, disabled: Bool = false) -> some View {
        toolbarButton(image, active: active, disabled: disabled, label: nil) { run(kind) }
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
    var accessibilityIdentifier: String? = nil
    var onFallback: (() -> Void)? = nil
    var onTapTextOffset: ((Int, NSAttributedString, CGFloat) -> Void)? = nil
    private var preparedSnapshot: NativeRichTextDisplayRenderResult?
    private var renderVersion: String?

    init(
        html: String,
        minHeight: CGFloat = 0,
        tableAppearance: NativeRichTextTableAppearance = .system,
        accessibilityIdentifier: String? = nil,
        noteFormatting: Bool = false,
        onFallback: (() -> Void)? = nil,
        onTapTextOffset: ((Int, NSAttributedString, CGFloat) -> Void)? = nil
    ) {
        self.html = html
        self.minHeight = minHeight
        self.tableAppearance = tableAppearance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.noteFormatting = noteFormatting
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
        onFallback: (() -> Void)? = nil,
        onTapTextOffset: ((Int, NSAttributedString, CGFloat) -> Void)? = nil
    ) {
        self.html = html
        self.minHeight = minHeight
        self.tableAppearance = tableAppearance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.noteFormatting = noteFormatting
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
            guard parent.noteFormatting,
                  let paragraph = textElement as? NSTextParagraph,
                  NativeRichTextNoteFormatting.isQuoted(paragraph.attributedString, at: 0) else {
                return NSTextLayoutFragment(textElement: textElement, range: nil)
            }
            return NoteQuoteLayoutFragment(textElement: textElement, range: nil)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? UITextView,
                  recognizer.state == .ended,
                  let position = view.closestPosition(to: recognizer.location(in: view)) else { return }
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            let snapshot = view.attributedText.map { $0.copy() as? NSAttributedString ?? $0 }
                ?? NSAttributedString(string: "")
            parent.onTapTextOffset?(max(0, min(offset, snapshot.length)), snapshot, view.bounds.width)
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
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = accessibilityIdentifier
        view.isUserInteractionEnabled = onTapTextOffset != nil
        guard context.coordinator.lastHTML != html
                || context.coordinator.lastRenderVersion != renderVersion
                || context.coordinator.lastTableAppearance != tableAppearance
                || context.coordinator.lastNoteFormatting != noteFormatting else { return }
        applyContent(to: view, coordinator: context.coordinator)
        context.coordinator.lastHTML = html
        context.coordinator.lastRenderVersion = renderVersion
        context.coordinator.lastTableAppearance = tableAppearance
        context.coordinator.lastNoteFormatting = noteFormatting
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: 65_536))
        let height = fitting.height.isFinite ? max(minHeight, ceil(fitting.height)) : minHeight
        return CGSize(width: width, height: height)
    }

    private func applyContent(to view: UITextView, coordinator: Coordinator) {
        let rendered = preparedSnapshot ?? NativeRichTextDisplayRenderer.render(
            html,
            tableAppearance: tableAppearance,
            noteFormatting: noteFormatting,
            cleanLegacyInjectedSpacing: noteFormatting
        )
        let styled = NativeRichTextDisplayRenderer.applyingTableAppearance(to: rendered.attributedText, appearance: tableAppearance)
        view.attributedText = styled
        view.accessibilityLabel = styled.string
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
        let attributed = applyingTableAppearance(
            to: RichTextTextView.attributed(
                from: html,
                noteFormatting: noteFormatting,
                cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing
            ),
            appearance: tableAppearance
        )
        guard html.contains("<"), attributed.string == html else {
            return NativeRichTextDisplayRenderResult(attributedText: attributed, usedSafeFallback: false)
        }
        let result = fallback(html, tableAppearance: tableAppearance)
        return noteFormatting
            ? applyingNoteFormatting(to: result, sourceHTML: html, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
            : result
    }

    static func applyingNoteFormatting(
        to result: NativeRichTextDisplayRenderResult,
        sourceHTML: String,
        cleanLegacyInjectedSpacing: Bool = false
    ) -> NativeRichTextDisplayRenderResult {
        NativeRichTextDisplayRenderResult(
            attributedText: RichTextTextView.applyingNoteParagraphFormatting(
                to: result.attributedText,
                sourceHTML: sourceHTML,
                cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing
            ),
            usedSafeFallback: result.usedSafeFallback
        )
    }

    static func applyingTableAppearance(
        to source: NSAttributedString,
        appearance: NativeRichTextTableAppearance
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        var replacements: [(NSRange, NativeTableAttachment)] = []
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let table = value as? NativeTableAttachment, table.appearance != appearance else { return }
            replacements.append((range, table.replacingAppearance(appearance)))
        }
        for (range, table) in replacements.reversed() {
            result.replaceCharacters(in: range, with: NSAttributedString(attachment: table))
        }
        return result.copy() as? NSAttributedString ?? result
    }

    private static func fallback(
        _ html: String,
        tableAppearance: NativeRichTextTableAppearance
    ) -> NativeRichTextDisplayRenderResult {
        let attributed = NSMutableAttributedString(string: "")
        let font = UIFont.systemFont(ofSize: RichTextMetrics.bodySize)
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        for run in NativeRichTextFallbackParser.parse(html) {
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

    static func editableAttributedText(from runs: [NativeRichTextFallbackRun]) -> NSAttributedString? {
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
                if imagePayloadBytes <= maximumImagePayloadBytes,
                   let attachment = NativeImageAttachment(dataURL: dataURL, marker: marker) {
                    attributed.append(NSAttributedString(attachment: attachment))
                } else {
                    attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: "图片", marker: marker)))
                }
            case .tableWithMarker(let encoded, let marker):
                if let table = fallbackTable(from: encoded) {
                    attributed.append(NSAttributedString(attachment: NativeTableAttachment(table: table, marker: marker)))
                } else {
                    attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: "表格", marker: marker)))
                }
            case .formulaWithMarker(let encoded, let marker):
                if let formula = fallbackFormula(from: encoded) {
                    attributed.append(NSAttributedString(attachment: NativeFormulaAttachment(formula: formula, marker: marker)))
                } else {
                    attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: "公式", marker: marker)))
                }
            case .opaque(let label, let marker):
                attributed.append(NSAttributedString(attachment: NativeOpaqueRichTextAttachment(label: label, marker: marker)))
            case .image, .table, .formula, .placeholder:
                return nil
            }
        }
        return attributed.copy() as? NSAttributedString ?? attributed
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

    private static func fallbackTextAttributes(
        _ style: NativeRichTextFallbackTextStyle,
        baseFont: UIFont
    ) -> [NSAttributedString.Key: Any] {
        let size: CGFloat = style.contains(.heading1)
            ? RichTextMetrics.heading1Size
            : (style.contains(.heading2) ? RichTextMetrics.heading2Size : baseFont.pointSize)
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
              (1...8).contains(table.columnCount),
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
    var onLayout: ((UITextView) -> Void)?

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

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
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
    let keyboardAccessory: AnyView
    let keyboardAccessoryHeight: CGFloat
    let keyboardAccessoryState: RichTextKeyboardAccessoryState
    var growsWithContent = false
    var tableAppearance: NativeRichTextTableAppearance = .system
    var noteFormatting = false
    var minimumContentHeight: CGFloat = 0
    var focusOnAppear = false
    var initialSelectionOffset: Int? = nil
    var initialSelectionWidth: CGFloat? = nil
    var preparedInitialHTML: String? = nil
    var preparedInitialAttributedText: NSAttributedString? = nil
    var editorSession: NativeRichTextEditorSession? = nil
    var editorDocumentID: String? = nil
    var editorSessionID: UUID = UUID()
    var usesLazyHTMLInitialization = false

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = RichTextPasteTextView(pasteEnabledUsingTextLayoutManager: true)
        view.onPaste = { [weak coordinator = context.coordinator] textView in
            coordinator?.handlePaste(textView) ?? false
        }
        view.delegate = context.coordinator
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        view.onLayout = { [weak coordinator = context.coordinator] textView in
            coordinator?.updateNativeTableWidths(in: textView)
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
        tableTap.cancelsTouchesInView = false
        tableTap.delaysTouchesBegan = false
        tableTap.delaysTouchesEnded = false
        tableTap.delegate = context.coordinator
        view.addGestureRecognizer(tableTap)
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
            let focusEditor = {
                guard view.window != nil else { return false }
                guard view.becomeFirstResponder() else { return false }
                view.scrollRangeToVisible(caret)
                view.window?.layoutIfNeeded()
                onFocusReady?(view)
                return true
            }
            DispatchQueue.main.async {
                if !focusEditor() {
                    DispatchQueue.main.async { _ = focusEditor() }
                }
            }
        }
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard growsWithContent, let width = proposal.width, width > 0 else { return nil }
        let measurementStart = ProcessInfo.processInfo.systemUptime
        let height = context.coordinator.contentHeight(
            for: uiView,
            width: width,
            minimum: max(42, minimumContentHeight)
        )
        if noteFormatting, editorSession != nil, context.coordinator.didMeasureHeightDuringLastRequest {
            LibraryPerformanceLog.markIfSlow("note.editor.height-measure", since: measurementStart)
        }
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.textLayoutManager?.delegate = noteFormatting ? context.coordinator : nil
        context.coordinator.updateKeyboardAccessory(
            keyboardAccessory,
            height: keyboardAccessoryHeight,
            state: keyboardAccessoryState,
            on: view
        )
        context.coordinator.connect(editorSession, to: view)
        let replacingDocumentContent = context.coordinator.lastHTML != html && !view.isFirstResponder
        if replacingDocumentContent {
            if let preparedInitialAttributedText, preparedInitialHTML == html {
                view.attributedText = NativeRichTextDisplayRenderer.applyingTableAppearance(
                    to: preparedInitialAttributedText,
                    appearance: tableAppearance
                )
                context.coordinator.setPublishedHTML(html)
            } else if !usesLazyHTMLInitialization {
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
            let imageCompletion = command.imageCompletion
            let tableCompletion = command.tableCompletion
            DispatchQueue.main.async {
                self.command = nil
                if let imageCompletion {
                    imageCompletion(result ?? .failure(NativeRichTextEditorError.imageAttachmentInvalid))
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
        weak var connectedSession: NativeRichTextEditorSession?
        private var pendingEndEditingCompletion: ((String?) -> Void)?
        private var lastEditingSelection = NSRange(location: 0, length: 0)
        private var pendingPublish: DispatchWorkItem?
        private var layoutRefreshScheduled = false
        private var layoutRefreshUpdatesToolbar = false
        private var layoutRefreshUpdatesLayout = false
        private weak var pendingLayoutRefreshView: UITextView?
        private var documentRevision: UInt64 = 0
        private var publishedRevision: UInt64 = 0
        private var publishedHTML = ""
        private var cachedSnapshot: NativeRichTextEditorSnapshot?
        private var lastTableWidth: CGFloat?
        private var lastMeasuredWidth: CGFloat?
        private var lastMeasuredHeight: CGFloat = 0
        private var measuredHeightNeedsRefresh = true
        private(set) var didMeasureHeightDuringLastRequest = false
        private var lastSelectionTable: RichTextTable?
        private var lastSelectionFormula: RichTextFormula?
        private var lastQueuedSelectionState: RichTextSelectionState?
        private var accessoryController: UIHostingController<AnyView>?
        private weak var accessoryContainer: RichTextKeyboardAccessoryView?
        private var lastKeyboardAccessoryState: RichTextKeyboardAccessoryState?
        init(parent: RichTextTextView) { self.parent = parent }

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            guard parent.noteFormatting,
                  let paragraph = textElement as? NSTextParagraph,
                  NativeRichTextNoteFormatting.isQuoted(paragraph.attributedString, at: 0) else {
                return NSTextLayoutFragment(textElement: textElement, range: nil)
            }
            return NoteQuoteLayoutFragment(textElement: textElement, range: nil)
        }

        func setPublishedHTML(_ html: String) {
            if lastHTML != html { documentRevision &+= 1 }
            lastHTML = html
            publishedHTML = html
            publishedRevision = documentRevision
            cachedSnapshot = nil
            measuredHeightNeedsRefresh = true
        }

        func contentHeight(for view: UITextView, width: CGFloat, minimum: CGFloat) -> CGFloat {
            didMeasureHeightDuringLastRequest = false
            let normalizedWidth = floor(width * 2) / 2
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

        private func updateCachedNoteHeightFromTextKit(_ view: UITextView) -> Bool {
            guard parent.noteFormatting,
                  let lastMeasuredWidth,
                  view.bounds.width.isFinite,
                  abs(lastMeasuredWidth - floor(view.bounds.width * 2) / 2) <= 0.5,
                  let usedHeight = view.textLayoutManager?.usageBoundsForTextContainer.height,
                  usedHeight.isFinite, usedHeight > 0 else { return false }
            let updatedHeight = max(parent.minimumContentHeight, ceil(usedHeight))
            measuredHeightNeedsRefresh = false
            guard abs(updatedHeight - lastMeasuredHeight) > 0.5 else { return false }
            lastMeasuredHeight = updatedHeight
            return true
        }

        func connect(_ session: NativeRichTextEditorSession?, to view: UITextView) {
            if connectedSession !== session { connectedSession?.disconnect() }
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
            let isComposing = textView.markedTextRange != nil
            connectedSession?.setComposingText(isComposing)
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
                schedulePublish(textView)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            rememberSelection(textView.selectedRange)
            scheduleLayoutAndToolbarRefresh(textView, updatesToolbar: true, updatesLayout: false)
            DispatchQueue.main.async { self.parent.isEditing = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            let latestHTML = publishNow(textView)
            let completion = pendingEndEditingCompletion
            pendingEndEditingCompletion = nil
            connectedSession?.setComposingText(false)
            DispatchQueue.main.async {
                self.parent.isEditing = false
                completion?(latestHTML)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
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
            scheduleLayoutAndToolbarRefresh(textView, updatesToolbar: true, updatesLayout: false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard connectedSession?.isInputLocked != true else { return false }
            if textView.markedTextRange != nil { return true }
            if text.isEmpty, range.length == 1, removeEmptyListPrefixBeforeBackspace(in: textView, range: range) {
                return false
            }
            guard text == "\n" else { return true }
            let source = textView.text as NSString
            let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let list = listPrefix(in: line) else { return true }
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
            for style in RichTextBulletStyle.allCases where line.hasPrefix(style.prefix) {
                return (style.prefix, style.prefix)
            }
            if line.hasPrefix("☐ ") { return ("☐ ", "☐ ") }
            guard let match = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression) else { return nil }
            let current = String(line[match])
            let digits = current.prefix { $0.isNumber }
            guard let number = Int(digits) else { return nil }
            return (current, "\(number + 1). ")
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
        private func replaceAttributed(_ replacement: NSAttributedString, in range: NSRange, view: UITextView) -> Bool {
            NativeRichTextPastePolicy.replace(
                replacement,
                in: range,
                of: view.textStorage,
                undoManager: view.undoManager,
                onReplacement: { [weak self, weak view] replacementRange, replacedText in
                    guard let self, let view else { return }
                    view.selectedRange = NSRange(location: replacementRange.location + replacedText.length, length: 0)
                    self.scheduleLayoutAndToolbarRefresh(view, updatesToolbar: true)
                    self.schedulePublish(view)
                }
            )
        }

        func handlePaste(_ textView: UITextView) -> Bool {
            guard connectedSession?.isInputLocked != true else { return true }
            guard textView.markedTextRange == nil else { return false }
            let range = textView.selectedRange
            guard range.location >= 0,
                  range.length >= 0,
                  NSMaxRange(range) <= textView.attributedText.length else { return false }

            guard let replacement = preparedClipboardText() else { return false }
            let compacted = NativeRichTextPastePolicy.compactParagraphSpacing(in: replacement)
            replaceAttributed(compacted, in: range, view: textView)
            if containsNativeTableAttachment(compacted) {
                updateNativeTableWidths(in: textView, force: true)
            }
            return true
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
                            sourceHTML: html
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
                    let clipboardHTML = item[UTType.html.identifier].flatMap(Self.stringRepresentation)
                    return finalizedRichPaste(
                        imported,
                        plainText: plainText,
                        htmlData: documentType == .html ? Self.dataRepresentation(raw) : nil,
                        sourceHTML: clipboardHTML
                    )
                }

                guard let plainText else { continue }
                if let markdownHTML = NativeRichTextMarkdown.htmlIfMarkdown(plainText) {
                    return finalizedRichPaste(
                        RichTextTextView.attributed(from: markdownHTML, noteFormatting: parent.noteFormatting),
                        plainText: plainText,
                        htmlData: nil,
                        sourceHTML: markdownHTML
                    )
                }
                return plainTextPaste(plainText)
            }
            return nil
        }

        private func finalizedRichPaste(
            _ source: NSAttributedString,
            plainText: String?,
            htmlData: Data?,
            sourceHTML: String? = nil
        ) -> NSAttributedString {
            let richText = NSMutableAttributedString(attributedString: source)
            RichTextTextView.restoreNativeTables(in: richText)
            if let plainText {
                NativeRichTextPastePolicy.removeOnlyProvenBoundaryNewlines(from: richText, matching: plainText)
            }
            RichTextTextView.normalizePastedFonts(
                in: richText,
                semanticHeadingSizes: htmlData.map { RichTextTextView.semanticHeadingSizes(in: $0) } ?? [:]
            )
            if parent.noteFormatting {
                let markup = sourceHTML
                    ?? htmlData.flatMap { String(data: $0, encoding: .utf8) }
                    ?? plainText.flatMap(NativeRichTextMarkdown.htmlIfMarkdown)
                let styled = RichTextTextView.applyingNoteParagraphFormatting(to: richText, sourceHTML: markup)
                richText.setAttributedString(styled)
            }
            return NativeRichTextDisplayRenderer.applyingTableAppearance(
                to: richText,
                appearance: parent.tableAppearance
            )
        }

        private func plainTextPaste(_ text: String) -> NSAttributedString {
            if parent.noteFormatting,
               let markdownHTML = NativeRichTextMarkdown.htmlIfMarkdown(text) {
                return RichTextTextView.attributed(from: markdownHTML, noteFormatting: true)
            }
            let plain = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize),
                    .foregroundColor: UIColor.label
                ]
            )
            return parent.noteFormatting
                ? RichTextTextView.applyingNoteParagraphFormatting(to: plain, sourceHTML: nil)
                : plain
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
                richText.setAttributedString(RichTextTextView.applyingNoteParagraphFormatting(to: richText, sourceHTML: html))
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
            case .quote: toggleQuote(view: view, range: range)
            case .border: toggleBorder(view: view, range: range)
            case .code: toggleCode(view: view, range: range)
            case .indent: changeIndent(18, view: view, range: range)
            case .outdent: changeIndent(-18, view: view, range: range)
            case let .bullets(style): toggleParagraphPrefixes(style.prefix, view: view, range: range); restoreSelection = false
            case .numbers: numberParagraphs(view: view, range: range); restoreSelection = false
            case .todos: toggleParagraphPrefixes("☐ ", view: view, range: range); restoreSelection = false
            case .divider: insertDivider(view: view, range: range); restoreSelection = false
            case let .table(table):
                tableResult = upsertTable(table, view: view, target: tableEditTarget)
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
                if case .success = imageResult {
                    _ = publishNow(view)
                    connectedSession?.setMediaOperationInProgress(false)
                }
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
            openTableEditor(tableAttachment, range: characterRange)
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handleNativeTableTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view = recognizer.view as? UITextView,
                  let match = tableAttachment(at: recognizer.location(in: view), in: view) else { return }
            openTableEditor(match.attachment, range: match.range)
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
                let attachmentRect = view.firstRect(for: textRange)
                if attachmentRect.insetBy(dx: -3, dy: -3).contains(point) {
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
                style.headIndent = max(0, style.headIndent + delta); style.firstLineHeadIndent = max(0, style.firstLineHeadIndent + delta)
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
            if parent.noteFormatting {
                toggleNoteQuote(view: view, range: range, paragraphRange: paragraphRange)
                return
            }
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

        private func toggleNoteQuote(view: UITextView, range: NSRange, paragraphRange: NSRange) {
            let location = min(paragraphRange.location, max(0, view.attributedText.length - 1))
            let attributes = view.attributedText.length > 0
                ? view.attributedText.attributes(at: location, effectiveRange: nil)
                : view.typingAttributes
            let isQuoted = NativeRichTextNoteFormatting.isQuoted(attributes)
            let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent = isQuoted ? 0 : 12
            style.firstLineHeadIndent = isQuoted ? 0 : 12
            style.paragraphSpacingBefore = 0
            style.paragraphSpacing = isQuoted ? 0 : 5
            if paragraphRange.length == 0 {
                var typing = view.typingAttributes
                typing[.paragraphStyle] = style
                if isQuoted { typing.removeValue(forKey: NativeRichTextNoteFormatting.quoteKey) }
                else { typing[NativeRichTextNoteFormatting.quoteKey] = true }
                view.typingAttributes = typing
            } else {
                view.textStorage.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
                if isQuoted {
                    view.textStorage.removeAttribute(NativeRichTextNoteFormatting.quoteKey, range: paragraphRange)
                } else {
                    view.textStorage.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
                }
            }
            if isQuoted {
                var legacyQuoteColorRanges: [NSRange] = []
                view.textStorage.enumerateAttribute(.foregroundColor, in: paragraphRange) { value, subrange, _ in
                    if (value as? UIColor)?.isEqual(UIColor.secondaryLabel) == true {
                        legacyQuoteColorRanges.append(subrange)
                    }
                }
                for subrange in legacyQuoteColorRanges {
                    view.textStorage.removeAttribute(.foregroundColor, range: subrange)
                }
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
                      replaceAttributed(replacement, in: existingRange, view: view) else {
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
                replacement.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]))
                guard replaceAttributed(replacement, in: target.range, view: view) else {
                    return .failure(.tableTargetChanged)
                }
                updateNativeTableWidths(in: view, force: true)
                parent.tableEditTarget = RichTextTableEditTarget(
                    documentID: target.documentID,
                    sessionID: target.sessionID,
                    attachmentInstanceID: attachment.instanceID,
                    range: NSRange(location: target.range.location, length: 1),
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
            guard view.attributedText.length > 0 else { return nil }
            for location in [range.location, range.location - 1] where location >= 0 && location < view.attributedText.length {
                var effective = NSRange()
                if let attachment = view.attributedText.attribute(.attachment, at: location, effectiveRange: &effective) as? NativeTableAttachment {
                    return (attachment, effective)
                }
            }
            return nil
        }

        private func formulaAttachment(near range: NSRange, view: UITextView) -> (attachment: NativeFormulaAttachment, range: NSRange)? {
            guard view.attributedText.length > 0 else { return nil }
            for location in [range.location, range.location - 1] where location >= 0 && location < view.attributedText.length {
                var effective = NSRange()
                if let attachment = view.attributedText.attribute(.attachment, at: location, effectiveRange: &effective) as? NativeFormulaAttachment {
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
                    documentRevision: documentRevision
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
                documentRevision: documentRevision
            )
            cachedSnapshot = snapshot
            if parent.noteFormatting, parent.editorSession != nil {
                LibraryPerformanceLog.markIfSlow("note.editor.rich-text-snapshot", since: snapshotStart)
            }
            return snapshot
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
                    if !self.parent.noteFormatting || self.updateCachedNoteHeightFromTextKit(view) {
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
            let heading: RichTextHeading = if everyAttribute(in: range, view: view, predicate: { (($0[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize) >= 20 }) {
                .heading1
            } else if everyAttribute(in: range, view: view, predicate: {
                let size = ($0[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize
                return size >= 17 && size < 20
            }) {
                .heading2
            } else {
                .body
            }
            let state = RichTextSelectionState(
                isBold: everyAttribute(in: range, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true },
                isItalic: everyAttribute(in: range, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true },
                isUnderlined: everyAttribute(in: range, view: view) { ($0[.underlineStyle] as? Int ?? 0) != 0 },
                isStruckThrough: everyAttribute(in: range, view: view) { ($0[.strikethroughStyle] as? Int ?? 0) != 0 },
                isHighlighted: everyAttribute(in: range, view: view) { $0[.backgroundColor] != nil },
                isParagraphHighlighted: paragraph.map { _ in
                    let paragraphRange = (view.text as NSString).paragraphRange(for: range)
                    return paragraphRange.length > 0 && self.everyAttribute(in: paragraphRange, view: view) { $0[.backgroundColor] != nil }
                } ?? false,
                isQuoted: everyAttribute(in: range, view: view) {
                    NativeRichTextNoteFormatting.isQuoted($0) || (($0[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0) >= 22
                },
                isBordered: abs((paragraph?.headIndent ?? 0) - 10) < 0.5 && abs((paragraph?.tailIndent ?? 0) + 10) < 0.5,
                isBulleted: RichTextBulletStyle.allCases.contains { currentLine.hasPrefix($0.prefix) },
                isNumbered: currentLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil,
                isCode: everyAttribute(in: range, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true },
                heading: heading,
                foreground: RichTextColor.allCases.first(where: { foreground?.isEqual($0.uiColor) == true }) ?? .primary,
                canUndo: view.undoManager?.canUndo == true,
                canRedo: view.undoManager?.canRedo == true
            )
            guard state != parent.selectionState, state != lastQueuedSelectionState else { return }
            lastQueuedSelectionState = state
            DispatchQueue.main.async {
                guard self.parent.selectionState != state else { return }
                self.parent.selectionState = state
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
        let source = !noteSource.contains("<") ? (NativeRichTextMarkdown.htmlIfMarkdown(noteSource) ?? noteSource) : noteSource
        if source.contains("<"), let data = source.data(using: .utf8), let result = try? NSMutableAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil
        ) {
            restoreNativeTables(in: result)
            normalizeFonts(in: result, semanticHeadingSizes: semanticHeadingSizes(in: data))
            return noteFormatting
                ? applyingNoteParagraphFormatting(to: result, sourceHTML: source, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
                : result
        }
        let plain = NSAttributedString(string: noteSource, attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)])
        return noteFormatting
            ? applyingNoteParagraphFormatting(to: plain, sourceHTML: source, cleanLegacyInjectedSpacing: cleanLegacyInjectedSpacing)
            : plain
    }

    fileprivate static func applyingNoteParagraphFormatting(
        to source: NSAttributedString,
        sourceHTML: String?,
        cleanLegacyInjectedSpacing: Bool = false
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
            style.headIndent = 12
            style.firstLineHeadIndent = 12
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            result.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
        }

        if let sourceHTML,
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
                fontSize: Double(fontSize)
            ))
            paragraphQuotes.append(quoted)
            paragraphContent.append(!content.isEmpty)
        }
        let normalizedStyles = cleanLegacyInjectedSpacing
            ? NativeRichTextNoteParagraphHTMLPolicy.removingLegacyInjectedSpacing(
                from: paragraphStyles,
                isQuoted: paragraphQuotes,
                hasContent: paragraphContent
            )
            : paragraphStyles
        for index in paragraphRanges.indices {
            let paragraphRange = paragraphRanges[index]
            guard paragraphRange.location < result.length else { continue }
            let quoted = paragraphQuotes[index]
            let cleaned = normalizedStyles[index]
            let style = (result.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.paragraphSpacingBefore = CGFloat(cleaned.spacingBefore)
            style.paragraphSpacing = CGFloat(cleaned.spacingAfter)
            style.lineSpacing = CGFloat(cleaned.lineSpacing)
            if quoted {
                style.headIndent = 12
                style.firstLineHeadIndent = 12
                style.paragraphSpacing = max(style.paragraphSpacing, 5)
                result.addAttribute(NativeRichTextNoteFormatting.quoteKey, value: true, range: paragraphRange)
            } else {
                result.removeAttribute(NativeRichTextNoteFormatting.quoteKey, range: paragraphRange)
            }
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
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

    private static func enumerateParagraphRanges(
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
        return String(data: data, encoding: .utf8) ?? value.string
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
            let quoted = NativeRichTextNoteFormatting.isQuoted(value, at: paragraphStart)
            let paragraphAttributes = value.attributes(at: paragraphStart, effectiveRange: nil)
            let paragraphStyle = paragraphAttributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            let paragraphFontSize = (paragraphAttributes[.font] as? UIFont)?.pointSize ?? RichTextMetrics.bodySize
            let headingLevel = noteHeadingLevel(in: value, range: contentRange)
            var body: String
            if contentRange.length == 0 {
                body = "<p><br></p>"
            } else {
                let fragment = value.attributedSubstring(from: contentRange)
                let inner = noteInlineHTML(from: fragment).trimmingCharacters(in: .whitespacesAndNewlines)
                if inner.isEmpty {
                    body = "<p><br></p>"
                } else if let headingLevel {
                    body = "<h\(headingLevel)>\(inner)</h\(headingLevel)>"
                } else {
                    body = wrappingInParagraphIfNeeded(inner)
                }
            }
            body = NativeRichTextNoteParagraphHTMLPolicy.applying(
                NativeRichTextNoteParagraphHTMLStyle(
                    spacingBefore: Double(paragraphStyle.paragraphSpacingBefore),
                    spacingAfter: Double(paragraphStyle.paragraphSpacing),
                    lineSpacing: Double(paragraphStyle.lineSpacing),
                    fontSize: Double(paragraphFontSize)
                ),
                to: body
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
        fragment.enumerateAttributes(in: NSRange(location: 0, length: fragment.length)) { attributes, range, _ in
            let run = fragment.attributedSubstring(from: range)
            let exported: String
            if let data = try? run.data(
                from: NSRange(location: 0, length: run.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            ), let html = String(data: data, encoding: .utf8) {
                exported = htmlBody(from: html).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                exported = escapeHTML(run.string)
            }

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
                link: link
            )
            output += NativeRichTextNoteInlineHTMLPolicy.applying(style, to: exported)
        }
        return output
    }

    private static func htmlBody(from html: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)<body\b[^>]*>(.*?)</body\s*>"#) else { return html }
        let full = html as NSString
        let match = expression.firstMatch(in: html, range: NSRange(location: 0, length: full.length))
        guard let match, match.numberOfRanges > 1 else { return html }
        return full.substring(with: match.range(at: 1))
    }

    private static func wrappingInParagraphIfNeeded(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(pattern: #"(?is)^<(p|div|h[1-6]|pre|ul|ol|blockquote|table)\b"#),
              expression.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) == nil else {
            return trimmed
        }
        return "<p>\(trimmed)</p>"
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
                  let table = try? JSONDecoder().decode(RichTextTable.self, from: data) else { continue }
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
    let table: RichTextTable
    let instanceID: UUID
    let appearance: NativeRichTextTableAppearance
    private let originalMarker: String?
    private(set) var displayWidth: CGFloat

    init(
        table: RichTextTable,
        marker: String? = nil,
        instanceID: UUID = UUID(),
        displayWidth: CGFloat = 440,
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
        let layout = Self.layout(normalizedTable, width: self.displayWidth, appearance: appearance)
        image = Self.render(normalizedTable, layout: layout, width: self.displayWidth, appearance: appearance)
        let height = layout.rowHeights.reduce(0, +)
        bounds = CGRect(x: 0, y: -4, width: self.displayWidth, height: height)
    }

    required init?(coder: NSCoder) { nil }

    func copy(with zone: NSZone? = nil) -> Any {
        NativeTableAttachment(table: table, marker: originalMarker, instanceID: instanceID, displayWidth: displayWidth, appearance: appearance)
    }

    func replacingAppearance(_ appearance: NativeRichTextTableAppearance) -> NativeTableAttachment {
        NativeTableAttachment(table: table, marker: originalMarker, instanceID: instanceID, displayWidth: displayWidth, appearance: appearance)
    }

    @discardableResult
    func updateDisplayWidth(_ width: CGFloat) -> Bool {
        let updatedWidth = max(80, floor(width))
        guard updatedWidth.isFinite, abs(updatedWidth - displayWidth) > 0.5 else { return false }
        displayWidth = updatedWidth
        let layout = Self.layout(table, width: displayWidth, appearance: appearance)
        image = Self.render(table, layout: layout, width: displayWidth, appearance: appearance)
        bounds = CGRect(x: 0, y: -4, width: displayWidth, height: layout.rowHeights.reduce(0, +))
        return true
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
                    + (appearance == .libraryContent ? 14 : 18)
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
                return appearance == .libraryContent
                    ? max(CGFloat(34), contentHeight + 14)
                    : max(CGFloat(20), contentHeight)
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
            let libraryStyle = appearance == .libraryContent
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
                context.cgContext.setStrokeColor(UIColor(red: 229.0 / 255.0, green: 229.0 / 255.0, blue: 234.0 / 255.0, alpha: 1).cgColor)
                context.cgContext.setLineWidth(1 / UIScreen.main.scale)
                for y in rowOrigins.dropFirst().dropLast() {
                    let alignedY = y + 0.5 / UIScreen.main.scale
                    context.cgContext.move(to: CGPoint(x: 0, y: alignedY))
                    context.cgContext.addLine(to: CGPoint(x: width, y: alignedY))
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
            }
            context.cgContext.strokePath()
            for (rowIndex, row) in table.cells.enumerated() {
                for (columnIndex, _) in row.enumerated() {
                    guard columnIndex < layout.columnWidths.count, rowIndex < layout.rowHeights.count else { continue }
                    let bottomInset: CGFloat = appearance == .libraryContent ? 7 : 3
                    let rect = CGRect(
                        x: columnOrigins[columnIndex] + 7,
                        y: rowOrigins[rowIndex] + 7,
                        width: max(1, layout.columnWidths[columnIndex] - 14),
                        height: max(20, layout.rowHeights[rowIndex] - 7 - bottomInset)
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
        let font = UIFont.systemFont(ofSize: 12, weight: isHeader ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let ink = foreground ?? (appearance == .libraryContent
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
            value.addAttribute(.font, value: UIFont.systemFont(ofSize: 12, weight: .bold), range: NSRange(location: range.location, length: range.length))
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
    let onSave: (RichTextTable, @escaping (Result<Void, NativeRichTextEditorError>) -> Void) -> Void

    init(
        initial: RichTextTable,
        onSave: @escaping (RichTextTable, @escaping (Result<Void, NativeRichTextEditorError>) -> Void) -> Void
    ) {
        _table = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
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

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(get: { table.cells[row][column] }, set: { table.cells[row][column] = $0 })
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
