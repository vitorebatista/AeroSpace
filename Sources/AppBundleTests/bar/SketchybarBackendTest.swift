@testable import AppBundle
import Foundation
import XCTest

/// The takeover rules, over injected seams only. Nothing here touches a real config
/// directory or a real sketchybar: what is being tested is the decision, and a test that
/// needed a bar on a screen could not make that decision observable.
final class SketchybarBackendTest: XCTestCase {
    private let configUrl = URL(filePath: "/Users/test/.config/sketchybar/sketchybarrc")
    private let backupUrl = URL(filePath: "/Users/test/.config/sketchybar/sketchybarrc.backup-2026-08-31-221504")
    private let helpers = BarHelperPaths(aerospaceCli: "/opt/homebrew/bin/aerospace-edge")

    private enum Failure: Error, Equatable {
        case backup
        case write
        case command
    }

    /// Records every side effect the backend was allowed to have.
    private final class Recorder: @unchecked Sendable {
        var written: [(Data, URL, Int?)] = []
        var backedUp: [URL] = []
        var commands: [[String]] = []
        var directoriesCreated: [URL] = []

        var reloaded: Int { commands.count(where: { $0 == ["--reload"] }) }
    }

    func testAnAbsentFileIsCreated() throws {
        let recorder = Recorder()
        let backend = makeBackend(recorder, existing: nil)

        XCTAssertEqual(try backend.apply(BarDraft()), .created)
        XCTAssertTrue(recorder.backedUp.isEmpty, "there was nothing to back up")
        XCTAssertEqual(recorder.written.count, 1)
        XCTAssertEqual(recorder.written.first?.1, configUrl)
        XCTAssertEqual(recorder.written.first?.2, 0o755, "sketchybar execs the file, so it needs the exec bit")
        XCTAssertEqual(recorder.reloaded, 1)
        XCTAssertEqual(recorder.directoriesCreated, [configUrl.deletingLastPathComponent()])
    }

    func testAFilePresentWithTheMarkerIsOverwrittenWithoutABackup() throws {
        let recorder = Recorder()
        let previous = BarConfigGenerator.generate(BarDraft(), helpers: helpers)
        let backend = makeBackend(recorder, existing: previous)

        XCTAssertEqual(try backend.apply(BarDraft()), .updated)
        XCTAssertTrue(recorder.backedUp.isEmpty, "our own file is not a user config")
        XCTAssertEqual(recorder.written.count, 1)
        XCTAssertEqual(recorder.reloaded, 1)
    }

    func testAMarkerFurtherDownTheHeaderIsStillRecognised() throws {
        // A user who adds a line above the marker has still not written this file.
        let recorder = Recorder()
        let backend = makeBackend(recorder, existing: "#!/bin/sh\n# mine\n\(BarConfigGenerator.markerLine)\n")
        XCTAssertEqual(try backend.apply(BarDraft()), .updated)
        XCTAssertTrue(recorder.backedUp.isEmpty)
    }

    func testAFilePresentWithoutTheMarkerIsBackedUpFirst() throws {
        let recorder = Recorder()
        let backend = makeBackend(recorder, existing: "-- 3485 lines of Lua\nrequire('bar')\n")

        XCTAssertEqual(try backend.apply(BarDraft()), .replacedUserConfig(backup: backupUrl))
        XCTAssertEqual(recorder.backedUp, [configUrl])
        XCTAssertEqual(recorder.written.count, 1)
        XCTAssertEqual(recorder.reloaded, 1)
    }

    func testAMarkerBuriedBelowTheHeaderDoesNotCountAsOurs() throws {
        // Someone else's config that happens to quote our marker deep inside is a user
        // config. The marker is a header, and only the header is trusted.
        let recorder = Recorder()
        let filler = String(repeating: "-- padding\n", count: 40)
        let backend = makeBackend(recorder, existing: "#!/bin/sh\n\(filler)\(BarConfigGenerator.markerLine)\n")

        XCTAssertEqual(try backend.apply(BarDraft()), .replacedUserConfig(backup: backupUrl))
        XCTAssertEqual(recorder.backedUp, [configUrl])
    }

    func testAFailedBackupAbortsTheSaveWithoutWritingAnything() {
        let recorder = Recorder()
        let backend = makeBackend(recorder, existing: "require('bar')\n", backupError: Failure.backup)

        XCTAssertThrowsError(try backend.apply(BarDraft())) { error in
            guard case SketchybarBackendError.backupFailed(let url, let underlying) = error else {
                return XCTFail("expected a backup failure, got \(error)")
            }
            XCTAssertEqual(url, self.configUrl)
            XCTAssertEqual(underlying as? Failure, .backup)
        }
        XCTAssertTrue(recorder.written.isEmpty, "the user's config must still be there")
        XCTAssertEqual(recorder.reloaded, 0)
    }

