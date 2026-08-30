@testable import AppBundle
import Common
import Foundation
import XCTest

@MainActor
final class SettingsModelTest: XCTestCase {
    private enum ExpectedFailure: Error {
        case backup
        case write
        case reload
    }

    func testInheritEnvVarsWithATrailingComment() {
        let raw = SettingsModel.rawExecConfig(from: "[exec]\ninherit-env-vars = true  # keep my PATH\n")
        assertEquals(raw.inheritEnvVariables, true)
    }

    func testEnvVarWithATrailingComment() {
        let raw = SettingsModel.rawExecConfig(from: """
            [exec.env-vars]
            PATH = '/opt/homebrew/bin' # my path
            """)
        assertEquals(raw.overriddenVars["PATH"], "/opt/homebrew/bin")
    }

    func testDottedKeyFormIsSeen() {
        // No `[exec]` header at all. Missing this used to leave the draft on the default
        // `true`, after which the writer deleted the dotted key and wrote nothing back.
        let raw = SettingsModel.rawExecConfig(from: "exec.inherit-env-vars = false\n")
        assertEquals(raw.inheritEnvVariables, false)
    }

    func testDottedEnvVarKeyIsSeen() {
        let raw = SettingsModel.rawExecConfig(from: "exec.env-vars.FOO = 'bar'\n")
        assertEquals(raw.overriddenVars["FOO"], "bar")
    }

    func testQuotedEnvVarKeyIsSeenAsOneName() {
        // A dot in a quoted TOML key is part of the environment variable's name, not a
        // nested table. This is the spelling ConfigTomlWriter emits for UI input such as
        // "MY.PATH", so recovering it correctly is required before the user edits [exec].
        let raw = SettingsModel.rawExecConfig(from: "[exec.env-vars]\n'MY.PATH' = 'bin'\n")
        assertEquals(raw.overriddenVars, ["MY.PATH": "bin"])
    }

    func testValuesAreNotInterpolated() {
        // `$VAR` has to come back exactly as written: this value is destined to be written
        // straight back into the user's file, not to be executed.
        let raw = SettingsModel.rawExecConfig(from: "[exec.env-vars]\nPATH = '/my/bin:${PATH}'\n")
        assertEquals(raw.overriddenVars["PATH"], "/my/bin:${PATH}")
    }

