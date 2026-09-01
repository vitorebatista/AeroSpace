@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class BarSettingsModelTest: XCTestCase {
    // MARK: - Loading

    func testAMissingFileLoadsDefaultsAndAnnouncesThatSavingCreatesIt() {
        let model = makeModel()
        model.load()
        assertEquals(model.mode, .form)
        assertEquals(model.willCreateConfig, true)
        assertEquals(model.draft, BarDraft())
    }

    func testAFileThatDoesNotParseRefusesToSave() async {
        let files = FakeBarFiles(contents: "[bar]\nheight = 'tall'\n")
        let model = makeModel(files: files)
        model.load()

        guard case .unreadable = model.mode else { return XCTFail("Expected .unreadable, got \(model.mode)") }
        await model.save()
        // Writing a defaulted draft over a file we could not read would destroy it.
        assertEquals(files.writes, 0)
    }

    // MARK: - Saving

    func testCreatingTheFileWritesEveryModelledKey() async {
        let files = FakeBarFiles()
        let model = makeModel(files: files)
        model.load()
        model.draft.geometry.height = 40
        await model.save()

        let written = files.text
        for key in ["version = 1", "[bar]", "height = 40", "margin = 8", "y-offset = 6", "corner-radius = 10",
                    "border-width = 1", "padding-left = 1", "padding-right = 0", "[bar.colors]",
                    "background = '0xb3202020'", "popup-border = '0xff7f8490'"]
        {
            XCTAssertTrue(written.contains(key), "A newly created bar.toml is missing \(key):\n\(written)")
        }
        assertEquals(model.willCreateConfig, false)
        assertEquals(model.isDirty, false)
    }

    func testEditingAnExistingFileRewritesOnlyTheEditedKey() async {
        let files = FakeBarFiles(contents: existingFile)
        let model = makeModel(files: files)
        model.load()
        model.draft.geometry.height = 44
        await model.save()

        let written = files.text
        XCTAssertTrue(written.contains("height = 44"))
        XCTAssertTrue(written.contains("# my own note"), "A comment outside the edit was dropped:\n\(written)")
        XCTAssertTrue(written.contains("margin = 8   # keep this"), "An untouched key lost its trailing comment:\n\(written)")
    }

    func testItemsAreWrittenInDocumentOrderPerCluster() async {
        let files = FakeBarFiles()
        let model = makeModel(files: files)
        model.load()
        model.draft.add(catalog("workspaces"), to: .left)
        model.draft.add(catalog("clock"), to: .right)
        model.draft.add(catalog("mode"), to: .left)
        await model.save()

        assertEquals(itemIds(files.text), ["workspaces", "mode", "clock"])
        XCTAssertTrue(files.text.contains("show-app-icons = true"), "Catalog defaults were not seeded:\n\(files.text)")
    }

    func testAWriteFailureReportsAndNeverReachesTheBackend() async {
        let files = FakeBarFiles()
        files.writeError = ExpectedFailure.write
        let backend = FakeBarBackend()
        let model = makeModel(files: files, backend: backend)
        model.load()
        model.draft.geometry.height = 40

        await model.save()

        assertIsError(model.status)
        assertEquals(backend.applied.count, 0)
        // The draft is kept, so the user can fix the cause and press Save again.
        assertEquals(model.draft.geometry.height, 40)
    }

    func testAnUnavailableBackendStillSavesAndSaysNothingRenders() async {
        let files = FakeBarFiles()
        let backend = FakeBarBackend(isAvailable: false)
        let model = makeModel(files: files, backend: backend)
        model.load()
        model.draft.geometry.margin = 12

        await model.save()

        XCTAssertTrue(files.text.contains("margin = 12"))
        assertEquals(backend.applied.count, 0)
        guard case .saved(let message) = model.status else { return XCTFail("Expected saved, got \(String(describing: model.status))") }
        XCTAssertTrue(message.contains("isn't installed"), message)
    }

    func testABackendFailureIsReportedWithoutRollingTheFileBack() async {
        let files = FakeBarFiles()
        let backend = FakeBarBackend(result: .failure(ExpectedFailure.apply))
        let model = makeModel(files: files, backend: backend)
        model.load()
        model.draft.geometry.margin = 12

        await model.save()

        XCTAssertTrue(files.text.contains("margin = 12"), "The file on disk is correct and must stay")
        let message = assertIsError(model.status)
        XCTAssertTrue(message.contains("Saved"), message)
    }

    func testTheBackendSeesWhatWasSaved() async {
        let backend = FakeBarBackend()
        let model = makeModel(backend: backend)
        model.load()
        model.draft.geometry.height = 41
        await model.save()

        assertEquals(backend.applied.count, 1)
        assertEquals(backend.applied.last?.geometry.height, 41)
    }

    func testReloadAppliesTheSavedDraftAndNotUnsavedEdits() async {
        let backend = FakeBarBackend()
        let model = makeModel(backend: backend)
        model.load()
        model.draft.geometry.height = 41
        await model.save()

        model.draft.geometry.height = 99 // unsaved
        await model.reloadBar()

        assertEquals(backend.applied.count, 2)
        assertEquals(backend.applied.last?.geometry.height, 41)
    }

    // MARK: - Takeover

    func testTheTakeoverNoticeOutlivesLaterEditsAndOnlyDismissClearsIt() async {
        let backup = URL(filePath: "/tmp/sketchybarrc.backup-2026-08-31-101500")
        let backend = FakeBarBackend(result: .success(.replacedUserConfig(backup: backup)))
        let model = makeModel(backend: backend)
        model.load()
        model.draft.geometry.height = 40
        await model.save()

        assertEquals(model.takeoverBackupUrl, backup)
        model.markEdited() // clears the status line, but not the path back to the user's config
        assertNil(model.status)
        assertEquals(model.takeoverBackupUrl, backup)

        model.dismissTakeoverNotice()
        assertNil(model.takeoverBackupUrl)
    }

    // MARK: - Ordered item edits

    func testMoveReordersOnlyItsOwnCluster() {
        var draft = BarDraft()
        draft.add(catalog("workspaces"), to: .left)
        draft.add(catalog("clock"), to: .right)
        draft.add(catalog("mode"), to: .left)
        draft.add(catalog("battery"), to: .right)

        draft.move(in: .left, fromOffsets: IndexSet(integer: 1), toOffset: 0)

        assertEquals(draft.items(in: .left).map(\.id), ["mode", "workspaces"])
        assertEquals(draft.items(in: .right).map(\.id), ["clock", "battery"])
    }

    func testAddAppendsToTheEndOfItsOwnCluster() {
        var draft = BarDraft()
        draft.add(catalog("clock"), to: .right)
        draft.add(catalog("workspaces"), to: .left)
        draft.add(catalog("battery"), to: .right)

        assertEquals(draft.items.map(\.id), ["clock", "battery", "workspaces"])
        assertEquals(draft.positions(in: .right), [0, 1])
    }

    func testRemoveTakesTheEntryAtTheClusterOffset() {
        var draft = BarDraft()
        draft.add(catalog("workspaces"), to: .left)
        draft.add(catalog("clock"), to: .right)
        draft.add(catalog("battery"), to: .right)

        draft.remove(in: .right, atOffsets: IndexSet(integer: 0))

        assertEquals(draft.items.map(\.id), ["workspaces", "battery"])
    }

    func testASettingFallsBackToTheCatalogDefaultUntilItIsSet() {
        var draft = BarDraft()
        draft.items = [BarItem(id: "clock", cluster: .right)] // no [item.settings] at all
        let format = catalog("clock").setting("format").orDie()

        assertEquals(draft.settingValue(at: 0, format), .string("%a %d %b %H:%M"))
        draft.setSettingValue(at: 0, "format", .string("%H:%M"))
        assertEquals(draft.settingValue(at: 0, format), .string("%H:%M"))
    }

    func testUnrecognisedSettingsArePreservedAndReported() async {
        let files = FakeBarFiles(contents: """
            [[item]]
            id = 'clock'
            cluster = 'right'

            [item.settings]
            format = '%H:%M'
            future-key = 'from a newer release'

            """)
        let model = makeModel(files: files)
        model.load()

        assertEquals(model.draft.unrecognisedSettings(at: 0), [BarUnrecognisedSetting(key: "future-key", value: .string("from a newer release"))])

        model.draft.geometry.height = 40
        await model.save()
        XCTAssertTrue(files.text.contains("future-key = 'from a newer release'"), "A key we don't model was dropped:\n\(files.text)")
    }

    // MARK: - Helpers

    private enum ExpectedFailure: Error {
        case write
        case apply
    }

    private var existingFile: String {
        """
        version = 1

        # my own note
        [bar]
        height = 32
        margin = 8   # keep this

        """
    }

    private func catalog(_ id: String) -> BarCatalogItem { BarCatalog.item(id: id).orDie() }

    private func itemIds(_ text: String) -> [String] {
        text.split(separator: "\n")
            .filter { $0.hasPrefix("id = ") }
            .map { $0.replacingOccurrences(of: "id = ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
    }

    private func makeModel(
        files: FakeBarFiles = FakeBarFiles(),
        backend: any BarBackend = FakeBarBackend(),
    ) -> BarSettingsModel {
        BarSettingsModel(
            configUrl: files.url,
            backend: backend,
            textReader: { [files] _ in files.read() },
            atomicWriter: { [files] data, _, _ in try files.write(data) },
            directoryCreator: { _ in },
        )
    }

    @discardableResult
    private func assertIsError(
        _ status: BarSettingsStatus?,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> String {
        guard case .error(let message) = status else {
            XCTFail("Expected error status, got \(String(describing: status))", file: file, line: line)
            return ""
        }
        return message
    }
}

/// `bar.toml` as bytes in memory. The model reaches the file system through two injected
/// closures and nothing else, so a save is exercised end to end — surgical rewrite included —
/// without a temp directory.
private final class FakeBarFiles: @unchecked Sendable {
    let url = URL(filePath: "/tmp/aerospace-bar-test/bar.toml")
    private let lock = NSLock()
    private var contents: String?
    private var writeCount = 0
    var writeError: (any Error)?

    init(contents: String? = nil) { self.contents = contents }

    var text: String { lock.withLock { contents ?? "" } }
    var writes: Int { lock.withLock { writeCount } }

    func read() -> String? { lock.withLock { contents } }

    func write(_ data: Data) throws {
        if let writeError { throw writeError }
        lock.withLock {
            contents = String(decoding: data, as: UTF8.self)
            writeCount += 1
        }
    }
}

/// A backend that records what it was handed. `apply` runs off the MainActor, so the
/// recording is locked.
private final class FakeBarBackend: BarBackend, @unchecked Sendable {
    let isAvailable: Bool
    private let result: Result<BarApplyOutcome, any Error>
    private let lock = NSLock()
    private var appliedDrafts: [BarDraft] = []

    init(isAvailable: Bool = true, result: Result<BarApplyOutcome, any Error> = .success(.updated)) {
        self.isAvailable = isAvailable
        self.result = result
    }

    var applied: [BarDraft] { lock.withLock { appliedDrafts } }

    func apply(_ draft: BarDraft) throws -> BarApplyOutcome {
        lock.withLock { appliedDrafts.append(draft) }
        return try result.get()
    }
}
