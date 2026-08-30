@testable import AppBundle
import Common
import XCTest

final class RefreshSessionSchedulingTest: XCTestCase {
    func testStartupDoesNotScheduleFollowUpRefresh() {
        XCTAssertFalse(shouldScheduleFollowUpRefresh(after: .startup))
    }

    func testNonStartupEventSchedulesFollowUpRefresh() {
        XCTAssertTrue(shouldScheduleFollowUpRefresh(after: .menuBarButton))
    }
}
