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
public final class SettingsModel: ObservableObject {
    // `public` because `AeroSpaceApp` (a separate SPM target) holds `.shared` as a
    // `@StateObject` to keep it alive for the settings window's lifetime.
    public static let shared = SettingsModel()

    @Published var draft: ConfigTomlWriter.ConfigDraft = ConfigTomlWriter.ConfigDraft.defaults
    @Published var mode: SettingsMode = .form
    @Published var isDirty = false
    @Published var status: SettingsStatus?
    @Published var wholeFileText = ""
    /// Bumped every time `load()` reseeds `draft` from disk (Revert, or the reload at the
    /// end of a successful `save()`). Sections that keep their own local "what was here
    /// before" memory across a value round trip — see `GapRow.lastKnownRules` — watch this
    /// to know when that memory refers to a document that no longer exists, since the
    /// value it was shadowing can come back looking identical (e.g. `.constant(5)` both
    /// before and after a revert) with no other signal that it changed out from under them.
    @Published private(set) var loadGeneration = 0

    /// The file we read and will write, as the config lookup spelled it. Kept unresolved
    /// because it is what the user recognises in a message; `writeUrl` is what we touch.
    private(set) var targetUrl: URL?
    /// `true` when no custom config exists yet, so saving creates `~/<configDotfileName>`.
    private(set) var willCreateConfig = false
    private var document = TomlBlockDocument("")
    private var loadedModificationDate: Date?

    private init() {}

    /// The path writes actually land on. `write(to:atomically:)` renames a fresh temp file
    /// over the path, which replaces a *symlink* with a regular file instead of writing
    /// through it — a config symlinked into a dotfiles repo would be silently detached and
    /// the real file left holding the old contents. Resolving first also keeps the
    /// modification-date check and the write looking at the same file.
    private var writeUrl: URL? { targetUrl?.resolvingSymlinksInPath() }

    /// `true` if the file changed on disk since `load()`. Checked before overwriting.
    var externallyModified: Bool {
        guard let writeUrl, let loadedModificationDate else { return false }
        guard let current = Self.modificationDate(of: writeUrl) else { return false }
        return current != loadedModificationDate
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    func load() {
        status = nil
        isDirty = false
        loadGeneration += 1

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
        // Read through the resolved path, the same one `save()` writes, so the two agree
        // when the config is a symlink (`attributesOfItem` does not follow one).
        loadedModificationDate = willCreateConfig ? nil : writeUrl.flatMap(Self.modificationDate(of:))

        let (config, errors) = parseConfig(text)
        if errors.isEmpty {
            // `parseConfig` expands `[exec]` into the full environment, which is not
            // writable back. Recover the file's own `[exec]` values instead.
            draft = ConfigTomlWriter.draft(from: config, rawExec: rawExecConfig(from: document), document: document)
            mode = .form
        } else {
            mode = .rawOnly(parseError: errors.joined(separator: "\n\n"))
        }
    }

    func revert() { load() }

    /// Renders the draft, validates it with the real parser against a temp file, and only
    /// then writes the user's config and reloads. A bad edit can never leave the user with
    /// a config AeroSpace refuses to load.
    func save() async {
        guard let targetUrl, let writeUrl else { return }
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

        // The atomic write gives the file the temp file's mode (0644 -> 0755 in practice),
        // so put the original permissions back afterwards.
        let originalPermissions = try? FileManager.default
            .attributesOfItem(atPath: writeUrl.path)[.posixPermissions] as? NSNumber
        do {
            try candidate.write(to: writeUrl, atomically: true, encoding: .utf8)
        } catch {
            status = .error("Can't write \(targetUrl.path): \(error.localizedDescription)")
            return
        }
        if let originalPermissions {
            try? FileManager.default.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: writeUrl.path)
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

    /// Recovers `inherit-env-vars` and the override map as written in `[exec]` /
    /// `[exec.env-vars]`, since `Config.execConfig` only holds the expanded environment.
    /// Takes the already-built document (`load()` just built one) rather than
    /// re-parsing the text into a throwaway one.
    private func rawExecConfig(from document: TomlBlockDocument) -> RawExecConfig {
        var result = RawExecConfig()
        if let table = document.blocks.first(where: { $0.name == "exec" })?.text {
            for line in table.linesWithTerminators() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let eq = trimmed.firstIndex(of: "=") else { continue }
                let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
                let rawValue = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if key == "inherit-env-vars" { result.inheritEnvVariables = rawValue == "true" }
            }
        }
        // `[exec.env-vars]` is its own table block. Values are plain (possibly quoted)
        // strings; the parser will do interpolation and validation on save.
        if let envTable = document.blocks.first(where: { $0.name == "exec.env-vars" })?.text {
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
        return result
    }
}
