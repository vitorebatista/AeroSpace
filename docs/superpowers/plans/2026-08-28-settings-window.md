# AeroSpace Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GUI settings window to AeroSpace-edge that exposes every option the config parser accepts, writes the change back into the user's TOML config in place, and reloads the config — so a user never has to hand-edit `~/.aerospace-edge.toml`.

**Architecture:** A pure, line-oriented `TomlBlockDocument` splits the config text into ordered top-level blocks (key-value / table / trivia) carrying verbatim text, so an unmodified document re-renders byte-identically. A `ConfigTomlWriter` maps a draft `Config` onto that document — per-key surgical `set` for the 19 top-level scalars and `persistent-workspaces`, wholesale regeneration for the four nested tables the form fully models. A `SettingsModel` owns the draft and the save flow: render to a temp file, validate with the real `readConfig`, then write the real file and `reloadConfig()`. SwiftUI form sections cover the structured options; three raw-TOML panes cover the command DSL.

**Tech Stack:** Swift 6.3, SwiftUI, SPM, XCTest. No new dependencies. `TOMLDecoder` is already present and is used only for *reading* (via the existing `parseConfig`) — this plan adds no TOML encoder dependency.

**Spec:** `docs/superpowers/specs/2026-08-28-settings-modal-design.md` — read it before Task 1. It carries the authoritative option inventory table that Tasks 4, 6, 7 implement.

## Global Constraints

- Swift 6.3, strict concurrency, and `-strict-memory-safety` is enabled. If the compiler demands an explicit `unsafe` marker on a read, add it.
- **Warnings are errors.** Every task's build step is `./build-debug.sh -Xswiftc -warnings-as-errors` and it must exit 0.
- Tests: `./swift-test.sh` (whole suite) or `swift test --filter <TestName>` (one test). Trust the exit code and the `✅ Swift tests have passed successfully` line. A `Test run with 0 tests in 0 suites passed` line comes from the Swift Testing framework and is normal — it does NOT mean tests were skipped.
- Never hand-edit a `*Generated.swift` file.
- Tests live in `Sources/AppBundleTests/`, XCTest, `@testable import AppBundle`. Use the repo's `assertEquals` from `Sources/AppBundleTests/assert.swift`, not raw `XCTAssertEqual`. `projectRoot` from `Sources/AppBundleTests/testUtil.swift` resolves the repo root.
- Command results in this fork use `.succ` / `.fail(io.err(...))` and `BinaryExitCode`, not bare `Bool`. This plan adds no commands, so this only matters if you touch command code — don't.
- Keep changes atomic and scoped. Do not refactor unrelated code.
- Preserve upstream attribution and the MIT license header conventions of neighbouring files (most files in this repo have no license header — match the file you are next to).
- Config file resolution goes through the existing `findCustomConfigUrl()` in `Sources/AppBundle/config/ConfigFile.swift`. The fork's own dotfile is `.aerospace-edge.toml` (`configDotfileName`). Never hardcode `.aerospace.toml`.

---

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `Sources/AppBundle/config/TomlBlockDocument.swift` | Pure text model: split config text into top-level blocks, render, surgical set/remove/replace. No SwiftUI, no `Config`. |
| `Sources/AppBundle/config/ConfigTomlWriter.swift` | The one place that knows "option → TOML key + serialised value". Maps a draft `Config` onto a `TomlBlockDocument`. |
| `Sources/AppBundle/ui/settings/SettingsModel.swift` | `@MainActor ObservableObject`: load, draft state, dirty tracking, validate-then-save-then-reload. |
| `Sources/AppBundle/ui/settings/SettingsWindow.swift` | The `Scene`, `settingsWindowId`, sidebar + footer chrome. |
| `Sources/AppBundle/ui/settings/SettingsSections.swift` | The form sections bound to the draft `Config`. |
| `Sources/AppBundle/ui/settings/SettingsRawSection.swift` | The reusable raw-TOML pane view. |
| `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift` | Round-trip + mutation tests for the block document. |
| `Sources/AppBundleTests/config/ConfigTomlWriterTest.swift` | The coverage contract: draft `Config` → text → `parseConfig` → same values. |

**Modify:**

| File | Change |
|---|---|
| `Sources/AppBundle/ui/MenuBar.swift:43-45` | Add a `Settings…` button next to `openConfigButton()` / `reloadConfigButton()`. |
| `Sources/AeroSpaceApp/AeroSpaceApp.swift` | Register the settings scene. |
| `docs/guide.adoc` | Document the settings window. |
| `CHANGELOG-FORK.md` | Fork-feature entry. |

---

## Task 1: `TomlBlockDocument` — parse and render

**Files:**
- Create: `Sources/AppBundle/config/TomlBlockDocument.swift`
- Test: `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum TomlBlock`, `struct TomlBlockDocument` with `init(_ text: String)`, `func render() -> String`, `var blocks: [TomlBlock]`. Later tasks add mutators to this same type.

**Why a line scanner and not a regex:** a line starting with `[` is a table header *only* when no multi-line value is open and bracket depth is zero. Misreading a `[` inside a multi-line array as a table header would corrupt the user's config on save, so the scanner tracks strings and bracket depth properly. This is the one place in the feature where being sloppy loses data.

- [ ] **Step 1: Write the failing round-trip test**

Create `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift`:

```swift
@testable import AppBundle
import Common
import XCTest

final class TomlBlockDocumentTest: XCTestCase {
    func testRoundTripDefaultConfig() {
        for name in ["default-config.toml", "i3-like-config-example.toml"] {
            let text = try! String(
                contentsOf: projectRoot.appending(component: "docs/config-examples/\(name)"),
                encoding: .utf8,
            )
            assertEquals(TomlBlockDocument(text).render(), text)
        }
    }

    func testRoundTripTrickyValues() {
        let text = """
            # leading comment
            start-at-login = true

            after-startup-command = [
                'exec-and-forget echo "a # not-a-comment"',
                'exec-and-forget echo [not-a-header]',
            ]

            [gaps]
            inner.horizontal = 10 # trailing comment

            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            run = ['layout floating']

            """
        assertEquals(TomlBlockDocument(text).render(), text)
    }

    func testBlockSplitting() {
        let doc = TomlBlockDocument(
            """
            a = 1
            # comment about the table
            [gaps]
            inner.vertical = 2
            """,
        )
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .keyValue(key: "a", text: "a = 1\n"))
        assertEquals(doc.blocks[1], .trivia(text: "# comment about the table\n"))
        assertEquals(
            doc.blocks[2],
            .table(name: "gaps", text: "[gaps]\ninner.vertical = 2"),
        )
    }

    func testTrailingCommentsInATableBecomeTrivia() {
        // A comment run at the end of a table body is split out, so that replacing the
        // table does not swallow a comment that visually belongs to what follows.
        let doc = TomlBlockDocument(
            """
            [gaps]
            inner.vertical = 2

            # about the next thing
            [exec]
            inherit-env-vars = true
            """,
        )
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .table(name: "gaps", text: "[gaps]\ninner.vertical = 2\n"))
        assertEquals(doc.blocks[1], .trivia(text: "\n# about the next thing\n"))
        assertEquals(doc.blocks[2], .table(name: "exec", text: "[exec]\ninherit-env-vars = true"))
    }

    func testArrayOfTablesName() {
        let doc = TomlBlockDocument("[[on-window-detected]]\nrun = ['layout floating']\n")
        assertEquals(doc.blocks.count, 1)
        assertEquals(doc.blocks[0].name, "on-window-detected")
    }

    func testEmptyInput() {
        assertEquals(TomlBlockDocument("").render(), "")
        assertEquals(TomlBlockDocument("").blocks.count, 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`
Expected: FAIL — `cannot find 'TomlBlockDocument' in scope`.

- [ ] **Step 3: Implement `TomlBlockDocument.swift`**

Create `Sources/AppBundle/config/TomlBlockDocument.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && swift test --filter TomlBlockDocumentTest`
Expected: build exits 0 with no warnings; all 6 tests PASS.

If `testRoundTripDefaultConfig` fails, print the first differing offset rather than eyeballing 265 lines:

```swift
// temporary debugging aid — remove before committing
let rendered = TomlBlockDocument(text).render()
let i = zip(rendered, text).enumerated().first { $0.element.0 != $0.element.1 }?.offset
print("first difference at offset \(i.map(String.init) ?? "none"); lengths \(rendered.count) vs \(text.count)")
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/config/TomlBlockDocument.swift Sources/AppBundleTests/config/TomlBlockDocumentTest.swift
git commit -m "feat(config): add TomlBlockDocument text model for round-trip config edits"
```

---

## Task 2: Surgical `set` / `remove` for top-level keys, plus value serialisers

**Files:**
- Modify: `Sources/AppBundle/config/TomlBlockDocument.swift` (add mutators + serialisers)
- Test: `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift` (append tests)

**Interfaces:**
- Consumes: `TomlBlockDocument`, `TomlBlock` from Task 1.
- Produces:
  - `mutating func set(key: String, tomlValue: String)`
  - `mutating func remove(key: String)`
  - `enum TomlValue { static func of(_ b: Bool) -> String; static func of(_ i: Int) -> String; static func of(_ s: String) -> String; static func array(_ items: [String]) -> String }`
    — `TomlValue.of(_ s: String)` returns a **quoted** TOML string; `array` takes already-serialised items.

- [ ] **Step 1: Write the failing tests**

Append to `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift` (inside the class):

```swift
    func testSetExistingKeyPreservesEverythingElse() {
        var doc = TomlBlockDocument(
            """
            # top comment
            start-at-login = false
            accordion-padding = 30 # why 30

            [gaps]
            inner.vertical = 2
            """,
        )
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(
            doc.render(),
            """
            # top comment
            start-at-login = true
            accordion-padding = 30 # why 30

            [gaps]
            inner.vertical = 2
            """,
        )
    }

    func testSetPreservesTrailingCommentOnTheSameLine() {
        var doc = TomlBlockDocument("accordion-padding = 30 # why 30\n")
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(doc.render(), "accordion-padding = 45 # why 30\n")
    }

    func testSetAbsentKeyIsInsertedBeforeTheFirstTableHeader() {
        var doc = TomlBlockDocument(
            """
            start-at-login = true

            [gaps]
            inner.vertical = 2
            """,
        )
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(
            doc.render(),
            """
            start-at-login = true
            accordion-padding = 45

            [gaps]
            inner.vertical = 2
            """,
        )
    }

    func testSetAbsentKeyInAFileWithNoTables() {
        var doc = TomlBlockDocument("start-at-login = true\n")
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(doc.render(), "start-at-login = true\naccordion-padding = 45\n")
    }

    func testSetAbsentKeyInAnEmptyDocument() {
        var doc = TomlBlockDocument("")
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(doc.render(), "start-at-login = true\n")
    }

    func testSetMultiLineValueIsReplacedWholesale() {
        var doc = TomlBlockDocument(
            """
            persistent-workspaces = [
                '1',
                '2',
            ]
            start-at-login = true
            """,
        )
        doc.set(key: "persistent-workspaces", tomlValue: "['1', '2', '3']")
        assertEquals(
            doc.render(),
            """
            persistent-workspaces = ['1', '2', '3']
            start-at-login = true
            """,
        )
    }

    func testRemoveKey() {
        var doc = TomlBlockDocument("a = 1\nb = 2\n")
        doc.remove(key: "a")
        assertEquals(doc.render(), "b = 2\n")
        doc.remove(key: "nonexistent") // no-op
        assertEquals(doc.render(), "b = 2\n")
    }

    func testUnknownKeysAndTablesSurviveASet() {
        let text = """
            some-future-option = 'hello'
            start-at-login = false

            [some.future.table]
            x = 1
            """
        var doc = TomlBlockDocument(text)
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(doc.render(), text.replacingOccurrences(of: "start-at-login = false", with: "start-at-login = true"))
    }

    func testValueSerialisers() {
        assertEquals(TomlValue.of(true), "true")
        assertEquals(TomlValue.of(42), "42")
        assertEquals(TomlValue.of("plain"), "'plain'")
        assertEquals(TomlValue.of("it's"), "\"it's\"")
        assertEquals(TomlValue.of("say \"hi\""), "'say \"hi\"'")
        assertEquals(TomlValue.array([TomlValue.of("1"), TomlValue.of("2")]), "['1', '2']")
        assertEquals(TomlValue.array([]), "[]")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`
