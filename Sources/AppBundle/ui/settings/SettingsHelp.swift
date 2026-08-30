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
    let topic: SettingHelpTopic
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Button { isPresented.toggle() } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(topic.content.tooltip)
            .accessibilityLabel("About \(title)")
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                SettingHelpPopover(title: title, content: topic.content)
            }
        }
        .help(topic.content.tooltip)
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
