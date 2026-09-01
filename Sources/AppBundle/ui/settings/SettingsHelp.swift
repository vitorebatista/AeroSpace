import SwiftUI

enum SettingsMigrationCopy {
    static let durableConfigVersionHelp = """
        Version 1 derives persistent workspaces from bindings and workspace-to-monitor assignments. Version 2 stores `persistent-workspaces` explicitly. If you change a loaded Version 1 config to Version 2, Save asks for confirmation, materializes that list, and creates a byte-identical backup named `<filename>.backup-v1-YYYYMMDD-HHmmss` before writing.
        """
    static let pending = """
        This is a migration from Version 1 to Version 2. Version 2 materializes the `persistent-workspaces` list that Version 1 derives from bindings and workspace-to-monitor assignments. Saving creates a byte-identical backup beside the config named `<filename>.backup-v1-YYYYMMDD-HHmmss`. No files change until Save is chosen and you confirm this migration.
        """
    static let confirmationTitle = "Migrate config from version 1 to version 2?"
    static let confirmationMessage = "Version 2 will write the persistent-workspaces list that version 1 currently derives from your bindings and workspace-to-monitor assignments. A byte-identical backup of the version 1 config is created before the migrated config is saved."

    static func configVersionHelp(migrationPending: Bool) -> String {
        migrationPending ? pending : durableConfigVersionHelp
    }
}

enum SettingHelpVisual: Equatable {
    case layout
    case orientation
    case tree
    case accordion
    case innerGaps
    case outerGaps
    case focus
    case border
    case monitors
}

struct SettingHelpContent: Equatable {
    let summary: String
    let details: String
    let tomlKeys: [String]
    let visual: SettingHelpVisual?
    /// Concrete values, for the controls where the user has to type something structured. A
    /// description of a format is not a format: seeing one correct line is what makes the shape
    /// obvious. Empty for controls that are just a switch or a picker.
    let examples: [String]

    /// What the hover tooltip says. The examples travel with it — the tooltip is what a user sees
    /// before deciding whether the popover is worth opening.
    var tooltip: String {
        examples.isEmpty ? summary : summary + "\n\nExamples:\n" + examples.joined(separator: "\n")
    }

    /// Help for one key of an item's `[item.settings]` table.
    ///
    /// These controls exist per catalog entry, not per `SettingHelpTopic` case, so a static
    /// topic per key would be a second copy of the catalog to keep in step by hand. The help
    /// comes from the same declaration the control itself is built from — including the
    /// examples, which is why `BarSettingKey` carries them.
    static func barItemSetting(_ item: BarCatalogItem, _ key: BarSettingKey) -> SettingHelpContent {
        SettingHelpContent(
            summary: key.summary,
            details: "Set on the \(item.displayName) item, under its [item.settings] table in bar.toml. Default: \(key.defaultValue.toml).",
            tomlKeys: ["item.settings.\(key.key)"],
            visual: nil,
            examples: key.examples,
        )
    }
}

enum SettingHelpTopic: String, CaseIterable {
    case startAtLogin
    case autoReload
    case unhideHiddenApps
    case configVersion
    case defaultLayout
    case defaultOrientation
    case flattenContainers
    case oppositeOrientation
    case binaryTree
    case accordionPadding
    case focusActivation
    case newWindowFlicker
    case focusedWindowBorder
    case borderColor
    case borderWidth
    case borderRadius
    case borderInset
    case borderOpacity
    case innerGaps
    case outerGaps
    case perMonitorGaps
    case persistentWorkspaces
    case workspaceMonitorAssignment
    case keyMappingPreset
    case keyNotationOverrides
    case inheritEnvVars
    case envVarOverrides
    case barHeight
    case barMargin
    case barYOffset
    case barCornerRadius
    case barBorderWidth
    case barPadding
    case barBackgroundColor
    case barBorderColor
    case barLabelColor
    case barIconColor
    case barAccentColor
    case barPopupBackgroundColor
    case barPopupBorderColor
    case barChipStrip
    case barItems
    case barProfiles
    case barProfileWorkspaces
    case barProfileVisibility
    case sketchybarStatus
    case sketchybarReload
    case menuBarStyle
    case menuBarItemPosition
    case openConfig
    case reloadConfig
    case crashReports
    case versionInfo

