@testable import AppBundle
import XCTest

final class PersistedFocusTest: XCTestCase {
    func testTheWorkspaceYouLeftOffOnIsRestored() {
        assertEquals(workspaceToFocusAtStartup(persisted: "4", existing: ["1", "2", "4"]), "4")
    }

    func testNothingPersistedKeepsWhateverStartupChose() {
        assertEquals(workspaceToFocusAtStartup(persisted: nil, existing: ["1", "2"]), nil)
    }

    /// The config can drop a workspace between runs. Focusing it would recreate it as a side
    /// effect of restarting, so a name that no longer exists is ignored.
    func testAWorkspaceThatNoLongerExistsIsNotResurrected() {
        assertEquals(workspaceToFocusAtStartup(persisted: "gone", existing: ["1", "2"]), nil)
    }
}
