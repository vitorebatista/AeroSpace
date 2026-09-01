@testable import AppBundle
import Foundation
import OrderedCollections
import XCTest

/// Golden-file tests for the generator.
///
/// The generator is a pure function and the file it writes is executed by another process
/// on the user's screen, so the bytes themselves are the contract. Set
/// `UPDATE_BAR_GOLDEN=1` to rewrite the expectations after a deliberate change, then read
/// the diff — that diff is the review.
final class BarConfigGeneratorTest: XCTestCase {
    private let helpers = BarHelperPaths(aerospaceCli: "/opt/homebrew/bin/aerospace-edge")
    private let helpersWithIconMap = BarHelperPaths(
        aerospaceCli: "/opt/homebrew/bin/aerospace-edge",
        appFontIconMap: "/opt/homebrew/share/sketchybar-app-font/icon_map.sh",
    )

    func testEmptyBar() throws {
        try assertGolden("empty-bar", BarDraft(), helpers: helpers)
    }

    func testOneItemFromEveryCatalogGroup() throws {
        var draft = BarDraft()
        draft.items = [
            BarItem(id: "workspaces", cluster: .left), // AeroSpace
            BarItem(id: "apple-menu", cluster: .left), // macOS
            BarItem(id: "clock", cluster: .right), // System
            BarItem(id: "volume", cluster: .right), // Privileged — no helper binary yet
            BarItem(id: "custom", cluster: .right, settings: [ // Escape hatch
                "script": .string("~/.config/sketchybar/plugins/vpn.sh"),
            ]),
        ]
        try assertGolden("one-per-group", draft, helpers: helpers)
    }