    var content: SettingHelpContent {
        switch self {
            case .startAtLogin:
                help("Launch AeroSpace-edge after you sign in.", "Enabling this registers the app as a macOS login item. Disabling it removes that automatic launch; it does not quit a running instance.", ["start-at-login"])
            case .autoReload:
                help("Watch the config file and reload saved changes.", "When enabled, edits made by this window or another editor are picked up automatically after the first manual reload. Leave it off if another tool manages reload timing.", ["auto-reload-config"])
            case .unhideHiddenApps:
                help("Unhide an app before focusing one of its windows.", "macOS can hide an entire application. This makes AeroSpace unhide it automatically when focus moves to one of its windows.", ["automatically-unhide-macos-hidden-apps"])
            case .configVersion:
                help("Choose the config format, not the app version.", SettingsMigrationCopy.configVersionHelp(migrationPending: false), ["config-version"])
            case .defaultLayout:
                help("Choose how new workspaces arrange windows.", "Tiles divide the available area. Accordion stacks window headers and shows one main window at a time. Existing workspaces keep their current layout until changed.", ["default-root-container-layout"], .layout)
            case .defaultOrientation:
                help("Choose the first split direction for a workspace.", "Horizontal places children left-to-right; vertical places them top-to-bottom. Auto selects horizontal on wide displays and vertical on tall displays.", ["default-root-container-orientation"], .orientation)
            case .flattenContainers:
                help("Remove containers that no longer add structure.", "A container left with a single child is replaced by that child; the root container may keep a single window. Turning this off preserves every manually-created nesting level.", ["enable-normalization-flatten-containers"], .tree)
            case .oppositeOrientation:
                help("Alternate split direction at each nesting level.", "A horizontal parent gets vertical child containers and vice versa. This prevents redundant nesting; binary-tree normalization takes precedence when both are enabled.", ["enable-normalization-opposite-orientation-for-nested-containers"], .tree)
            case .binaryTree:
                help("Keep every container to at most two children.", "AeroSpace reshapes the tree into binary splits and picks each container's orientation from its rectangle. This overrides opposite-orientation normalization.", ["enable-normalization-binary-tree"], .tree)
            case .accordionPadding:
                help("Set how much of stacked accordion windows remains visible.", "Larger values expose more of each neighbouring window as a tab-like strip. Zero removes the visible strips.", ["accordion-padding"], .accordion)
            case .focusActivation:
                help("Control what happens when macOS activates an app elsewhere.", "Always follows the activated app to its workspace. Smart follows only when activation looks user-initiated, avoiding unexpected workspace jumps from background activity.", ["focus-follows-app-activation"], .focus)
            case .newWindowFlicker:
                help("Hide a new window until its first layout is ready.", "This reduces the brief flash at an app's default position before AeroSpace tiles it. It may make unusual windows appear a fraction later.", ["new-window-prevent-flicker"])
            case .focusedWindowBorder:
                help("Draw an overlay around the focused window.", "The border follows focus and uses the colour, width, opacity, radius and inset below. It is an AeroSpace-edge feature and does not change the window itself.", borderKeys, .border)
            case .borderColor:
                help(
                    "Set the focused border colour.",
                    "The value is stored as 0xAARRGGBB: alpha, red, green and blue. The colour picker preserves that exact config representation.",
                    ["focused-window-border-color"],
                    .border,
                    examples: [
                        "0xFFFF7F00  opaque orange",
                        "0x80FFFFFF  white at 50% alpha",
                    ],
                )
            case .borderWidth:
                help("Set the border stroke thickness in points.", "Higher values make focus easier to spot but cover more pixels near the window edge.", ["focused-window-border-width"], .border)
            case .borderRadius:
                help("Round the focused border corners.", "Match this roughly to the app window's corner radius. Zero produces square corners.", ["focused-window-border-radius"], .border)
            case .borderInset:
                help("Move the border inward or outward.", "Positive values move it inside the window frame; negative values expand it outside. Use this to avoid covering content or leaving a visible gap.", ["focused-window-border-inset"], .border)
            case .borderOpacity:
                help("Set how transparent the focused border is.", "100% is fully opaque; lower values let the window and desktop show through.", ["focused-window-border-opacity"], .border)
            case .innerGaps:
                help("Set spacing between adjacent tiled windows.", "Horizontal controls space between columns; vertical controls space between rows. Each value can also vary by monitor.", ["gaps.inner.horizontal", "gaps.inner.vertical"], .innerGaps)
            case .outerGaps:
                help("Set spacing between tiles and each screen edge.", "Left, right, top and bottom are independent, making room for docks, menu bars or a preferred visual margin.", ["gaps.outer.left", "gaps.outer.right", "gaps.outer.top", "gaps.outer.bottom"], .outerGaps)
            case .perMonitorGaps:
                help(
                    "Override this gap on selected monitors.",
                    "Match main, secondary, a 1-based monitor number or a monitor-name regex. Rules are checked in order; the default value applies when none match.",
                    ["gaps"],
                    .monitors,
                    examples: [
                        "main = 12          the built-in display",
                        "2 = 0              the second monitor, no gap",
                        "'^LG' = 8          every monitor whose name starts with LG",
                    ],
                )
            case .persistentWorkspaces:
                help(
                    "Keep named workspaces available even when empty.",
                    "The order here is also their stable ordering in menus and navigation. This option requires config version 2.",
                    ["persistent-workspaces"],
                    examples: [
                        "1, 2, 3            numbered workspaces",
                        "mail, web, chat    named workspaces, kept in this order",
                    ],
                )
            case .workspaceMonitorAssignment:
                help(
                    "Force a workspace onto a preferred monitor.",
                    "List monitor descriptions in priority order. AeroSpace uses the first available match and moves the workspace when monitor availability changes.",
                    ["workspace-to-monitor-force-assignment"],
                    .monitors,
                    examples: [
                        "1 -> secondary            workspace 1 on the external display",
                        "mail -> main              workspace 'mail' on the built-in one",
                        "web -> '^DELL', main      first match wins, main as fallback",
                    ],
                )
            case .keyMappingPreset:
                help("Interpret key notation using your keyboard layout.", "Choose the layout used when resolving binding names. It changes which physical keys the same notation refers to; it does not rewrite your bindings.", ["key-mapping.preset"])
            case .keyNotationOverrides:
                help(
                    "Define or remap individual key names.",
                    "The left side is the notation used in bindings; the right side is an AeroSpace key-code name. Overrides win over the selected preset.",
                    ["key-mapping.key-notation-to-key-code"],
                    examples: [
                        "zz -> semicolon     then 'alt-zz' binds the ; key",
                        "ö -> leftSquareBracket",
                    ],
                )
            case .inheritEnvVars:
                help("Pass the launching process environment to commands.", "When disabled, exec-and-forget starts with only the explicit overrides below plus AeroSpace-provided variables. This can remove PATH and other shell-dependent values.", ["exec.inherit-env-vars"])
            case .barHeight:
                help("Set how tall the bar is.", "Points, as sketchybar measures them. Item heights follow the bar; this is the space they get.", ["bar.height"])
            case .barMargin:
                help("Inset the bar from the screen edges.", "Points of empty space left of, right of, and around the bar. A non-zero margin is what makes the bar look detached rather than glued to the top of the screen.", ["bar.margin"])
            case .barYOffset:
                help("Move the bar down from the top of the screen.", "Points. Combined with a margin and a corner radius this is what produces a floating bar; zero puts it flush against the menu bar.", ["bar.y-offset"])
            case .barCornerRadius:
                help("Round the bar's corners.", "Points. Zero gives square corners. Only visible when the bar is inset by a margin.", ["bar.corner-radius"])
            case .barBorderWidth:
                help("Set the bar's outline thickness.", "Points, drawn in the border colour. Zero removes the outline.", ["bar.border-width"])
            case .barPadding:
                help("Pad the bar's contents from its own edges.", "Points between the bar's edge and the first and last item. Left and right are independent.", ["bar.padding-left", "bar.padding-right"])
            case .barBackgroundColor:
                barColor("Set the bar's background colour.", "The fill behind every item. Alpha below ff makes the desktop show through.", "bar.colors.background")
            case .barBorderColor:
                barColor("Set the bar's outline colour.", "Drawn at the border width above. Nothing is drawn when that width is zero.", "bar.colors.border")
            case .barLabelColor:
                barColor("Set the default text colour.", "Every item's label unless the item overrides it.", "bar.colors.label")
            case .barIconColor:
                barColor("Set the default icon colour.", "Every item's icon glyph unless the item overrides it.", "bar.colors.icon")
            case .barAccentColor:
                barColor("Set the highlight colour.", "Used for the parts of an item that have to stand out — the focused workspace, a warning state.", "bar.colors.accent")
            case .barPopupBackgroundColor:
                barColor("Set the popup background colour.", "The fill behind the panel an item opens when it is clicked.", "bar.colors.popup-background")
            case .barPopupBorderColor:
                barColor("Set the popup outline colour.", "The outline of the panel an item opens when it is clicked.", "bar.colors.popup-border")
            case .barChipStrip:
                help(
                    "Drag a chip between the three positions, or within one, to place an item.",
                    "The strip is a schematic of the bar, not a picture of it: it says which items sit left, centre and right and in what order, and it edits the same list the rows below do. While sketchybar is running, the bar at the top of the screen follows the drag — that is the preview, so there is nothing here to drift out of sync with it. A dashed chip needs a helper binary that ships in a later release, or is an item this release doesn't recognise; either way it won't render yet.",
                    ["item.cluster"],
                )
            case .barItems:
                help(
                    "Build the bar from the catalog, in the order you drag them into.",
                    "Each list is one of sketchybar's three positions, and a list's order is the order its items are drawn in. An item's own settings are under it. Items that need a helper binary are listed but cannot be added yet.",
                    ["item", "item.id", "item.cluster"],
                )
            case .barProfiles:
                help(
                    "Give a group of workspaces its own set of bar items.",
                    "A profile owns workspaces and changes which items are drawn while one of them is focused. Items are still declared once, above — a profile only lists the exceptions, so the clock is never repeated per profile. Switching is pushed by AeroSpace-edge itself the moment focus crosses into another profile's workspace; the generated config holds no profile logic. A workspace no profile names belongs to every profile and draws everything.",
                    ["profile", "profile.name"],
                    examples: [
                        "[[profile]]",
                        "name = 'Work'",
                        "workspaces = ['1', '2', 'C']",
                    ],
                )
            case .barProfileWorkspaces:
                help(
                    "List the workspaces this profile owns.",
                    "Comma-separated workspace names, matched exactly as they are written in ~/.aerospace.toml. A workspace listed by two profiles belongs to the first one. While the profile is active the workspaces item lists only these, so the bar shows the group rather than every workspace on the machine.",
                    ["profile.workspaces"],
                    examples: [
                        "1, 2, 3, C, S",
                        "media, chat",
                    ],
                )
            case .barProfileVisibility:
                help(
                    "Choose which items this profile draws.",
                    "Every item is drawn unless a profile hides it, and a hidden item is written to that profile's hide list. Showing an item in one profile makes it opt-in everywhere: it then appears only in the profiles that list it under show, which is how an item can belong to a single profile without every other one having to hide it. Turning off the last profile that showed an item makes it ordinary again, and it goes back to being drawn everywhere.",
                    ["profile.show", "profile.hide"],
                    examples: [
                        "show = ['cpu']",
                        "hide = ['weather', 'network']",
                    ],
                )
            case .sketchybarStatus:
                appPref(
                    "Whether sketchybar is installed, and which file this page writes.",
                    "sketchybar stays a separate Homebrew install that AeroSpace-edge configures rather than replaces. Without it the page still edits and saves; nothing renders until it is installed. bar.toml is the source of truth and is hand-editable; sketchybar's own config is generated from it and overwritten on every save.",
                )
            case .sketchybarReload:
                appPref(
                    "Regenerate sketchybar's config from the last save and reload it.",
                    "Save already does this. Use it after starting sketchybar by hand, or when something else has overwritten its config. It uses the saved bar.toml, not unsaved edits.",
                )
            case .menuBarStyle:
                appPref(
                    "Choose how workspaces are drawn in the menu bar.",
                    "Monospaced font keeps the item from shifting as you switch workspaces. The experimental styles require macOS 14 or later and carry no stability guarantee.",
                )
            case .menuBarItemPosition:
                appPref(
                    "Pin where the menu-bar item sits.",
                    "macOS stores a status item's position per app and restores it on every launch, so an item that once landed behind the notch stays there. A value here is re-applied at startup — nothing can move the item once it exists, which is why the change only shows after Relaunch to Apply. While the app runs the position belongs to macOS, so ⌘-dragging the item wins until the next launch.",
                    examples: [
                        "0    let macOS place it (default)",
                        "400  left of the Control Center icons on a 1512-point-wide display",
                    ],
                )
            case .openConfig:
                appPref(
                    "Open the config AeroSpace-edge actually loaded.",
                    "This is the resolved file, not a guess. With no custom config yet, the bundled default is copied to ~/.aerospace-edge.toml first and that copy is opened.",
                )
            case .reloadConfig:
                appPref(
                    "Re-read the config and refresh window management.",
                    "Identical to the reload-config command. Use it after editing the file in another editor; Save in this window already reloads for you.",
                )
            case .crashReports:
                appPref(
                    "Show the crash reports macOS wrote for this app.",
                    "Selects ~/Library/Logs/DiagnosticReports/AeroSpace-edge-*.ips in Finder, or opens the folder when there are none. macOS writes these, not AeroSpace-edge; attach the newest one to a bug report, since it names the code that crashed.",
                )
            case .versionInfo:
                appPref(
                    "Copy the exact build you are running.",
                    "App name, version and the full git hash — the thing to paste into a bug report so a fix lands against the right code. The line beside the button shows the short form.",
                )
            case .envVarOverrides:
                help(
                    "Add or replace environment variables for commands.",
                    "Overrides apply to every exec-and-forget command. Use $VAR to include an inherited value; PWD is managed by AeroSpace and cannot be overridden.",
                    ["exec.env-vars"],
                    examples: [
                        "PATH -> /opt/homebrew/bin:$PATH",
                        "EDITOR -> nvim",
                    ],
                )
        }
    }

