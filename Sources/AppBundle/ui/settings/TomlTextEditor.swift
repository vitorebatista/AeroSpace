import AppKit
import SwiftUI

/// A plain-text TOML editor that colours comments, strings, numbers, booleans, table
/// headers and keys.
///
/// SwiftUI's `TextEditor` carries no per-range attributes on the versions this app
/// supports, so this wraps `NSTextView` — the control `TextEditor` is itself built on —
/// directly. It stays a *text* editor: nothing here rewrites, completes or reformats what
/// the user types, and the colours are derived from the text rather than from a parse, so
/// an invalid document still looks like the TOML it is trying to be.
@MainActor
struct TomlTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Mirrors `.disabled(...)` from SwiftUI, which an `NSView` doesn't otherwise honour.
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false // or typing inherits the colour of the token under the caret
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false // "smart" quotes are invalid TOML
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        context.coordinator.highlight(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        textView.isEditable = isEnabled
        // The draft can change under the editor — Revert, a reload, a migration. Reassigning
        // `string` moves the caret to the start, so only do it when the text really differs.
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            highlight(textView)
        }

        func highlight(_ textView: NSTextView) {
            // `textStorage` is `unowned(unsafe)`; it outlives this synchronous call.
            guard let storage = unsafe textView.textStorage else { return }
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
            let source = storage.string
            let whole = NSRange(location: 0, length: (source as NSString).length)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: whole)
            for token in tomlTokens(source) {
                storage.addAttribute(.foregroundColor, value: tomlColor(token.kind), range: token.range)
            }
            storage.endEditing()
        }
    }
}

/// VS Code's Dark+ / Light+ colours, so the editor reads the way the file does in the
/// editor most users have open next to it. Dynamic `NSColor`s resolve at draw time, so
/// switching the system appearance recolours the text with no work here.
private func tomlColor(_ kind: TomlToken.Kind) -> NSColor {
    switch kind {
        case .comment: dynamicColor(light: 0x008000, dark: 0x6A9955)
        case .string: dynamicColor(light: 0xA31515, dark: 0xCE9178)
        case .number: dynamicColor(light: 0x098658, dark: 0xB5CEA8)
        case .boolean: dynamicColor(light: 0x0000FF, dark: 0x569CD6)
        case .tableHeader: dynamicColor(light: 0x267F99, dark: 0x4EC9B0)
        case .key: dynamicColor(light: 0x001080, dark: 0x9CDCFE)
    }
}

private func dynamicColor(light: Int, dark: Int) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(rgb: isDark ? dark : light)
    }
}

extension NSColor {
    fileprivate convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1,
        )
    }
}