    func testAllThreeClustersInDocumentOrder() throws {
        var draft = BarDraft()
        // Deliberately interleaved: emission has to sort by cluster and keep document
        // order inside one, not follow the array.
        draft.items = [
            BarItem(id: "clock", cluster: .right),
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "battery", cluster: .right),
            BarItem(id: "front-app", cluster: .center),
            BarItem(id: "mode", cluster: .left),
        ]
        try assertGolden("all-clusters", draft, helpers: helpers)
    }

    /// A bar with profiles. The generated file is always the *shared* bar — the one a
    /// workspace no profile names gets — because the generator cannot know which workspace is
    /// focused. AeroSpace-edge pushes the active profile over the top of it.
    func testProfilesGenerateTheSharedBar() throws {
        var draft = BarDraft()
        draft.items = [
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "cpu", cluster: .right),
            BarItem(id: "weather", cluster: .right),
        ]
        draft.profiles = [
            BarProfile(name: "Work", workspaces: ["1", "2"], show: ["cpu"], hide: ["weather"]),
            BarProfile(name: "Play", workspaces: ["9"]),
        ]
        try assertGolden("profiles", draft, helpers: helpers)
    }

    func testCustomItemsAndItemsThatCannotBeGenerated() throws {
        var draft = BarDraft()
        draft.items = [
            BarItem(id: "custom", cluster: .left, settings: [
                "script": .string("/opt/homebrew/bin/my-status --oneline"),
                "update-freq": .int(0),
                "events": .array([.string("front_app_switched"), .string("system_woke")]),
            ]),
            BarItem(id: "custom", cluster: .left, settings: [
                // A path with a space is the user's to quote: `script` is a command line,
                // not a path, so the generator passes it through as written.
                "script": .string("\"$HOME/scripts/my status.sh\" --json"),
                "update-freq": .int(15),
            ]),
            BarItem(id: "custom", cluster: .right, settings: ["script": .string("")]),
            BarItem(id: "not-a-catalog-item", cluster: .right),
        ]
        try assertGolden("custom-items", draft, helpers: helpers)
    }

    func testNonDefaultSettingsAndPalette() throws {
        var draft = BarDraft()
        draft.geometry = BarGeometry(
            height: 40,
            margin: 0,
            yOffset: 0,
            cornerRadius: 0,
            borderWidth: 2,
            paddingLeft: 4,
            paddingRight: 4,
        )
        draft.colors = BarColors(
            background: "0xff1e1e2e",
            border: "0xff313244",
            label: "0xffcdd6f4",
            icon: "0xffcdd6f4",
            accent: "0xfff38ba8",
            popupBackground: "0xff181825",
            popupBorder: "0xff45475a",
        )
        draft.items = [
            BarItem(id: "workspaces", cluster: .left, settings: [
                "show-app-icons": .bool(true),
                "per-monitor": .bool(false),
                "hide-empty": .bool(false),
                "focused-color": .string("0xfff9e2af"),
            ]),
            BarItem(id: "mode", cluster: .left, settings: [
                "hide-in-main": .bool(false),
                "label-format": .string("-- %s --"),
            ]),
            BarItem(id: "floats", cluster: .left, settings: [
                "show-count": .bool(false),
                "hide-when-empty": .bool(false),
            ]),
            BarItem(id: "front-app", cluster: .center, settings: [
                "show-icon": .bool(false),
                "max-length": .int(24),
            ]),
            BarItem(id: "cpu", cluster: .right, settings: ["show-graph": .bool(true), "update-freq": .int(2)]),
            BarItem(id: "network", cluster: .right, settings: ["show-throughput": .bool(true)]),
            BarItem(id: "weather", cluster: .right, settings: [
                "location": .string("New York,US"),
                "units": .string("imperial"),
            ]),
            BarItem(id: "battery", cluster: .right, settings: ["show-percentage": .bool(false)]),
            BarItem(id: "secure-input", cluster: .right, settings: ["hide-when-inactive": .bool(false)]),
        ]
        try assertGolden("tuned-settings", draft, helpers: helpersWithIconMap)
    }

    // MARK: - Properties the golden files cannot state on their own

    func testGenerationIsDeterministic() {
        var draft = BarDraft()
        draft.items = [
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .right),
            BarItem(id: "custom", cluster: .center, settings: ["script": .string("/tmp/x.sh")]),
        ]
        let first = BarConfigGenerator.generate(draft, helpers: helpers)
        for _ in 0 ..< 5 {
            XCTAssertEqual(BarConfigGenerator.generate(draft, helpers: helpers), first)
        }
    }

    func testHeaderCarriesTheShebangAndTheTakeoverMarker() {
        let lines = BarConfigGenerator.generate(BarDraft(), helpers: helpers).split(separator: "\n")
        XCTAssertEqual(lines.first, "#!/bin/sh")
        XCTAssertEqual(BarConfigGenerator.markerLine, "# aerospace-edge-generated: 1")
        XCTAssertTrue(lines.contains(Substring(BarConfigGenerator.markerLine)))
        // The generated config must not need luarocks, a Lua interpreter or SbarLua.
        XCTAssertFalse(BarConfigGenerator.generate(BarDraft(), helpers: helpers).contains("lua"))
    }

    func testEveryGeneratedNameIsNamespaced() {
        var draft = BarDraft()
        draft.items = BarCatalog.items.map { BarItem(id: $0.id, cluster: $0.defaultCluster) }
        draft.items.append(BarItem(id: "custom", cluster: .center, settings: ["script": .string("/tmp/x.sh")]))
        let generated = BarConfigGenerator.generate(draft, helpers: helpers)

        var names: [String] = []
        for line in generated.split(separator: "\n") where line.hasPrefix("sketchybar --") {
            let words = line.split(separator: " ")
            switch words[1] {
                case "--add": names.append(String(words[3])) // sketchybar --add <kind> <name> …
                case "--set", "--subscribe": names.append(String(words[2]))
                default: continue
            }
        }
        XCTAssertFalse(names.isEmpty)
        for name in names {
            XCTAssertTrue(name.hasPrefix(BarCatalog.namePrefix), "'\(name)' is not namespaced")
        }
    }

    func testRepeatedIdsGetDistinctNames() {
        var draft = BarDraft()
        draft.items = (1 ... 3).map {
            BarItem(id: "custom", cluster: .right, settings: ["script": .string("/tmp/\($0).sh")])
        }
        let generated = BarConfigGenerator.generate(draft, helpers: helpers)
        for name in ["aerospace.custom", "aerospace.custom.2", "aerospace.custom.3"] {
            XCTAssertTrue(generated.contains("--add item \(name) right"), "missing \(name)")
        }
    }

    func testPrivilegedItemsAreSkippedWithAnExplanationRatherThanEmitted() {
        var draft = BarDraft()
        draft.items = BarCatalog.items(in: .privileged).map { BarItem(id: $0.id, cluster: .right) }
        let generated = BarConfigGenerator.generate(draft, helpers: helpers)
        XCTAssertFalse(generated.contains("--add"))
        for item in BarCatalog.items(in: .privileged) {
            XCTAssertTrue(
                generated.contains("# \(BarCatalog.sketchybarName(for: item.id)): needs a helper binary"),
                "\(item.id) must say why it is missing",
            )
        }
    }

    func testGeometryAndColorsReachTheBar() {
        var draft = BarDraft()
        draft.geometry.height = 44
        draft.colors.background = "0xff112233"
        let generated = BarConfigGenerator.generate(draft, helpers: helpers)
        XCTAssertTrue(generated.contains("height=44"))
        XCTAssertTrue(generated.contains("color=0xff112233"))
    }

    func testUserSuppliedValuesAreShellQuoted() {
        XCTAssertEqual(BarConfigGenerator.shellArg("0xff112233"), "0xff112233")
        XCTAssertEqual(BarConfigGenerator.shellArg("%a %d %b"), "'%a %d %b'")
        XCTAssertEqual(BarConfigGenerator.shellArg("it's"), "'it'\\''s'")
        XCTAssertEqual(BarConfigGenerator.shellArg("; rm -rf /"), "'; rm -rf /'")
        XCTAssertEqual(BarConfigGenerator.shellArg(""), "''")

        var draft = BarDraft()
        draft.items = [BarItem(id: "clock", cluster: .right, settings: ["format": .string("'; touch /tmp/pwn; '")])]
        let generated = BarConfigGenerator.generate(draft, helpers: helpers)
        XCTAssertFalse(generated.contains("; touch /tmp/pwn; '\n"))
        XCTAssertTrue(generated.contains("'\\''"))
    }

    // MARK: - Golden files

    private static let goldenDirectory = projectRoot.appending(path: "Sources/AppBundleTests/bar/golden")

    private func assertGolden(
        _ name: String,
        _ draft: BarDraft,
        helpers: BarHelperPaths,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let url = Self.goldenDirectory.appending(component: "\(name).sh")
        let actual = BarConfigGenerator.generate(draft, helpers: helpers)
        if ProcessInfo.processInfo.environment["UPDATE_BAR_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: Self.goldenDirectory, withIntermediateDirectories: true)
            try Data(actual.utf8).write(to: url)
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(actual, expected, "\(name).sh is stale — rerun with UPDATE_BAR_GOLDEN=1", file: file, line: line)
    }
}