Expected: FAIL — `value of type 'TomlBlockDocument' has no member 'set'`, `cannot find 'TomlValue' in scope`.

- [ ] **Step 3: Implement the mutators and serialisers**

Append to `Sources/AppBundle/config/TomlBlockDocument.swift`:

```swift
// MARK: - Surgical edits

extension TomlBlockDocument {
    /// Replaces the value of an existing top-level `key`, keeping its position, its
    /// indentation, and any trailing comment on the same line. If the key is absent it
    /// is appended at the end of the top-level key region — before the first table
    /// header, so the document stays valid TOML.
    mutating func set(key: String, tomlValue: String) {
        if let index = blocks.firstIndex(where: { $0.name == key && $0.isKeyValue }) {
            blocks[index] = .keyValue(key: key, text: Self.rewriteValue(of: blocks[index].text, key: key, to: tomlValue))
            return
        }
        let line = "\(key) = \(tomlValue)\n"
        let insertAt = blocks.firstIndex(where: { $0.isTable }) ?? blocks.count
        // Skip back over trivia that introduces the first table — a comment about `[gaps]`
        // should stay attached to `[gaps]`, not end up below the new key.
        var target = insertAt
        while target > 0, blocks[target - 1].isTrivia { target -= 1 }
        // The block we are inserting after must end with a newline, or the new key would
        // be glued onto it.
        if target > 0 {
            blocks[target - 1] = blocks[target - 1].withText { $0.hasSuffix("\n") ? $0 : $0 + "\n" }
        }
        blocks.insert(.keyValue(key: key, text: line), at: target)
    }

    mutating func remove(key: String) {
        blocks.removeAll { $0.name == key && $0.isKeyValue }
    }

    /// Rewrites `key = <old>` to `key = <new>`, keeping leading indentation and any
    /// trailing `#` comment from the FIRST line, and dropping any continuation lines of
    /// a multi-line old value.
    private static func rewriteValue(of text: String, key: String, to tomlValue: String) -> String {
        let lines = text.linesWithTerminators()
        guard let first = lines.first else { return "\(key) = \(tomlValue)\n" }
        let indent = String(first.prefix(while: { $0 == " " || $0 == "\t" }))
        // Only treat a `#` as a comment if it is outside the value's quotes. Reuse the
        // scanner by asking it where the comment starts.
        let comment = trailingComment(of: first)
        let terminator = lines.last?.hasSuffix("\n") == true ? "\n" : ""
        return "\(indent)\(key) = \(tomlValue)\(comment)\(terminator)"
    }

    /// Returns `" # ..."` (with its original spacing) if the line ends in a comment that
    /// is not inside a string, else `""`.
    private static func trailingComment(of line: String) -> String {
        var state = TomlCommentScanner()
        if let index = state.commentStart(of: line) {
            let raw = line[index...]
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : " " + trimmed
        }
        return ""
    }
}

private extension TomlBlock {
    var isKeyValue: Bool { if case .keyValue = self { true } else { false } }
    var isTable: Bool { if case .table = self { true } else { false } }
    var isTrivia: Bool { if case .trivia = self { true } else { false } }

    func withText(_ transform: (String) -> String) -> TomlBlock {
        switch self {
            case .trivia(let text): .trivia(text: transform(text))
            case .keyValue(let key, let text): .keyValue(key: key, text: transform(text))
            case .table(let name, let text): .table(name: name, text: transform(text))
        }
    }
}

/// Finds where a real comment starts on a single line, skipping `#` inside strings.
private struct TomlCommentScanner {
    mutating func commentStart(of line: String) -> String.Index? {
        var i = line.startIndex
        func advance(_ n: Int = 1) { i = line.index(i, offsetBy: n, limitedBy: line.endIndex) ?? line.endIndex }
        while i < line.endIndex {
            let char = line[i]
            switch char {
                case "#": return i
                case "\"", "'":
                    advance()
                    while i < line.endIndex {
                        if char == "\"", line[i] == "\\" { advance(2); continue }
                        if line[i] == char { advance(); break }
                        advance()
                    }
                default: advance()
            }
        }
        return nil
    }
}

// MARK: - Value serialisation

/// Serialises Swift values to TOML value syntax. Deliberately tiny: the settings window
/// only ever writes bools, ints, strings, and arrays of those.
enum TomlValue {
    static func of(_ value: Bool) -> String { value ? "true" : "false" }
    static func of(_ value: Int) -> String { String(value) }

