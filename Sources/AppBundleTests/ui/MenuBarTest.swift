@testable import AppBundle
import XCTest

@MainActor
final class MenuBarTest: XCTestCase {
    private func ws(_ name: String) -> WorkspaceViewModel {
        WorkspaceViewModel(
            name: name,
            suffix: "",
            isFocused: false,
            isEffectivelyEmpty: true,
            isVisible: false,
            hasFullscreenWindows: false,
        )
    }

    private func names(_ workspaces: [WorkspaceViewModel]) -> [String] { workspaces.map(\.name) }

    func testMixed_persistentFirstInConfigOrderThenRestAlphabetical() {
        // Input order is intentionally shuffled to prove the comparator (not input order) drives output.
        let input = [ws("delta"), ws("2"), ws("alpha"), ws("1"), ws("charlie")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: ["2", "1"])
        // Persistent first in config order ("2" before "1"), then the rest alphabetically.
        assertEquals(names(result), ["2", "1", "alpha", "charlie", "delta"])
    }

    func testAllPersistent_keepConfigOrder() {
        let input = [ws("a"), ws("b"), ws("c")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: ["c", "a", "b"])
        assertEquals(names(result), ["c", "a", "b"])
    }

    func testNonePersistent_alphabetical() {
        let input = [ws("charlie"), ws("alpha"), ws("bravo")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: [])
        assertEquals(names(result), ["alpha", "bravo", "charlie"])
    }

    func testPersistentNameNotPresentInWorkspaces_isIgnored() {
        // A persistent name with no matching workspace doesn't appear and doesn't disturb ordering.
        let input = [ws("b"), ws("a")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: ["z", "a"])
        // "a" is persistent (present), "b" is not -> "a" first, then "b".
        assertEquals(names(result), ["a", "b"])
    }

    func testEmptyInput() {
        let result = sortWorkspacesForMenuBar([], persistentWorkspaces: ["1", "2"])
        assertEquals(names(result), [])
    }
}
