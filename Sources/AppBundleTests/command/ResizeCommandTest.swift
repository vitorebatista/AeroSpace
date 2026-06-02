@testable import AppBundle
import Common
import XCTest

@MainActor
final class ResizeCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseCommand() {
        testParseCommandSucc("resize smart +10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .add(10)))
        testParseCommandSucc("resize smart -10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .subtract(10)))
        testParseCommandSucc("resize smart 10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .set(10)))

        testParseCommandSucc("resize smart-opposite +10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .add(10)))
        testParseCommandSucc("resize smart-opposite -10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .subtract(10)))
        testParseCommandSucc("resize smart-opposite 10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .set(10)))

        testParseCommandSucc("resize height 10", ResizeCmdArgs(rawArgs: [], dimension: .height, units: .set(10)))
        testParseCommandSucc("resize width 10", ResizeCmdArgs(rawArgs: [], dimension: .width, units: .set(10)))

        testParseCommandFail("resize s 10", msg: """
            ERROR: Can't parse 's'.
                   Possible values: (width|height|smart|smart-opposite)
            """, exitCode: 2)
        testParseCommandFail("resize smart foo", msg: "ERROR: <number> argument must be a number", exitCode: 2)
    }

    // MARK: - Floating window resize

    /// Helper: create a focused floating window (parent is the workspace) with a known rect.
    private func newFocusedFloatingWindow(rect: Rect) -> (Workspace, TestWindow) {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        let window = TestWindow.new(id: 1, parent: workspace, rect: rect)
        assertEquals(window.isFloating, true)
        assertEquals(window.focusWindow(), true)
        return (workspace, window)
    }

    func testFloating_addWidth_growsAndRecenters() async throws {
        let (_, window) = newFocusedFloatingWindow(rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200))
        let result = try await ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: .width, units: .add(100)))
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect().orDie()
        // newX = max(0, 100 - 100/2) = 50, newY unchanged, width grows by 100.
        assertEquals(rect.topLeftX, 50)
        assertEquals(rect.topLeftY, 100)
        assertEquals(rect.width, 300)
        assertEquals(rect.height, 200)
    }

    func testFloating_addHeight_growsAndRecenters() async throws {
        let (_, window) = newFocusedFloatingWindow(rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200))
        let result = try await ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: .height, units: .add(100)))
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect().orDie()
        assertEquals(rect.topLeftX, 100)
        assertEquals(rect.topLeftY, 50)
        assertEquals(rect.width, 200)
        assertEquals(rect.height, 300)
    }

    func testFloating_setWidth_shrinks() async throws {
        let (_, window) = newFocusedFloatingWindow(rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200))
        let result = try await ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: .width, units: .set(100)))
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect().orDie()
        // diff = 100 - 200 = -100, diffSize = (-100, 0). newX = max(0, 100 - (-100)/2) = 150.
        assertEquals(rect.topLeftX, 150)
        assertEquals(rect.topLeftY, 100)
        assertEquals(rect.width, 100)
        assertEquals(rect.height, 200)
    }

    func testFloating_addWidth_clampsToMonitorRightEdge() async throws {
        // Window near the right edge: topLeftX + width + diff/2 exceeds monitor width (1920),
        // so newX is pinned to keep the grown window inside the monitor.
        let (_, window) = newFocusedFloatingWindow(rect: Rect(topLeftX: 1800, topLeftY: 100, width: 100, height: 100))
        let result = try await ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: .width, units: .add(100)))
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect().orDie()
        // 1800 + 100 + 50 = 1950 > 1920 -> newX = max(0, 1920 - 100 - 100) = 1720.
        assertEquals(rect.topLeftX, 1720)
        assertEquals(rect.width, 200)
    }

    func testFloating_addHeight_clampsToMonitorBottomEdge() async throws {
        // Window near the bottom edge of the monitor (maxY = 1080): growing height would push
        // topLeftY + height + diff/2 below the monitor, so newY is pinned to keep the grown
        // window inside the monitor.
        let (_, window) = newFocusedFloatingWindow(rect: Rect(topLeftX: 100, topLeftY: 1000, width: 200, height: 100))
        let result = try await ResizeCommand(args: ResizeCmdArgs(rawArgs: [], dimension: .height, units: .add(100)))
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect().orDie()
        // 1000 + 100 + 50 = 1150 > 1080 -> newY = max(0, 1080 - 100 - 100) = 880.
        // newX is unaffected (width fits), so it stays recentered at 100.
        assertEquals(rect.topLeftX, 100)
        assertEquals(rect.topLeftY, 880)
        assertEquals(rect.width, 200)
        assertEquals(rect.height, 200)
    }
}
