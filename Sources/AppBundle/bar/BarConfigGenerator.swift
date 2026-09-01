import Foundation

/// Absolute paths the generator is handed rather than resolving itself.
///
/// Keeping resolution out of `BarConfigGenerator` is what makes the generator a pure
/// function: the same draft plus the same paths always produce the same bytes, on any
/// machine, with no environment to stub in a test.
struct BarHelperPaths: Equatable, Sendable {
    /// The `aerospace-edge` CLI the AeroSpace items shell out to.
    var aerospaceCli: String
    /// An executable that prints the `sketchybar-app-font` glyph for the application name
    /// given as `$1`. `nil` when the font (and its map) is not installed, in which case
    /// `show-app-icons` degrades to plain workspace names rather than to blank glyphs.
    var appFontIconMap: String?
    // The bundled helper the privileged items need has no field here yet: it does not
    // ship until stage 4, and a path nothing reads is a path nothing keeps correct.

    init(aerospaceCli: String, appFontIconMap: String? = nil) {
        self.aerospaceCli = aerospaceCli
        self.appFontIconMap = appFontIconMap
    }
}

/// Turns a `BarDraft` into the bytes of a `sketchybarrc`.
///
/// Pure: no I/O, no environment reads, no path resolution. `SketchybarBackend` does all
/// three and hands the results in. Emission order is fixed — header, `--bar`, `--default`,
/// items in cluster order, brackets, `--update` — so a golden file is a meaningful test.
///
/// The output is `#!/bin/sh`. Sketchybar's native config language already is a shell
/// script, and a *generated* config has no reason to require luarocks, a Lua interpreter
/// and SbarLua.
enum BarConfigGenerator {
    /// The integer on the marker line. Bumped when a later generator would need to
    /// recognise a file this one wrote.
    static let formatVersion = 1
    /// What `SketchybarBackend` looks for to decide whether a file on disk is ours.
    static let markerPrefix = "# aerospace-edge-generated:"
    static var markerLine: String { "\(markerPrefix) \(formatVersion)" }

    /// The colour an item switches to past its warning threshold. Not a `bar.toml` key:
    /// the model carries the bar's palette, not a semantic one, and inventing a key now
    /// would have to be migrated when stage 4's theme switcher lands.
    private static let warningColor = "0xffff5f5f"
    private static let iconFontStyle = "Semibold:14.0"
    private static let labelFontStyle = "Semibold:13.0"

