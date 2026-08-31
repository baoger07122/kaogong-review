import SwiftUI
import UIKit

enum RichTextToolbarMode { case full, compact }

private enum RichTextCommandKind: Equatable {
    case bold, italic, underline, strike, indent, outdent, bullets, numbers
    case link(String)
    case undo, redo
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
                    formatButton(.bold, "bold")
                    if mode == .full {
                        formatButton(.italic, "italic")
                        formatButton(.underline, "underline")
                        formatButton(.strike, "strikethrough")
                    }
                    formatButton(.outdent, "decrease.indent")
                    formatButton(.indent, "increase.indent")
                    formatButton(.bullets, "list.bullet")
                    formatButton(.numbers, "list.number")
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

        func apply(_ command: RichTextCommandKind, to view: UITextView) {
            let range = view.selectedRange
            var restoreSelection = true
            switch command {
            case .bold: toggleFontTrait(.traitBold, view: view, range: range)
            case .italic: toggleFontTrait(.traitItalic, view: view, range: range)
            case .underline: toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, view: view, range: range)
            case .strike: toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, view: view, range: range)
            case .indent: changeIndent(18, view: view, range: range)
            case .outdent: changeIndent(-18, view: view, range: range)
            case .bullets: prefixParagraphs("• ", view: view, range: range)
            case .numbers: numberParagraphs(view: view, range: range)
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

        private func publish(_ view: UITextView) {
            let html = RichTextTextView.html(from: view.attributedText)
            lastHTML = html; parent.html = html
        }
    }

    private static func attributed(from value: String) -> NSAttributedString {
        if value.contains("<"), let data = value.data(using: .utf8), let result = try? NSMutableAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil
        ) {
            result.addAttribute(.font, value: UIFont.systemFont(ofSize: 13), range: NSRange(location: 0, length: result.length))
            return result
        }
        return NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: 13)])
    }

    private static func html(from value: NSAttributedString) -> String {
        guard value.length > 0, let data = try? value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { return "" }
        return String(data: data, encoding: .utf8) ?? value.string
    }
}
