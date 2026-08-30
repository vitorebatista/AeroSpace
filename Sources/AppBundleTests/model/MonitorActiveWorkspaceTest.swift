@testable import AppBundle
import Common
import XCTest

private struct DetachedMonitor: Monitor {
    let monitorAppKitNsScreenScreensId = 42
    let name = "Detached"
    let rect: Rect
    var visibleRect: Rect { rect }
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    let isMain = false
}

@MainActor
final class MonitorActiveWorkspaceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// Regression: a `Monitor` that `NSScreen.screens` no longer reports (display
    /// reconfiguration — closing/opening the lid with external monitors attached) used to
    /// send `activeWorkspace` into unbounded recursion and blow the stack.
    func testActiveWorkspaceOfDetachedMonitorTerminates() {
        // `monitors` is `[testMonitor]` at (0, 0) under test, so this one can never be found.
        let detached = DetachedMonitor(rect: Rect(topLeftX: 9000, topLeftY: 9000, width: 1920, height: 1080))
        assertNotNil(detached.activeWorkspace) // Hangs/crashes if the recursion comes back
    }
}
