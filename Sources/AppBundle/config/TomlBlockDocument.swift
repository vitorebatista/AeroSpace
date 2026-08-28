import Foundation

/// One top-level region of a TOML document, carrying its source text verbatim.
///
/// `text` includes the line terminators exactly as they appeared, so joining every
/// block's `text` reproduces the input byte for byte.
enum TomlBlock: Equatable {
    /// Blank lines and comment lines that sit between blocks.
    case trivia(text: String)
    /// A top-level `key = value`, including any continuation lines of a multi-line value.
    case keyValue(key: String, text: String)
    /// A `[table]` or `[[array.of.tables]]` header and its body up to the next top-level header.
    case table(name: String, text: String)

    var text: String {
        switch self {
            case .trivia(let text): text
            case .keyValue(_, let text): text
            case .table(_, let text): text
        }
    }

    /// The key or table name, or `nil` for trivia. Array-of-tables and plain tables
    /// share a name: `[[on-window-detected]]` and `[on-window-detected]` are both
    /// `"on-window-detected"`.
    var name: String? {
        switch self {
            case .trivia: nil
            case .keyValue(let key, _): key
            case .table(let name, _): name
        }
    }
}

/// A TOML document split into top-level blocks, supporting surgical edits that leave
/// comments, key order, and unknown keys untouched.
///
/// This is deliberately NOT a TOML parser: values are never interpreted, only carried
/// as text. Reading typed values is the job of `parseConfig`. That split is what makes
/// the round-trip exact and keeps this type small.
struct TomlBlockDocument {
    private(set) var blocks: [TomlBlock]

    init(_ text: String) {
        blocks = Self.split(text)
    }

    func render() -> String { blocks.map(\.text).joined() }

    // MARK: - Parsing

    private static func split(_ text: String) -> [TomlBlock] {
        var blocks: [TomlBlock] = []
        var state = TomlLineState()
        // The block being accumulated. `nil` name means trivia.
        var pending: (kind: PendingKind, text: String)? = nil

        func flush() {
            guard let p = pending else { return }
            switch p.kind {
                case .trivia: blocks.append(.trivia(text: p.text))
                case .keyValue(let key): blocks.append(.keyValue(key: key, text: p.text))
                case .table(let name): blocks.append(contentsOf: splitTrailingTrivia(name: name, text: p.text))
            }
            pending = nil
        }

        for line in text.linesWithTerminators() {
            let insideValue = state.isInsideValue
            state.consume(line)
            if insideValue {
                pending?.text += line // continuation of a multi-line value or table body
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                // Trivia joins the table body it is inside; `splitTrailingTrivia` pulls a
                // trailing run back out on flush.
                if case .table = pending?.kind {
                    pending?.text += line
                } else if case .trivia = pending?.kind {
                    pending?.text += line
                } else {
                    flush()
                    pending = (.trivia, String(line))
                }
            } else if trimmed.hasPrefix("[") {
                flush()
                pending = (.table(name: tableName(of: trimmed)), String(line))
            } else if case .table = pending?.kind {
                pending?.text += line // a key inside the current table body
            } else {
                flush()
                pending = (.keyValue(key: keyName(of: trimmed)), String(line))
            }
        }
        flush()
        return blocks
    }

    private enum PendingKind {
        case trivia
        case keyValue(key: String)
        case table(name: String)
    }

    /// Splits a trailing run of blank/comment lines out of a table body into its own
    /// trivia block, so replacing the table does not carry away a comment that
    /// introduces whatever comes next.
    ///
    /// ponytail: this can also move a comment that genuinely trailed the table's last
    /// key. Rendering is unaffected either way; erring toward "belongs to what follows"
    /// is the safer half for splicing.
    private static func splitTrailingTrivia(name: String, text: String) -> [TomlBlock] {
        let lines = text.linesWithTerminators()
        var cut = lines.count
        while cut > 1 {
            let trimmed = lines[cut - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty || trimmed.hasPrefix("#") else { break }
            cut -= 1
        }
        if cut == lines.count { return [.table(name: name, text: text)] }
        return [
            .table(name: name, text: lines[..<cut].joined()),
            .trivia(text: lines[cut...].joined()),
        ]
    }

    /// `[[on-window-detected]]` -> `on-window-detected`; `[mode.main.binding]` -> `mode.main.binding`
    private static func tableName(of trimmedLine: String) -> String {
        var s = Substring(trimmedLine)
        // Drop a trailing comment before unwrapping the brackets.
        if let hash = s.firstIndex(of: "#") { s = s[..<hash] }
        s = Substring(s.trimmingCharacters(in: .whitespaces))
        while s.hasPrefix("[") { s = s.dropFirst() }
        while s.hasSuffix("]") { s = s.dropLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func keyName(of trimmedLine: String) -> String {
        guard let eq = trimmedLine.firstIndex(of: "=") else { return trimmedLine }
        return trimmedLine[..<eq].trimmingCharacters(in: .whitespaces)
    }
}

extension StringProtocol {
    /// Splits into lines, each keeping its trailing `\n` (or `\r\n`) if it had one.
    func linesWithTerminators() -> [String] {
        var result: [String] = []
        var current = ""
        for char in self {
            current.append(char)
            if char == "\n" {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// Tracks just enough TOML lexical state across lines to know where a top-level line
/// really starts: open bracket/brace depth and whether a multi-line string is open.
/// String contents and comments are skipped so that a `[` or `#` inside them is inert.
private struct TomlLineState {
    private var depth = 0
    private var openMultilineDelimiter: String? = nil

    var isInsideValue: Bool { depth > 0 || openMultilineDelimiter != nil }

    mutating func consume(_ line: String) {
        var i = line.startIndex
        func matches(_ needle: String) -> Bool { line[i...].hasPrefix(needle) }
        func advance(_ n: Int = 1) { i = line.index(i, offsetBy: n, limitedBy: line.endIndex) ?? line.endIndex }

        while i < line.endIndex {
            if let delimiter = openMultilineDelimiter {
                if matches(delimiter) {
                    openMultilineDelimiter = nil
                    advance(delimiter.count)
                } else {
                    advance()
                }
                continue
            }
            if matches("\"\"\"") { openMultilineDelimiter = "\"\"\""; advance(3); continue }
            if matches("'''") { openMultilineDelimiter = "'''"; advance(3); continue }
            let char = line[i]
            switch char {
                case "#":
                    return // rest of the line is a comment
                case "\"", "'":
                    advance()
                    while i < line.endIndex {
                        if char == "\"", line[i] == "\\" { advance(2); continue }
                        if line[i] == char { advance(); break }
                        advance()
                    }
                // A header line such as `[[on-window-detected]]` is balanced, so it nets to zero.
                case "[", "{": depth += 1; advance()
                case "]", "}": depth = max(0, depth - 1); advance()
                default: advance()
            }
        }
    }
}
