@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("list-windows --pid 1").errorOrNil, "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        assertNil(parseCommand("list-windows --workspace M --pid 1").errorOrNil)
        assertEquals(parseCommand("list-windows --pid 1 --focused").errorOrNil, "--focused conflicts with other \"filtering\" flags")
        assertEquals(parseCommand("list-windows --pid 1 --all").errorOrNil, "--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")
        assertNil(parseCommand("list-windows --all").errorOrNil)
        assertEquals(parseCommand("list-windows --all --workspace M").errorOrNil, "ERROR: Conflicting options: --all, --workspace")
        assertEquals(parseCommand("list-windows --all --focused").errorOrNil, "ERROR: Conflicting options: --all, --focused")
        assertEquals(parseCommand("list-windows --all --count --format %{window-title}").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse").errorOrNil,
            "ERROR: Conflicting options: --all, --focused")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --focused, --workspace")
        assertEquals(
            parseCommand("list-windows --all --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --workspace")
        assertNil(parseCommand("list-windows --monitor mouse").errorOrNil)

        // --json
        assertEquals(parseCommand("list-windows --all --count --json").errorOrNil, "ERROR: Conflicting options: --count, --json")
        assertEquals(parseCommand("list-windows --all --format '%{right-padding}' --json").errorOrNil, "%{right-padding} interpolation variable is not allowed when --json is used")
        assertEquals(parseCommand("list-windows --all --format '%{window-title} |' --json").errorOrNil, "Only interpolation variables and spaces are allowed in \'--format\' when \'--json\' is used")
        assertNil(parseCommand("list-windows --all --format '%{window-title}' --json").errorOrNil)
    }

    func testParseSort() {
        // Default sort
        assertEquals((parseCommand("list-windows --all").cmdOrNil as? ListWindowsCommand)?.args.sort, [.appName, .windowTitle])
        // Single value
        assertEquals((parseCommand("list-windows --all --sort recent").cmdOrNil as? ListWindowsCommand)?.args.sort, [.recent])
        // Comma-separated multi value
        assertEquals(
            (parseCommand("list-windows --all --sort recent,app-name,window-title").cmdOrNil as? ListWindowsCommand)?.args.sort,
            [.recent, .appName, .windowTitle],
        )
        // Invalid value
        assertEquals(parseCommand("list-windows --all --sort bogus").errorOrNil, "ERROR: Invalid sort option 'bogus'. Valid options: recent, app-name, window-title")
        // Missing value
        assertEquals(parseCommand("list-windows --all --sort").errorOrNil, "ERROR: '--sort' requires a value. Valid options: recent, app-name, window-title")
    }

    func testSortOrdering() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let w1 = TestWindow.new(id: 1, parent: $0)
            let w2 = TestWindow.new(id: 2, parent: $0)
            let w3 = TestWindow.new(id: 3, parent: $0)
            w1.lastFocusedAt = 3
            w2.lastFocusedAt = 1
            w3.lastFocusedAt = 2

            let o1 = WindowWithPrefetchedTitle.forTest(window: w1, title: "b")
            let o2 = WindowWithPrefetchedTitle.forTest(window: w2, title: "a")
            let o3 = WindowWithPrefetchedTitle.forTest(window: w3, title: "c")

            // recent => most recently focused first (descending lastFocusedAt): w1(3), w3(2), w2(1)
            let byRecent = [o1, o2, o3].sorted { ListWindowsCommand.sortLess($0, $1, by: [.recent]) }
            assertEquals(byRecent.map { $0.window.windowId }, [1, 3, 2])

            // window-title => ascending title: a(w2), b(w1), c(w3)
            let byTitle = [o1, o2, o3].sorted { ListWindowsCommand.sortLess($0, $1, by: [.windowTitle]) }
            assertEquals(byTitle.map { $0.window.windowId }, [2, 1, 3])
        }
    }

    func testInterpolationVariablesConsistency() {
        for kind in AeroObjKind.allCases {
            switch kind {
                case .window:
                    assertTrue(FormatVar.WindowFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "window-") })
                case .app:
                    assertTrue(FormatVar.AppFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "app-") })
                case .workspace:
                    assertTrue(FormatVar.WorkspaceFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "workspace") })
                case .monitor:
                    assertTrue(FormatVar.MonitorFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "monitor-") })
            }
        }
    }

    func testFormat() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "non-empty")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 1, parent: $0), title: "")),
            ]
            assertEquals(windows.format([.interVar("window-title")]), .success(["non-empty", ""]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "non-empty")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 10, parent: $0), title: "")),
            ]
            assertEquals(windows.format([.interVar("window-id"), .interVar("right-padding"), .interVar("window-title")]), .success(["2 non-empty", "10"]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "title1")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 10, parent: $0), title: "title2")),
            ]
            assertEquals(windows.format([.interVar("window-id"), .interVar("right-padding"), .literal(" | "), .interVar("window-title")]), .success(["2  | title1", "10 | title2"]))
        }
    }

    func testAllFormatVariable() {
        // Test that %{all} without --json fails at parsing level
        assertEquals(parseCommand("list-windows --all --format '%{all}'").errorOrNil, "'%{all}' format option requires --json flag")

        // Test that %{all} with JSON succeeds at parsing level
        assertNil(parseCommand("list-windows --all --format '%{all}' --json").errorOrNil)

        // Test that %{all} mixed with other variables fails
        assertEquals(parseCommand("list-windows --all --json --format '%{all} %{window-id}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")
        assertEquals(parseCommand("list-windows --all --json --format '%{window-title} %{all}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")
        assertEquals(parseCommand("list-windows --all --json --format '%{all}     %{window-title}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")

        // Test that %{all} with only spaces is allowed
        assertNil(parseCommand("list-windows --all --format ' %{all} ' --json").errorOrNil)
    }

    func testOrientationInterpolationVariables() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            $0.changeOrientation(.h)
            let window = TestWindow.new(id: 1, parent: $0)
            let windows = [AeroObj.window(.forTest(window: window, title: "test"))]
            assertEquals(
                windows.format([.interVar("window-parent-container-orientation")]),
                .success(["horizontal"]),
            )
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            $0.changeOrientation(.v)
            let window = TestWindow.new(id: 2, parent: $0)
            let windows = [AeroObj.window(.forTest(window: window, title: "test"))]
            assertEquals(
                windows.format([.interVar("window-parent-container-orientation")]),
                .success(["vertical"]),
            )
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            $0.changeOrientation(.h)
            let workspace = Workspace.get(byName: name)
            let workspaces = [AeroObj.workspace(workspace)]
            assertEquals(
                workspaces.format([.interVar("workspace-root-container-orientation")]),
                .success(["horizontal"]),
            )
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            $0.changeOrientation(.v)
            let workspace = Workspace.get(byName: name)
            let workspaces = [AeroObj.workspace(workspace)]
            assertEquals(
                workspaces.format([.interVar("workspace-root-container-orientation")]),
                .success(["vertical"]),
            )
        }

        Workspace.get(byName: name).rootTilingContainer.apply { root in
            root.changeOrientation(.h)
            let nestedContainer = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1, index: 0)
            let window = TestWindow.new(id: 3, parent: nestedContainer)
            let windows = [AeroObj.window(.forTest(window: window, title: "nested"))]
            assertEquals(
                windows.format([.interVar("window-parent-container-orientation")]),
                .success(["vertical"]),
            )
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            $0.changeOrientation(.h)
            let window = TestWindow.new(id: 4, parent: $0)
            let windows = [AeroObj.window(.forTest(window: window, title: "combined"))]
            assertEquals(
                windows.format([
                    .interVar("window-parent-container-orientation"),
                    .literal(" | "),
                    .interVar("window-parent-container-layout"),
                ]),
                .success(["horizontal | h_tiles"]),
            )
        }
    }
}