    private var borderKeys: [String] {
        [
            "focused-window-border",
            "focused-window-border-color",
            "focused-window-border-width",
            "focused-window-border-opacity",
            "focused-window-border-radius",
            "focused-window-border-inset",
        ]
    }

    /// A `bar.toml` colour. Every one of them is typed as `0xAARRGGBB`, so they all need the
    /// same worked examples and none of them gets a hand-written variation of them.
    private func barColor(_ summary: String, _ details: String, _ key: String) -> SettingHelpContent {
        help(
            summary,
            details + " Stored as 0xAARRGGBB: alpha, red, green, blue. The colour well writes back exactly that spelling.",
            [key],
            examples: [
                "0xb3202020  near-black at 70% alpha",
                "0xffeeeeee  opaque near-white",
                "0xff717ebb  the default accent",
            ],
        )
    }

    /// A control that is not a config key: app preferences and immediate actions. They still get
    /// the same popover, minus the TOML block.
    private func appPref(_ summary: String, _ details: String, examples: [String] = []) -> SettingHelpContent {
        SettingHelpContent(summary: summary, details: details, tomlKeys: [], visual: nil, examples: examples)
    }

    private func help(
        _ summary: String,
        _ details: String,
        _ tomlKeys: [String],
        _ visual: SettingHelpVisual? = nil,
        examples: [String] = [],
    ) -> SettingHelpContent {
        SettingHelpContent(summary: summary, details: details, tomlKeys: tomlKeys, visual: visual, examples: examples)
    }
}

