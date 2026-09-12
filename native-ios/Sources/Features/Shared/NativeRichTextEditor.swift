import PhotosUI
import SwiftUI
import UIKit

enum RichTextToolbarMode { case full, compact, minimal }

private enum RichTextMetrics {
    static let bodySize: CGFloat = 16
    static let heading2Size: CGFloat = 18
    static let heading1Size: CGFloat = 21
}

private enum RichTextCommandKind: Equatable {
    case bold, italic, underline, strike, indent, outdent, bullets, numbers, todos, divider
    case heading(RichTextHeading)
    case foreground(RichTextColor)
    case highlight
    case quote
    case code
    case table(RichTextTable)
    case image(String)
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

private struct RichTextTable: Codable, Equatable, Identifiable {
    var id = UUID()
    var cells: [[String]] = Array(repeating: Array(repeating: "", count: 2), count: 2)

    var rowCount: Int { cells.count }
    var columnCount: Int { cells.first?.count ?? 0 }
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
    case main, format, paragraph, insert
}

private struct RichTextSelectionState: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStruckThrough = false
    var isHighlighted = false
    var isQuoted = false
    var isCode = false
    var heading: RichTextHeading = .body
    var foreground: RichTextColor = .primary
    var canUndo = false
    var canRedo = false
}

private struct RichTextCommand: Equatable {
    let id = UUID()
    let kind: RichTextCommandKind
}

struct NativeRichTextEditor: View {
    @Binding var html: String
    let minHeight: CGFloat
    var mode: RichTextToolbarMode = .full
    var documentStyle = false
    var focusOnAppear = false
    var internalLinks: [RichTextInternalLink] = []
    var onOpenInternalLink: ((RichTextInternalLink) -> Void)?
    @State private var command: RichTextCommand?
    @State private var showLinkPrompt = false
    @State private var linkTarget = "https://"
    @State private var selectedTable: RichTextTable?
    @State private var tableEditor: RichTextTable?
    @State private var selectedFormula: RichTextFormula?
    @State private var formulaEditor: RichTextFormula?
    @State private var photoItem: PhotosPickerItem?
    @State private var internalLinkPicker: InternalLinkPickerRequest?
    @State private var isEditing = false
    @State private var toolbarPage: RichTextToolbarPage = .main
    @State private var selectionState = RichTextSelectionState()

