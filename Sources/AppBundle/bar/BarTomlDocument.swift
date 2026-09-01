import Common
import Foundation
import OrderedCollections
import TOMLDecoder

enum BarTomlError: Error, CustomStringConvertible, Equatable {
    /// The file is not valid TOML at all.
    case syntax(_ message: String)
    /// The file parses, but a value is missing or of the wrong shape.
    case semantic(_ message: String)

    var description: String {
        switch self {
            case .syntax(let message): "Failed to parse bar.toml: \(message)"
            case .semantic(let message): message
        }
    }
}

/// `~/.config/aerospace/bar.toml`, read as a `BarDraft` and written back so that every
/// region the editor did not touch comes back byte for byte — comments, key order, and
/// keys this app does not model included.
///
/// The byte preservation is `TomlBlockDocument`'s, reused rather than reimplemented: this
/// type only knows the TOML spelling of the bar schema and which region each part of the
/// draft lives in. Reading values goes through the real TOML deserialiser for the same
/// reason `SettingsModel.rawExecConfig` does — the block document carries source text
/// verbatim and never interprets it, and hand-lexing values out of it turns every gap in
/// the lexer into a silently wrong value.
struct BarTomlDocument {
    private var document: TomlBlockDocument

    init(_ text: String) { document = TomlBlockDocument(text) }

    func render() -> String { document.render() }

    // MARK: - Region ownership

    private static func isBarTable(_ name: String) -> Bool { name == "bar" || name.hasPrefix("bar.") }
    private static func isItemTable(_ name: String) -> Bool { name == "item" || name.hasPrefix("item.") }

    /// The TOML spelling of every modelled key, in emission order. One list per table, so
    /// the reader, the surgical writer, and the generator cannot disagree about a name.
    /// Computed rather than stored: a key-path tuple is not `Sendable`.
    private static var geometryKeys: [(key: String, path: WritableKeyPath<BarGeometry, Int>)] { [
        ("height", \.height),
        ("margin", \.margin),
        ("y-offset", \.yOffset),
        ("corner-radius", \.cornerRadius),
        ("border-width", \.borderWidth),
        ("padding-left", \.paddingLeft),
        ("padding-right", \.paddingRight),
    ] }

    private static var colorKeys: [(key: String, path: WritableKeyPath<BarColors, String>)] { [
        ("background", \.background),
        ("border", \.border),
        ("label", \.label),
        ("icon", \.icon),
        ("accent", \.accent),
        ("popup-background", \.popupBackground),
        ("popup-border", \.popupBorder),
    ] }
}

// MARK: - Reading

extension BarTomlDocument {
    func draft() -> Result<BarDraft, BarTomlError> {
        do {
            return .success(try parse())
        } catch let error as BarTomlError {
            return .failure(error)
        } catch {
            return .failure(.syntax(String(describing: error)))
        }
    }

    private func parse() throws -> BarDraft {
        var text = render()
        // TOMLDecoder unpacks scalars through `withContiguousStorageIfAvailable { ... }!`,
        // which traps on a String that isn't natively stored — and text coming back from
        // the settings editors is NSString-backed. Same guard as `parseConfig`.
        text.makeContiguousUTF8()
        let root: [String: Any]
        do {
            root = try [String: Any](try TOMLTable(source: text))
        } catch {
            throw BarTomlError.syntax(String(describing: error))
        }

        var draft = BarDraft()
        draft.version = try Self.int(root, "version", draft.version, path: "version")
        let bar = try Self.table(root, "bar", path: "bar")
        for (key, path) in Self.geometryKeys {
            draft.geometry[keyPath: path] = try Self.int(bar, key, draft.geometry[keyPath: path], path: "bar.\(key)")
        }
        let colors = try Self.table(bar, "colors", path: "bar.colors")
        for (key, path) in Self.colorKeys {
            draft.colors[keyPath: path] = try Self.string(colors, key, draft.colors[keyPath: path], path: "bar.colors.\(key)")
        }
        draft.items = try parseItems(root)
        return draft
    }

