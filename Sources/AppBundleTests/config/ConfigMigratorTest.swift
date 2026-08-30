@testable import AppBundle
import Common
import XCTest

@MainActor
final class ConfigMigratorTest: XCTestCase {
    func testMigrateAddsVersionAndPersistentWorkspacesToAnImplicitV1Config() {
        let candidate = migrate(
            """
            [mode.main.binding]
            alt-1 = 'workspace 1'
            """,
        )

        assertEquals(candidate.fromVersion, 1)
        assertEquals(candidate.toVersion, 2)
        assertEquals(candidate.persistentWorkspaces, ["1"])
        assertEquals(
            candidate.text,
            """
            config-version = 2
            persistent-workspaces = ['1']
            [mode.main.binding]
            alt-1 = 'workspace 1'
            """,
        )
    }

    func testMigrateRewritesAnExplicitV1VersionInPlace() {
        let candidate = migrate(
            """
            # Keep this comment
            config-version = 1 # old format
            start-at-login = true

            [mode.main.binding]
            alt-w = 'workspace web'
            """,
        )

        assertEquals(
            candidate.text,
            """
            # Keep this comment
            config-version = 2 # old format
            start-at-login = true
            persistent-workspaces = ['web']

            [mode.main.binding]
            alt-w = 'workspace web'
            """,
        )
    }

    func testMigrateRejectsUnsupportedPaths() {
        assertEquals(
            ConfigMigrator.migrate(text: "", from: 2, to: 1),
            .failure(.unsupportedPath(from: 2, to: 1)),
        )
    }

    func testMigrateRejectsAnInvalidSource() {
        assertEquals(
            ConfigMigrator.migrate(text: "config-version = 0\n", from: 1, to: 2),
            .failure(.invalidSource(["config-version: Must be in [1, 2] range"])),
        )
    }

    func testMigrateEmitsBindingThenAssignmentWorkspacesInSourceOrder() {
        let candidate = migrate(
            """
            [key-mapping]
            preset = 'qwerty'

            [key-mapping.key-notation-to-key-code]
            zz = 'a'

            [mode.main.binding]
            alt-zz = ['workspace three', 'move-node-to-workspace two']
            alt-1 = 'workspace one'

            [mode.second.binding]
            alt-2 = 'move-node-to-workspace four'

            [workspace-to-monitor-force-assignment]
            five = 'main'
            two = 'secondary'
            """,
        )

        assertEquals(candidate.persistentWorkspaces, ["three", "two", "one", "four", "five"])
        XCTAssertTrue(candidate.text.contains("persistent-workspaces = ['three', 'two', 'one', 'four', 'five']"))
    }

    func testMigrateOnlyRewritesVersionAndPersistentWorkspaceLines() {
        let candidate = migrate(
            """
            config-version = 1
            # This block must stay byte-for-byte identical.
            [mode.main.binding]
            alt-1 = [
                'workspace 1', # keep
                'move-node-to-workspace 2',
            ]
            """,
        )

        assertEquals(
            candidate.text,
            """
            config-version = 2
            persistent-workspaces = ['1', '2']
            # This block must stay byte-for-byte identical.
            [mode.main.binding]
            alt-1 = [
                'workspace 1', # keep
                'move-node-to-workspace 2',
            ]
            """,
        )
    }

    private func migrate(_ text: String) -> ConfigMigrationCandidate {
        switch ConfigMigrator.migrate(text: text, from: 1, to: 2) {
            case .success(let candidate): return candidate
            case .failure(let error):
                XCTFail("Migration failed: \(error)")
                fatalError("Migration failed")
        }
    }
}