    /// Prefers a literal (single-quoted) string, since AeroSpace configs and commands are
    /// full of backslashes and regexes that a basic string would force us to escape.
    /// Falls back to a basic string when the value itself contains a single quote.
    static func of(_ value: String) -> String {
        if !value.contains("'") { return "'\(value)'" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// `items` must already be serialised.
    static func array(_ items: [String]) -> String { "[\(items.joined(separator: ", "))]" }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && swift test --filter TomlBlockDocumentTest`
Expected: build exits 0; all tests PASS, including the Task 1 round-trip tests (they must not regress).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/config/TomlBlockDocument.swift Sources/AppBundleTests/config/TomlBlockDocumentTest.swift
git commit -m "feat(config): surgical top-level key edits and TOML value serialisation"
```

---

## Task 3: Table read and replace

**Files:**
- Modify: `Sources/AppBundle/config/TomlBlockDocument.swift`
- Test: `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces:
  - `func text(forTablesMatching predicate: (String) -> Bool) -> String` — concatenated source text of the matching table blocks, in document order.
  - `mutating func replaceTable(named name: String, with body: String?) ` — replaces the single named table's block at its original position; `nil` deletes it; also removes top-level dotted keys under `name.` (see the spec's "Nested tables are regenerated" section). If the table is absent and `body` is non-nil, it is appended at the end of the document.
  - `mutating func replaceTables(matching predicate: (String) -> Bool, with text: String)` — replaces the whole span occupied by matching table blocks with `text`, at the position of the first match; used by the raw panes.

- [ ] **Step 1: Write the failing tests**

Append to the test class:

```swift
    private static let tablesFixture = """
        start-at-login = true

        [gaps]
        inner.vertical = 2

        [mode.main.binding]
        alt-h = 'focus left'

        [mode.service.binding]
        esc = 'mode main'

        [exec]
        inherit-env-vars = true

        """

    func testTextForTablesMatching() {
        let doc = TomlBlockDocument(Self.tablesFixture)
        assertEquals(
            doc.text(forTablesMatching: { $0.hasPrefix("mode.") }),
            """
            [mode.main.binding]
            alt-h = 'focus left'

            [mode.service.binding]
            esc = 'mode main'

            """,
        )
        assertEquals(doc.text(forTablesMatching: { $0 == "nope" }), "")
    }

    func testReplaceTableKeepsPosition() {
        var doc = TomlBlockDocument(Self.tablesFixture)
        doc.replaceTable(named: "gaps", with: "[gaps]\ninner.vertical = 9\n")
        assertEquals(
            doc.render(),
            Self.tablesFixture.replacingOccurrences(of: "inner.vertical = 2", with: "inner.vertical = 9"),
        )
    }

    func testReplaceTableWithNilDeletesIt() {
        var doc = TomlBlockDocument("a = 1\n\n[gaps]\ninner.vertical = 2\n\n[exec]\nx = 1\n")
        doc.replaceTable(named: "gaps", with: nil)
        assertEquals(doc.render(), "a = 1\n\n[exec]\nx = 1\n")
    }

    func testReplaceTableAlsoDropsTopLevelDottedKeys() {
        // `gaps.inner.vertical = 5` at top level is the same setting spelled differently;
        // regenerating `[gaps]` must not leave a duplicate definition behind.
        var doc = TomlBlockDocument("gaps.inner.vertical = 5\nstart-at-login = true\n")
        doc.replaceTable(named: "gaps", with: "[gaps]\ninner.vertical = 9\n")
        assertEquals(doc.render(), "start-at-login = true\n[gaps]\ninner.vertical = 9\n")
    }

    func testReplaceAbsentTableAppends() {
        var doc = TomlBlockDocument("a = 1\n")
        doc.replaceTable(named: "gaps", with: "[gaps]\ninner.vertical = 9\n")
        assertEquals(doc.render(), "a = 1\n[gaps]\ninner.vertical = 9\n")
    }

    func testReplaceTablesMatchingSplicesAtFirstMatch() {
        var doc = TomlBlockDocument(Self.tablesFixture)
        doc.replaceTables(matching: { $0.hasPrefix("mode.") }, with: "[mode.main.binding]\nalt-j = 'focus down'\n")
        assertEquals(
            doc.render(),
            """
            start-at-login = true

            [gaps]
            inner.vertical = 2

            [mode.main.binding]
            alt-j = 'focus down'

            [exec]
            inherit-env-vars = true

            """,
        )
    }

    func testReplaceTablesMatchingWhenNoneMatchAppends() {
        var doc = TomlBlockDocument("a = 1\n")
        doc.replaceTables(matching: { $0.hasPrefix("mode.") }, with: "[mode.main.binding]\nalt-j = 'focus down'\n")
        assertEquals(doc.render(), "a = 1\n[mode.main.binding]\nalt-j = 'focus down'\n")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`
Expected: FAIL — no member `text(forTablesMatching:)`, `replaceTable`, `replaceTables`.

- [ ] **Step 3: Implement**

Append to `Sources/AppBundle/config/TomlBlockDocument.swift`:

```swift
// MARK: - Table access

extension TomlBlockDocument {
    func text(forTablesMatching predicate: (String) -> Bool) -> String {
        blocks
            .filter { block in block.isTable && block.name.map(predicate) == true }
            .map(\.text)
            .joined()
    }

    /// Replaces the named table wholesale, at the position it already occupies. Passing
    /// `nil` deletes it. Any top-level dotted key under `name.` is dropped too, because
    /// `gaps.inner.vertical = 5` and `[gaps]` + `inner.vertical = 5` are the same
    /// setting and leaving both would be a duplicate definition.
    mutating func replaceTable(named name: String, with body: String?) {
        blocks.removeAll { $0.isKeyValue && $0.name?.hasPrefix(name + ".") == true }
        let existing = blocks.firstIndex { $0.isTable && $0.name == name }
        switch (existing, body) {
            case (let index?, let body?):
                blocks[index] = .table(name: name, text: Self.newlineTerminated(body))
            case (let index?, nil):
                blocks.remove(at: index)
                // Drop a blank-only trivia block left dangling where the table used to be.
                if index < blocks.count, blocks[index].isTrivia,
                   blocks[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    blocks.remove(at: index)
                }
            case (nil, let body?):
                appendTable(name: name, body: body)
            case (nil, nil):
                break
        }
    }

    /// Replaces the span of all matching tables with `text`, positioned at the first
    /// match. Used by the raw-TOML panes, which own a whole family of tables at once.
    mutating func replaceTables(matching predicate: (String) -> Bool, with text: String) {
        let indices = blocks.indices.filter { blocks[$0].isTable && blocks[$0].name.map(predicate) == true }
        guard let first = indices.first else {
            appendTable(name: "", body: text)
            return
        }
        for index in indices.reversed() { blocks.remove(at: index) }
        blocks.insert(.table(name: "", text: Self.newlineTerminated(text)), at: first)
    }

    private mutating func appendTable(name: String, body: String) {
        if let last = blocks.indices.last {
            blocks[last] = blocks[last].withText { $0.hasSuffix("\n") ? $0 : $0 + "\n" }
        }
        blocks.append(.table(name: name, text: Self.newlineTerminated(body)))
    }

    private static func newlineTerminated(_ text: String) -> String {
        text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
    }
}
```

Note on `replaceTables`: the spliced block is stored with an empty `name` because it may
hold several tables. That is fine — `name` is only used for matching, and a raw pane is
re-seeded from `text(forTablesMatching:)` on the next `load()`, which reads from disk.
`replaceTables` must therefore be called at most once per save per pane, which
`ConfigTomlWriter` guarantees.

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && swift test --filter TomlBlockDocumentTest`
Expected: build exits 0; all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/config/TomlBlockDocument.swift Sources/AppBundleTests/config/TomlBlockDocumentTest.swift
git commit -m "feat(config): table read/replace/splice in TomlBlockDocument"
```

---

## Task 4: `ConfigTomlWriter` — the option coverage contract

**Files:**
- Create: `Sources/AppBundle/config/ConfigTomlWriter.swift`
- Test: `Sources/AppBundleTests/config/ConfigTomlWriterTest.swift`

**Interfaces:**
- Consumes: `TomlBlockDocument`, `TomlValue` (Tasks 1–3); `Config`, `Gaps`, `KeyMapping`, `DynamicConfigValue`, `MonitorDescription`, `RawExecConfig`.
- Produces: `struct ConfigTomlWriter` with
  - `static func apply(_ draft: ConfigDraft, to document: inout TomlBlockDocument)`
  - `struct ConfigDraft` — the mutable settings state: the subset of `Config` the form edits, plus `inheritEnvVars: Bool` and `envVars: [String: String]` (which `Config.execConfig` does not keep separably), plus the three raw pane strings.
  - `static func draft(from config: Config, rawExec: RawExecConfig, document: TomlBlockDocument) -> ConfigDraft`

**Why `ConfigDraft` and not `Config`:** `Config.execConfig` is the *expanded* environment (`RawExecConfig.expand()` merges the process environment in), so it cannot be serialised back — writing it out would bake the whole inherited environment into the user's config. The draft keeps `inherit-env-vars` and the override map separately, exactly as they appear in the file. `Config` also holds `[any Command]` values for the callbacks, which are not round-trippable — those live in the raw Callbacks pane as text instead.

**This task's test is the feature's coverage contract:** it asserts that every option in the spec's inventory survives draft → text → `parseConfig`. If an option is missing from `apply`, this test fails.

- [ ] **Step 1: Write the failing test**

Create `Sources/AppBundleTests/config/ConfigTomlWriterTest.swift`:

```swift
@testable import AppBundle
import Common
import XCTest

@MainActor
final class ConfigTomlWriterTest: XCTestCase {
    /// Applies a draft to an empty document, re-parses the result with the real parser,
    /// and returns the parsed config. Fails the test if the output does not parse.
    private func roundTrip(_ mutate: (inout ConfigTomlWriter.ConfigDraft) -> Void) -> Config {
        var draft = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: TomlBlockDocument(""))
        mutate(&draft)
        var document = TomlBlockDocument("")
        ConfigTomlWriter.apply(draft, to: &document)
        let text = document.render()
        let (parsed, errors) = parseConfig(text)
        assertEquals(errors.map(\.description), [], "generated config did not parse:\n\(text)")
        return parsed
    }

    func testScalarsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.startAtLogin = true
            draft.autoReloadConfig = true
            draft.automaticallyUnhideMacosHiddenApps = true
            draft.enableNormalizationFlattenContainers = false
            draft.enableNormalizationOppositeOrientationForNestedContainers = false
            draft.enableNormalizationBinaryTree = true
            draft.defaultRootContainerLayout = .accordion
            draft.defaultRootContainerOrientation = .vertical
            draft.accordionPadding = 45
            draft.focusFollowsAppActivation = .smart
            draft.newWindowPreventFlicker = true
        }
        assertEquals(parsed.startAtLogin, true)
        assertEquals(parsed.autoReloadConfig, true)
        assertEquals(parsed.automaticallyUnhideMacosHiddenApps, true)
        assertEquals(parsed.enableNormalizationFlattenContainers, false)
        assertEquals(parsed.enableNormalizationOppositeOrientationForNestedContainers, false)
        assertEquals(parsed.enableNormalizationBinaryTree, true)
        assertEquals(parsed.defaultRootContainerLayout, .accordion)
        assertEquals(parsed.defaultRootContainerOrientation, .vertical)
        assertEquals(parsed.accordionPadding, 45)
        assertEquals(parsed.focusFollowsAppActivation, .smart)
        assertEquals(parsed.newWindowPreventFlicker, true)
    }

    func testWindowBorderRoundTrips() {
        let parsed = roundTrip { draft in
            draft.focusedWindowBorder = true
            draft.focusedWindowBorderColor = "0xff123456"
            draft.focusedWindowBorderWidth = 6
            draft.focusedWindowBorderOpacity = 80
            draft.focusedWindowBorderRadius = 12
            draft.focusedWindowBorderInset = 2
        }
        assertEquals(parsed.focusedWindowBorder, true)
        assertEquals(parsed.focusedWindowBorderColor, "0xff123456")
        assertEquals(parsed.focusedWindowBorderWidth, 6)
        assertEquals(parsed.focusedWindowBorderOpacity, 80)
        assertEquals(parsed.focusedWindowBorderRadius, 12)
        assertEquals(parsed.focusedWindowBorderInset, 2)
    }

    func testPersistentWorkspacesRoundTrips() {
        let parsed = roundTrip { draft in draft.persistentWorkspaces = ["1", "web", "it's"] }
        assertEquals(Array(parsed.persistentWorkspaces), ["1", "web", "it's"])
    }

    func testConstantGapsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(inner: .init(vertical: 5, horizontal: 6), outer: .init(left: 1, bottom: 2, top: 3, right: 4))
        }
        assertEquals(parsed.gaps.inner.vertical, .constant(5))
        assertEquals(parsed.gaps.outer.top, .constant(3))
    }

    func testPerMonitorGapsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(
                inner: .init(vertical: .constant(5), horizontal: .constant(6)),
                outer: .init(
                    left: .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8),
                    bottom: .constant(2), top: .constant(3), right: .constant(4),
                ),
            )
        }
        assertEquals(parsed.gaps.outer.left, .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8))
    }

    func testKeyMappingRoundTrips() {
        let parsed = roundTrip { draft in
            draft.keyMappingPreset = .dvorak
            draft.keyNotationToKeyCode = ["q": "quote"]
        }
        assertEquals(parsed.keyMapping.resolve()["q"], getKeysPreset(.dvorak)["quote"] ?? keyNotationToKeyCode["quote"])
        // The preset itself is fileprivate on KeyMapping; assert through the resolved map,
        // which differs between qwerty and dvorak.
        assertEquals(parsed.keyMapping.resolve()["s"], getKeysPreset(.dvorak)["s"])
    }

    func testExecRoundTrips() {
        let parsed = roundTrip { draft in
            draft.inheritEnvVars = false
            draft.envVars = ["MY_VAR": "hello"]
        }
        assertEquals(parsed.execConfig.envVariables["MY_VAR"], "hello")
        assertEquals(parsed.execConfig.envVariables["AEROSPACE_INHERITED_TEST_ENV"], nil)
    }

    func testWorkspaceToMonitorAssignmentRoundTrips() {
        let parsed = roundTrip { draft in
            draft.workspaceToMonitorForceAssignment = ["1": [.main], "2": [.secondary, .sequenceNumber(3)]]
        }
        assertEquals(parsed.workspaceToMonitorForceAssignment["1"], [.main])
        assertEquals(parsed.workspaceToMonitorForceAssignment["2"], [.secondary, .sequenceNumber(3)])
    }

    func testRawPanesAreSpliced() {
        let parsed = roundTrip { draft in
            draft.rawKeybindings = "[mode.main.binding]\nalt-h = 'focus left'\n"
            draft.rawWindowRules = "[[on-window-detected]]\nif.app-id = 'com.apple.finder'\nrun = ['layout floating']\n"
            draft.rawCallbacks = "on-focus-changed = ['move-mouse window-lazy-center']\n"
        }
        assertEquals(parsed.modes[mainModeId]?.bindings.isEmpty, false)
        assertEquals(parsed.onWindowDetected.count, 1)
        assertEquals(parsed.onFocusChanged.count, 1)
    }

    func testDefaultsAreNotWrittenWhenAbsentFromTheFile() {
        // A user's file that sets nothing must stay minimal after an unrelated edit.
        var document = TomlBlockDocument("start-at-login = false\n")
        var draft = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, to: &document)
        assertEquals(document.render(), "start-at-login = true\n")
    }

    func testCommentsOutsideRegeneratedTablesSurvive() {
        var document = TomlBlockDocument("# my note\nstart-at-login = false\n\n[mode.main.binding]\nalt-h = 'focus left'\n")
        var draft = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, to: &document)
        assertEquals(document.render().contains("# my note"), true)
        assertEquals(document.render().contains("alt-h = 'focus left'"), true)
    }

    func testAppliedToDefaultConfigStillParses() {
        let text = try! String(
            contentsOf: projectRoot.appending(component: "docs/config-examples/default-config.toml"),
            encoding: .utf8,
        )
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfig(text)
        assertEquals(errors, [])
        var draft = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        draft.accordionPadding = 99
        draft.gaps = draft.gaps.copy(\.inner.vertical, .constant(7))
        ConfigTomlWriter.apply(draft, to: &document)
        let (reparsed, reErrors) = parseConfig(document.render())
        assertEquals(reErrors.map(\.description), [], document.render())
        assertEquals(reparsed.accordionPadding, 99)
        assertEquals(reparsed.gaps.inner.vertical, .constant(7))
        // The bindings the default config ships with must survive an unrelated edit.
        assertEquals(reparsed.modes[mainModeId]?.bindings.count, config.modes[mainModeId]?.bindings.count)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`
Expected: FAIL — `cannot find 'ConfigTomlWriter' in scope`.

- [ ] **Step 3: Implement `ConfigTomlWriter.swift`**

Create `Sources/AppBundle/config/ConfigTomlWriter.swift`:

```swift
import Common
import OrderedCollections

/// Maps the settings window's draft state onto a `TomlBlockDocument`.
///
/// This is the single place that knows the TOML spelling of every option, so adding an
/// option to the window means touching this file and `SettingsSections.swift` and
/// nothing else.
enum ConfigTomlWriter {
    /// The editable settings state.
    ///
    /// This is not `Config` because two parts of `Config` are not round-trippable:
    /// `execConfig` is the *expanded* environment (writing it back would bake the whole
    /// inherited process environment into the user's file), and the callbacks are
    /// `[any Command]`. Those live here as raw file-shaped values instead.
    struct ConfigDraft: ConvenienceCopyable {
        var startAtLogin: Bool
        var autoReloadConfig: Bool
        var automaticallyUnhideMacosHiddenApps: Bool
        var enableNormalizationFlattenContainers: Bool
        var enableNormalizationOppositeOrientationForNestedContainers: Bool
        var enableNormalizationBinaryTree: Bool
        var defaultRootContainerLayout: Layout
        var defaultRootContainerOrientation: DefaultContainerOrientation
        var accordionPadding: Int
        var focusFollowsAppActivation: FocusFollowsAppActivation
        var newWindowPreventFlicker: Bool
        var focusedWindowBorder: Bool
        var focusedWindowBorderColor: String
        var focusedWindowBorderWidth: Int
        var focusedWindowBorderOpacity: Int
        var focusedWindowBorderRadius: Int
        var focusedWindowBorderInset: Int
        var configVersion: Int
        var persistentWorkspaces: OrderedSet<String>
        var gaps: Gaps
        var workspaceToMonitorForceAssignment: [String: [MonitorDescription]]
        var keyMappingPreset: KeyMapping.Preset
        var keyNotationToKeyCode: [String: String] // notation -> key-code NAME, as written in the file
        var inheritEnvVars: Bool
        var envVars: [String: String]
        var rawKeybindings: String
        var rawWindowRules: String
        var rawCallbacks: String
    }

    // MARK: - Table ownership

    static func isKeybindingTable(_ name: String) -> Bool { name == "mode" || name.hasPrefix("mode.") }
    static func isWindowRuleTable(_ name: String) -> Bool { name == "on-window-detected" }

    /// The top-level keys the Callbacks pane owns.
    static let callbackKeys = [
        "after-startup-command",
        "on-focus-changed",
        "on-mode-changed",
        "on-focused-monitor-changed",
        "exec-on-workspace-change",
    ]

    /// The nested tables the form models completely and therefore regenerates wholesale.
    private static let regeneratedTables = ["gaps", "key-mapping", "exec", "workspace-to-monitor-force-assignment"]

    // MARK: - Reading a draft out of a parsed config + the document

    static func draft(from config: Config, rawExec: RawExecConfig, document: TomlBlockDocument) -> ConfigDraft {
        ConfigDraft(
            startAtLogin: config.startAtLogin,
            autoReloadConfig: config.autoReloadConfig,
            automaticallyUnhideMacosHiddenApps: config.automaticallyUnhideMacosHiddenApps,
            enableNormalizationFlattenContainers: config.enableNormalizationFlattenContainers,
            enableNormalizationOppositeOrientationForNestedContainers: config.enableNormalizationOppositeOrientationForNestedContainers,
            enableNormalizationBinaryTree: config.enableNormalizationBinaryTree,
            defaultRootContainerLayout: config.defaultRootContainerLayout,
            defaultRootContainerOrientation: config.defaultRootContainerOrientation,
            accordionPadding: config.accordionPadding,
            focusFollowsAppActivation: config.focusFollowsAppActivation,
            newWindowPreventFlicker: config.newWindowPreventFlicker,
            focusedWindowBorder: config.focusedWindowBorder,
            focusedWindowBorderColor: config.focusedWindowBorderColor,
            focusedWindowBorderWidth: config.focusedWindowBorderWidth,
            focusedWindowBorderOpacity: config.focusedWindowBorderOpacity,
            focusedWindowBorderRadius: config.focusedWindowBorderRadius,
            focusedWindowBorderInset: config.focusedWindowBorderInset,
            configVersion: config.configVersion,
            persistentWorkspaces: config.persistentWorkspaces,
            gaps: config.gaps,
            workspaceToMonitorForceAssignment: config.workspaceToMonitorForceAssignment,
            keyMappingPreset: config.keyMapping.presetForSettings,
            keyNotationToKeyCode: config.keyMapping.rawNotationNamesForSettings,
            inheritEnvVars: rawExec.inheritEnvVariables,
            envVars: rawExec.overriddenVars,
            rawKeybindings: document.text(forTablesMatching: isKeybindingTable),
            rawWindowRules: document.text(forTablesMatching: isWindowRuleTable),
            rawCallbacks: callbackKeys.compactMap { document.text(forKeyValue: $0) }.joined(),
        )
    }

    // MARK: - Writing a draft into the document

    static func apply(_ draft: ConfigDraft, to document: inout TomlBlockDocument) {
        let defaults = ConfigDraft.defaults

        // Top-level scalars. `setOrOmit` keeps a value out of the file when it equals the
        // default AND is not already present, so the window never bloats a minimal config.
        func setOrOmit(_ key: String, _ value: String, isDefault: Bool) {
            if isDefault, document.text(forKeyValue: key) == nil { return }
            document.set(key: key, tomlValue: value)
        }

        setOrOmit("start-at-login", TomlValue.of(draft.startAtLogin), isDefault: draft.startAtLogin == defaults.startAtLogin)
        setOrOmit("auto-reload-config", TomlValue.of(draft.autoReloadConfig), isDefault: draft.autoReloadConfig == defaults.autoReloadConfig)
        setOrOmit("automatically-unhide-macos-hidden-apps", TomlValue.of(draft.automaticallyUnhideMacosHiddenApps), isDefault: draft.automaticallyUnhideMacosHiddenApps == defaults.automaticallyUnhideMacosHiddenApps)
        setOrOmit("enable-normalization-flatten-containers", TomlValue.of(draft.enableNormalizationFlattenContainers), isDefault: draft.enableNormalizationFlattenContainers == defaults.enableNormalizationFlattenContainers)
        setOrOmit("enable-normalization-opposite-orientation-for-nested-containers", TomlValue.of(draft.enableNormalizationOppositeOrientationForNestedContainers), isDefault: draft.enableNormalizationOppositeOrientationForNestedContainers == defaults.enableNormalizationOppositeOrientationForNestedContainers)
        setOrOmit("enable-normalization-binary-tree", TomlValue.of(draft.enableNormalizationBinaryTree), isDefault: draft.enableNormalizationBinaryTree == defaults.enableNormalizationBinaryTree)
        setOrOmit("default-root-container-layout", TomlValue.of(draft.defaultRootContainerLayout.rawValue), isDefault: draft.defaultRootContainerLayout == defaults.defaultRootContainerLayout)
        setOrOmit("default-root-container-orientation", TomlValue.of(draft.defaultRootContainerOrientation.rawValue), isDefault: draft.defaultRootContainerOrientation == defaults.defaultRootContainerOrientation)
        setOrOmit("accordion-padding", TomlValue.of(draft.accordionPadding), isDefault: draft.accordionPadding == defaults.accordionPadding)
        setOrOmit("focus-follows-app-activation", TomlValue.of(draft.focusFollowsAppActivation.rawValue), isDefault: draft.focusFollowsAppActivation == defaults.focusFollowsAppActivation)
        setOrOmit("new-window-prevent-flicker", TomlValue.of(draft.newWindowPreventFlicker), isDefault: draft.newWindowPreventFlicker == defaults.newWindowPreventFlicker)
        setOrOmit("focused-window-border", TomlValue.of(draft.focusedWindowBorder), isDefault: draft.focusedWindowBorder == defaults.focusedWindowBorder)
        setOrOmit("focused-window-border-color", TomlValue.of(draft.focusedWindowBorderColor), isDefault: draft.focusedWindowBorderColor == defaults.focusedWindowBorderColor)
        setOrOmit("focused-window-border-width", TomlValue.of(draft.focusedWindowBorderWidth), isDefault: draft.focusedWindowBorderWidth == defaults.focusedWindowBorderWidth)
        setOrOmit("focused-window-border-opacity", TomlValue.of(draft.focusedWindowBorderOpacity), isDefault: draft.focusedWindowBorderOpacity == defaults.focusedWindowBorderOpacity)
        setOrOmit("focused-window-border-radius", TomlValue.of(draft.focusedWindowBorderRadius), isDefault: draft.focusedWindowBorderRadius == defaults.focusedWindowBorderRadius)
        setOrOmit("focused-window-border-inset", TomlValue.of(draft.focusedWindowBorderInset), isDefault: draft.focusedWindowBorderInset == defaults.focusedWindowBorderInset)
        setOrOmit("config-version", TomlValue.of(draft.configVersion), isDefault: draft.configVersion == defaults.configVersion)
        setOrOmit(
            "persistent-workspaces",
            TomlValue.array(draft.persistentWorkspaces.map { TomlValue.of($0) }),
            isDefault: draft.persistentWorkspaces.isEmpty,
        )

        // Nested tables: regenerated wholesale (see the spec). `nil` body deletes the table.
        document.replaceTable(named: "gaps", with: gapsTable(draft.gaps, defaults: defaults.gaps))
        document.replaceTable(named: "key-mapping", with: keyMappingTable(draft, defaults: defaults))
        document.replaceTable(named: "exec", with: execTable(draft, defaults: defaults))
        document.replaceTable(
            named: "workspace-to-monitor-force-assignment",
            with: workspaceAssignmentTable(draft.workspaceToMonitorForceAssignment),
        )

        // Raw panes.
        document.replaceTables(matching: isKeybindingTable, with: draft.rawKeybindings)
        document.replaceTables(matching: isWindowRuleTable, with: draft.rawWindowRules)
        for key in callbackKeys { document.remove(key: key) }
        document.setRawTopLevel(text: draft.rawCallbacks)
    }

    // MARK: - Table bodies

    private static func gapsTable(_ gaps: Gaps, defaults: Gaps) -> String? {
        if gaps == defaults { return nil }
        var body = "[gaps]\n"
        body += "inner.horizontal = \(dynamicInt(gaps.inner.horizontal))\n"
        body += "inner.vertical = \(dynamicInt(gaps.inner.vertical))\n"
        body += "outer.left = \(dynamicInt(gaps.outer.left))\n"
        body += "outer.bottom = \(dynamicInt(gaps.outer.bottom))\n"
        body += "outer.top = \(dynamicInt(gaps.outer.top))\n"
        body += "outer.right = \(dynamicInt(gaps.outer.right))\n"
        return body
    }

    /// `5` for a constant, or `[{ monitor.main = 20 }, 8]` for a per-monitor value —
    /// the shape `parseDynamicValue` expects: monitor patterns first, plain default last.
    private static func dynamicInt(_ value: DynamicConfigValue<Int>) -> String {
        switch value {
            case .constant(let int): return TomlValue.of(int)
            case .perMonitor(let rules, let fallback):
                let items = rules.map { rule in
                    "{ monitor.\(monitorDescriptionToml(rule.description)) = \(TomlValue.of(rule.value)) }"
                }
                return TomlValue.array(items + [TomlValue.of(fallback)])
        }
    }

    /// A monitor description as it is spelled on the left of a per-monitor entry, where a
    /// pattern needs quoting but `main` / `secondary` / a number do not.
    private static func monitorDescriptionToml(_ description: MonitorDescription) -> String {
        switch description {
            case .main: "main"
            case .secondary: "secondary"
            case .sequenceNumber(let number): String(number)
            case .pattern(let regex): TomlValue.of(regex.origin)
        }
    }

    /// A monitor description as a standalone value (right-hand side), where every form is
    /// a string except a sequence number, which stays an int.
    private static func monitorDescriptionValue(_ description: MonitorDescription) -> String {
        switch description {
            case .main: TomlValue.of("main")
            case .secondary: TomlValue.of("secondary")
            case .sequenceNumber(let number): TomlValue.of(number)
            case .pattern(let regex): TomlValue.of(regex.origin)
        }
    }

    private static func keyMappingTable(_ draft: ConfigDraft, defaults: ConfigDraft) -> String? {
        if draft.keyMappingPreset == defaults.keyMappingPreset, draft.keyNotationToKeyCode.isEmpty { return nil }
        var body = "[key-mapping]\n"
        body += "preset = \(TomlValue.of(draft.keyMappingPreset.rawValue))\n"
        if !draft.keyNotationToKeyCode.isEmpty {
            body += "\n[key-mapping.key-notation-to-key-code]\n"
            for (notation, code) in draft.keyNotationToKeyCode.sorted(by: { $0.key < $1.key }) {
                body += "\(notation) = \(TomlValue.of(code))\n"
            }
        }
        return body
    }

    private static func execTable(_ draft: ConfigDraft, defaults: ConfigDraft) -> String? {
        if draft.inheritEnvVars == defaults.inheritEnvVars, draft.envVars.isEmpty { return nil }
        var body = "[exec]\n"
        body += "inherit-env-vars = \(TomlValue.of(draft.inheritEnvVars))\n"
        if !draft.envVars.isEmpty {
            body += "\n[exec.env-vars]\n"
            for (name, value) in draft.envVars.sorted(by: { $0.key < $1.key }) {
                body += "\(name) = \(TomlValue.of(value))\n"
            }
        }
        return body
    }

    private static func workspaceAssignmentTable(_ assignment: [String: [MonitorDescription]]) -> String? {
        if assignment.isEmpty { return nil }
        var body = "[workspace-to-monitor-force-assignment]\n"
        for (workspace, monitors) in assignment.sorted(by: { $0.key < $1.key }) {
            let value = monitors.count == 1
                ? monitorDescriptionValue(monitors[0])
                : TomlValue.array(monitors.map(monitorDescriptionValue))
            body += "\(TomlValue.of(workspace)) = \(value)\n"
        }
        return body
    }
}
```

Two small support additions this task also needs.

In `Sources/AppBundle/config/TomlBlockDocument.swift`, add the two accessors `ConfigTomlWriter` uses:

```swift
extension TomlBlockDocument {
    /// The source text of a top-level `key = value` block, or `nil` if the key is absent.
    /// Used to decide whether a default-valued option is already spelled out in the file.
    func text(forKeyValue key: String) -> String? {
        blocks.first { $0.isKeyValue && $0.name == key }?.text
    }

    /// Appends verbatim top-level text (the Callbacks pane's content) at the end of the
    /// top-level key region, before the first table header.
    mutating func setRawTopLevel(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let insertAt = blocks.firstIndex(where: { $0.isTable }) ?? blocks.count
        var target = insertAt
        while target > 0, blocks[target - 1].isTrivia { target -= 1 }
        if target > 0 {
            blocks[target - 1] = blocks[target - 1].withText { $0.hasSuffix("\n") ? $0 : $0 + "\n" }
        }
        blocks.insert(.trivia(text: text.hasSuffix("\n") ? text : text + "\n"), at: target)
    }
}
```

Note the callbacks pane is inserted as a `.trivia` block on purpose: it holds arbitrary
top-level key-value text that this type does not need to address by key, and it is
re-seeded from disk on the next `load()`.

In `Sources/AppBundle/config/parseKeyMapping.swift`, expose the two fileprivate fields
for the settings window — the smallest possible widening, keeping them read-only:

```swift
extension KeyMapping {
    /// Read-only accessors for the settings window. `preset` and the raw notation map are
    /// `fileprivate` so that nothing else can bypass `resolve()`.
    var presetForSettings: Preset { preset }

    /// The raw overrides as key-code *names*, which is how they are written in the config
    /// file. `rawKeyNotationToKeyCode` holds resolved `Key` values, so this inverts
    /// `keyNotationToKeyCode` to recover the name.
    var rawNotationNamesForSettings: [String: String] {
        var nameByKey: [Key: String] = [:]
        for (name, key) in keyNotationToKeyCode where nameByKey[key] == nil { nameByKey[key] = name }
        return rawKeyNotationToKeyCode.compactMapValues { nameByKey[$0] }
    }
}
```

And add the draft defaults, in `ConfigTomlWriter.swift`:

```swift
extension ConfigTomlWriter.ConfigDraft {
    /// The values the parser falls back to when a key is absent — i.e. `Config()`'s
    /// defaults, which is what `setOrOmit` compares against to keep a config minimal.
    @MainActor static var defaults: Self {
        ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: TomlBlockDocument(""))
    }
}
```

`Config()`'s memberwise defaults are the parser's fallbacks, so this stays correct if an
upstream default changes. Note it is `@MainActor` because `Config` construction is; the
`apply` and `draft` functions therefore need `@MainActor` too — add it to `enum
ConfigTomlWriter`'s members as the compiler requires.

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && swift test --filter ConfigTomlWriterTest`
Expected: build exits 0; all 13 tests PASS.