    var body: some View {
        VStack(spacing: 0) {
            RichTextTextView(
                html: $html,
                command: $command,
                selectedTable: $selectedTable,
                selectedFormula: $selectedFormula,
                isEditing: $isEditing,
                selectionState: $selectionState,
                internalLinks: internalLinks,
                onOpenInternalLink: onOpenInternalLink,
                keyboardAccessory: AnyView(keyboardToolbar),
                keyboardAccessoryHeight: keyboardAccessoryHeight,
                growsWithContent: documentStyle,
                focusOnAppear: focusOnAppear
            )
                .frame(minHeight: minHeight)
                .padding(.horizontal, documentStyle ? 0 : 5)
        }
        .background(Color.primary.opacity(documentStyle ? 0 : 0.035), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius).stroke(Color.primary.opacity(documentStyle ? 0 : 0.07), lineWidth: 0.7))
        .alert("添加链接", isPresented: $showLinkPrompt) {
            TextField("https://example.com", text: $linkTarget)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("取消", role: .cancel) {}
            Button("添加") {
                let value = linkTarget.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                command = RichTextCommand(kind: .link(value))
                linkTarget = "https://"
            }
        } message: {
            Text("选中文字后添加链接；没有选中文字时会直接插入链接地址。")
        }
        .sheet(item: $tableEditor) { table in
            RichTextTableEditor(initial: table) { updated in
                command = RichTextCommand(kind: .table(updated))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $formulaEditor) { formula in
            DataAnalysisFormulaPicker(initial: formula) { updated in
                command = RichTextCommand(kind: .formula(updated))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $internalLinkPicker) { _ in
            RichTextInternalLinkPicker(links: internalLinks) { link in
                command = RichTextCommand(kind: .internalLink(link))
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.jpegData(compressionQuality: 0.82)
                else { return }
                command = RichTextCommand(kind: .image("data:image/jpeg;base64,\(compressed.base64EncodedString())"))
            }
        }
        .onChange(of: isEditing) { _, active in
            if !active { toolbarPage = .main }
        }
    }

    private var keyboardAccessoryHeight: CGFloat {
        toolbarPage == .insert || toolbarPage == .paragraph ? 250 : 58
    }

    private var keyboardToolbar: some View {
        VStack(spacing: 8) {
            if toolbarPage == .insert {
                insertPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if toolbarPage == .paragraph {
                paragraphPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 2) {
                toolbarStrip
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
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.top, 3)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Color.clear)
        .animation(.easeOut(duration: 0.14), value: toolbarPage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("笔记格式栏")
    }

    @ViewBuilder private var toolbarStrip: some View {
        HStack(spacing: 2) {
            if toolbarPage == .format {
                toolbarButton("chevron.left", label: "返回") { toolbarPage = .main }
                formatButton(.italic, "italic", active: selectionState.isItalic)
                formatButton(.underline, "underline", active: selectionState.isUnderlined)
                formatButton(.strike, "strikethrough", active: selectionState.isStruckThrough)
                formatButton(.highlight, "highlighter", active: selectionState.isHighlighted)
                formatButton(.code, "chevron.left.forwardslash.chevron.right", active: selectionState.isCode)
                toolbarButton("link", label: "链接") { showLinkPrompt = true }
                formatButton(.numbers, "list.number")
                formatButton(.todos, "checklist")
            } else if mode == .full {
                toolbarButton("plus", label: "插入") { togglePage(.insert) }
                toolbarButton("textformat", label: "标题与段落") { togglePage(.paragraph) }
                formatButton(.bold, "bold", active: selectionState.isBold)
                colorMenu
                formatButton(.bullets, "list.bullet")
                formatButton(.undo, "arrow.uturn.backward", disabled: !selectionState.canUndo)
                formatButton(.redo, "arrow.uturn.forward", disabled: !selectionState.canRedo)
                toolbarButton("ellipsis", label: "更多格式") { toolbarPage = .format }
            } else {
                formatButton(.undo, "arrow.uturn.backward", disabled: !selectionState.canUndo)
                formatButton(.redo, "arrow.uturn.forward", disabled: !selectionState.canRedo)
                formatButton(.bold, "bold", active: selectionState.isBold)
                if mode == .compact {
                    formatButton(.bullets, "list.bullet")
                    formatButton(.todos, "checklist")
                }
            }
        }
    }

    private var colorMenu: some View {
        Menu {
            ForEach(RichTextColor.allCases) { color in
                Button {
                    command = RichTextCommand(kind: .foreground(color))
                } label: {
                    if selectionState.foreground == color { Label(color.rawValue, systemImage: "checkmark") }
                    else { Text(color.rawValue) }
                }
            }
        } label: {
            toolbarImage("paintpalette", active: selectionState.foreground != .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("文字颜色")
    }

    private var insertPanel: some View {
        toolbarPanel(title: "插入") {
            LazyVGrid(columns: panelColumns, spacing: 5) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    panelItem("photo", "图片")
                }
                .buttonStyle(.plain)
                panelButton("tablecells", "表格") { tableEditor = selectedTable ?? RichTextTable() }
                panelButton("minus", "分割线") { run(.divider) }
                panelButton("function", "公式") { formulaEditor = selectedFormula ?? RichTextFormula() }
                panelButton("link", "网页链接") { showLinkPrompt = true }
                if !internalLinks.isEmpty {
                    panelButton("link.circle", "关联笔记") { internalLinkPicker = InternalLinkPickerRequest() }
                }
            }
        }
    }

    private var paragraphPanel: some View {
        toolbarPanel(title: "段落") {
            LazyVGrid(columns: panelColumns, spacing: 5) {
                ForEach(RichTextHeading.allCases) { heading in
                    panelButton(heading == .body ? "text.alignleft" : "textformat.size", heading.rawValue, active: selectionState.heading == heading) {
                        run(.heading(heading))
                    }
                }
                panelButton("text.quote", "引用", active: selectionState.isQuoted) { run(.quote) }
                panelButton("list.bullet", "项目列表") { run(.bullets) }
                panelButton("list.number", "编号列表") { run(.numbers) }
                panelButton("checklist", "待办列表") { run(.todos) }
                panelButton("increase.indent", "增加缩进") { run(.indent) }
                panelButton("decrease.indent", "减少缩进") { run(.outdent) }
            }
        }
    }

    private var panelColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)]
    }

