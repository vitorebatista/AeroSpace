@testable import AppBundle
import Common
import XCTest

@MainActor
final class SummonWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
    }

    func testParseWhenVisibleDefault() {
        let cmd = parseCommand("summon-workspace foo").cmdOrDie as! SummonWorkspaceCommand
        assertEquals(cmd.args.rawWhenVisibleAction, nil)
        assertEquals(cmd.args.whenVisible, .focus)
    }

    func testParseWhenVisibleFocus() {
        let cmd = parseCommand("summon-workspace --when-visible focus foo").cmdOrDie as! SummonWorkspaceCommand
        assertEquals(cmd.args.whenVisible, .focus)
    }

    func testParseWhenVisibleSwap() {
        let cmd = parseCommand("summon-workspace --when-visible swap foo").cmdOrDie as! SummonWorkspaceCommand
        assertEquals(cmd.args.whenVisible, .swap)
    }

    func testParseWhenVisibleUnknown() {
        XCTAssertNotNil(parseCommand("summon-workspace --when-visible bogus foo").errorOrNil)
    }
}