    private func parseItems(_ root: [String: Any]) throws -> [BarItem] {
        guard let raw = root["item"] else { return [] }
        guard let array = raw as? [Any] else {
            throw BarTomlError.semantic("'item' must be a list of [[item]] tables, got \(Self.typeName(raw))")
        }
        let orders = settingsKeyOrders()
        return try array.enumerated().map { index, element in
            let path = "item[\(index)]"
            guard let table = element as? [String: Any] else {
                throw BarTomlError.semantic("\(path) must be a table, got \(Self.typeName(element))")
            }
            guard let id = table["id"] as? String, !id.isEmpty else {
                throw BarTomlError.semantic("\(path) must have a non-empty string 'id'")
            }
            guard let rawCluster = table["cluster"] as? String else {
                throw BarTomlError.semantic("\(path) ('\(id)') must have a string 'cluster'")
            }
            guard let cluster = BarCluster(rawValue: rawCluster) else {
                let expected = BarCluster.allCases.map(\.rawValue).joined(separator: ", ")
                throw BarTomlError.semantic("\(path) ('\(id)') has unknown cluster '\(rawCluster)'. Expected one of: \(expected)")
            }
            let settings = try Self.table(table, "settings", path: "\(path).settings")
            return BarItem(
                id: id,
                cluster: cluster,
                settings: try Self.settings(settings, order: orders.getOrNil(atIndex: index) ?? [], path: "\(path).settings"),
            )
        }
    }

    /// The source order of each item's `[item.settings]` keys, by item index. The
    /// deserialiser hands back an unordered dictionary, and regenerating the item region
    /// from it would otherwise shuffle the user's own settings lines.
    private func settingsKeyOrders() -> [[String]] {
        var orders: [[String]] = []
        for block in document.blocks {
            guard case .table(let name, let text) = block else { continue }
            if name == "item" { orders.append([]) }
            if name == "item.settings", !orders.isEmpty { orders[orders.count - 1] = Self.keyNames(inTableText: text) }
        }
        return orders
    }

    /// The keys of a table body, in source order. With the header line dropped, a body is
    /// a document of top-level keys, so the block splitter answers this — multi-line
    /// values, comments and CRLF included — instead of a second hand-rolled lexer.
    private static func keyNames(inTableText text: String) -> [String] {
        let lines = text.linesWithTerminators()
        guard lines.count > 1 else { return [] }
        return TomlBlockDocument(lines.dropFirst().joined()).blocks.compactMap(\.name)
    }

    private static func settings(
        _ raw: [String: Any],
        order: [String],
        path: String,
    ) throws -> OrderedDictionary<String, BarSettingValue> {
        var result: OrderedDictionary<String, BarSettingValue> = [:]
        // Keys the file spelled out come first, in its order; anything else (an inline
        // `settings = { ... }` has no line order to recover) follows deterministically.
        for key in order + raw.keys.sorted() {
            guard result[key] == nil, let value = raw[key] else { continue }
            result[key] = try settingValue(value, path: "\(path).\(key)")
        }
        return result
    }

    private static func settingValue(_ any: Any, path: String) throws -> BarSettingValue {
        switch any {
            case let value as Bool: return .bool(value)
            case let value as any BinaryInteger: return .int(Int(value))
            case let value as Double: return .double(value)
            case let value as String: return .string(value)
            case let values as [Any]:
                return .array(try values.enumerated().map { try settingValue($1, path: "\(path)[\($0)]") })
            default:
                throw BarTomlError.semantic("\(path) has unsupported type \(typeName(any)). Expected a string, number, boolean, or a list of those")
        }
    }

    private static func table(_ parent: [String: Any], _ key: String, path: String) throws -> [String: Any] {
        guard let raw = parent[key] else { return [:] }
        guard let table = raw as? [String: Any] else {
            throw BarTomlError.semantic("\(path) must be a table, got \(typeName(raw))")
        }
        return table
    }

    private static func int(_ table: [String: Any], _ key: String, _ fallback: Int, path: String) throws -> Int {
        guard let raw = table[key] else { return fallback }
        // Bool is not a BinaryInteger, so `true` is rejected rather than read as 1.
        guard let value = raw as? any BinaryInteger else {
            throw BarTomlError.semantic("\(path) must be an integer, got \(typeName(raw))")
        }
        return Int(value)
    }

    private static func string(_ table: [String: Any], _ key: String, _ fallback: String, path: String) throws -> String {
        guard let raw = table[key] else { return fallback }
        guard let value = raw as? String else {
            throw BarTomlError.semantic("\(path) must be a string, got \(typeName(raw))")
        }
        return value
    }

    private static func typeName(_ any: Any) -> String { "\(type(of: any))" }
}

// MARK: - Writing

extension BarTomlDocument {
    /// Writes `draft` into the document, touching only the regions whose values actually
    /// changed. `original` is the draft as it was read from this same document.
    mutating func apply(_ draft: BarDraft, original: BarDraft) {
        if draft.version != original.version {
            document.set(key: "version", tomlValue: TomlValue.of(draft.version))
        }
        applyBar(draft, original)
        applyItems(draft, original)
    }