@MainActor
struct SettingHelpLabel: View {
    let title: String
    let content: SettingHelpContent
    @State private var isPresented = false

    init(title: String, topic: SettingHelpTopic) {
        self.title = title
        content = topic.content
    }

    /// For the controls the catalog generates — see `SettingHelpContent.barItemSetting`.
    init(title: String, content: SettingHelpContent) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Button { isPresented.toggle() } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(content.tooltip)
            .accessibilityLabel("About \(title)")
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                SettingHelpPopover(title: title, content: content)
            }
        }
        .help(content.tooltip)
    }
}

@MainActor
private struct SettingHelpPopover: View {
    let title: String
    let content: SettingHelpContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let visual = content.visual {
                SettingHelpDiagram(visual: visual)
                    .frame(height: 112)
                    .accessibilityHidden(true)
            }
            Text(content.summary).fontWeight(.medium)
            Text(content.details).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !content.examples.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Examples").font(.caption).foregroundStyle(.secondary)
                    ForEach(content.examples, id: \.self) { example in
                        Text(example).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                // No TOML key means this isn't a config option at all — an app preference or an
                // immediate action. Saying so is the point: it explains why Save stays disabled.
                if content.tomlKeys.isEmpty {
                    Text("Not a config option — it never touches your TOML.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(content.tomlKeys.count == 1 ? "TOML key" : "TOML keys")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(content.tomlKeys, id: \.self) { key in
                        Text(key).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

@MainActor
private struct SettingHelpDiagram: View {
    let visual: SettingHelpVisual

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.07))
            switch visual {
                case .layout: layout
                case .orientation: orientation
                case .tree: tree
                case .accordion: accordion
                case .innerGaps: gaps(outer: false)
                case .outerGaps: gaps(outer: true)
                case .focus: focus
                case .border: border
                case .monitors: monitors
            }
        }
    }

