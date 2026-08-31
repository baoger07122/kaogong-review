import SwiftUI
import UIKit

enum RichTextToolbarMode { case full, compact }

private enum RichTextCommandKind: Equatable {
    case bold, italic, underline, strike, indent, outdent, bullets, numbers, todos, divider
    case heading(RichTextHeading)
    case foreground(RichTextColor)
    case highlight
    case quote
    case code
    case link(String)
    case undo, redo
}

private enum RichTextHeading: String, CaseIterable, Identifiable {
    case body = "正文", heading1 = "一级标题", heading2 = "二级标题"
    var id: String { rawValue }
    var size: CGFloat { self == .heading1 ? 18 : self == .heading2 ? 16 : 13 }
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

private struct RichTextCommand: Equatable {
    let id = UUID()
    let kind: RichTextCommandKind
}

struct NativeRichTextEditor: View {
    @Binding var html: String
    let minHeight: CGFloat
    var mode: RichTextToolbarMode = .full
    @State private var command: RichTextCommand?
    @State private var showLinkPrompt = false
    @State private var linkTarget = "https://"

    var body: some View {
        VStack(spacing: 0) {
            RichTextTextView(html: $html, command: $command)
                .frame(minHeight: minHeight)
                .padding(.horizontal, 5)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if mode == .full {
                        Menu {
                            ForEach(RichTextHeading.allCases) { heading in
                                Button(heading.rawValue) { command = RichTextCommand(kind: .heading(heading)) }
                            }
                        } label: { toolbarImage("textformat.size") }
                        Menu {
                            ForEach(RichTextColor.allCases) { color in
                                Button(color.rawValue) { command = RichTextCommand(kind: .foreground(color)) }
                            }
                        } label: { toolbarImage("paintpalette") }
                        formatButton(.highlight, "highlighter")
                    }
                    formatButton(.bold, "bold")
                    if mode == .full {
                        formatButton(.italic, "italic")
                        formatButton(.underline, "underline")
                        formatButton(.strike, "strikethrough")
                        formatButton(.quote, "text.quote")
                        formatButton(.code, "chevron.left.forwardslash.chevron.right")
                        formatButton(.divider, "minus")
                    }
                    formatButton(.outdent, "decrease.indent")
                    formatButton(.indent, "increase.indent")
                    formatButton(.bullets, "list.bullet")
                    formatButton(.numbers, "list.number")
                    if mode == .full { formatButton(.todos, "checklist") }
                    if mode == .full {
                        Button { showLinkPrompt = true } label: {
                            toolbarImage("link.badge.plus")
                        }
                        .buttonStyle(.plain)
                        formatButton(.undo, "arrow.uturn.backward")
                        formatButton(.redo, "arrow.uturn.forward")
                    }
                }.padding(6)
            }
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius).stroke(Color.primary.opacity(0.07), lineWidth: 0.7))
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
    }

    private func formatButton(_ kind: RichTextCommandKind, _ image: String) -> some View {
        Button { command = RichTextCommand(kind: kind) } label: {
            toolbarImage(image)
        }.buttonStyle(.plain)
    }

    private func toolbarImage(_ image: String) -> some View {
        Image(systemName: image).font(.system(size: 13, weight: .semibold)).frame(width: 31, height: 29)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RichTextTextView: UIViewRepresentable {
    @Binding var html: String
    @Binding var command: RichTextCommand?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 13)
        view.adjustsFontForContentSizeCategory = false
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        view.allowsEditingTextAttributes = true
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.attributedText = Self.attributed(from: html)
        context.coordinator.lastHTML = html
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
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
        init(parent: RichTextTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) { publish(textView) }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
            publish(textView)
            return false
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
            case let .link(target): addLink(target, view: view, range: range); restoreSelection = false
            case .undo: view.undoManager?.undo(); restoreSelection = false
            case .redo: view.undoManager?.redo(); restoreSelection = false
            }
            if restoreSelection { view.selectedRange = range }
            publish(view)
        }

        private func addLink(_ target: String, view: UITextView, range: NSRange) {
            guard let url = URL(string: target) else { return }
            if range.length == 0 {
                let insertion = NSAttributedString(
                    string: target,
                    attributes: [.link: url, .font: UIFont.systemFont(ofSize: 13)]
                )
                view.textStorage.insert(insertion, at: range.location)
                view.selectedRange = NSRange(location: range.location + insertion.length, length: 0)
            } else {
                view.textStorage.addAttribute(.link, value: url, range: range)
            }
        }

        private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, view: UITextView, range: NSRange) {
            let base = font(at: range.location, view: view)
            let hasTrait = base.fontDescriptor.symbolicTraits.contains(trait)
            var traits = base.fontDescriptor.symbolicTraits
            if hasTrait { traits.remove(trait) } else { traits.insert(trait) }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
            applyAttribute(.font, value: UIFont(descriptor: descriptor, size: base.pointSize), view: view, range: range)
        }

        private func toggleAttribute(_ key: NSAttributedString.Key, value: Any, view: UITextView, range: NSRange) {
            let hasValue = range.length > 0 && view.attributedText.attribute(key, at: range.location, effectiveRange: nil) != nil
            if range.length == 0 {
                var attributes = view.typingAttributes
                if attributes[key] == nil { attributes[key] = value } else { attributes.removeValue(forKey: key) }
                view.typingAttributes = attributes
            } else if hasValue { view.textStorage.removeAttribute(key, range: range) }
            else { view.textStorage.addAttribute(key, value: value, range: range) }
        }

        private func applyAttribute(_ key: NSAttributedString.Key, value: Any, view: UITextView, range: NSRange) {
            if range.length == 0 { var attributes = view.typingAttributes; attributes[key] = value; view.typingAttributes = attributes }
            else { view.textStorage.addAttribute(key, value: value, range: range) }
        }

        private func font(at location: Int, view: UITextView) -> UIFont {
            guard view.attributedText.length > 0 else { return .systemFont(ofSize: 13) }
            return view.attributedText.attribute(.font, at: min(location, view.attributedText.length - 1), effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: 13)
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
            let font = isMonospaced ? UIFont.systemFont(ofSize: 13) : UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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
            view.typingAttributes = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.label]
        }

        private func publish(_ view: UITextView) {
            let html = RichTextTextView.html(from: view.attributedText)
            lastHTML = html; parent.html = html
        }
    }

    private static func attributed(from value: String) -> NSAttributedString {
        if value.contains("<"), let data = value.data(using: .utf8), let result = try? NSMutableAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil
        ) {
            normalizeFonts(in: result)
            return result
        }
        return NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: 13)])
    }

    private static func html(from value: NSAttributedString) -> String {
        guard value.length > 0, let data = try? value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return "" }
        return String(data: data, encoding: .utf8) ?? value.string
    }

    private static func normalizeFonts(in value: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(.font, in: fullRange) { attribute, range, _ in
            let source = attribute as? UIFont ?? .systemFont(ofSize: 13)
            let size = source.pointSize <= 14 ? 13 : source.pointSize
            let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(source.fontDescriptor.symbolicTraits)
                ?? UIFont.systemFont(ofSize: size).fontDescriptor
            value.addAttribute(.font, value: UIFont(descriptor: descriptor, size: size), range: range)
        }
    }
}