    private func toolbarPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { toolbarPage = .main } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                }.buttonStyle(.plain)
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: 570)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }

    private func panelButton(_ image: String, _ title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { panelItem(image, title, active: active) }.buttonStyle(.plain)
    }

    private func panelItem(_ image: String, _ title: String, active: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: image).font(.system(size: 14, weight: .medium)).frame(width: 22)
            Text(title).font(.system(size: 13, weight: .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 37)
        .background(active ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 21).padding(.horizontal, 2)
    }

    private func togglePage(_ page: RichTextToolbarPage) {
        toolbarPage = toolbarPage == page ? .main : page
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

struct NativeRichTextDisplay: UIViewRepresentable {
    let html: String
    var minHeight: CGFloat = 0

    final class Coordinator {
        var lastHTML = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.attributedText = RichTextTextView.attributed(from: html)
        context.coordinator.lastHTML = html
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        view.attributedText = RichTextTextView.attributed(from: html)
        context.coordinator.lastHTML = html
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minHeight, ceil(fitting.height)))
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

private struct RichTextTextView: UIViewRepresentable {
    @Binding var html: String
    @Binding var command: RichTextCommand?
    @Binding var selectedTable: RichTextTable?
    @Binding var selectedFormula: RichTextFormula?
    @Binding var isEditing: Bool
    @Binding var selectionState: RichTextSelectionState
    let internalLinks: [RichTextInternalLink]
    let onOpenInternalLink: ((RichTextInternalLink) -> Void)?
    let keyboardAccessory: AnyView
    let keyboardAccessoryHeight: CGFloat
    var growsWithContent = false
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: RichTextMetrics.bodySize)
        view.adjustsFontForContentSizeCategory = false
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        if growsWithContent {
            view.isScrollEnabled = false
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        view.allowsEditingTextAttributes = true
        view.keyboardDismissMode = .interactive
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.attributedText = Self.attributed(from: html)
        context.coordinator.lastHTML = html
        context.coordinator.installKeyboardAccessory(keyboardAccessory, height: keyboardAccessoryHeight, on: view)
        if focusOnAppear {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard growsWithContent, let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(42, ceil(size.height)))
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateKeyboardAccessory(keyboardAccessory, height: keyboardAccessoryHeight, on: view)
        if context.coordinator.lastHTML != html, !view.isFirstResponder {
            view.attributedText = Self.attributed(from: html)
            context.coordinator.lastHTML = html
        }
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.kind, to: view)
            DispatchQueue.main.async { self.command = nil }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextTextView
        var lastHTML = ""
        var lastCommandID: UUID?
        private var pendingPublish: DispatchWorkItem?
        private var accessoryController: UIHostingController<AnyView>?
        private weak var accessoryContainer: RichTextKeyboardAccessoryView?
        init(parent: RichTextTextView) { self.parent = parent }

        func installKeyboardAccessory(_ content: AnyView, height: CGFloat, on textView: UITextView) {
            let controller = UIHostingController(rootView: content)
            controller.view.backgroundColor = .clear
            let container = RichTextKeyboardAccessoryView(contentView: controller.view, height: height)
            accessoryController = controller
            accessoryContainer = container
            textView.inputAccessoryView = container
        }

        func updateKeyboardAccessory(_ content: AnyView, height: CGFloat, on textView: UITextView) {
            accessoryController?.rootView = content
            if accessoryContainer?.updateHeight(height) == true, textView.isFirstResponder {
                textView.reloadInputViews()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            textView.invalidateIntrinsicContentSize()
            schedulePublish(textView)
            publishSelectionState(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            publishSelectionState(textView)
            DispatchQueue.main.async { self.parent.isEditing = true }
            keepSelectionVisible(in: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            publishNow(textView)
            DispatchQueue.main.async { self.parent.isEditing = false }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let table = tableAttachment(near: textView.selectedRange, view: textView)?.attachment.table
            let formula = formulaAttachment(near: textView.selectedRange, view: textView)?.attachment.formula
            DispatchQueue.main.async {
                self.parent.selectedTable = table
                self.parent.selectedFormula = formula
            }
            publishSelectionState(textView)
            keepSelectionVisible(in: textView)
        }

        private func keepSelectionVisible(in textView: UITextView) {
            guard textView.isFirstResponder else { return }
            let selection = textView.selectedRange
            DispatchQueue.main.async {
                guard selection.location <= textView.attributedText.length else { return }
                textView.layoutIfNeeded()
                textView.scrollRangeToVisible(selection)
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text.count > 1, MarkdownRichTextConverter.isMarkdown(text) {
                let replacement = RichTextTextView.attributed(from: MarkdownRichTextConverter.html(from: text))
                replaceAttributed(replacement, in: range, view: textView)
                return false
            }
            guard text == "\n" else { return true }
            let source = textView.text as NSString
            let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let prefix: String?
            if line.hasPrefix("• ") { prefix = "• " }
            else if line.hasPrefix("☐ ") { prefix = "☐ " }
            else if let match = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression),
                    let number = Int(line[match].dropLast(2)) {
                prefix = "\(number + 1). "
            } else { prefix = nil }
            guard let prefix else { return true }
            let content = line.replacingOccurrences(of: #"^(•|☐|\d+\.)\s"#, with: "", options: .regularExpression)
            if content.isEmpty {
                textView.textStorage.replaceCharacters(in: lineRange, with: "\n")
                textView.selectedRange = NSRange(location: lineRange.location + 1, length: 0)
            } else {
                textView.textStorage.replaceCharacters(in: range, with: "\n" + prefix)
                textView.selectedRange = NSRange(location: range.location + prefix.utf16.count + 1, length: 0)
            }
            textView.invalidateIntrinsicContentSize()
            schedulePublish(textView)
            return false
        }

        private func replaceAttributed(_ replacement: NSAttributedString, in range: NSRange, view: UITextView) {
            let previous = view.attributedText.attributedSubstring(from: range)
            view.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.replaceAttributed(
                    previous,
                    in: NSRange(location: range.location, length: replacement.length),
                    view: view
                )
            }
            view.textStorage.replaceCharacters(in: range, with: replacement)
            view.selectedRange = NSRange(location: range.location + replacement.length, length: 0)
            view.invalidateIntrinsicContentSize()
            schedulePublish(view)
        }

        func apply(_ command: RichTextCommandKind, to view: UITextView) {
            let range = view.selectedRange
            var restoreSelection = true
            switch command {
            case .bold: toggleFontTrait(.traitBold, view: view, range: range)
            case .italic: toggleFontTrait(.traitItalic, view: view, range: range)
            case .underline: toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, view: view, range: range)
            case .strike: toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, view: view, range: range)
            case let .heading(level): applyHeading(level, view: view, range: range)
            case let .foreground(color): applyAttribute(.foregroundColor, value: color.uiColor, view: view, range: range)
            case .highlight: toggleAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), view: view, range: range)
            case .quote: toggleQuote(view: view, range: range)
            case .code: toggleCode(view: view, range: range)
            case .indent: changeIndent(18, view: view, range: range)
            case .outdent: changeIndent(-18, view: view, range: range)
            case .bullets: prefixParagraphs("• ", view: view, range: range)
            case .numbers: numberParagraphs(view: view, range: range)
            case .todos: prefixParagraphs("☐ ", view: view, range: range)
            case .divider: insertDivider(view: view, range: range); restoreSelection = false
            case let .table(table): upsertTable(table, view: view, range: range); restoreSelection = false
            case let .image(dataURL): insertImage(dataURL, view: view, range: range); restoreSelection = false
            case let .formula(formula): upsertFormula(formula, view: view, range: range); restoreSelection = false
            case let .internalLink(link): insertInternalLink(link, view: view, range: range); restoreSelection = false
            case let .link(target): addLink(target, view: view, range: range); restoreSelection = false
            case .undo: view.undoManager?.undo(); restoreSelection = false
            case .redo: view.undoManager?.redo(); restoreSelection = false
            }
            if restoreSelection { view.selectedRange = range }
            view.invalidateIntrinsicContentSize()
            schedulePublish(view)
            publishSelectionState(view)
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

        private func prefixParagraphs(_ prefix: String, view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let lines = (view.text as NSString).substring(with: paragraphRange).split(separator: "\n", omittingEmptySubsequences: false)
            let replacement = lines.map { line in String(line).hasPrefix(prefix) ? String(line).dropFirst(prefix.count).description : prefix + line }.joined(separator: "\n")
            view.textStorage.replaceCharacters(in: paragraphRange, with: replacement)
        }

        private func numberParagraphs(view: UITextView, range: NSRange) {
            let paragraphRange = (view.text as NSString).paragraphRange(for: range)
            let lines = (view.text as NSString).substring(with: paragraphRange).split(separator: "\n", omittingEmptySubsequences: false)
            let replacement = lines.enumerated().map { index, line in
                let raw = String(line).replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                return "\(index + 1). \(raw)"
            }.joined(separator: "\n")
            view.textStorage.replaceCharacters(in: paragraphRange, with: replacement)
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

        private func upsertTable(_ table: RichTextTable, view: UITextView, range: NSRange) {
            let attachment = NativeTableAttachment(table: table)
            let replacement = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            if let existing = tableAttachment(near: range, view: view), existing.attachment.table.id == table.id {
                replaceAttributed(replacement, in: existing.range, view: view)
            } else {
                replacement.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]))
                replaceAttributed(replacement, in: range, view: view)
            }
            parent.selectedTable = table
        }

        private func insertImage(_ dataURL: String, view: UITextView, range: NSRange) {
            guard let attachment = NativeImageAttachment(dataURL: dataURL) else { return }
            let replacement = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            replacement.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)]))
            replaceAttributed(replacement, in: range, view: view)
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
            pendingPublish?.cancel()
            let work = DispatchWorkItem { [weak self, weak view] in
                guard let self, let view else { return }
                self.publishNow(view)
            }
            pendingPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }

        private func publishNow(_ view: UITextView) {
            pendingPublish?.cancel()
            pendingPublish = nil
            view.invalidateIntrinsicContentSize()
            let html = RichTextTextView.html(from: view.attributedText)
            guard html != lastHTML else { return }
            lastHTML = html; parent.html = html
        }

        private func publishSelectionState(_ view: UITextView) {
            let range = view.selectedRange
            let attributes = attributesForCaretOrSelection(range, view: view)
            let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
            let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
            let foreground = attributes[.foregroundColor] as? UIColor
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
                isQuoted: everyAttribute(in: range, view: view) { (($0[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0) >= 22 },
                isCode: everyAttribute(in: range, view: view) { ($0[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true },
                heading: heading,
                foreground: RichTextColor.allCases.first(where: { foreground?.isEqual($0.uiColor) == true }) ?? .primary,
                canUndo: view.undoManager?.canUndo == true,
                canRedo: view.undoManager?.canRedo == true
            )
            guard state != parent.selectionState else { return }
            DispatchQueue.main.async { self.parent.selectionState = state }
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

    fileprivate static func attributed(from value: String) -> NSAttributedString {
        let source = !value.contains("<") && MarkdownRichTextConverter.isMarkdown(value) ? MarkdownRichTextConverter.html(from: value) : value
        if source.contains("<"), let data = source.data(using: .utf8), let result = try? NSMutableAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil
        ) {
            restoreNativeTables(in: result)
            normalizeFonts(in: result)
            return result
        }
        return NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: RichTextMetrics.bodySize)])
    }

    private static func html(from value: NSAttributedString) -> String {
        let serializable = NSMutableAttributedString(attributedString: value)
        var replacements: [(NSRange, String)] = []
        serializable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: serializable.length)) { attribute, range, _ in
            if let table = attribute as? NativeTableAttachment, let marker = table.marker { replacements.append((range, marker)) }
            else if let image = attribute as? NativeImageAttachment { replacements.append((range, image.marker)) }
            else if let formula = attribute as? NativeFormulaAttachment, let marker = formula.marker { replacements.append((range, marker)) }
        }
        for (range, marker) in replacements.reversed() { serializable.replaceCharacters(in: range, with: marker) }
        guard serializable.length > 0, let data = try? serializable.data(from: NSRange(location: 0, length: serializable.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return "" }
        return String(data: data, encoding: .utf8) ?? value.string
    }

    private static func restoreNativeTables(in value: NSMutableAttributedString) {
        let pattern = #"\[\[NATIVE_TABLE:([A-Za-z0-9+/=]+)\]\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let text = value.string as NSString
        for match in expression.matches(in: value.string, range: NSRange(location: 0, length: text.length)).reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let encoded = text.substring(with: match.range(at: 1))
            guard let data = Data(base64Encoded: encoded), let table = try? JSONDecoder().decode(RichTextTable.self, from: data) else { continue }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: NativeTableAttachment(table: table)))
        }
        let imagePattern = #"\[\[NATIVE_IMAGE:([A-Za-z0-9+/=]+)\]\]"#
        guard let imageExpression = try? NSRegularExpression(pattern: imagePattern) else { return }
        let updatedText = value.string as NSString
        for match in imageExpression.matches(in: value.string, range: NSRange(location: 0, length: updatedText.length)).reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let encoded = updatedText.substring(with: match.range(at: 1))
            guard let data = Data(base64Encoded: encoded), let dataURL = String(data: data, encoding: .utf8), let attachment = NativeImageAttachment(dataURL: dataURL) else { continue }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: attachment))
        }
        let formulaPattern = #"\[\[NATIVE_FORMULA:([A-Za-z0-9+/=]+)\]\]"#
        guard let formulaExpression = try? NSRegularExpression(pattern: formulaPattern) else { return }
        let formulaText = value.string as NSString
        for match in formulaExpression.matches(in: value.string, range: NSRange(location: 0, length: formulaText.length)).reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let encoded = formulaText.substring(with: match.range(at: 1))
            guard let data = Data(base64Encoded: encoded), let formula = try? JSONDecoder().decode(RichTextFormula.self, from: data) else { continue }
            value.replaceCharacters(in: match.range, with: NSAttributedString(attachment: NativeFormulaAttachment(formula: formula)))
        }
    }

    private static func normalizeFonts(in value: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(.font, in: fullRange) { attribute, range, _ in
            let source = attribute as? UIFont ?? .systemFont(ofSize: RichTextMetrics.bodySize)
            let size = source.pointSize <= RichTextMetrics.bodySize ? RichTextMetrics.bodySize : source.pointSize
            let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(source.fontDescriptor.symbolicTraits)
                ?? UIFont.systemFont(ofSize: size).fontDescriptor
            value.addAttribute(.font, value: UIFont(descriptor: descriptor, size: size), range: range)
        }
    }
}