    private var layout: some View {
        HStack(spacing: 28) {
            diagramColumn("Tiles") { HStack(spacing: 3) { panel; panel } }
            Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
            diagramColumn("Accordion") {
                ZStack { panel.offset(x: -8); panel.offset(x: 0); panel.offset(x: 8) }
            }
        }
    }

    private var orientation: some View {
        HStack(spacing: 24) {
            diagramColumn("Horizontal") { HStack(spacing: 3) { panel; panel } }
            diagramColumn("Vertical") { VStack(spacing: 3) { panel; panel } }
        }
    }

    private var tree: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Image(systemName: "rectangle.split.2x1").font(.system(size: 38)).foregroundStyle(Color.accentColor)
        }
    }

    private var accordion: some View {
        HStack(spacing: 18) {
            ZStack { panel.offset(x: -12); panel.offset(x: 0); panel.offset(x: 12) }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            ZStack { panel.offset(x: -22); panel.offset(x: 0); panel.offset(x: 22) }
        }
    }

    private func gaps(outer: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .stroke(outer ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: outer ? 7 : 1)
                .frame(width: 148, height: 82)
            HStack(spacing: outer ? 4 : 12) {
                panel.frame(width: 60, height: 62)
                panel.frame(width: 60, height: 62)
            }
            if !outer {
                Rectangle().fill(Color.accentColor).frame(width: 7, height: 62)
            }
        }
    }

    private var focus: some View {
        HStack(spacing: 14) {
            Image(systemName: "macwindow").font(.system(size: 38)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Image(systemName: "macwindow").font(.system(size: 38)).foregroundStyle(Color.accentColor)
        }
        .overlay(alignment: .bottomTrailing) { Image(systemName: "cursorarrow.click.2").offset(x: -36, y: -5) }
    }

    private var border: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.08)).frame(width: 150, height: 82)
            RoundedRectangle(cornerRadius: 11).stroke(Color.accentColor, lineWidth: 5).frame(width: 138, height: 70)
        }
    }

    private var monitors: some View {
        HStack(spacing: 12) {
            monitor("1", workspace: "A")
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            monitor("2", workspace: "A")
        }
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.72)).frame(width: 48, height: 55)
    }

    private func diagramColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) { content().frame(width: 105, height: 60); Text(title).font(.caption2) }
    }

    private func monitor(_ number: String, workspace: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Image(systemName: "display").font(.system(size: 42)).foregroundStyle(.secondary)
                Text(workspace).font(.caption.bold()).foregroundStyle(Color.accentColor).offset(y: -3)
            }
            Text("Monitor \(number)").font(.caption2)
        }
    }
}