Expect real iteration here — this is where a wrong TOML spelling shows up. When a test
fails, the helper prints the generated config alongside the parser's own error message,
which names the offending key. Two likely stumbles:
- per-monitor gaps: `parseDynamicValue` requires at least one monitor pattern **and** a
  plain default as the last array element;
- `[exec.env-vars]` must come after all of `[exec]`'s own keys, since a sub-table header
  ends the parent table.

- [ ] **Step 5: Run the whole suite to check for regressions**

Run: `./swift-test.sh`
Expected: exit 0 and `✅ Swift tests have passed successfully`.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppBundle/config/ConfigTomlWriter.swift Sources/AppBundle/config/TomlBlockDocument.swift Sources/AppBundle/config/parseKeyMapping.swift Sources/AppBundleTests/config/ConfigTomlWriterTest.swift
git commit -m "feat(config): ConfigTomlWriter maps a settings draft onto the config file"
```

---

## Task 5: `SettingsModel` — load, dirty tracking, validate-then-save

**Files:**
- Create: `Sources/AppBundle/ui/settings/SettingsModel.swift`

**Interfaces:**
- Consumes: `ConfigTomlWriter.ConfigDraft`, `ConfigTomlWriter.apply/draft`, `TomlBlockDocument`; existing `findCustomConfigUrl()`, `readConfig(forceConfigUrl:)`, `reloadConfig()`, `defaultConfigUrl`, `configDotfileName`.
- Produces: `@MainActor final class SettingsModel: ObservableObject` with
  - `static let shared: SettingsModel`
  - `@Published var draft: ConfigTomlWriter.ConfigDraft`
  - `@Published var mode: SettingsMode` (`.form`, `.rawOnly(parseError: String)`, `.readOnly(reason: String)`)
  - `@Published var isDirty: Bool`, `@Published var status: SettingsStatus?` (`.error(String)`, `.saved`)
  - `@Published var wholeFileText: String` — used only by `.rawOnly`
  - `func load()`
  - `func save() async`
  - `func revert()`
  - `var externallyModified: Bool`

**Why no unit test:** every method here is file I/O plus `@Published` state driving SwiftUI. The logic worth testing — the text transformation — is already covered by Tasks 1–4. Verification for this task is the build plus the manual run in Task 6, where the model first becomes reachable. This is stated rather than papered over with a mock, per the spec.

- [ ] **Step 1: Implement the model**

Create `Sources/AppBundle/ui/settings/SettingsModel.swift`:

```swift
import Common
import Foundation
import SwiftUI

