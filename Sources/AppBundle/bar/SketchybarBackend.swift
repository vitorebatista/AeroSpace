import Common
import Foundation

enum SketchybarBackendError: Error, LocalizedError {
    case backupFailed(URL, any Error)
    case writeFailed(URL, any Error)
    /// The files on disk are correct and only the reload failed, so the outcome travels
    /// with the error: the page still has to report what happened to `sketchybarrc`, and
    /// `apply` has one return value to say it with.
    case reloadFailed(outcome: BarApplyOutcome, underlying: any Error)
    case notInstalled
    /// A live push that sketchybar rejected. The bar is now in a state that matches neither
    /// draft, and the way back is `discardLiveChanges`, not a second diff from a baseline
    /// that is no longer what is on screen.
    case livePushFailed(any Error)

    var errorDescription: String? {
        switch self {
            case .backupFailed(let url, let error):
                "Can't back up \(url.path): \(error.localizedDescription). Nothing was written."
            case .writeFailed(let url, let error):
                "Can't write \(url.path): \(error.localizedDescription)"
            case .reloadFailed(_, let error):
                "The config was written, but reloading sketchybar failed: \(error.localizedDescription). " +
                    "Run `sketchybar --reload` to pick it up."
            case .notInstalled:
                "sketchybar is not installed, so there is nothing to reload."
            case .livePushFailed(let error):
                "Can't update the running bar: \(error.localizedDescription). " +
                    "Revert to put it back to the last saved bar."
        }
    }
}

/// Renders a `BarDraft` by generating `~/.config/sketchybar/sketchybarrc` and reloading
/// sketchybar. The only component in the change that knows sketchybar exists.
///
/// Every filesystem and process touch goes through an injected closure, in the same shape
/// `SettingsModel` uses, so the takeover rules are testable without a real config
/// directory and without a real bar.
struct SketchybarBackend: BarBackend {
    static let configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/sketchybar")
    static let defaultConfigUrl: URL = configDirectory.appending(component: "sketchybarrc")

    /// sketchybar execs its config, so the file has to carry the exec bit. A generated
    /// file that is not executable is a silently empty bar.
    static let configPermissions = 0o755

    let configUrl: URL
    let helpers: BarHelperPaths

    private let binaryLocator: @Sendable () -> URL?
    private let fileExists: @Sendable (URL) -> Bool
    private let fileReader: @Sendable (URL) throws -> Data
    private let directoryCreator: @Sendable (URL) throws -> Void
    private let backupCreator: @Sendable (URL) throws -> URL
    private let atomicWriter: @Sendable (Data, URL, Int?) throws -> Void
    /// Every sketchybar invocation, reload and live push alike, goes through here, so a test
    /// observes the exact argument vector and never spawns a process.
    private let commandRunner: @Sendable (URL, [String]) throws -> Void

    init(
        configUrl: URL = SketchybarBackend.defaultConfigUrl,
        helpers: BarHelperPaths = SketchybarBackend.resolvedHelpers(),
        binaryLocator: @escaping @Sendable () -> URL? = { SketchybarBackend.locateSketchybar() },
        fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        fileReader: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        directoryCreator: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        backupCreator: @escaping @Sendable (URL) throws -> URL = { try SketchybarBackend.createBackup(of: $0) },
        atomicWriter: @escaping @Sendable (Data, URL, Int?) throws -> Void = {
            try SketchybarBackend.writeAtomically($0, to: $1, permissions: $2)
        },
        commandRunner: @escaping @Sendable (URL, [String]) throws -> Void = {
            try SketchybarBackend.run(binary: $0, arguments: $1)
        },
    ) {
        self.configUrl = configUrl
        self.helpers = helpers
        self.binaryLocator = binaryLocator
        self.fileExists = fileExists
        self.fileReader = fileReader
        self.directoryCreator = directoryCreator
        self.backupCreator = backupCreator
        self.atomicWriter = atomicWriter
        self.commandRunner = commandRunner
    }

    var isAvailable: Bool { binaryLocator() != nil }

    func apply(_ draft: BarDraft) throws -> BarApplyOutcome {
        let data = BarConfigGenerator.generateData(draft, helpers: helpers)

        let outcome: BarApplyOutcome
        if !fileExists(configUrl) {
            outcome = .created
        } else if isGenerated(configUrl) {
            outcome = .updated
        } else {
            // The user's own config. It is copied aside before anything is written, and a
            // failure here aborts the save: losing 3,485 lines of Lua is not recoverable.
            do {
                outcome = .replacedUserConfig(backup: try backupCreator(configUrl))
            } catch {
                throw SketchybarBackendError.backupFailed(configUrl, error)
            }
        }

        do {
            try directoryCreator(configUrl.deletingLastPathComponent())
            try atomicWriter(data, configUrl, Self.configPermissions)
        } catch {
            throw SketchybarBackendError.writeFailed(configUrl, error)
        }

        guard let binary = binaryLocator() else {
            throw SketchybarBackendError.reloadFailed(outcome: outcome, underlying: SketchybarBackendError.notInstalled)
        }
        do {
            try reload(binary)
        } catch {
            // Deliberately no rollback: the config on disk is the one the user asked for,
            // and reverting it to a stale version to match a process that failed to
            // restart makes the next manual `sketchybar --reload` wrong too.
            throw SketchybarBackendError.reloadFailed(outcome: outcome, underlying: error)
        }
        return outcome
    }