    func testAReloadFailureReportsTheOutcomeAndLeavesTheFilesAlone() {
        let recorder = Recorder()
        let backend = makeBackend(recorder, existing: "require('bar')\n", commandError: Failure.command)

        XCTAssertThrowsError(try backend.apply(BarDraft())) { error in
            guard case SketchybarBackendError.reloadFailed(let outcome, let underlying) = error else {
                return XCTFail("expected a reload failure, got \(error)")
            }
            // The config on disk is correct, so the page still has to be told the user's
            // config was moved aside and where it went.
            XCTAssertEqual(outcome, .replacedUserConfig(backup: self.backupUrl))
            XCTAssertEqual(underlying as? Failure, .command)
        }
        XCTAssertEqual(recorder.written.count, 1, "a failed reload must not roll the file back")
        XCTAssertEqual(recorder.backedUp, [configUrl])
    }

    func testAFailedWriteIsReportedAsAWriteFailure() {
        let recorder = Recorder()
        let backend = makeBackend(recorder, existing: nil, writeError: Failure.write)

        XCTAssertThrowsError(try backend.apply(BarDraft())) { error in
            guard case SketchybarBackendError.writeFailed(_, let underlying) = error else {
                return XCTFail("expected a write failure, got \(error)")
            }
            XCTAssertEqual(underlying as? Failure, .write)
        }
        XCTAssertEqual(recorder.reloaded, 0)
    }

    func testWhatIsWrittenIsWhatTheGeneratorProduced() throws {
        let recorder = Recorder()
        var draft = BarDraft()
        draft.items = [BarItem(id: "clock", cluster: .right)]
        _ = try makeBackend(recorder, existing: nil).apply(draft)

        XCTAssertEqual(recorder.written.first?.0, BarConfigGenerator.generateData(draft, helpers: helpers))
    }

    func testAvailabilityFollowsTheBinaryAndAMissingBinaryStillWritesTheConfig() {
        let recorder = Recorder()
        XCTAssertTrue(makeBackend(recorder, existing: nil).isAvailable)

        let uninstalled = makeBackend(recorder, existing: nil, binary: nil)
        XCTAssertFalse(uninstalled.isAvailable)
        XCTAssertThrowsError(try uninstalled.apply(BarDraft())) { error in
            guard case SketchybarBackendError.reloadFailed(let outcome, _) = error else {
                return XCTFail("expected a reload failure, got \(error)")
            }
            XCTAssertEqual(outcome, .created, "the page still edits and saves without sketchybar")
        }
        XCTAssertEqual(recorder.written.count, 1)
        XCTAssertEqual(recorder.reloaded, 0)
    }

    func testItAnswersThroughTheBackendProtocol() throws {
        // The Settings page holds an `any BarBackend` and never names sketchybar, so the
        // behaviour is exercised through the protocol and not through the concrete type.
        let recorder = Recorder()
        let backend: any BarBackend = makeBackend(recorder, existing: nil)
        XCTAssertTrue(backend.isAvailable)
        XCTAssertEqual(try backend.apply(BarDraft()), .created)
        XCTAssertEqual(recorder.written.count, 1)
    }

    func testAnUnreadableFileIsTreatedAsAUserConfig() throws {
        let recorder = Recorder()
        let backend = SketchybarBackend(
            configUrl: configUrl,
            helpers: helpers,
            binaryLocator: { URL(filePath: "/opt/homebrew/bin/sketchybar") },
            fileExists: { _ in true },
            fileReader: { _ in throw Failure.write },
            directoryCreator: { _ in },
            backupCreator: { [backupUrl] url in recorder.backedUp.append(url); return backupUrl },
            atomicWriter: { data, url, permissions in recorder.written.append((data, url, permissions)) },
            commandRunner: { _, arguments in recorder.commands.append(arguments) },
        )
        XCTAssertEqual(try backend.apply(BarDraft()), .replacedUserConfig(backup: backupUrl))
    }

    func testTheDefaultBackupNameCarriesATimestampAndNeverClobbers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "aerospace-bar-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(component: "sketchybarrc")
        try Data("require('bar')\n".utf8).write(to: target)

        let now = Date(timeIntervalSince1970: 1_788_211_504) // 2026-08-31 21:25:04 UTC
        let first = try SketchybarBackend.createBackup(of: target, now: now)
        XCTAssertEqual(first.lastPathComponent, "sketchybarrc.backup-2026-08-31-212504")
        XCTAssertEqual(try Data(contentsOf: first), Data("require('bar')\n".utf8))