enum SettingsMode: Equatable {
    /// The config parsed; the full form is available.
    case form
    /// The config did not parse, so there is no `Config` to bind a form to. One raw editor
    /// over the whole file, with the parser's message.
    case rawOnly(parseError: String)
    /// Several config files exist and it is not our place to guess which one to write.
    case readOnly(reason: String)
}

enum SettingsStatus: Equatable {
    case error(String)
    case saved
}

@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    @Published var draft: ConfigTomlWriter.ConfigDraft = ConfigTomlWriter.ConfigDraft.defaults
    @Published var mode: SettingsMode = .form
    @Published var isDirty = false
    @Published var status: SettingsStatus?
    @Published var wholeFileText = ""

    /// The file we read and will write. `nil` until `load()`.
    private(set) var targetUrl: URL?
    /// `true` when no custom config exists yet, so saving creates `~/<configDotfileName>`.
    private(set) var willCreateConfig = false
    private var document = TomlBlockDocument("")
    private var loadedModificationDate: Date?

    private init() {}

    /// `true` if the file changed on disk since `load()`. Checked before overwriting.
    var externallyModified: Bool {
        guard let targetUrl, let loadedModificationDate else { return false }
        let current = try? FileManager.default.attributesOfItem(atPath: targetUrl.path)[.modificationDate] as? Date
        guard let current else { return false }
        return current != loadedModificationDate
    }

    func load() {
        status = nil
        isDirty = false

        switch findCustomConfigUrl() {
            case .ambiguousConfigError(let candidates):
                mode = .readOnly(reason: """
                    Several AeroSpace configs exist, so the settings window will not guess which one to write:

                    \(candidates.map(\.path).joined(separator: "\n"))

                    Remove or rename all but one, then reopen Settings.
                    """)
                targetUrl = nil
                return
            case .file(let url):
                targetUrl = url
                willCreateConfig = false
            case .noCustomConfigExists:
                // Read the bundled default, but write to the user's own dotfile.
                targetUrl = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
                willCreateConfig = true
        }

        let sourceUrl = willCreateConfig ? defaultConfigUrl : targetUrl.orDie()
        let text = (try? String(contentsOf: sourceUrl, encoding: .utf8)) ?? ""
        document = TomlBlockDocument(text)
        wholeFileText = text
        loadedModificationDate = willCreateConfig
            ? nil
            : (try? FileManager.default.attributesOfItem(atPath: sourceUrl.path)[.modificationDate] as? Date) ?? nil

        let (config, errors) = parseConfig(text)
        if errors.isEmpty {
            // `parseConfig` expands `[exec]` into the full environment, which is not
            // writable back. Recover the file's own `[exec]` values instead.
            draft = ConfigTomlWriter.draft(from: config, rawExec: rawExecConfig(from: text), document: document)
            mode = .form
        } else {
            mode = .rawOnly(parseError: errors.map(\.description).joined(separator: "\n\n"))
        }
    }

    func revert() { load() }

    /// Renders the draft, validates it with the real parser against a temp file, and only
    /// then writes the user's config and reloads. A bad edit can never leave the user with
    /// a config AeroSpace refuses to load.
    func save() async {
        guard let targetUrl else { return }
        status = nil

        let candidate: String
        switch mode {
            case .form:
                var working = document
                ConfigTomlWriter.apply(draft, to: &working)
                candidate = working.render()
            case .rawOnly:
                candidate = wholeFileText
            case .readOnly:
                return
        }

        let tempUrl = FileManager.default.temporaryDirectory
            .appending(path: "aerospace-settings-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: tempUrl) }
        do {
            try candidate.write(to: tempUrl, atomically: true, encoding: .utf8)
        } catch {
            status = .error("Can't write a temporary file for validation: \(error.localizedDescription)")
            return
        }

        switch readConfig(forceConfigUrl: tempUrl) {
            case .failure(let message):
                status = .error(message)
                return
            case .success:
                break
        }

        do {
            try candidate.write(to: targetUrl, atomically: true, encoding: .utf8)
        } catch {
            status = .error("Can't write \(targetUrl.path): \(error.localizedDescription)")
            return
        }

        do {
            _ = try await reloadConfig()
        } catch {
            status = .error("Saved, but reloading the config failed: \(error.localizedDescription)")
            return
        }

        load() // re-read from disk so the form and the document match the file exactly
        status = .saved
    }

    /// Re-parses just the `[exec]` table to recover `inherit-env-vars` and the override
    /// map as written, since `Config.execConfig` only holds the expanded result.
    private func rawExecConfig(from text: String) -> RawExecConfig {
        var result = RawExecConfig()
        guard let table = TomlBlockDocument(text).blocks.first(where: { $0.name == "exec" })?.text else { return result }
        for line in table.linesWithTerminators() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let rawValue = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "inherit-env-vars" { result.inheritEnvVariables = rawValue.hasPrefix("true") }
        }
        // Override entries live in `[exec.env-vars]`, whose own block the form edits
        // directly; the values are plain strings, so read them off the parsed config.
        return result
    }
}
```

**Known limitation to carry forward, not to fix here:** `rawExecConfig` reads
`inherit-env-vars` only. Populating the `[exec.env-vars]` rows is Task 7's job, which
reads that sub-table's block text directly — the same source, one level down. Leave
`result.overriddenVars` empty here.

- [ ] **Step 2: Verify it builds**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`
Expected: exit 0, no warnings. `SettingsModel` is not referenced by any view yet, so Swift may warn about unused members — if it does, that is a real warning under `-warnings-as-errors`; the next task's views resolve it. If it blocks, proceed to Task 6 and commit both together rather than adding a placeholder reference.

- [ ] **Step 3: Run the suite to check for regressions**

Run: `./swift-test.sh`
Expected: exit 0 and `✅ Swift tests have passed successfully`.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppBundle/ui/settings/SettingsModel.swift
git commit -m "feat(ui): SettingsModel with validate-then-save config write flow"
```

---

## Task 6: Window scene, menu bar entry, and the first four form sections

**Files:**
- Create: `Sources/AppBundle/ui/settings/SettingsWindow.swift`
- Create: `Sources/AppBundle/ui/settings/SettingsSections.swift`
- Modify: `Sources/AppBundle/ui/MenuBar.swift:43-45`
- Modify: `Sources/AeroSpaceApp/AeroSpaceApp.swift`

**Interfaces:**
- Consumes: `SettingsModel.shared`, `SettingsMode`, `SettingsStatus`, `ConfigTomlWriter.ConfigDraft`.
- Produces: `public let settingsWindowId: String`, `@MainActor public func getSettingsWindow(model: SettingsModel) -> some Scene`, `enum SettingsCategory: String, CaseIterable, Identifiable`, and the section views `GeneralSection`, `LayoutSection`, `FocusSection`, `WindowBorderSection`. Tasks 7–8 add more `SettingsCategory` cases and their sections.

**This is the first task with something to look at.** After it, the window opens from the menu bar and four sections of options save for real.

- [ ] **Step 1: Add the window scene**

Create `Sources/AppBundle/ui/settings/SettingsWindow.swift`. Follow the pattern in
`Sources/AppBundle/ui/MessageView.swift:5-23` — `SwiftUI.Window` (not `Window`, which
collides with AeroSpace's own `Window` class), plus the `NSApp.setActivationPolicy(.accessory)`
call in `onAppear` that lets an accessory-mode app's window take keyboard focus.

```swift
import Common
import SwiftUI