    func applyLive(from previous: BarDraft, to next: BarDraft) throws {
        let commands = BarLiveDiff.commands(from: previous, to: next, helpers: helpers)
        // A drag that lands where it started must not cost a process.
        guard !commands.isEmpty else { return }
        guard let binary = binaryLocator() else { throw SketchybarBackendError.notInstalled }
        do {
            // One invocation for the whole diff: sketchybar applies an argument vector before
            // it redraws, so the bar never shows a half-applied drag. Nothing is written —
            // the live bar is scratch state and `bar.toml` stays the last saved draft.
            try commandRunner(binary, commands.flatMap { $0 })
        } catch {
            throw SketchybarBackendError.livePushFailed(error)
        }
    }

    func discardLiveChanges() throws {
        // Live editing never writes, so the file is still the last saved state and reloading
        // it is the whole restore. Nothing to undo command-by-command.
        guard let binary = binaryLocator() else { throw SketchybarBackendError.notInstalled }
        try reload(binary)
    }

    private func reload(_ binary: URL) throws { try commandRunner(binary, ["--reload"]) }

    /// Whether the file at `url` is one we wrote. Only the header is inspected — a file we
    /// cannot read, or one that is not UTF-8, is by definition not ours and is backed up.
    private func isGenerated(_ url: URL) -> Bool {
        guard let data = try? fileReader(url), let text = String(data: data, encoding: .utf8) else { return false }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(10)
            .contains { $0.hasPrefix(BarConfigGenerator.markerPrefix) }
    }

    // MARK: - Defaults

    /// A GUI app does not inherit a login shell's `PATH`, so the Homebrew prefixes are
    /// checked first and whatever `PATH` we do have only supplements them.
    static func locateSketchybar(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL? {
        locate("sketchybar", fileManager: fileManager, environment: environment)
    }

    /// The app bundle does not ship the CLI — Homebrew installs it beside the cask — so the
    /// generated config has to name it by absolute path, found the same way sketchybar is.
    static func locateAerospaceCli(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL? {
        locate(aeroSpaceCliName, fileManager: fileManager, environment: environment)
    }

    private static func locate(
        _ binary: String,
        fileManager: FileManager,
        environment: [String: String],
    ) -> URL? {
        var candidates = ["/opt/homebrew/bin/\(binary)", "/usr/local/bin/\(binary)"]
        for directory in (environment["PATH"] ?? "").split(separator: ":") where !directory.isEmpty {
            candidates.append("\(directory)/\(binary)")
        }
        return candidates
            .lazy
            .map { URL(filePath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// What the generator needs from the world, resolved once at construction.
    ///
    /// `appFontIconMap` stays `nil`: the map that turns an application name into a
    /// `sketchybar-app-font` glyph is a script the user supplies, and there is no location
    /// convention worth guessing at. Absent, `show-app-icons` degrades to plain names, which
    /// is what the catalog documents.
    static func resolvedHelpers() -> BarHelperPaths {
        BarHelperPaths(aerospaceCli: locateAerospaceCli()?.path ?? aeroSpaceCliName, externalTools: locateExternalTools())
    }

    /// Where each catalog tool was found. Absent from the map means not installed, which the
    /// generator turns into a comment and the Settings page into an install hint — neither
    /// guesses, and neither has to be told which tools exist.
    static func locateExternalTools(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> [BarExternalTool: String] {
        var found: [BarExternalTool: String] = [:]
        for tool in BarExternalTool.allCases {
            // Assigning nil removes the key, so the map holds exactly what was found.
            found[tool] = locate(tool.rawValue, fileManager: fileManager, environment: environment)?.path
        }
        return found
    }

    /// Stage into a sibling temp file and rename over the target, so a crash or a full
    /// disk mid-write leaves the previous `sketchybarrc` intact rather than a half-written
    /// one that sketchybar would happily exec.
    ///
    /// `SettingsModel` does the same for `~/.aerospace.toml`, but its version is
    /// `@MainActor`-isolated and this runs off the main actor.
    static func writeAtomically(
        _ data: Data,
        to target: URL,
        permissions: Int?,
        fileManager: FileManager = .default,
    ) throws {
        let staging = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent).aerospace-bar-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: staging) }
        try data.write(to: staging, options: .withoutOverwriting)
        if let permissions {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: staging.path)
        }
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: target)
        }
    }

    static func run(binary: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SketchybarBackendError.writeFailed(
                binary,
                CocoaError(.executableLoad, userInfo: [
                    NSLocalizedDescriptionKey: "sketchybar \(arguments.first ?? "") exited with \(process.terminationStatus)",
                ]),
            )
        }
    }

    /// `sketchybarrc.backup-<yyyy-MM-dd-HHmmss>`, beside the file it replaces. The suffix
    /// loop is what keeps two saves in the same second from overwriting each other's
    /// backup, which would defeat the point of taking one.
    static func createBackup(of target: URL, now: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        let target = target.standardizedFileURL
        let source = try Data(contentsOf: target)
        let permissions = try fileManager.attributesOfItem(atPath: target.path)[.posixPermissions]
        let baseName = "\(target.lastPathComponent).backup-\(timestamp(now))"

        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            let destination = target.deletingLastPathComponent().appending(path: name)
            do {
                try source.write(to: destination, options: .withoutOverwriting)
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteFileExists.rawValue
            {
                suffix += 1
                continue
            }
            do {
                if let permissions {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
                }
                return destination.absoluteURL
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
