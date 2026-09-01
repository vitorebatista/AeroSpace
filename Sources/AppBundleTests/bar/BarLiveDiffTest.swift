@testable import AppBundle
import Foundation
import XCTest

/// The live-push diff.
///
/// `BarLiveDiff` is a pure function, so what it emits is directly assertable. The last test
/// is the one that matters most: it replays the diff against a model of sketchybar and
/// checks the result against the same model fed the generated config, because a bar the user
/// dragged into shape and the same bar saved and reloaded must not be two different bars.
final class BarLiveDiffTest: XCTestCase {
    private let helpers = BarHelperPaths(aerospaceCli: "/opt/homebrew/bin/aerospace-edge")

    private func diff(_ previous: BarDraft, _ next: BarDraft) -> [[String]] {
        BarLiveDiff.commands(from: previous, to: next, helpers: helpers)
    }

    private func draft(_ items: [BarItem]) -> BarDraft {
        var draft = BarDraft()
        draft.items = items
        return draft
    }

    // MARK: - The mapping

    func testAnUnchangedDraftEmitsNothing() {
        let bar = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .right),
        ])
        XCTAssertEqual(diff(bar, bar), [])
        XCTAssertEqual(diff(BarDraft(), BarDraft()), [])
    }

    func testAReorderWithinOneClusterIsOneReorder() {
        // Different catalog groups, so no bracket spans them and the reorder stands alone.
        let previous = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .left),
        ])
        let next = draft([
            BarItem(id: "clock", cluster: .left),
            BarItem(id: "workspaces", cluster: .left),
        ])
        XCTAssertEqual(diff(previous, next), [["--reorder", "aerospace.clock", "aerospace.workspaces"]])
    }

    func testMovingAnItemToAnotherClusterRebuildsIt() {
        // sketchybar has no command to move an item between positions: the position is what
        // `--add` was given.
        let previous = draft([BarItem(id: "clock", cluster: .left)])
        let next = draft([BarItem(id: "clock", cluster: .right)])

        let commands = diff(previous, next)
        XCTAssertEqual(commands.first, ["--remove", "aerospace.clock"])
        XCTAssertEqual(commands.dropFirst().first, ["--add", "item", "aerospace.clock", "right"])
        XCTAssertEqual(commands.map(\.first), ["--remove", "--add", "--set"])
    }

    func testAnAddedItemIsAddedSetSubscribedAndPositioned() {
        let previous = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .left),
        ])
        let next = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "front-app", cluster: .left),
            BarItem(id: "clock", cluster: .left),
        ])

        let commands = diff(previous, next)
        XCTAssertEqual(commands.first, ["--add", "item", "aerospace.front-app", "left"])
        XCTAssertEqual(Array(commands[1].prefix(2)), ["--set", "aerospace.front-app"])
        XCTAssertEqual(commands[2], ["--subscribe", "aerospace.front-app", "front_app_switched"])
        // `--add` appends, so the item lands at the end of the cluster and has to be moved.
        XCTAssertTrue(
            commands.contains(["--reorder", "aerospace.workspaces", "aerospace.front-app", "aerospace.clock"]),
            "got \(commands.map(\.first))",
        )
    }

    func testAnItemAppendedToTheEndNeedsNoReorder() {
        let previous = draft([BarItem(id: "workspaces", cluster: .left)])
        let next = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .left),
        ])
        XCTAssertEqual(diff(previous, next).map(\.first), ["--add", "--set"])
    }

    func testARemovedItemIsOneRemove() {
        let previous = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .left),
        ])
        let next = draft([BarItem(id: "workspaces", cluster: .left)])
        XCTAssertEqual(diff(previous, next), [["--remove", "aerospace.clock"]])
    }

    func testASettingsChangeEmitsOnlyTheChangedKeys() {
        let previous = draft([BarItem(id: "clock", cluster: .right)])
        let next = draft([BarItem(id: "clock", cluster: .right, settings: ["format": .string("%H:%M")])])

        let commands = diff(previous, next)
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(Array(commands[0].prefix(2)), ["--set", "aerospace.clock"])
        // The icon and the update frequency did not move, so they are not re-sent.
        XCTAssertEqual(commands.first?.count, 3)
        XCTAssertEqual(commands.first?.last?.hasPrefix("script="), true)
    }

    func testAGeometryChangeEmitsOnlyBar() {
        var next = BarDraft()
        next.geometry.height = 44
        XCTAssertEqual(diff(BarDraft(), next), [["--bar", "height=44"]])
    }

    func testABarColourChangeEmitsOnlyBar() {
        var next = BarDraft()
        next.colors.background = "0xff1e1e2e"
        XCTAssertEqual(diff(BarDraft(), next), [["--bar", "color=0xff1e1e2e"]])
    }

    func testAPaletteChangeRebuildsEveryItem() {
        // `--default` reaches only what is added after it, so the items already on screen
        // have to be re-added for a new label colour to reach them.
        let previous = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .right),
        ])
        var next = previous
        next.colors.label = "0xffcdd6f4"

        let commands = diff(previous, next)
        XCTAssertEqual(commands.first, ["--default", "label.color=0xffcdd6f4"])
        XCTAssertEqual(
            commands.filter { $0.first == "--remove" },
            [["--remove", "aerospace.workspaces"], ["--remove", "aerospace.clock"]],
        )
        XCTAssertEqual(commands.count(where: { $0.first == "--add" }), 2)
    }

    func testASettingThatDropsAKeyRebuildsTheItemRatherThanLeavingItSet() {
        // Turning the icon back on means *not* emitting `icon.drawing=off`, and sketchybar
        // has no way to unset a property. Only a fresh `--add` gets back to the default.
        let hidden = draft([BarItem(id: "front-app", cluster: .center, settings: ["show-icon": .bool(false)])])
        let shown = draft([BarItem(id: "front-app", cluster: .center, settings: ["show-icon": .bool(true)])])

        let commands = diff(hidden, shown)
        XCTAssertEqual(commands.map(\.first), ["--remove", "--add", "--set", "--subscribe"])
    }

    func testAGraphToggleRebuildsTheItemAsTheOtherComponent() {
        // A graph is not an item with a property set: `--add graph` takes its width.
        let plain = draft([BarItem(id: "cpu", cluster: .right, settings: ["show-graph": .bool(false)])])
        let graphed = draft([BarItem(id: "cpu", cluster: .right, settings: ["show-graph": .bool(true)])])

        let commands = diff(plain, graphed)
        XCTAssertEqual(commands.first, ["--remove", "aerospace.cpu"])
        XCTAssertEqual(commands.dropFirst().first, ["--add", "graph", "aerospace.cpu", "right", "40"])
    }

    func testAnEventListChangeRebuildsTheItemBecauseThereIsNoUnsubscribe() {
        let previous = draft([BarItem(id: "custom", cluster: .right, settings: [
            "script": .string("/usr/local/bin/vpn"),
            "events": .array([.string("front_app_switched"), .string("system_woke")]),
        ])])
        let next = draft([BarItem(id: "custom", cluster: .right, settings: [
            "script": .string("/usr/local/bin/vpn"),
            "events": .array([.string("front_app_switched")]),
        ])])

        let commands = diff(previous, next)
        XCTAssertEqual(commands.map(\.first), ["--remove", "--add", "--set", "--subscribe"])
        XCTAssertEqual(commands.last, ["--subscribe", "aerospace.custom", "front_app_switched"])
    }

    func testItemsTheGeneratorSkipsAreNeverAdded() {
        // An item whose tool is not installed, an unknown id and a `custom` with no script are
        // all comments in the generated config. Adding one live would put something on screen
        // that the next save would silently delete.
        let next = draft([
            BarItem(id: "brightness", cluster: .right),
            BarItem(id: "not-a-catalog-item", cluster: .right),
            BarItem(id: "custom", cluster: .right, settings: ["script": .string("")]),
        ])
        XCTAssertEqual(diff(BarDraft(), next), [])
    }

    func testABracketFollowsTheItemsItSpansAndIsRebuiltLast() {
        // Two adjacent AeroSpace items are bracketed; splitting them with a system item
        // leaves no run to bracket.
        let bracketed = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "mode", cluster: .left),
            BarItem(id: "clock", cluster: .left),
        ])
        let split = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .left),
            BarItem(id: "mode", cluster: .left),
        ])

        let removing = diff(bracketed, split)
        XCTAssertEqual(removing.first, ["--remove", "aerospace.bracket.left.aerospace"])

        let adding = diff(split, bracketed)
        // The bracket is added after the reorder, so it spans the items where they end up.
        XCTAssertEqual(adding.map(\.first), ["--reorder", "--add", "--set"])
        XCTAssertEqual(
            adding.dropFirst().first,
            ["--add", "bracket", "aerospace.bracket.left.aerospace", "aerospace.workspaces", "aerospace.mode"],
        )
    }

    func testARebuiltItemTakesItsBracketWithIt() {
        // sketchybar drops a removed item out of the bracket that held it, so a bracket
        // whose member is re-added has to be re-added too or it draws around a gap.
        let previous = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "front-app", cluster: .left, settings: ["show-icon": .bool(false)]),
        ])
        let next = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "front-app", cluster: .left, settings: ["show-icon": .bool(true)]),
        ])

        let commands = diff(previous, next)
        XCTAssertEqual(commands.first, ["--remove", "aerospace.bracket.left.aerospace"])
        XCTAssertEqual(commands[1], ["--remove", "aerospace.front-app"])
        XCTAssertEqual(
            commands.map(\.first),
            ["--remove", "--remove", "--add", "--set", "--subscribe", "--add", "--set"],
        )
    }

    func testSeveralEditsAtOnce() {
        let previous = draft([
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "clock", cluster: .left),
            BarItem(id: "battery", cluster: .right),
        ])
        var next = draft([
            BarItem(id: "clock", cluster: .left),
            BarItem(id: "workspaces", cluster: .left),
            BarItem(id: "apple-menu", cluster: .right),
        ])
        next.geometry.margin = 0

        let commands = diff(previous, next)
        XCTAssertEqual(commands.first, ["--bar", "margin=0"])
        XCTAssertEqual(commands.map(\.first), ["--bar", "--remove", "--add", "--set", "--reorder"])
        XCTAssertEqual(commands[1], ["--remove", "aerospace.battery"])
        XCTAssertEqual(commands[2], ["--add", "item", "aerospace.apple-menu", "right"])
        XCTAssertEqual(commands.last, ["--reorder", "aerospace.clock", "aerospace.workspaces"])
    }

    // MARK: - Convergence

    /// The test the rest exist to support: a bar edited live and a bar saved and reloaded
    /// have to end up the same bar.
    ///
    /// Both sides go through the same model of sketchybar. The saved side is fed the commands
    /// parsed straight out of the generated `sketchybarrc`, so what is being compared against
    /// is the bytes the user actually gets, not a second description of them.
    func testALiveEditAndASavedReloadDescribeTheSameBar() throws {
        for (name, previous, next) in Self.convergenceCases {
            let saved = try state(of: next, name: name)

            var live = try state(of: previous, name: name)
            let problems = live.apply(diff(previous, next))
            XCTAssertEqual(problems, [], "\(name): the diff gave sketchybar a command it could not honour")
            XCTAssertEqual(live, saved, "\(name): the live bar and the saved bar diverged")
        }
    }

    func testConvergenceHoldsInBothDirections() throws {
        for (name, previous, next) in Self.convergenceCases {
            var live = try state(of: next, name: name)
            let problems = live.apply(diff(next, previous))
            XCTAssertEqual(problems, [], "\(name), reversed: unhonourable command")
            XCTAssertEqual(live, try state(of: previous, name: name), "\(name), reversed: diverged")
        }
    }

    private func state(of draft: BarDraft, name: String) throws -> SketchybarState {
        var state = SketchybarState()
        let problems = state.apply(SketchybarState.commands(inConfig: BarConfigGenerator.generate(draft, helpers: helpers)))
        XCTAssertEqual(problems, [], "\(name): the generated config itself did not replay")
        return state
    }

    private static let convergenceCases: [(String, BarDraft, BarDraft)] = {
        func make(_ build: (inout BarDraft) -> Void) -> BarDraft {
            var draft = BarDraft()
            build(&draft)
            return draft
        }
        let full = make {
            $0.items = [
                BarItem(id: "workspaces", cluster: .left),
                BarItem(id: "mode", cluster: .left),
                BarItem(id: "front-app", cluster: .center),
                BarItem(id: "cpu", cluster: .right),
                BarItem(id: "clock", cluster: .right),
            ]
        }
        return [
            ("an empty bar filled in", BarDraft(), full),
            ("a bar emptied out", full, BarDraft()),
            ("a reorder inside one cluster", full, make {
                $0.items = [
                    BarItem(id: "mode", cluster: .left),
                    BarItem(id: "workspaces", cluster: .left),
                    BarItem(id: "front-app", cluster: .center),
                    BarItem(id: "cpu", cluster: .right),
                    BarItem(id: "clock", cluster: .right),
                ]
            }),
            ("a move between clusters", full, make {
                $0.items = [
                    BarItem(id: "workspaces", cluster: .left),
                    BarItem(id: "front-app", cluster: .center),
                    BarItem(id: "mode", cluster: .right),
                    BarItem(id: "cpu", cluster: .right),
                    BarItem(id: "clock", cluster: .right),
                ]
            }),
            ("an item added in the middle", full, make {
                $0.items = [
                    BarItem(id: "workspaces", cluster: .left),
                    BarItem(id: "mode", cluster: .left),
                    BarItem(id: "front-app", cluster: .center),
                    BarItem(id: "battery", cluster: .right),
                    BarItem(id: "cpu", cluster: .right),
                    BarItem(id: "clock", cluster: .right),
                ]
            }),
            ("an item removed from the middle", full, make {
                $0.items = [
                    BarItem(id: "workspaces", cluster: .left),
                    BarItem(id: "mode", cluster: .left),
                    BarItem(id: "cpu", cluster: .right),
                    BarItem(id: "clock", cluster: .right),
                ]
            }),
            ("a settings-only edit", full, make {
                $0.items = full.items
                $0.items[4].settings = ["format": .string("%H:%M"), "update-freq": .int(5)]
            }),
            ("a setting that drops a property", full, make {
                $0.items = full.items
                $0.items[2].settings = ["show-icon": .bool(false)]
            }),
            ("a graph appearing", full, make {
                $0.items = full.items
                $0.items[3].settings = ["show-graph": .bool(true)]
            }),
            ("a geometry edit", full, make {
                $0.items = full.items
                $0.geometry = BarGeometry(height: 40, margin: 0, yOffset: 0, cornerRadius: 0, borderWidth: 2, paddingLeft: 4, paddingRight: 4)
            }),
            ("a palette edit", full, make {
                $0.items = full.items
                $0.colors = BarColors(
                    background: "0xff1e1e2e",
                    border: "0xff313244",
                    label: "0xffcdd6f4",
                    icon: "0xffcdd6f4",
                    accent: "0xfff38ba8",
                    popupBackground: "0xff181825",
                    popupBorder: "0xff45475a",
                )
            }),
            ("items the generator skips on both sides", make {
                $0.items = [
                    BarItem(id: "volume", cluster: .left),
                    BarItem(id: "clock", cluster: .right),
                    BarItem(id: "custom", cluster: .right, settings: ["script": .string("")]),
                ]
            }, make {
                $0.items = [
                    BarItem(id: "not-a-catalog-item", cluster: .left),
                    BarItem(id: "clock", cluster: .right),
                    BarItem(id: "custom", cluster: .right, settings: ["script": .string("/usr/local/bin/vpn")]),
                ]
            }),
            ("two custom items, the first deleted so the second is renamed", make {
                $0.items = [
                    BarItem(id: "custom", cluster: .left, settings: ["script": .string("/usr/local/bin/a")]),
                    BarItem(id: "custom", cluster: .left, settings: ["script": .string("/usr/local/bin/b")]),
                ]
            }, make {
                $0.items = [BarItem(id: "custom", cluster: .left, settings: ["script": .string("/usr/local/bin/b")])]
            }),
            ("a bracket forming", make {
                $0.items = [
                    BarItem(id: "workspaces", cluster: .left),
                    BarItem(id: "clock", cluster: .left),
                    BarItem(id: "mode", cluster: .left),
                ]
            }, make {
                $0.items = [
                    BarItem(id: "workspaces", cluster: .left),
                    BarItem(id: "mode", cluster: .left),
                    BarItem(id: "clock", cluster: .left),
                ]
            }),
            ("everything at once", full, make {
                $0.geometry.height = 28
                $0.colors.accent = "0xfff38ba8"
                $0.items = [
                    BarItem(id: "front-app", cluster: .left, settings: ["max-length": .int(20)]),
                    BarItem(id: "workspaces", cluster: .center, settings: ["hide-empty": .bool(false)]),
                    BarItem(id: "clock", cluster: .right),
                    BarItem(id: "battery", cluster: .right),
                ]
            }),
        ]
    }()
}