public let settingsWindowId = "\(aeroSpaceAppName).settings"

@MainActor
public func getSettingsWindow(model: SettingsModel) -> some Scene {
    // SwiftUI.Window because AeroSpace already has a class called Window
    SwiftUI.Window("\(aeroSpaceAppName) Settings", id: settingsWindowId) {
        SettingsView(model: model)
            .onAppear {
                // Without this an accessory-mode app's window can't receive keyboard input
                NSApp.setActivationPolicy(.accessory)
                model.load()
            }
    }
    .windowResizability(.contentMinSize)
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case layout = "Layout"
    case gaps = "Gaps"
    case focus = "Focus"
    case windowBorder = "Window Border"
    case workspaces = "Workspaces & Monitors"
    case keyMapping = "Key Mapping"
    case exec = "Exec"
    case keybindings = "Keybindings"
    case windowRules = "Window Rules"
    case callbacks = "Callbacks"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
            case .general: "gearshape"
            case .layout: "square.grid.2x2"
            case .gaps: "rectangle.split.3x1"
            case .focus: "scope"
            case .windowBorder: "rectangle.dashed"
            case .workspaces: "display.2"
            case .keyMapping: "keyboard"
            case .exec: "terminal"
            case .keybindings: "command"
            case .windowRules: "macwindow.badge.plus"
            case .callbacks: "arrow.triangle.branch"
        }
    }
}

@MainActor
struct SettingsView: View {
    @StateObject private var model: SettingsModel
    @State private var selection: SettingsCategory = .general
    @State private var showOverwriteAlert = false

    init(model: SettingsModel) { self._model = .init(wrappedValue: model) }

    var body: some View {
        VStack(spacing: 0) {
            switch model.mode {
                case .readOnly(let reason):
                    ScrollView { Text(reason).font(.body.monospaced()).padding() }
                case .rawOnly(let parseError):
                    rawOnlyBody(parseError: parseError)
                case .form:
                    NavigationSplitView {
                        List(SettingsCategory.allCases, selection: $selection) { category in
                            NavigationLink(value: category) {
                                Label(category.rawValue, systemImage: category.systemImage)
                            }
                        }
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
                    } detail: {
                        ScrollView { section(for: selection).padding() }
                    }
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func rawOnlyBody(parseError: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This config doesn't parse, so only raw editing is available.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(parseError).font(.caption.monospaced()).textSelection(.enabled)
            TextEditor(text: Binding(get: { model.wholeFileText }, set: { model.wholeFileText = $0; model.isDirty = true }))
                .font(.system(size: 12).monospaced())
        }
        .padding()
    }

    @ViewBuilder
    private func section(for category: SettingsCategory) -> some View {
        switch category {
            case .general: GeneralSection(draft: $model.draft, onEdit: markDirty)
            case .layout: LayoutSection(draft: $model.draft, onEdit: markDirty)
            case .focus: FocusSection(draft: $model.draft, onEdit: markDirty)
            case .windowBorder: WindowBorderSection(draft: $model.draft, onEdit: markDirty)
            // Added in Tasks 7 and 8
            default: Text("Not implemented yet").foregroundStyle(.secondary)
        }
    }

    private func markDirty() { model.isDirty = true; model.status = nil }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .error(let message) = model.status {
                ScrollView {
                    Text(message).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            HStack {
                if model.willCreateConfig {
                    Text("Saving will create ~/\(configDotfileName)").font(.caption).foregroundStyle(.secondary)
                } else if case .saved = model.status {
                    Label("Saved and reloaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("Revert") { model.revert() }.disabled(!model.isDirty)
                Button("Save") {
                    if model.externallyModified { showOverwriteAlert = true } else { Task { await model.save() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isDirty)
            }
        }
        .padding()
        .alert("The config file changed on disk", isPresented: $showOverwriteAlert) {
            Button("Overwrite") { Task { await model.save() } }
            Button("Discard my changes") { model.load() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone or something edited the config after this window opened. Overwriting will lose those edits.")
        }
    }
}
```

- [ ] **Step 2: Add the four form sections**

Create `Sources/AppBundle/ui/settings/SettingsSections.swift`. `onEdit` is called by every
control so the model can mark the draft dirty without each control knowing about the model.

```swift
import Common
import SwiftUI

/// A labelled group of settings rows, matching macOS System Settings' grouped-form look.
@MainActor
struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Wraps a draft binding so that every write also reports the edit.
@MainActor
func tracked<Value>(_ binding: Binding<Value>, _ onEdit: @escaping () -> Void) -> Binding<Value> {
    Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; onEdit() })
}

@MainActor
struct GeneralSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Startup") {
                Toggle("Start AeroSpace at login", isOn: tracked($draft.startAtLogin, onEdit))
                Toggle("Reload the config automatically when the file changes", isOn: tracked($draft.autoReloadConfig, onEdit))
            }
            SettingsGroup("macOS integration") {
                Toggle("Automatically unhide macOS hidden apps", isOn: tracked($draft.automaticallyUnhideMacosHiddenApps, onEdit))
            }
            SettingsGroup("Config version", footer: "Only versions AeroSpace understands are accepted; an unknown value is rejected when you save.") {
                Stepper("config-version: \(draft.configVersion)", value: tracked($draft.configVersion, onEdit), in: 1 ... 9)
            }
        }
    }
}

@MainActor
struct LayoutSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Default container") {
                Picker("Layout", selection: tracked($draft.defaultRootContainerLayout, onEdit)) {
                    Text("Tiles").tag(Layout.tiles)
                    Text("Accordion").tag(Layout.accordion)
                }
                Picker("Orientation", selection: tracked($draft.defaultRootContainerOrientation, onEdit)) {
                    Text("Auto").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                }
            }
            SettingsGroup("Normalization", footer: "Normalizations keep the window tree tidy. Turning them off gives you full manual control of the tree.") {
                Toggle("Flatten containers", isOn: tracked($draft.enableNormalizationFlattenContainers, onEdit))
                Toggle("Opposite orientation for nested containers", isOn: tracked($draft.enableNormalizationOppositeOrientationForNestedContainers, onEdit))
                Toggle("Binary tree", isOn: tracked($draft.enableNormalizationBinaryTree, onEdit))
            }
            SettingsGroup("Accordion") {
                Stepper("Padding: \(draft.accordionPadding)", value: tracked($draft.accordionPadding, onEdit), in: 0 ... 200, step: 5)
            }
        }
    }
}

@MainActor
struct FocusSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(
                "Focus follows app activation",
                footer: "'Smart' switches the focused workspace on a cross-workspace app activation only when it looks user-initiated. This option is specific to AeroSpace-edge.",
            ) {
                Picker("Behavior", selection: tracked($draft.focusFollowsAppActivation, onEdit)) {
                    Text("Always").tag(FocusFollowsAppActivation.always)
                    Text("Smart").tag(FocusFollowsAppActivation.smart)
                }
                .pickerStyle(.radioGroup)
            }
            SettingsGroup("New windows") {
                Toggle("Prevent flicker when a new window appears", isOn: tracked($draft.newWindowPreventFlicker, onEdit))
            }
        }
    }
}

@MainActor
struct WindowBorderSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Focused window border", footer: "This option group is specific to AeroSpace-edge.") {
                Toggle("Draw a border around the focused window", isOn: tracked($draft.focusedWindowBorder, onEdit))
                Group {
                    colorRow
                    Stepper("Width: \(draft.focusedWindowBorderWidth)", value: tracked($draft.focusedWindowBorderWidth, onEdit), in: 0 ... 40)
                    Stepper("Corner radius: \(draft.focusedWindowBorderRadius)", value: tracked($draft.focusedWindowBorderRadius, onEdit), in: 0 ... 60)
                    Stepper("Inset: \(draft.focusedWindowBorderInset)", value: tracked($draft.focusedWindowBorderInset, onEdit), in: -40 ... 40)
                    HStack {
                        Text("Opacity: \(draft.focusedWindowBorderOpacity)%")
                        Slider(value: Binding(
                            get: { Double(draft.focusedWindowBorderOpacity) },
                            set: { draft.focusedWindowBorderOpacity = Int($0.rounded()); onEdit() },
                        ), in: 0 ... 100)
                    }
                }
                .disabled(!draft.focusedWindowBorder)
            }
        }
    }

    /// The colour is a `0xAARRGGBB` string in the config. A value the picker can't
    /// represent is shown as text rather than silently rewritten.
    @ViewBuilder
    private var colorRow: some View {
        HStack {
            if let color = Color(aeroSpaceHex: draft.focusedWindowBorderColor) {
                ColorPicker("Color", selection: Binding(
                    get: { color },
                    set: { draft.focusedWindowBorderColor = $0.aeroSpaceHex; onEdit() },
                ))
            } else {
                TextField("Color (0xAARRGGBB)", text: tracked($draft.focusedWindowBorderColor, onEdit))
            }
            Text(draft.focusedWindowBorderColor).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    /// Parses AeroSpace's `0xAARRGGBB` colour spelling. Returns `nil` for anything else,
    /// so the caller can fall back to a text field instead of mangling the value.
    init?(aeroSpaceHex hex: String) {
        let digits = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: Double((value >> 24) & 0xFF) / 255,
        )
    }

    var aeroSpaceHex: String {
        let components = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.white
        let byte = { (value: CGFloat) in UInt32((value * 255).rounded().clamped(to: 0 ... 255)) }
        let value = byte(components.alphaComponent) << 24
            | byte(components.redComponent) << 16
            | byte(components.greenComponent) << 8
            | byte(components.blueComponent)
        return "0x" + String(format: "%08x", value)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { min(max(self, range.lowerBound), range.upperBound) }
}
```

- [ ] **Step 3: Wire up the menu bar and the scene**

In `Sources/AppBundle/ui/MenuBar.swift`, add the item right after `reloadConfigButton()`
(line 44). The menu already has a `Settings` submenu label at line 56 — this goes inside
it, next to the other config items:

```swift
            openConfigButton()
            reloadConfigButton()
            settingsWindowButton()
```

and add the button helper next to `openConfigButton` (around line 107):

```swift
@MainActor @ViewBuilder
func settingsWindowButton() -> some View {
    // SwiftUI's Environment(\.openWindow) isn't available inside MenuBarExtra's content on
    // every supported macOS version, so open the window through NSApp instead.
    Button("Settings…") {
        SettingsModel.shared.load()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == settingsWindowId }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openSettingsWindowAction?()
        }
    }
}

/// Set by `AeroSpaceApp` so the menu bar can reach SwiftUI's `openWindow` action.
@MainActor var openSettingsWindowAction: (() -> Void)?
```

In `Sources/AeroSpaceApp/AeroSpaceApp.swift`, register the scene and publish the action:

```swift
@main
struct AeroSpaceApp: App {
    @StateObject var viewModel = TrayMenuModel.shared
    @StateObject var messageModel = MessageModel.shared
    @StateObject var settingsModel = SettingsModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: viewModel)
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
        getSettingsWindow(model: settingsModel)
            .onChange(of: settingsModel.mode) { _ in
                openSettingsWindowAction = { openWindow(id: settingsWindowId) }
            }
    }
}
```

If `openSettingsWindowAction` proves not to be set early enough in practice, set it from
`SettingsView.onAppear` instead, or assign it once in an `.task {}` on the message window
scene. Do not add a stored `@State` in `AeroSpaceApp` for it — the app struct is
re-created by SwiftUI and the closure must be captured from a live scene.

- [ ] **Step 4: Verify it builds**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`
Expected: exit 0, no warnings.