    static func generate(_ draft: BarDraft, helpers: BarHelperPaths) -> String {
        var blocks: [String] = [header(), barBlock(draft), defaultBlock(draft)]

        var emitted: [EmittedItem] = []
        // Repeated ids — `custom` is the one a user can reasonably add twice — get a
        // numeric suffix, so two escape hatches do not overwrite each other's properties.
        var occurrences: [String: Int] = [:]
        for cluster in BarCluster.allCases {
            for item in draft.items(in: cluster) {
                let count = (occurrences[item.id] ?? 0) + 1
                occurrences[item.id] = count
                let base = BarCatalog.sketchybarName(for: item.id)
                let name = count == 1 ? base : "\(base).\(count)"
                switch emit(item, name: name, colors: draft.colors, helpers: helpers) {
                    case .skipped(let comment):
                        blocks.append(comment)
                    case .emitted(let emittedItem, let block):
                        emitted.append(emittedItem)
                        blocks.append(block)
                }
            }
        }

        blocks.append(contentsOf: brackets(for: emitted, draft: draft))
        blocks.append("sketchybar --update")
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func generateData(_ draft: BarDraft, helpers: BarHelperPaths) -> Data {
        Data(generate(draft, helpers: helpers).utf8)
    }

    // MARK: - Fixed sections

    private static func header() -> String {
        """
        #!/bin/sh
        # Managed by AeroSpace-edge. Generated from ~/.config/aerospace/bar.toml.
        # Edits to this file are overwritten on the next save.
        \(markerLine)
        """
    }

    private static func barBlock(_ draft: BarDraft) -> String {
        let geometry = draft.geometry
        return command("sketchybar --bar", [
            "position=top",
            "height=\(geometry.height)",
            "margin=\(geometry.margin)",
            "y_offset=\(geometry.yOffset)",
            "corner_radius=\(geometry.cornerRadius)",
            "border_width=\(geometry.borderWidth)",
            "padding_left=\(geometry.paddingLeft)",
            "padding_right=\(geometry.paddingRight)",
            "color=\(shellArg(draft.colors.background))",
            "border_color=\(shellArg(draft.colors.border))",
        ])
    }

    private static func defaultBlock(_ draft: BarDraft) -> String {
        let colors = draft.colors
        return command("sketchybar --default", [
            "icon.font=\(shellArg("\(BarIconFont.sfSymbols.fontFamily):\(iconFontStyle)"))",
            "icon.color=\(shellArg(colors.icon))",
            "icon.padding_left=6",
            "icon.padding_right=4",
            "label.font=\(shellArg("\(BarIconFont.sfSymbols.fontFamily):\(labelFontStyle)"))",
            "label.color=\(shellArg(colors.label))",
            "label.padding_left=0",
            "label.padding_right=6",
            "background.drawing=off",
            "background.corner_radius=6",
            "background.height=24",
            "popup.background.color=\(shellArg(colors.popupBackground))",
            "popup.background.border_color=\(shellArg(colors.popupBorder))",
            "popup.background.border_width=1",
            "popup.background.corner_radius=6",
        ])
    }

    // MARK: - Items

    private struct EmittedItem {
        let name: String
        let cluster: BarCluster
        let group: BarItemGroup
    }

    private enum Emission {
        case skipped(String)
        case emitted(EmittedItem, String)
    }

    private struct Program {
        /// `--add item` unless the item draws a rolling graph, which is a different
        /// sketchybar component and takes its width at add time.
        var graphWidth: Int?
        var properties: [String] = []
        var events: [String] = []
    }

    private static func emit(
        _ item: BarItem,
        name: String,
        colors: BarColors,
        helpers: BarHelperPaths,
    ) -> Emission {
        guard let catalog = BarCatalog.item(id: item.id) else {
            return .skipped("# \(name): no catalog entry, not generated")
        }
        if case .unavailable = catalog.availability {
            return .skipped("# \(name): needs a helper binary that ships in a later release, not generated")
        }
        guard let program = program(for: item, catalog: catalog, colors: colors, helpers: helpers) else {
            return .skipped("# \(name): no script path set, not generated")
        }

        var lines: [String] = []
        if let width = program.graphWidth {
            lines.append("sketchybar --add graph \(name) \(item.cluster.rawValue) \(width)")
        } else {
            lines.append("sketchybar --add item \(name) \(item.cluster.rawValue)")
        }
        lines.append(command("sketchybar --set \(name)", program.properties))
        if !program.events.isEmpty {
            lines.append("sketchybar --subscribe \(name) \(program.events.joined(separator: " "))")
        }
        let emitted = EmittedItem(name: name, cluster: item.cluster, group: catalog.group)
        return .emitted(emitted, lines.joined(separator: "\n"))
    }

    private static func program(
        for item: BarItem,
        catalog: BarCatalogItem,
        colors: BarColors,
        helpers: BarHelperPaths,
    ) -> Program? {
        let cli = shellArg(helpers.aerospaceCli)
        var program = Program()
        program.properties = iconProperties(item, catalog)

        switch catalog.id {
            case "workspaces":
                let monitor = bool(item, catalog, "per-monitor") ? "focused" : "all"
                let empty = bool(item, catalog, "hide-empty") ? " --empty no" : ""
                var body = "\(cli) list-workspaces --monitor \(monitor)\(empty)"
                    + " --format '%{workspace}|%{workspace-is-focused}'"
                    + " | while IFS='|' read -r w f; do"
                    + " if [ \"$f\" = true ]; then printf '[%s]' \"$w\"; else printf '%s' \"$w\"; fi;"
                if bool(item, catalog, "show-app-icons"), let map = helpers.appFontIconMap {
                    body += " \(cli) list-windows --workspace \"$w\" --format '%{app-name}'"
                        + " | sort -u | while IFS= read -r a; do \(shellArg(map)) \"$a\"; done;"
                }
                body += " printf ' '; done | sed 's/ $//'"
                program.properties += [
                    "icon.color=\(shellArg(string(item, catalog, "focused-color", fallback: colors.accent)))",
                    "update_freq=1",
                    "script=\(shellArg("sketchybar --set $NAME label=\"$(\(body))\""))",
                ]
                program.events = ["front_app_switched", "space_change", "display_change"]

            case "front-app":
                if !bool(item, catalog, "show-icon") { program.properties.append("icon.drawing=off") }
                let maxLength = int(item, catalog, "max-length")
                let label = maxLength > 0 ? "\"$(printf '%.\(maxLength)s' \"$INFO\")\"" : "\"$INFO\""
                program.properties.append("script=\(shellArg("sketchybar --set $NAME label=\(label)"))")
                program.events = ["front_app_switched"]

            case "mode":
                let format = shellArg(string(item, catalog, "label-format"))
                let show = "sketchybar --set $NAME drawing=on label=\"$(printf \(format) \"$m\")\""
                var body = "m=$(\(cli) list-modes --current)"
                if bool(item, catalog, "hide-in-main") {
                    body += "; if [ \"$m\" = main ]; then sketchybar --set $NAME drawing=off; else \(show); fi"
                } else {
                    body += "; \(show)"
                }
                program.properties += ["update_freq=1", "script=\(shellArg(body))"]

            case "floats":
                let showCount = bool(item, catalog, "show-count")
                let hideWhenEmpty = bool(item, catalog, "hide-when-empty")
                let label = showCount ? " label=\"$n\"" : " label.drawing=off"
                // Counting is skipped entirely when neither switch reads the count, so the
                // item does not fork `aerospace-edge` twice a second for nothing.
                let count = "n=$(\(cli) list-windows --workspace focused"
                    + " --format '%{window-parent-container-layout}' | grep -c '^floating$'); "
                var body = showCount || hideWhenEmpty ? count : ""
                if hideWhenEmpty {
                    body += "if [ \"$n\" -gt 0 ]; then sketchybar --set $NAME drawing=on\(label);"
                        + " else sketchybar --set $NAME drawing=off; fi"
                } else {
                    body += "sketchybar --set $NAME drawing=on\(label)"
                }
                // Clicking focuses the first float rather than cycling: cycling needs
                // state a generated script cannot hold. The app pushes that in stage 2,
                // where it is the one that knows the focus order.
                let click = "id=$(\(cli) list-windows --workspace focused"
                    + " --format '%{window-id}|%{window-parent-container-layout}'"
                    + " | grep '|floating$' | head -n1 | cut -d'|' -f1);"
                    + " [ -n \"$id\" ] && \(cli) focus --window-id \"$id\""
                program.properties += [
                    "update_freq=2",
                    "script=\(shellArg(body))",
                    "click_script=\(shellArg(click))",
                ]
                program.events = ["front_app_switched", "space_change"]

            case "battery":
                let label = bool(item, catalog, "show-percentage") ? " label=\"$p%\"" : " label.drawing=off"
                let body = "p=$(pmset -g batt | grep -Eo '[0-9]+%' | head -n1 | tr -d '%');"
                    + " [ -z \"$p\" ] && p=0;"
                    + " if [ \"$p\" -lt \(int(item, catalog, "warn-below")) ];"
                    + " then c=\(warningColor); else c=\(colors.icon); fi;"
                    + " sketchybar --set $NAME icon.color=$c label.color=$c\(label)"
                program.properties += [
                    "update_freq=\(int(item, catalog, "update-freq"))",
                    "script=\(shellArg(body))",
                ]
                program.events = ["power_source_change", "system_woke"]

            case "clock":
                let body = "sketchybar --set $NAME label=\"$(date +\(shellArg(string(item, catalog, "format"))))\""
                program.properties += [
                    "update_freq=\(int(item, catalog, "update-freq"))",
                    "script=\(shellArg(body))",
                ]

            case "cpu":
                var body = "u=$(ps -A -o %cpu= | awk -v n=\"$(sysctl -n hw.ncpu)\""
                    + " '{s+=$1} END {printf \"%d\", s/n}');"
                    + " if [ \"$u\" -gt \(int(item, catalog, "warn-above")) ];"
                    + " then c=\(warningColor); else c=\(colors.icon); fi;"
                    + " sketchybar --set $NAME label=\"$u%\" icon.color=$c label.color=$c"
                if bool(item, catalog, "show-graph") {
                    program.graphWidth = 40
                    body += "; sketchybar --push $NAME \"$(awk -v u=\"$u\" 'BEGIN {printf \"%.2f\", u/100}')\""
                    program.properties.append("graph.color=\(shellArg(colors.accent))")
                }
                program.properties += [
                    "update_freq=\(int(item, catalog, "update-freq"))",
                    "script=\(shellArg(body))",
                ]

            case "network":
                var body = ""
                var parts: [String] = []
                if bool(item, catalog, "show-ssid") {
                    body += "s=$(networksetup -getairportnetwork en0 2>/dev/null"
                        + " | sed -n 's/^Current Wi-Fi Network: //p'); [ -z \"$s\" ] && s=offline; "
                    parts.append("$s")
                }
                if bool(item, catalog, "show-throughput") {
                    // Two samples a second apart: netstat reports counters, not rates.
                    let sample = "netstat -ib | awk '$1==\"en0\" && /Link/ {print $7\"|\"$10; exit}'"
                    body += "a=$(\(sample)); sleep 1; b=$(\(sample));"
                        + " rx=$(( (${b%|*} - ${a%|*}) / 1024 )); tx=$(( (${b#*|} - ${a#*|}) / 1024 )); "
                    parts.append("v${rx}K ^${tx}K")
                }
                if parts.isEmpty {
                    body += "sketchybar --set $NAME label.drawing=off"
                } else {
                    body += "sketchybar --set $NAME label=\"\(parts.joined(separator: " "))\""
                }
                program.properties += [
                    "update_freq=\(int(item, catalog, "update-freq"))",
                    "script=\(shellArg(body))",
                ]

            case "weather":
                let location = string(item, catalog, "location")
                let path = location == "auto" ? "" : location.replacingOccurrences(of: " ", with: "%20")
                let unit = string(item, catalog, "units") == "imperial" ? "u" : "m"
                let url = "https://wttr.in/\(path)?format=%t&\(unit)"
                let body = "sketchybar --set $NAME label=\"$(curl -sf --max-time 10 \(shellArg(url)) | tr -d '+ ')\""
                program.properties += [
                    "update_freq=\(int(item, catalog, "update-freq"))",
                    "script=\(shellArg(body))",
                ]

            case "apple-menu":
                let front = "tell application \"System Events\" to tell (first process whose frontmost is true)"
                let click: String = switch string(item, catalog, "click-action") {
                    case "about-this-mac":
                        "osascript -e \(shellArg("\(front) to click menu item 1 of menu 1 of menu bar item 1 of menu bar 1"))"
                    case "system-settings":
                        "open -b com.apple.systempreferences"
                    default:
                        "osascript -e \(shellArg("\(front) to click menu bar item 1 of menu bar 1"))"
                }
                program.properties.append("click_script=\(shellArg(click))")
                if bool(item, catalog, "show-label") {
                    program.properties += [
                        "update_freq=3600",
                        "script=\(shellArg("sketchybar --set $NAME label=\"$(sw_vers -productVersion)\""))",
                    ]
                } else {
                    program.properties.append("label.drawing=off")
                }

            case "secure-input":
                let label = bool(item, catalog, "show-process") ? " label=\"$n\"" : " label.drawing=off"
                let inactive = bool(item, catalog, "hide-when-inactive")
                    ? "sketchybar --set $NAME drawing=off"
                    : "sketchybar --set $NAME drawing=on label.drawing=off"
                let body = "pid=$(ioreg -l -w 0"
                    + " | sed -n 's/.*\"kCGSSessionSecureInputPID\"=\\([0-9]*\\).*/\\1/p' | head -n1);"
                    + " if [ -n \"$pid\" ] && [ \"$pid\" != 0 ];"
                    + " then n=$(ps -p \"$pid\" -o comm= 2>/dev/null | sed 's|.*/||');"
                    + " sketchybar --set $NAME drawing=on\(label); else \(inactive); fi"
                program.properties += ["update_freq=2", "script=\(shellArg(body))"]

            case "custom":
                let script = string(item, catalog, "script")
                guard !script.isEmpty else { return nil }
                // Passed through as written: sketchybar runs `script` as a command line,
                // and the documented examples pass arguments, so quoting it as one path
                // would break them. A path with a space is the user's to quote.
                program.properties.append("script=\(shellArg(script))")
                let frequency = int(item, catalog, "update-freq")
                // sketchybar reads `update_freq=0` as "never on a timer", which is what an
                // events-only item wants, but saying so explicitly is noise.
                if frequency > 0 { program.properties.append("update_freq=\(frequency)") }
                program.events = strings(item, catalog, "events")

            default:
                return nil
        }
        return program
    }

    private static func iconProperties(_ item: BarItem, _ catalog: BarCatalogItem) -> [String] {
        // `BarItem` carries no icon choice yet, so the catalog's first icon is the default
        // and an `icon` key in `[item.settings]` overrides it. The name goes out verbatim:
        // resolving an SF Symbols name to the character sketchybar draws needs the font,
        // which is the icon picker's job and not the generator's.
        let chosen = string(item, catalog, "icon", fallback: catalog.icons.first?.name ?? "")
        guard !chosen.isEmpty else { return [] }
        let font = catalog.icons.first { $0.name == chosen }?.font ?? catalog.icons.first?.font ?? .sfSymbols
        return ["icon=\(shellArg(chosen))", "icon.font=\(shellArg("\(font.fontFamily):\(iconFontStyle)"))"]
    }

    // MARK: - Brackets

    private static func brackets(for emitted: [EmittedItem], draft: BarDraft) -> [String] {
        var blocks: [String] = []
        for cluster in BarCluster.allCases {
            // Only *adjacent* items of one catalog group are bracketed. A bracket spanning
            // a gap would draw its border around the items in between as well.
            for run in runs(of: emitted.filter { $0.cluster == cluster }) where run.count > 1 {
                guard let group = run.first?.group else { continue }
                let name = "\(BarCatalog.namePrefix)bracket.\(cluster.rawValue).\(slug(group))"
                let members = run.map(\.name).joined(separator: " ")
                blocks.append(
                    "sketchybar --add bracket \(name) \(members)\n"
                        + command("sketchybar --set \(name)", [
                            "background.drawing=on",
                            "background.border_color=\(shellArg(draft.colors.accent))",
                            "background.border_width=\(draft.geometry.borderWidth)",
                            "background.corner_radius=\(draft.geometry.cornerRadius)",
                            "background.height=26",
                        ]),
                )
            }
        }
        return blocks
    }

    private static func runs(of items: [EmittedItem]) -> [[EmittedItem]] {
        var result: [[EmittedItem]] = []
        for item in items {
            if result.last?.last?.group == item.group {
                result[result.count - 1].append(item)
            } else {
                result.append([item])
            }
        }
        return result
    }

    private static func slug(_ group: BarItemGroup) -> String {
        switch group {
            case .aerospace: "aerospace"
            case .system: "system"
            case .privileged: "privileged"
            case .macos: "macos"
            case .escapeHatch: "escape-hatch"
        }
    }

    // MARK: - Settings lookup

    private static func bool(_ item: BarItem, _ catalog: BarCatalogItem, _ key: String) -> Bool {
        if case .bool(let value)? = item.settings[key] { return value }
        if case .bool(let value)? = catalog.setting(key)?.defaultValue { return value }
        return false
    }

    private static func int(_ item: BarItem, _ catalog: BarCatalogItem, _ key: String) -> Int {
        if case .int(let value)? = item.settings[key] { return value }
        if case .int(let value)? = catalog.setting(key)?.defaultValue { return value }
        return 0
    }

    private static func string(
        _ item: BarItem,
        _ catalog: BarCatalogItem,
        _ key: String,
        fallback: String = "",
    ) -> String {
        if case .string(let value)? = item.settings[key], !value.isEmpty { return value }
        if case .string(let value)? = catalog.setting(key)?.defaultValue, !value.isEmpty { return value }
        return fallback
    }

    private static func strings(_ item: BarItem, _ catalog: BarCatalogItem, _ key: String) -> [String] {
        let value = item.settings[key] ?? catalog.setting(key)?.defaultValue
        guard case .array(let elements)? = value else { return [] }
        return elements.compactMap { if case .string(let element) = $0 { element } else { nil } }
    }

    // MARK: - Shell

    /// `key=value` pairs go out bare when every character is safe, and single-quoted
    /// otherwise. Bare is what keeps `height=32` and `color=0xff...` readable; quoting is
    /// what keeps a user-supplied script path or strftime string from being reparsed.
    static func shellArg(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy(safeShellCharacters.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let safeShellCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,:/=+-@%",
    )

    private static func command(_ head: String, _ arguments: [String]) -> String {
        arguments.isEmpty ? head : ([head] + arguments).joined(separator: " \\\n    ")
    }
}
