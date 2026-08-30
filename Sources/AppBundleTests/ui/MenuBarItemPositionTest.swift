@testable import AppBundle
import XCTest

final class MenuBarItemPositionTest: XCTestCase {
    func testZeroAndNegativeLeaveThePositionToMacOs() {
        assertEquals(statusItemPositionToPersist(0), nil)
        assertEquals(statusItemPositionToPersist(-1), nil)
    }

    func testAPositiveValueIsPersisted() {
        assertEquals(statusItemPositionToPersist(400), 400)
    }

    func testAValueThatWouldHideTheItemIsFlagged() {
        XCTAssertNotNil(menuBarPositionWarning(2000, screenWidth: 1512))
        XCTAssertNotNil(menuBarPositionWarning(1313, screenWidth: 1512))
    }

    func testAUsableValueIsNotFlagged() {
        assertEquals(menuBarPositionWarning(400, screenWidth: 1512), nil)
        assertEquals(menuBarPositionWarning(1312, screenWidth: 1512), nil)
        // 0 means "let macOS decide", and an unknown screen can't be judged.
        assertEquals(menuBarPositionWarning(0, screenWidth: 1512), nil)
        assertEquals(menuBarPositionWarning(2000, screenWidth: nil), nil)
    }
}