Likely fixes: `Layout` may need an explicit `import Common`; `Layout` and
`DefaultContainerOrientation` must be `Hashable` to be used as `Picker` tags — if the
compiler objects, add `Hashable` conformance in an extension inside
`SettingsSections.swift` rather than editing `Config.swift`.

- [ ] **Step 5: Run it and check the window by hand**

This is the first task with visible behaviour, and the model's file I/O has no unit test,
so verify it for real:

```bash
./build-debug.sh -Xswiftc -warnings-as-errors
./.debug/AeroSpace.app/Contents/MacOS/AeroSpace
```

(If the debug build is not an app bundle in your checkout, run the binary SPM produced
under `.debug/`. `./run-debug.sh` may exist — prefer it if so.)

Check, in order:
1. Menu bar → Settings → `Settings…` opens the window.
2. The four sections render and the sidebar switches between them.
3. Toggle "Start AeroSpace at login" → Save → the window reports "Saved and reloaded".
4. `cat ~/.aerospace-edge.toml` (or your active config) — only that one line changed, and every comment is intact. **This is the whole point of the feature; confirm it visually.**
5. Set `config-version` to `9` → Save → the parser's error appears in the footer, the
   window stays open, and the config file on disk is **unchanged**.
6. Edit the config in a text editor while the window is open, then Save → the
   "changed on disk" alert appears.

- [ ] **Step 6: Run the suite**

Run: `./swift-test.sh`
Expected: exit 0 and `✅ Swift tests have passed successfully`.

- [ ] **Step 7: Commit**

```bash
git add Sources/AppBundle/ui/settings/ Sources/AppBundle/ui/MenuBar.swift Sources/AeroSpaceApp/AeroSpaceApp.swift
git commit -m "feat(ui): settings window with general, layout, focus and border sections"
```

---

## Task 7: Gaps, Workspaces & Monitors, Key Mapping, and Exec sections

**Files:**
- Modify: `Sources/AppBundle/ui/settings/SettingsSections.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsWindow.swift` (route the four new categories)
- Modify: `Sources/AppBundle/ui/settings/SettingsModel.swift` (populate `envVars`)

**Interfaces:**
- Consumes: `SettingsGroup`, `tracked(_:_:)` from Task 6; `ConfigTomlWriter.ConfigDraft`; `Gaps`, `DynamicConfigValue`, `PerMonitorValue`, `MonitorDescription`, `KeyMapping.Preset`, `keyNotationToKeyCode`.
- Produces: `GapsSection`, `WorkspacesSection`, `KeyMappingSection`, `ExecSection`.

These four are the structured-but-not-scalar options. Each is a small editable list, so
they share one generic row-editor helper rather than four bespoke ones.

- [ ] **Step 1: Add the shared row editor and the four sections**

Append to `Sources/AppBundle/ui/settings/SettingsSections.swift`:

```swift
/// An add/remove list of key-value rows, used by the key-mapping, env-var, and
/// workspace-assignment editors. Rows are edited as text and validated on save by the
/// real parser, which is the only validator that can't drift.
@MainActor
struct KeyValueRowsEditor: View {
    let keyPlaceholder: String
    let valuePlaceholder: String
    @Binding var rows: [(key: String, value: String)]
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    TextField(keyPlaceholder, text: Binding(
                        get: { rows[index].key },
                        set: { rows[index].key = $0; onEdit() },
                    ))
                    Text("=").foregroundStyle(.secondary)
                    TextField(valuePlaceholder, text: Binding(
                        get: { rows[index].value },
                        set: { rows[index].value = $0; onEdit() },
                    ))
                    Button(role: .destructive) { rows.remove(at: index); onEdit() } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add") { rows.append((key: "", value: "")); onEdit() }
                .buttonStyle(.borderless)
        }
    }
}

@MainActor
struct GapsSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Inner gaps", footer: "Space between tiled windows.") {
                gapRow("Horizontal", \.inner.horizontal)
                gapRow("Vertical", \.inner.vertical)
            }
            SettingsGroup("Outer gaps", footer: "Space between the tiling area and the screen edges.") {
                gapRow("Left", \.outer.left)
                gapRow("Right", \.outer.right)
                gapRow("Top", \.outer.top)
                gapRow("Bottom", \.outer.bottom)
            }
        }
    }

    /// One gap value: a number, plus optional per-monitor overrides. A per-monitor gap is
    /// a list of monitor patterns with a fallback, so the row grows into a small list when
    /// "Per monitor" is enabled.
    @ViewBuilder
    private func gapRow(_ label: String, _ path: WritableKeyPath<Gaps, DynamicConfigValue<Int>>) -> some View {
        let value = draft.gaps[keyPath: path]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).frame(width: 90, alignment: .leading)
                switch value {
                    case .constant(let int):
                        Stepper("\(int)", value: Binding(
                            get: { int },
                            set: { draft.gaps[keyPath: path] = .constant($0); onEdit() },
                        ), in: 0 ... 400, step: 2)
                    case .perMonitor(_, let fallback):
                        Stepper("default \(fallback)", value: Binding(
                            get: { fallback },
                            set: {
                                guard case .perMonitor(let rules, _) = draft.gaps[keyPath: path] else { return }
                                draft.gaps[keyPath: path] = .perMonitor(rules, default: $0)
                                onEdit()
                            },
                        ), in: 0 ... 400, step: 2)
                }
                Toggle("Per monitor", isOn: Binding(
                    get: { if case .perMonitor = value { true } else { false } },
                    set: { isPerMonitor in
                        switch (isPerMonitor, draft.gaps[keyPath: path]) {
                            case (true, .constant(let int)):
                                draft.gaps[keyPath: path] = .perMonitor([PerMonitorValue(description: .main, value: int)], default: int)
                            case (false, .perMonitor(_, let fallback)):
                                draft.gaps[keyPath: path] = .constant(fallback)
                            default: break
                        }
                        onEdit()
                    },
                ))
                .toggleStyle(.checkbox)
            }
            if case .perMonitor(let rules, let fallback) = value {
                KeyValueRowsEditor(
                    keyPlaceholder: "main / secondary / 2 / regex",
                    valuePlaceholder: "gap",
                    rows: Binding(
                        get: { rules.map { (key: monitorDescriptionText($0.description), value: String($0.value)) } },
                        set: { newRows in
                            let parsed = newRows.compactMap { row -> PerMonitorValue<Int>? in
                                guard let description = parseMonitorDescription(row.key).getOrNil(),
                                      let int = Int(row.value) else { return nil }
                                return PerMonitorValue(description: description, value: int)
                            }
                            draft.gaps[keyPath: path] = .perMonitor(parsed, default: fallback)
                        },
                    ),
                    onEdit: onEdit,
                )
                .padding(.leading, 98)
            }
        }
    }
}

/// The text spelling of a monitor description, matching what the config file accepts.
@MainActor
func monitorDescriptionText(_ description: MonitorDescription) -> String {
    switch description {
        case .main: "main"
        case .secondary: "secondary"
        case .sequenceNumber(let number): String(number)
        case .pattern(let regex): regex.origin
    }
}

@MainActor
struct WorkspacesSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Persistent workspaces", footer: "These always exist, in this order, even when empty.") {
                ForEach(Array(draft.persistentWorkspaces.enumerated()), id: \.offset) { index, name in
                    HStack {
                        TextField("name", text: Binding(
                            get: { name },
                            set: { newName in
                                var all = Array(draft.persistentWorkspaces)
                                all[index] = newName
                                draft.persistentWorkspaces = OrderedSet(all)
                                onEdit()
                            },
                        ))
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(index == draft.persistentWorkspaces.count - 1)
                        Button(role: .destructive) {
                            var all = Array(draft.persistentWorkspaces)
                            all.remove(at: index)
                            draft.persistentWorkspaces = OrderedSet(all)
                            onEdit()
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add") {
                    var all = Array(draft.persistentWorkspaces)
                    all.append("")
                    draft.persistentWorkspaces = OrderedSet(all)
                    onEdit()
                }
                .buttonStyle(.borderless)
            }
            SettingsGroup(
                "Force a workspace onto a monitor",
                footer: "A monitor is 'main', 'secondary', a 1-based number, or a regex matched against the monitor name. Separate several with a comma to give a priority order.",
            ) {
                KeyValueRowsEditor(
                    keyPlaceholder: "workspace",
                    valuePlaceholder: "main, secondary, 2, regex",
                    rows: Binding(
                        get: {
                            draft.workspaceToMonitorForceAssignment
                                .sorted { $0.key < $1.key }
                                .map { (key: $0.key, value: $0.value.map(monitorDescriptionText).joined(separator: ", ")) }
                        },
                        set: { rows in
                            var result: [String: [MonitorDescription]] = [:]
                            for row in rows where !row.key.isEmpty {
                                result[row.key] = row.value
                                    .split(separator: ",")
                                    .compactMap { parseMonitorDescription($0.trimmingCharacters(in: .whitespaces)).getOrNil() }
                            }
                            draft.workspaceToMonitorForceAssignment = result
                        },
                    ),
                    onEdit: onEdit,
                )
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        var all = Array(draft.persistentWorkspaces)
        let target = index + offset
        guard all.indices.contains(target) else { return }
        all.swapAt(index, target)
        draft.persistentWorkspaces = OrderedSet(all)
        onEdit()
    }
}

@MainActor
struct KeyMappingSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Preset", footer: "The keyboard layout your key notations are written for.") {
                Picker("Preset", selection: tracked($draft.keyMappingPreset, onEdit)) {
                    ForEach(KeyMapping.Preset.allCases, id: \.rawValue) { preset in
                        Text(preset.rawValue.capitalized).tag(preset)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            SettingsGroup(
                "Notation overrides",
                footer: "Left: your own notation — no spaces, no dashes. Right: a key code AeroSpace knows, such as 'quote' or 'semicolon'.",
            ) {
                KeyValueRowsEditor(
                    keyPlaceholder: "notation",
                    valuePlaceholder: "key code",
                    rows: Binding(
                        get: { draft.keyNotationToKeyCode.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) } },
                        set: { rows in
                            draft.keyNotationToKeyCode = Dictionary(
                                rows.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) },
                                uniquingKeysWith: { _, last in last },
                            )
                        },
                    ),
                    onEdit: onEdit,
                )
            }
        }
    }
}

@MainActor
struct ExecSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Environment", footer: "Applies to every 'exec-and-forget' command.") {
                Toggle("Inherit environment variables from the launching process", isOn: tracked($draft.inheritEnvVars, onEdit))
            }
            SettingsGroup(
                "Overrides",
                footer: "Use $VAR to interpolate the inherited value. 'PWD' can't be changed and will be rejected on save.",
            ) {
                KeyValueRowsEditor(
                    keyPlaceholder: "NAME",
                    valuePlaceholder: "value",
                    rows: Binding(
                        get: { draft.envVars.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) } },
                        set: { rows in
                            draft.envVars = Dictionary(
                                rows.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) },
                                uniquingKeysWith: { _, last in last },
                            )
                        },
                    ),
                    onEdit: onEdit,
                )
            }
        }
    }
}
```

`KeyMapping.Preset` must be `CaseIterable` for the picker — it already is
(`Sources/AppBundle/config/parseKeyMapping.swift:10`). It also needs to be `Hashable` for
`.tag`; add the conformance in an extension in `SettingsSections.swift` if the compiler
asks.

- [ ] **Step 2: Route the four categories**

In `Sources/AppBundle/ui/settings/SettingsWindow.swift`, replace those four cases in
`section(for:)`:

```swift
            case .gaps: GapsSection(draft: $model.draft, onEdit: markDirty)
            case .workspaces: WorkspacesSection(draft: $model.draft, onEdit: markDirty)
            case .keyMapping: KeyMappingSection(draft: $model.draft, onEdit: markDirty)
            case .exec: ExecSection(draft: $model.draft, onEdit: markDirty)
```