        // A second save in the same second must not overwrite the first backup.
        let second = try SketchybarBackend.createBackup(of: target, now: now)
        XCTAssertEqual(second.lastPathComponent, "sketchybarrc.backup-2026-08-31-212504-2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    // MARK: - Live preview

    func testALivePushRunsTheDiffAndWritesNothing() throws {
        let recorder = Recorder()
        var next = BarDraft()
        next.items = [BarItem(id: "clock", cluster: .right)]

        try makeBackend(recorder, existing: nil).applyLive(from: BarDraft(), to: next)

        XCTAssertTrue(recorder.written.isEmpty, "the live bar is scratch state, never a file")
        XCTAssertTrue(recorder.backedUp.isEmpty)
        XCTAssertEqual(recorder.reloaded, 0, "a reload would throw the preview away")
        XCTAssertEqual(
            recorder.commands,
            [BarLiveDiff.commands(from: BarDraft(), to: next, helpers: helpers).flatMap { $0 }],
            "the whole diff goes out as one invocation, so the bar never shows it half applied",
        )
    }

    func testALivePushOfNoChangeSpawnsNothing() throws {
        let recorder = Recorder()
        var draft = BarDraft()
        draft.items = [BarItem(id: "clock", cluster: .right)]

        try makeBackend(recorder, existing: nil).applyLive(from: draft, to: draft)

        XCTAssertTrue(recorder.commands.isEmpty, "a drag that lands where it started costs nothing")
    }

    func testALiveRunnerFailureIsReported() {
        let recorder = Recorder()
        var next = BarDraft()
        next.geometry.height = 44
        let backend = makeBackend(recorder, existing: nil, commandError: Failure.command)

        XCTAssertThrowsError(try backend.applyLive(from: BarDraft(), to: next)) { error in
            guard case SketchybarBackendError.livePushFailed(let underlying) = error else {
                return XCTFail("expected a live push failure, got \(error)")
            }
            XCTAssertEqual(underlying as? Failure, .command)
        }
        XCTAssertTrue(recorder.written.isEmpty)
    }

    func testALivePushWithoutSketchybarSaysSoAndWritesNothing() {
        let recorder = Recorder()
        var next = BarDraft()
        next.geometry.height = 44
        let backend = makeBackend(recorder, existing: nil, binary: nil)

        XCTAssertThrowsError(try backend.applyLive(from: BarDraft(), to: next)) { error in
            guard case SketchybarBackendError.notInstalled = error else {
                return XCTFail("expected a not-installed failure, got \(error)")
            }
        }
        XCTAssertTrue(recorder.written.isEmpty)
    }

    func testDiscardingLiveChangesReloadsTheFileOnDisk() throws {
        let recorder = Recorder()
        try makeBackend(recorder, existing: nil).discardLiveChanges()

        XCTAssertEqual(recorder.commands, [["--reload"]], "the saved file is the restore")
        XCTAssertTrue(recorder.written.isEmpty)
    }

    func testDiscardingLiveChangesWithoutSketchybarSaysSo() {
        let recorder = Recorder()
        XCTAssertThrowsError(try makeBackend(recorder, existing: nil, binary: nil).discardLiveChanges()) { error in
            guard case SketchybarBackendError.notInstalled = error else {
                return XCTFail("expected a not-installed failure, got \(error)")
            }
        }
    }

    // MARK: -

    private func makeBackend(
        _ recorder: Recorder,
        existing: String?,
        binary: URL? = URL(filePath: "/opt/homebrew/bin/sketchybar"),
        backupError: Failure? = nil,
        writeError: Failure? = nil,
        commandError: Failure? = nil,
    ) -> SketchybarBackend {
        let backupUrl = backupUrl
        return SketchybarBackend(
            configUrl: configUrl,
            helpers: helpers,
            binaryLocator: { binary },
            fileExists: { _ in existing != nil },
            fileReader: { _ in Data((existing ?? "").utf8) },
            directoryCreator: { recorder.directoriesCreated.append($0) },
            backupCreator: { url in
                if let backupError { throw backupError }
                recorder.backedUp.append(url)
                return backupUrl
            },
            atomicWriter: { data, url, permissions in
                if let writeError { throw writeError }
                recorder.written.append((data, url, permissions))
            },
            commandRunner: { _, arguments in
                if let commandError { throw commandError }
                recorder.commands.append(arguments)
            },
        )
    }
}