    private mutating func applyBar(_ draft: BarDraft, _ original: BarDraft) {
        let edits = Self.barEdits(draft, original)
        guard !edits.isEmpty else { return }

        // `bar.height = 32` written as a dotted top-level key is the same setting as
        // `[bar]` + `height = 32`, and leaving both behind would be a duplicate definition
        // TOML rejects. Rare enough that the whole family is regenerated from the draft
        // rather than edited in place.
        let dotted = topLevelKeys { $0 == "bar" || $0.hasPrefix("bar.") }
        var family = dotted.isEmpty ? document.text(forTablesMatching: Self.isBarTable) : ""
        for key in dotted { document.remove(key: key) }

        if family.isEmpty {
            family = Self.barFamilyText(draft)
        } else {
            for table in ["bar", "bar.colors"] {
                let tableEdits = edits.filter { $0.table == table }.map { (key: $0.key, value: $0.value) }
                guard !tableEdits.isEmpty else { continue }
                family = Self.setKeys(tableEdits, inTable: table, familyText: family)
            }
        }
        document.replaceTables(matching: Self.isBarTable, with: family, name: "bar")
    }

    /// The item region is regenerated wholesale, because an item edit is a change to an
    /// ordered array — a reorder or an insertion has no stable identity a comment inside
    /// the region could be reattached to. Unknown `[item.settings]` keys survive anyway:
    /// they round-trip through `BarItem.settings`.
    private mutating func applyItems(_ draft: BarDraft, _ original: BarDraft) {
        guard draft.items != original.items else { return }
        document.remove(key: "item") // an inline `item = [{ ... }]` would duplicate the generated [[item]] tables
        document.replaceTables(matching: Self.isItemTable, with: Self.itemsText(draft), name: "item")
    }

    private func topLevelKeys(matching predicate: (String) -> Bool) -> [String] {
        document.blocks.compactMap { block in
            guard case .keyValue(let key, _) = block, predicate(key) else { return nil }
            return key
        }
    }

    private static func barEdits(_ draft: BarDraft, _ original: BarDraft) -> [(table: String, key: String, value: String)] {
        var edits: [(table: String, key: String, value: String)] = []
        for (key, path) in geometryKeys where draft.geometry[keyPath: path] != original.geometry[keyPath: path] {
            edits.append((table: "bar", key: key, value: TomlValue.of(draft.geometry[keyPath: path])))
        }
        for (key, path) in colorKeys where draft.colors[keyPath: path] != original.colors[keyPath: path] {
            edits.append((table: "bar.colors", key: key, value: TomlValue.of(draft.colors[keyPath: path])))
        }
        return edits
    }

    /// Rewrites keys inside one table of the `[bar]` family, leaving every other byte of
    /// the family where it was.
    private static func setKeys(_ edits: [(key: String, value: String)], inTable table: String, familyText: String) -> String {
        let family = TomlBlockDocument(familyText)
        guard family.blocks.contains(where: { $0.name == table }) else {
            var text = familyText.isEmpty || familyText.endsWithNewline ? familyText : familyText + "\n"
            text += "\n[\(table)]\n"
            for edit in edits { text += "\(edit.key) = \(edit.value)\n" }
            return text
        }
        return family.blocks.map { block -> String in
            guard case .table(let name, let body) = block, name == table else { return block.text }
            return setKeys(edits, inTableBody: body)
        }.joined()
    }

    /// With its header line dropped, a table body is a document of top-level keys, so
    /// `TomlBlockDocument.set` does the delicate part: it keeps indentation, the trailing
    /// comment, and the line's own terminator, and appends the key if it is absent.
    private static func setKeys(_ edits: [(key: String, value: String)], inTableBody text: String) -> String {
        let lines = text.linesWithTerminators()
        guard let header = lines.first else { return text }
        var body = TomlBlockDocument(lines.dropFirst().joined())
        for edit in edits { body.set(key: edit.key, tomlValue: edit.value) }
        return header + body.render()
    }

    private static func barFamilyText(_ draft: BarDraft) -> String {
        var text = "[bar]\n"
        for (key, path) in geometryKeys { text += "\(key) = \(TomlValue.of(draft.geometry[keyPath: path]))\n" }
        text += "\n[bar.colors]\n"
        for (key, path) in colorKeys { text += "\(key) = \(TomlValue.of(draft.colors[keyPath: path]))\n" }
        return text
    }

    private static func itemsText(_ draft: BarDraft) -> String {
        draft.items.map { item in
            var text = "[[item]]\n"
            text += "id = \(TomlValue.of(item.id))\n"
            text += "cluster = \(TomlValue.of(item.cluster.rawValue))\n"
            if !item.settings.isEmpty {
                text += "\n[item.settings]\n"
                for (key, value) in item.settings { text += "\(TomlValue.key(key)) = \(value.toml)\n" }
            }
            return text
        }.joined(separator: "\n")
    }
}
