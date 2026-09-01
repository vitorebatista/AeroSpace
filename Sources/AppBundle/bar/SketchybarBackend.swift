import Foundation

enum SketchybarBackendError: Error, LocalizedError {
    case backupFailed(URL, any Error)
    case writeFailed(URL, any Error)
    /// The files on disk are correct and only the reload failed, so the outcome travels
    /// with the error: the page still has to report what happened to `sketchybarrc`, and
    /// `apply` has one return value to say it with.
    case reloadFailed(outcome: BarApplyOutcome, underlying: any Error)
    case notInstalled

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
    private let reloader: @Sendable (URL) throws -> Void

    init(
        configUrl: URL = SketchybarBackend.defaultConfigUrl,
        helpers: BarHelperPaths,
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
        reloader: @escaping @Sendable (URL) throws -> Void = { try SketchybarBackend.reload(binary: $0) },
    ) {
        self.configUrl = configUrl
        self.helpers = helpers
        self.binaryLocator = binaryLocator
        self.fileExists = fileExists
        self.fileReader = fileReader
        self.directoryCreator = directoryCreator
        self.backupCreator = backupCreator
        self.atomicWriter = atomicWriter
        self.reloader = reloader
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
            try reloader(binary)
        } catch {
            // Deliberately no rollback: the config on disk is the one the user asked for,
            // and reverting it to a stale version to match a process that failed to
            // restart makes the next manual `sketchybar --reload` wrong too.
            throw SketchybarBackendError.reloadFailed(outcome: outcome, underlying: error)
        }
        return outcome
    }

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
        var candidates = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        for directory in (environment["PATH"] ?? "").split(separator: ":") where !directory.isEmpty {
            candidates.append("\(directory)/sketchybar")
        }
        return candidates
            .lazy
            .map { URL(filePath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
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

    static func reload(binary: URL) throws {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--reload"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SketchybarBackendError.writeFailed(
                binary,
                CocoaError(.executableLoad, userInfo: [
                    NSLocalizedDescriptionKey: "sketchybar --reload exited with \(process.terminationStatus)",
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