private enum MarkdownRichTextConverter {
    static func isMarkdown(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if value.contains("\n") { return true }
        let patterns = [#"^#{1,4}\s"#, #"^[-*]\s"#, #"^\d+\.\s"#, #"^>\s?"#, #"^```"#, #"^---+$"#, #"\*\*.+\*\*"#, #"~~.+~~"#, #"`[^`]+`"#, #"\[.+\]\(.+\)"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    static func html(from markdown: String) -> String {
        var output: [String] = []
        var codeLines: [String] = []
        var inCode = false
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines = []
                }
                inCode.toggle()
                continue
            }
            if inCode { codeLines.append(rawLine); continue }
            if trimmed.isEmpty { output.append("<p><br></p>"); continue }
            if trimmed == "---" { output.append("<p style=\"color:#999;font-size:10px\">────────────────</p>"); continue }
            if let heading = trimmed.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                let level = min(2, trimmed[heading].filter { $0 == "#" }.count)
                output.append("<h\(level)>\(inline(String(trimmed[heading.upperBound...])))</h\(level)>")
                continue
            }
            if let item = trimmed.range(of: #"^[-*]\s+\[[ xX]\]\s+"#, options: .regularExpression) {
                let checked = trimmed[item].lowercased().contains("[x]")
                output.append("<p>\(checked ? "☑" : "☐") \(inline(String(trimmed[item.upperBound...])))</p>")
                continue
            }
            if let item = trimmed.range(of: #"^[-*]\s+"#, options: .regularExpression) {
                output.append("<p>• \(inline(String(trimmed[item.upperBound...])))</p>")
                continue
            }
            if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                output.append("<p>\(inline(trimmed))</p>")
                continue
            }
            if let quote = trimmed.range(of: #"^>\s?"#, options: .regularExpression) {
                output.append("<blockquote>\(inline(String(trimmed[quote.upperBound...])))</blockquote>")
                continue
            }
            output.append("<p>\(inline(rawLine))</p>")
        }
        if inCode { output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>") }
        return output.joined()
    }

    private static func inline(_ value: String) -> String {
        var result = escape(value)
        let replacements = [
            (#"\[([^\]]+)\]\(([^)]+)\)"#, #"<a href="$2">$1</a>"#),
            (#"\*\*(.+?)\*\*"#, #"<strong>$1</strong>"#),
            (#"~~(.+?)~~"#, #"<del>$1</del>"#),
            (#"`([^`]+)`"#, #"<code>$1</code>"#),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, #"<em>$1</em>"#)
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class NativeTableAttachment: NSTextAttachment {
    let table: RichTextTable

    init(table: RichTextTable) {
        self.table = table
        super.init(data: nil, ofType: "com.kaogong.native-table")
        image = Self.render(table)
        let height = CGFloat(max(1, table.rowCount)) * 34
        bounds = CGRect(x: 0, y: -4, width: 440, height: height)
    }

    required init?(coder: NSCoder) { nil }

    var marker: String? {
        guard let data = try? JSONEncoder().encode(table) else { return nil }
        return "[[NATIVE_TABLE:\(data.base64EncodedString())]]"
    }

    private static func render(_ table: RichTextTable) -> UIImage {
        let width: CGFloat = 440
        let rowHeight: CGFloat = 34
        let height = CGFloat(max(1, table.rowCount)) * rowHeight
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.separator.setStroke()
            context.cgContext.setLineWidth(1)
            let columns = max(1, table.columnCount)
            let columnWidth = width / CGFloat(columns)
            for row in 0...table.rowCount {
                let y = CGFloat(row) * rowHeight
                context.cgContext.move(to: CGPoint(x: 0, y: y)); context.cgContext.addLine(to: CGPoint(x: width, y: y))
            }
            for column in 0...columns {
                let x = CGFloat(column) * columnWidth
                context.cgContext.move(to: CGPoint(x: x, y: 0)); context.cgContext.addLine(to: CGPoint(x: x, y: height))
            }
            context.cgContext.strokePath()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.label]
            for (rowIndex, row) in table.cells.enumerated() {
                for (columnIndex, cell) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(columnIndex) * columnWidth + 7, y: CGFloat(rowIndex) * rowHeight + 8, width: columnWidth - 14, height: rowHeight - 10)
                    (cell as NSString).draw(in: rect, withAttributes: attributes)
                }
            }
        }
    }
}

private final class NativeImageAttachment: NSTextAttachment {
    let dataURL: String

    init?(dataURL: String) {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let source = UIImage(data: data)
        else { return nil }
        self.dataURL = dataURL
        super.init(data: nil, ofType: "com.kaogong.native-image")
        image = source
        let maxWidth: CGFloat = 420
        let scale = min(1, maxWidth / max(1, source.size.width))
        bounds = CGRect(x: 0, y: -4, width: source.size.width * scale, height: source.size.height * scale)
    }

    required init?(coder: NSCoder) { nil }

    var marker: String {
        "[[NATIVE_IMAGE:\(Data(dataURL.utf8).base64EncodedString())]]"
    }
}

private final class NativeFormulaAttachment: NSTextAttachment {
    let formula: RichTextFormula

    init(formula: RichTextFormula) {
        self.formula = formula
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
    let onSave: (RichTextTable) -> Void

    init(initial: RichTextTable, onSave: @escaping (RichTextTable) -> Void) {
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
                    Button("保存") { onSave(table); dismiss() }
                        .buttonStyle(NativePrimaryButtonStyle())
                        .frame(maxWidth: 210)
                }
                .padding(14)
                .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(get: { table.cells[row][column] }, set: { table.cells[row][column] = $0 })
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
