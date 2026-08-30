import Foundation

/// One coloured span of TOML source.
struct TomlToken: Equatable {
    let range: NSRange
    let kind: Kind

    enum Kind: Equatable {
        case comment
        case string
        case number
        case boolean
        case tableHeader
        case key
    }
}

/// Tokenizes TOML for display only. It never rejects input and never reports an error:
/// anything it doesn't recognize keeps the default colour, and a half-typed line is
/// coloured as far as it makes sense. `parseConfig` remains the only validator.
///
/// ponytail: re-tokenizes the whole document on every keystroke. Configs are a few
/// hundred lines, so this is microseconds; if it ever shows up, re-tokenize only the
/// edited line and the multi-line-string state after it.
func tomlTokens(_ text: String) -> [TomlToken] {
    var tokens: [TomlToken] = []
    var openMultilineQuote: Character? = nil
    var lineStart = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        tokenize(line: line, lineStart: lineStart, into: &tokens, openMultilineQuote: &openMultilineQuote)
        lineStart += line.utf16.count + 1 // + the "\n" that split() consumed
    }
    return tokens
}

private func tokenize(
    line: Substring,
    lineStart: Int,
    into tokens: inout [TomlToken],
    openMultilineQuote: inout Character?,
) {
    let chars = Array(line)
    // UTF-16 offset of every character, so a token's NSRange survives emoji in a string.
    var offsets: [Int] = []
    offsets.reserveCapacity(chars.count + 1)
    var utf16Length = 0
    for char in chars {
        offsets.append(utf16Length)
        utf16Length += char.utf16.count
    }
    offsets.append(utf16Length)
    func range(_ from: Int, _ to: Int) -> NSRange {
        NSRange(location: lineStart + offsets[from], length: offsets[to] - offsets[from])
    }
    func append(_ from: Int, _ to: Int, _ kind: TomlToken.Kind) {
        if to > from { tokens.append(TomlToken(range: range(from, to), kind: kind)) }
    }

    var i = 0

    // A multi-line string opened on an earlier line swallows everything, `#` included,
    // until its closing delimiter.
    if let quote = openMultilineQuote {
        if let end = multilineStringEnd(chars, from: 0, quote: quote) {
            append(0, end, .string)
            openMultilineQuote = nil
            i = end
        } else {
            append(0, chars.count, .string)
            return
        }
    }

    // A table header is only a header at the start of its line; `[` anywhere else is an array.
    while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
    if i < chars.count, chars[i] == "[" {
        let close = chars[i...].lastIndex(of: "]").map { chars.index(after: $0) } ?? chars.count
        append(i, close, .tableHeader)
        i = close
    }

    var seenEquals = false
    while i < chars.count {
        let char = chars[i]
        switch true {
            case char == "#":
                append(i, chars.count, .comment)
                return
            case char == "\"" || char == "'":
                let start = i
                if chars.count - i >= 3, chars[i + 1] == char, chars[i + 2] == char {
                    if let end = multilineStringEnd(chars, from: i + 3, quote: char) {
                        append(start, end, .string)
                        i = end
                    } else {
                        openMultilineQuote = char
                        append(start, chars.count, .string)
                        return
                    }
                } else {
                    let end = stringEnd(chars, from: i + 1, quote: char)
                    append(start, end, .string)
                    i = end
                }
            case char == "=":
                seenEquals = true
                i += 1
            case isWordCharacter(char):
                let start = i
                while i < chars.count, isWordCharacter(chars[i]) { i += 1 }
                let word = String(chars[start ..< i])
                switch true {
                    case word == "true" || word == "false": append(start, i, .boolean)
                    case !seenEquals: append(start, i, .key)
                    case word.first?.isNumber == true: append(start, i, .number)
                    default: break // a bare value the parser will judge; leave it plain
                }
            default:
                i += 1
        }
    }
}

/// Word characters are deliberately generous: a bare key, a number with separators and a
/// date all scan as one word, and which of those it is is decided afterwards.
private func isWordCharacter(_ char: Character) -> Bool {
    char.isLetter || char.isNumber || char == "_" || char == "-" || char == "." || char == "+" || char == ":"
}

/// Index just past the closing quote, or the end of the line when the string is unterminated.
private func stringEnd(_ chars: [Character], from: Int, quote: Character) -> Int {
    var i = from
    while i < chars.count {
        // Only basic strings have escapes; in a literal string a backslash is a backslash.
        if quote == "\"", chars[i] == "\\" {
            i += 2
            continue
        }
        if chars[i] == quote { return i + 1 }
        i += 1
    }
    return chars.count
}

/// Index just past the closing `"""` / `'''`, or nil when the block stays open past this line.
private func multilineStringEnd(_ chars: [Character], from: Int, quote: Character) -> Int? {
    guard chars.count >= 3 else { return nil }
    var i = from
    while i <= chars.count - 3 {
        if chars[i] == quote, chars[i + 1] == quote, chars[i + 2] == quote { return i + 3 }
        i += 1
    }
    return nil
}
