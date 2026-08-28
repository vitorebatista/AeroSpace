import Common
import Foundation
import SwiftUI
import TOMLDecoder

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
    /// `true` while `save()` is in flight. The save suspends across the config reload with
    /// the window still interactive, so the UI freezes its bindings and both footer buttons
    /// for the duration — see `save()`.
    @Published private(set) var isSaving = false
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
    /// `draft` as `load()` read it, before the user touched anything. `apply` compares
    /// against it so a region the user never went near is left byte-for-byte alone.
    private var loadedDraft: ConfigTomlWriter.ConfigDraft = ConfigTomlWriter.ConfigDraft.defaults
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
            draft = ConfigTomlWriter.draft(from: config, rawExec: Self.rawExecConfig(from: text), document: document)
            loadedDraft = draft
            mode = .form
        } else {
            mode = .rawOnly(parseError: errors.joined(separator: "\n\n"))
        }
    }

    func revert() { load() }

    /// Renders the draft, validates it with the real parser against a temp file, and only
    /// then writes the user's config and reloads. A bad edit can never leave the user with
    /// a config AeroSpace refuses to load.
    ///
    /// `isSaving` is set for the whole of this, because it suspends (the reload awaits
    /// `activateMode`) with the MainActor free and the window live: without it a keystroke
    /// landing in that gap would be silently overwritten by the closing `load()`, and a
    /// second click on Save would start an overlapping save.
    func save() async {
        guard let targetUrl, let writeUrl, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        status = nil

        let candidate: String
        switch mode {
            case .form:
                var working = document
                ConfigTomlWriter.apply(draft, original: loadedDraft, to: &working)
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
            // Mirror `reloadConfigButton`: a reload swaps the config in, and the windows
            // only pick up the new gaps/normalization once a refresh session relays them
            // out. A bare `reloadConfig()` would leave the footer claiming "Saved and
            // reloaded" while nothing on screen moved until the next natural refresh.
            if let token: RunSessionGuard = .isServerEnabled {
                try await runLightSession(.menuBarButton, token) { _ = try await reloadConfig() }
            } else {
                _ = try await reloadConfig()
            }
        } catch {
            status = .error("Saved, but reloading the config failed: \(error.localizedDescription)")
            return
        }

        load() // re-read from disk so the form and the document match the file exactly
        status = .saved
    }

    /// Recovers `inherit-env-vars` and the override map exactly as written in the file,
    /// which `Config` cannot give back: `Config.execConfig` holds the *expanded*
    /// environment, and `parseEnvVariables` has already interpolated every `$VAR`.
    ///
    /// This deliberately re-deserialises the config text with `TOMLDecoder` — the same
    /// deserialiser `parseConfig` runs — rather than reading values out of the block
    /// document. The block document carries source text verbatim and does not interpret
    /// it, so recovering values from it means hand-lexing TOML, and every gap in that lexer
    /// (a trailing comment, a partially quoted value, `exec.inherit-env-vars` written as a
    /// dotted key with no `[exec]` header) silently produces a *valid* wrong value that
    /// `save()`'s validation pass cannot catch. Going through the real deserialiser removes
    /// the whole class. It is un-interpolated because interpolation happens later, in
    /// `parseEnvVariables`, which is exactly what we need to write back.
    nonisolated static func rawExecConfig(from configText: String) -> RawExecConfig {
        var result = RawExecConfig()
        guard let root = try? [String: Any](TOMLTable(source: configText)),
              let exec = root["exec"] as? [String: Any]
        else {
            return result
        }
        if let inheritEnvVars = exec["inherit-env-vars"] as? Bool { result.inheritEnvVariables = inheritEnvVars }
        // Non-string values are left out on purpose: the real parser rejects them, and
        // `save()`'s validation pass will report that against the user's own text.
        for (name, value) in exec["env-vars"] as? [String: Any] ?? [:] {
            if let value = value as? String { result.overriddenVars[name] = value }
        }
        return result
    }
}
