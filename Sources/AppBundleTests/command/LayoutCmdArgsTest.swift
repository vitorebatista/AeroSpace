@testable import AppBundle
import Common
import XCTest

final class LayoutCmdArgsTest: XCTestCase {
    func testParseSticky() {
        let cmd = parseCommand("layout sticky").cmdOrDie as! LayoutCommand
        assertEquals(cmd.args.toggleBetween.val, [.sticky])
    }

    func testParseStickyAmongOthers() {
        let cmd = parseCommand("layout sticky floating").cmdOrDie as! LayoutCommand
        assertEquals(cmd.args.toggleBetween.val, [.sticky, .floating])
    }

    func testParseUnknownLayout() {
        switch parseCommand("layout bogus") {
            case .cmd, .help: XCTFail("Expected failure")
            case .failure: break
        }
    }
}