    func testEscapesInABasicStringAreResolved() {
        let raw = SettingsModel.rawExecConfig(from: #"""
        [exec.env-vars]
        QUOTED = "a\"b"
        """#)
        assertEquals(raw.overriddenVars["QUOTED"], #"a"b"#)
    }

    func testDefaultsWhenThereIsNoExecTable() {
        let raw = SettingsModel.rawExecConfig(from: "start-at-login = true\n")
        assertEquals(raw.inheritEnvVariables, true)
        assertEquals(raw.overriddenVars, [:])
    }

    func testUnparseableConfigFallsBackToDefaults() {
        let raw = SettingsModel.rawExecConfig(from: "this is not toml [[[\n")
        assertEquals(raw.inheritEnvVariables, true)
        assertEquals(raw.overriddenVars, [:])
    }

    func testRequiresVersionMigrationOnlyForLoadedV1DraftV2() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        try Data(v1Config.utf8).write(to: target)
        let model = makeModel(target: target)

        model.load()
        XCTAssertFalse(model.requiresVersionMigration)

        model.draft.configVersion = 2
        XCTAssertTrue(model.requiresVersionMigration)

        model.draft.configVersion = 1
        XCTAssertFalse(model.requiresVersionMigration)
    }

    func testMigrationBacksUpOriginalAndAppliesDraftEditsToMigratedBaseline() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let model = makeModel(target: target)
        model.load()
        model.draft.configVersion = 2
        model.draft.startAtLogin = true

        await model.save()

        guard case .migrated(let backupUrl) = model.status else {
            return XCTFail("Expected migrated status, got \(String(describing: model.status))")
        }
        XCTAssertEqual(backupUrl, backupUrl.absoluteURL)
        XCTAssertEqual(backupUrl.deletingLastPathComponent(), directory)
        XCTAssertEqual(try Data(contentsOf: backupUrl), original)
        let written = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(written.contains("config-version = 2"))
        XCTAssertTrue(written.contains("persistent-workspaces = ['two', 'one', 'assigned']"))
        XCTAssertTrue(written.contains("start-at-login = true"))
        XCTAssertTrue(written.contains("# untouched marker"))
    }

    func testMigrationKeepsUserEditedPersistentWorkspaceOrder() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        try Data(v1Config.utf8).write(to: target)
        let model = makeModel(target: target)
        model.load()
        model.draft.configVersion = 2
        model.draft.persistentWorkspaces = ["custom", "two"]

        await model.save()

        let written = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(written.contains("persistent-workspaces = ['custom', 'two']"))
    }

    func testInvalidMigrationCandidateCreatesNoBackupAndDoesNotChangeTarget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let originalDirectoryEntries = try directoryEntries(in: directory)
        let model = makeModel(target: target)
        model.load()
        model.draft.configVersion = 2
        model.draft.rawKeybindings = "[mode.main.binding]\nalt-a = 'not-a-command'\n"

        await model.save()

        assertIsError(model.status)
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try directoryEntries(in: directory), originalDirectoryEntries)
    }

    func testBackupFailureDoesNotWriteAndLeavesDirectoryUnchanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let originalDirectoryEntries = try directoryEntries(in: directory)
        let model = makeModel(
            target: target,
            backupCreator: { _, _ in throw ExpectedFailure.backup },
            atomicWriter: { data, url in try data.write(to: url, options: .atomic) },
        )
        model.load()
        model.draft.configVersion = 2

        await model.save()

        assertIsError(model.status)
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try directoryEntries(in: directory), originalDirectoryEntries)
    }

    func testWriteFailureAfterBackupRestoresExactOriginalBytes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        try original.write(to: target)
        let model = makeModel(
            target: target,
            atomicWriter: { _, url in
                try Data("corrupted".utf8).write(to: url, options: .atomic)
                throw ExpectedFailure.write
            },
        )
        model.load()
        model.draft.configVersion = 2

        await model.save()

        assertIsError(model.status)
        XCTAssertEqual(try Data(contentsOf: target), original)
        let backups = try backupUrls(in: directory)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backups.first)), original)
    }

    func testSavingUnrelatedV1EditCreatesNoBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        try Data(v1Config.utf8).write(to: target)
        let model = makeModel(target: target)
        model.load()
        model.draft.startAtLogin = true

        await model.save()

        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(try backupUrls(in: directory), [])
        let written = try String(contentsOf: target, encoding: .utf8)
        XCTAssertFalse(written.contains("config-version = 2"))
        XCTAssertTrue(written.contains("start-at-login = true"))
    }

    func testMigrationThroughSymlinkPreservesLinkTargetPermissionsAndBackupPlacement() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetDirectory = directory.appending(path: "dotfiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let target = targetDirectory.appending(path: "aerospace.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        let symlink = directory.appending(path: ".aerospace.toml")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let model = makeModel(target: symlink)
        model.load()
        model.draft.configVersion = 2

        await model.save()

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path), target.path)
        XCTAssertNotEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try permissions(of: target), 0o640)
        let backups = try backupUrls(in: targetDirectory)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backups.first)), original)
        XCTAssertEqual(try backupUrls(in: directory), [])
        guard case .migrated(let backupUrl) = model.status else {
            return XCTFail("Expected migrated status, got \(String(describing: model.status))")
        }
        XCTAssertEqual(backupUrl.resolvingSymlinksInPath(), backups.first?.resolvingSymlinksInPath())
    }

    func testReloadFailureKeepsMigratedFileAndReportsBackupPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let model = makeModel(target: target, reloadAfterSave: { throw ExpectedFailure.reload })
        model.load()
        model.draft.configVersion = 2

        await model.save()

        let message = assertIsError(model.status)
        let backup = try XCTUnwrap(backupUrls(in: directory).first)
        XCTAssertTrue(message.contains(backup.resolvingSymlinksInPath().path))
        XCTAssertNotEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    private var v1Config: String {
        """
        # untouched marker
        [mode.main.binding]
        alt-2 = 'workspace two'
        alt-1 = 'move-node-to-workspace one'

        [workspace-to-monitor-force-assignment]
        assigned = 'main'
        """
    }

    private func makeModel(
        target: URL,
        backupCreator: @escaping (URL, Int) throws -> ConfigMigrationBackup = {
            try ConfigMigrationBackup.create(forResolvedTarget: $0, fromVersion: $1)
        },
        atomicWriter: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        reloadAfterSave: @escaping () async throws -> Void = {},
    ) -> SettingsModel {
        SettingsModel(
            configFile: { .file(target) },
            backupCreator: backupCreator,
            atomicWriter: atomicWriter,
            reloadAfterSave: reloadAfterSave,
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SettingsModelTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func directoryEntries(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func backupUrls(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".backup-v") }
    }

    @discardableResult
    private func assertIsError(
        _ status: SettingsStatus?,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> String {
        guard case .error(let message) = status else {
            XCTFail("Expected error status, got \(String(describing: status))", file: file, line: line)
            return ""
        }
        return message
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
