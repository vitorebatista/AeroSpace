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
}