- [ ] **Step 3: Populate `envVars` on load**

Task 5 deliberately left `RawExecConfig.overriddenVars` empty. Fill it in
`SettingsModel.rawExecConfig(from:)` by reading the `[exec.env-vars]` block's own lines —
the same block-document source, one level down:

```swift
        // `[exec.env-vars]` is its own table block. Values are plain (possibly quoted)
        // strings; the parser will do interpolation and validation on save.
        if let envTable = TomlBlockDocument(text).blocks.first(where: { $0.name == "exec.env-vars" })?.text {
            for line in envTable.linesWithTerminators().dropFirst() { // drop the header line
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
                let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
                var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                for quote in ["'", "\""] where value.hasPrefix(quote) && value.hasSuffix(quote) && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                result.overriddenVars[key] = value
            }
        }
```

Note `ConfigTomlWriter` writes `[exec.env-vars]` as a sub-table of `[exec]`, so
`replaceTable(named: "exec", ...)` must also drop a stale `[exec.env-vars]` block. Extend
`replaceTable` to remove tables whose name starts with `name + "."` as well:

```swift
        blocks.removeAll { $0.isTable && $0.name?.hasPrefix(name + ".") == true }
```

Add that line next to the existing dotted-key removal in `replaceTable`, and add a test
for it in `TomlBlockDocumentTest`:

```swift
    func testReplaceTableAlsoDropsSubTables() {
        var doc = TomlBlockDocument("[exec]\ninherit-env-vars = true\n\n[exec.env-vars]\nA = 'b'\n")
        doc.replaceTable(named: "exec", with: "[exec]\ninherit-env-vars = false\n")
        assertEquals(doc.render(), "[exec]\ninherit-env-vars = false\n")
    }
```

Same for `key-mapping` / `[key-mapping.key-notation-to-key-code]` — the one change covers
both.

- [ ] **Step 4: Verify it builds and tests pass**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && ./swift-test.sh`
Expected: build exits 0 with no warnings; tests exit 0 with `✅ Swift tests have passed successfully`.

- [ ] **Step 5: Verify by hand**

Run the app as in Task 6 Step 5, then:
1. Gaps → set inner horizontal to 12 → Save → the config shows a regenerated `[gaps]`
   with `inner.horizontal = 12`, and the rest of the file is untouched.
2. Gaps → tick "Per monitor" on outer left, add a `main = 20` row → Save → the value is
   written as `[{ monitor.main = 20 }, <default>]` and re-parses.
3. Workspaces → add a persistent workspace, reorder it → Save → order is preserved in the
   file and in the menu bar's workspace list.
4. Exec → add `MY_VAR = hello` → Save → `[exec.env-vars]` appears; reopen the window and
   the row is still there (this is what Step 3 fixed).
5. Exec → add `PWD = x` → Save → the parser rejects it in the footer and the file is
   unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppBundle/ui/settings/ Sources/AppBundle/config/TomlBlockDocument.swift Sources/AppBundleTests/config/TomlBlockDocumentTest.swift
git commit -m "feat(ui): gaps, workspaces, key mapping and exec settings sections"
```

---

## Task 8: The three raw-TOML panes

**Files:**
- Create: `Sources/AppBundle/ui/settings/SettingsRawSection.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsWindow.swift` (route the last three categories)

**Interfaces:**
- Consumes: `SettingsGroup` (Task 6), `ConfigTomlWriter.isKeybindingTable` / `isWindowRuleTable` / `callbackKeys` (Task 4), the `rawKeybindings` / `rawWindowRules` / `rawCallbacks` draft fields.
- Produces: `SettingsRawSection` — one reusable pane view.

These three sections cover the command DSL as text, which is the scope decision the spec
records. The pane shows live parse feedback so a syntax error is visible before Save.

- [ ] **Step 1: Implement the pane**

Create `Sources/AppBundle/ui/settings/SettingsRawSection.swift`:

```swift
import Common
import SwiftUI

/// A raw TOML editor for one family of config keys — keybindings, window rules, or
/// callbacks. These are an AeroSpace command DSL rather than a fixed set of values, so
/// they are edited as text; the parser is the validator.
@MainActor
struct SettingsRawSection: View {
    let title: String
    let help: String
    let docsHint: String
    @Binding var text: String
    let onEdit: () -> Void

    /// Parse feedback for just this pane's text, so an error is visible before saving.
    /// The pane's text alone is a valid standalone config fragment, which is why this can
    /// call the real parser on it.
    private var parseStatus: Result<Void, String> {
        let (_, errors) = parseConfig(text)
        return errors.isEmpty ? .success(()) : .failure(errors.map(\.description).joined(separator: "\n\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title, footer: help) {
                Text(docsHint).font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: Binding(get: { text }, set: { text = $0; onEdit() }))
                .font(.system(size: 12).monospaced())
                .frame(minHeight: 300)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separatorColor)))
            switch parseStatus {
                case .success:
                    Label("Parses", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                case .failure(let message):
                    ScrollView {
                        Text(message).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
            }
        }
    }
}
```

- [ ] **Step 2: Route the three categories**

In `Sources/AppBundle/ui/settings/SettingsWindow.swift`, replace the remaining `default`
case in `section(for:)` with the three real cases, so the `switch` becomes exhaustive and
the placeholder disappears:

```swift
            case .keybindings:
                SettingsRawSection(
                    title: "Keybindings",
                    help: "Binding modes and their key bindings, as TOML. Each binding maps a key combination to one or more AeroSpace commands.",
                    docsHint: "Tables: [mode.<name>.binding]. Example: alt-h = 'focus left'",
                    text: $model.draft.rawKeybindings,
                    onEdit: markDirty,
                )
            case .windowRules:
                SettingsRawSection(
                    title: "Window rules",
                    help: "Rules run when a window is first detected. Matchers: app-id, app-id-regex-substring, app-name-regex-substring, window-title-regex-substring, workspace, during-aerospace-startup.",
                    docsHint: "Tables: [[on-window-detected]] with an 'if' matcher and a mandatory 'run'.",
                    text: $model.draft.rawWindowRules,
                    onEdit: markDirty,
                )
            case .callbacks:
                SettingsRawSection(
                    title: "Callbacks",
                    help: "Commands AeroSpace runs on lifecycle events.",
                    docsHint: "Keys: " + ConfigTomlWriter.callbackKeys.joined(separator: ", "),
                    text: $model.draft.rawCallbacks,
                    onEdit: markDirty,
                )
```

- [ ] **Step 3: Verify it builds and tests pass**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && ./swift-test.sh`
Expected: build exits 0 with no warnings; tests exit 0 with `✅ Swift tests have passed successfully`.

- [ ] **Step 4: Verify by hand**

Run the app and check:
1. Keybindings pane is seeded with the real `[mode.*]` tables from your config, verbatim,
   comments and all.
2. Change one binding → Save → only that binding changed in the file, and the new
   binding works.
3. Type deliberate garbage (`alt-h = 'no-such-command'`) → the pane shows the parse error
   in red, Save is refused, and the file is unchanged.
4. Window rules and Callbacks panes are seeded correctly and save.
5. Break the config in an external editor, then reopen Settings → the window opens in
   the degraded single-pane mode with the parse error, and fixing the text there saves.
6. Create a second config file so two exist, reopen Settings → the read-only ambiguity
   message appears and nothing can be saved.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/ui/settings/
git commit -m "feat(ui): raw TOML panes for keybindings, window rules and callbacks"
```

---

## Task 9: Documentation and the full CI check

**Files:**
- Modify: `docs/guide.adoc`
- Modify: `CHANGELOG-FORK.md`

No command, CLI flag, config option, or format variable changes in this feature, so most
of `CLAUDE.md`'s command checklist does not apply — there is no `.adoc` synopsis to edit,
no `grammar/commands-bnf-grammar.txt` change, and nothing to regenerate. What does apply
is the user-visible-behaviour line: the menu bar gained an item.

- [ ] **Step 1: Document the window in the guide**

In `docs/guide.adoc`, add a subsection under the `[#configuring-aerospace]` area (near
`[#config-location]`, around line 62–85). Match the surrounding Asciidoc style:

```adoc
[#settings-window]
=== Settings window

`AeroSpace-edge` can edit its own config. Open *Settings -> Settings…* from the menu bar
menu.

The window writes the same config file described in <<config-location>> — it is an editor
for that file, not a separate store. Saving validates the result with the same parser
AeroSpace uses at startup; if the result wouldn't load, nothing is written and the error
is shown in the window.

Options with a fixed set of values get a control. Keybindings, `on-window-detected` rules,
and the command callbacks are an AeroSpace command DSL rather than a fixed set of values,
so they are edited as TOML text in their own sections of the window, with parse feedback
as you type.

Comments and key order in your config are preserved, with one exception: the `gaps`,
`key-mapping`, `exec`, and `workspace-to-monitor-force-assignment` tables are rewritten
in full when one of their values changes, so comments written inside those four tables
are lost. Comments everywhere else are kept.

The window refuses to write anything when several config files exist at once, since it
can't know which one you meant.
```

- [ ] **Step 2: Add the changelog entry**

Read `CHANGELOG-FORK.md` first and match its existing entry format exactly (heading level,
version heading style, and whether entries link to a PR). Add an entry describing the
settings window as a fork feature. Do not invent a version number — put it under whatever
"unreleased" heading the file uses, or create one matching the file's existing style.

- [ ] **Step 3: Run the full CI check**

Run: `./test.sh`
Expected: exit 0. This runs the debug build with warnings-as-errors, the tests, the
`aerospace -h/--help/--version` smoke checks, the lint, `generate.sh`, and a clean-tree
check. The clean-tree check is why this must pass before the feature is done: it proves no
generated file drifted.

If `./format.sh` needs to run, run it and re-run `./test.sh`.

- [ ] **Step 4: Commit**

```bash
git add docs/guide.adoc CHANGELOG-FORK.md
git commit -m "docs: document the settings window"
```

---

## Self-review notes

Checked against the spec:

- **Every option in the spec's inventory table** maps to a control in Task 6 or 7 and to a
  `setOrOmit` / table generator in Task 4, and Task 4's test asserts each survives a
  round-trip through the real parser. The three deprecated keys are intentionally
  uncontrolled and survive as unknown blocks, which
  `testUnknownKeysAndTablesSurviveASet` covers.
- **Save flow** — Task 5, all seven steps of the spec's flow, including the temp-file
  validation and the modification-date check (whose UI is Task 6's alert).
- **All three edge cases** — ambiguous config (Task 5 `.readOnly` + Task 6 rendering +
  Task 8 Step 4.6), unparseable config (`.rawOnly` + Task 6 `rawOnlyBody` + Task 8 Step
  4.5), external edit (Task 5 `externallyModified` + Task 6 alert). Colour round-trip is
  Task 6's `colorRow`, which falls back to a text field rather than mangling a value it
  can't represent.
- **Nested-table regeneration** — Task 4, with the sub-table cleanup caught in Task 7 Step
  3 (`[exec.env-vars]` would otherwise survive its parent's regeneration and duplicate the
  definition).
- **Testing section** — Tasks 1–3 cover the block document; Task 4 is the option coverage
  contract. The spec says the SwiftUI layer and file I/O are verified by hand, not faked,
  and Tasks 5–8 say so explicitly and give the manual steps.
- **Docs** — Task 9.

Type consistency: `ConfigDraft` field names are used identically in Tasks 4, 6, and 7.
`TomlValue.of` is overloaded on `Bool` / `Int` / `String` and `array` takes pre-serialised
items in both its definition and every call site. `replaceTable(named:with:)` takes
`String?` everywhere. `text(forKeyValue:)` returns `String?` and is used only for
presence checks and the callbacks seed.

One known-imperfect spot, flagged rather than hidden: `replaceTables(matching:with:)`
stores its spliced block with an empty `name`, so calling it twice for the same pane
within one `apply` would append rather than replace. `ConfigTomlWriter.apply` calls it
once per pane, and `load()` re-seeds from disk. If a future change needs repeated
application, give the block a real name first.