/// A model of what sketchybar holds after a sequence of commands.
///
/// It is faithful on the three points convergence turns on: `--default` reaches only the
/// entities added after it, `--add` appends to the end of its cluster, and `--subscribe`
/// has no inverse. Anything a command cannot honour — setting an entity that is not there,
/// adding one twice — is reported rather than ignored, because those are exactly the bugs
/// this is looking for.
private struct SketchybarState: Equatable {
    struct Entity: Equatable {
        var name: String
        /// `item`, `graph:<width>` or `bracket:<members>` — what `--add` created, which is
        /// not something a later `--set` can change.
        var kind: String
        var cluster: String
        var properties: [String: String] = [:]
        var events: Set<String> = []
    }

    var bar: [String: String] = [:]
    var defaults: [String: String] = [:]
    var entities: [Entity] = []

    /// What sketchybar actually draws: the order of a cluster's items, and a set of brackets.
    /// The order of the underlying array is an artefact of when things were added — live
    /// editing appends and reorders, generation writes cluster by cluster — and comparing it
    /// would fail two identical bars.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bar == rhs.bar
            && lhs.defaults == rhs.defaults
            && lhs.itemsByCluster == rhs.itemsByCluster
            && lhs.bracketsByName == rhs.bracketsByName
    }

    private var itemsByCluster: [String: [Entity]] {
        Dictionary(grouping: entities.filter { !$0.kind.hasPrefix("bracket") }, by: \.cluster)
    }

    private var bracketsByName: [String: Entity] {
        Dictionary(
            entities.filter { $0.kind.hasPrefix("bracket") }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    /// Replays commands, returning what could not be honoured.
    mutating func apply(_ commands: [[String]]) -> [String] {
        var problems: [String] = []
        for command in commands {
            guard let head = command.first else { continue }
            let arguments = Array(command.dropFirst())
            switch head {
                case "--bar": merge(arguments, into: &bar)
                case "--default": merge(arguments, into: &defaults)
                case "--update": continue
                case "--add":
                    if let problem = add(arguments) { problems.append(problem) }
                case "--set", "--subscribe", "--remove":
                    guard let name = arguments.first, let index = entities.firstIndex(where: { $0.name == name }) else {
                        problems.append("\(head) on an entity that is not there: \(arguments.first ?? "")")
                        continue
                    }
                    switch head {
                        case "--set": merge(Array(arguments.dropFirst()), into: &entities[index].properties)
                        case "--subscribe": entities[index].events.formUnion(arguments.dropFirst())
                        default: entities.remove(at: index)
                    }
                case "--reorder":
                    if let problem = reorder(arguments) { problems.append(problem) }
                default: problems.append("unknown command \(head)")
            }
        }
        return problems
    }

    private mutating func add(_ arguments: [String]) -> String? {
        guard arguments.count >= 2 else { return "malformed --add" }
        let name = arguments[1]
        guard !entities.contains(where: { $0.name == name }) else { return "--add of an existing entity: \(name)" }
        let kind: String
        let cluster: String
        switch arguments[0] {
            case "item":
                kind = "item"
                cluster = arguments.count > 2 ? arguments[2] : ""
            case "graph":
                kind = "graph:\(arguments.count > 3 ? arguments[3] : "")"
                cluster = arguments.count > 2 ? arguments[2] : ""
            case "bracket":
                kind = "bracket:\(arguments.dropFirst(2).joined(separator: ","))"
                // A bracket has no position of its own; it takes the span of its members.
                cluster = ""
            default: return "unknown --add kind \(arguments[0])"
        }
        entities.append(Entity(name: name, kind: kind, cluster: cluster, properties: defaults))
        return nil
    }

    private mutating func reorder(_ names: [String]) -> String? {
        let positions = entities.indices.filter { names.contains(entities[$0].name) }.sorted()
        guard positions.count == names.count else { return "--reorder naming an entity that is not there" }
        let moved = names.compactMap { name in entities.first { $0.name == name } }
        for (position, entity) in zip(positions, moved) { entities[position] = entity }
        return nil
    }

    private func merge(_ arguments: [String], into target: inout [String: String]) {
        for argument in arguments {
            guard let index = argument.firstIndex(of: "=") else { continue }
            target[String(argument[..<index])] = String(argument[argument.index(after: index)...])
        }
    }

    // MARK: - Reading a generated config back

    /// The commands a generated `sketchybarrc` runs, in order. The file is `sh`, but a
    /// generated one is regular: one `sketchybar` invocation per statement, arguments either
    /// bare or single-quoted.
    static func commands(inConfig text: String) -> [[String]] {
        var statements: [String] = []
        var pending = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if line.hasSuffix(" \\") {
                pending += String(line.dropLast(1))
                continue
            }
            statements.append(pending + line)
            pending = ""
        }
        return statements.compactMap { statement in
            let words = shellWords(statement)
            guard words.first == "sketchybar" else { return nil }
            return Array(words.dropFirst())
        }
    }

    private static func shellWords(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var started = false
        var quoted = false
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if !quoted, character == "\\" {
                escaped = true
                started = true
                continue
            }
            if character == "'" {
                quoted.toggle()
                started = true
                continue
            }
            if !quoted, character == " " || character == "\t" {
                if started { words.append(current) }
                current = ""
                started = false
                continue
            }
            if !started, words.isEmpty, character == "#" { return [] }
            current.append(character)
            started = true
        }
        if started { words.append(current) }
        return words
    }
}
