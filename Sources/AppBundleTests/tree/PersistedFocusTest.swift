@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class PersistedFocusTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        UserDefaults.standard.removeObject(forKey: focusedWorkspaceDefaultsKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: focusedWorkspaceDefaultsKey)
    }

    func testFocusedWorkspaceIsStoredImmediately() {
        let workspace = Workspace.get(byName: "1")
        assertEquals(workspace.focusWorkspace(), true)

        assertEquals(storedFocusedWorkspace(), "1")
    }

    func testRefocusingTheSameWorkspaceDoesNotRewriteTheStore() {
        assertEquals(Workspace.get(byName: "1").focusWorkspace(), true)
        storeFocusedWorkspace("stale-marker")

        assertEquals(Workspace.get(byName: "1").focusWorkspace(), true)
        assertEquals(storedFocusedWorkspace(), "stale-marker")
    }

    func testTheWorkspaceYouLeftOffOnIsRestored() {
        assertEquals(workspaceToFocusAtStartup(persisted: "4", existing: ["1", "2", "4"]), "4")
    }

    func testImmediatelyRememberedWorkspaceWinsOverOlderLayoutSnapshot() {
        assertEquals(workspaceToFocusAtStartup(remembered: "1", persisted: "4", existing: ["1", "4"]), "1")
    }

    func testNothingPersistedKeepsWhateverStartupChose() {
        assertEquals(workspaceToFocusAtStartup(persisted: nil, existing: ["1", "2"]), nil)
        assertEquals(workspaceToFocusAtStartup(remembered: nil, persisted: nil, existing: ["1", "2"]), nil)
    }

    /// The config may have dropped the workspace between runs. Focusing it by name would create it,
    /// so a restart would resurrect a workspace the user deleted.
    func testAWorkspaceThatNoLongerExistsIsNotResurrected() {
        assertEquals(workspaceToFocusAtStartup(persisted: "gone", existing: ["1", "2"]), nil)
        assertEquals(workspaceToFocusAtStartup(remembered: "gone", persisted: nil, existing: ["1", "2"]), nil)
    }

    func testInvalidRememberedWorkspaceFallsBackToLayoutSnapshot() {
        assertEquals(workspaceToFocusAtStartup(remembered: "gone", persisted: "4", existing: ["1", "4"]), "4")
    }

    /// On `config-version = 2` a workspace named only by a binding is not a live object until it is
    /// first visited, so `Workspace.all` alone would refuse to return the user to it.
    func testAWorkspaceDeclaredOnlyByABindingIsStillRestored() {
        let (config, errors) = parseConfig("""
            [mode.main.binding]
            alt-d = 'workspace D'
            """)
        assertEquals(errors, [])
        assertEquals(Workspace.all.map(\.name).contains("D"), false)

        assertEquals(
            workspaceToFocusAtStartup(
                remembered: "D",
                persisted: nil,
                existing: Workspace.all.map(\.name) + Array(workspaceNamesMentionedIn(config)),
            ),
            "D",
        )
    }
}
