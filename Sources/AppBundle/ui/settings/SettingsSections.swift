import Common
import SwiftUI

/// A labelled group of settings rows, matching macOS System Settings' grouped-form look.
@MainActor
struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Wraps a draft binding so that every write also reports the edit.
@MainActor
func tracked<Value>(_ binding: Binding<Value>, _ onEdit: @escaping () -> Void) -> Binding<Value> {
    Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; onEdit() })
}

@MainActor
struct GeneralSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let migrationPending: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Startup") {
                Toggle(isOn: tracked($draft.startAtLogin, onEdit)) {
                    SettingHelpLabel(title: "Start AeroSpace at login", topic: .startAtLogin)
                }
                Toggle(isOn: tracked($draft.autoReloadConfig, onEdit)) {
                    SettingHelpLabel(title: "Reload the config automatically when the file changes", topic: .autoReload)
                }
            }
            SettingsGroup("macOS integration") {
                Toggle(isOn: tracked($draft.automaticallyUnhideMacosHiddenApps, onEdit)) {
                    SettingHelpLabel(title: "Automatically unhide macOS hidden apps", topic: .unhideHiddenApps)
                }
            }
            SettingsGroup(
                "Config version",
                footer: """
                    This is the format your config is written in, not a version to bump. \
                    Version 1 derives persistent workspaces from bindings and monitor assignments. \
                    Version 2 stores that list explicitly. Moving from version 1 to version 2 \
                    is an explicit migration; moving back is not its inverse.
                    """,
            ) {
                Picker(selection: tracked($draft.configVersion, onEdit)) {
                    Text("Version 1 — legacy derived workspaces").tag(1)
                    Text("Version 2 — explicit persistent workspaces").tag(2)
                } label: {
                    SettingHelpLabel(title: "Config version", topic: .configVersion)
                }
                .pickerStyle(.radioGroup)
                if migrationPending {
                    Text(SettingsMigrationCopy.configVersionHelp(migrationPending: true))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Menu-bar appearance. Its own destination rather than a group inside Application: it is
/// the one thing here the user looks at all day, and it has nothing to do with the
/// config-file and diagnostics plumbing Application collects.
@MainActor
struct MenuBarSection: View {
    @ObservedObject var viewModel: TrayMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(
                "Menu bar appearance",
                footer: "Experimental styles require macOS 14 or later and have no stability guarantees.",
            ) {
                SettingHelpLabel(title: "Style", topic: .menuBarStyle)
                let color = AppearanceTheme.current == .dark ? Color.white : Color.black
                ForEach(MenuBarStyle.allCases) { style in
                    MenuBarStyleButton(style: style, color: color).environmentObject(viewModel)
                }
            }
            SettingsGroup(
                "Position",
                footer: """
                    Points from the right edge of the menu bar; bigger moves the item further left. \
                    0 leaves the position to macOS. Applied at startup: while the app runs the \
                    position belongs to macOS, so ⌘-dragging the item still wins until the next launch.
                    """,
            ) {
                HStack {
                    SettingHelpLabel(title: "Distance from the right edge", topic: .menuBarItemPosition)
                    Spacer()
                    TextField(
                        "",
                        value: Binding(
                            get: { viewModel.experimentalUISettings.menuBarItemPosition },
                            set: { viewModel.experimentalUISettings.menuBarItemPosition = $0 },
                        ),
                        format: .number,
                    )
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .help(SettingHelpTopic.menuBarItemPosition.content.tooltip)
                }
            }
        }
    }
}

@MainActor
struct ApplicationSection: View {
    private var shortIdentification: String {
        "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
    }

    private var identification: String {
        "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Configuration file") {
                HStack {
                    SettingHelpLabel(title: "Open config in editor", topic: .openConfig)
                    Spacer()
                    openConfigButton()
                }
                HStack {
                    SettingHelpLabel(title: "Reload config", topic: .reloadConfig)
                    Spacer()
                    reloadConfigButton()
                }
            }
            SettingsGroup(
                "Diagnostics",
                footer: "Crash reports macOS wrote for \(aeroSpaceAppName). Attach the newest one to a bug report — it names the code that crashed, which is what a fix starts from.",
            ) {
                HStack {
                    SettingHelpLabel(title: "Crash reports", topic: .crashReports)
                    Spacer()
                    Button("Show Crash Reports") { revealCrashReports() }
                }
            }
            // "Check for Updates…" lives in the window footer, not here: it applies to every
            // category and was too easy to miss buried in this one.
            SettingsGroup("Version") {
                HStack {
                    SettingHelpLabel(title: shortIdentification, topic: .versionInfo)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Version Info") { identification.copyToClipboard() }
                }
            }
        }
    }
}

/// Selects this app's crash reports in Finder, so the user can drag one into a bug report.
/// macOS writes them per-user as `<executable>-<timestamp>.ips`; nothing here is written by
/// AeroSpace-edge itself. With no crash reports (the happy case) it just opens the folder
/// rather than doing nothing visible.
@MainActor
func revealCrashReports() {
    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/DiagnosticReports")
    let reports = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
        .filter { $0.lastPathComponent.hasPrefix(aeroSpaceAppName) } ?? []
    if reports.isEmpty {
        NSWorkspace.shared.open(directory)
    } else {
        NSWorkspace.shared.activateFileViewerSelecting(reports)
    }
}

@MainActor
struct LayoutSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Default container") {
                Picker(selection: tracked($draft.defaultRootContainerLayout, onEdit)) {
                    Text("Tiles").tag(Layout.tiles)
                    Text("Accordion").tag(Layout.accordion)
                } label: {
                    SettingHelpLabel(title: "Layout", topic: .defaultLayout)
                }
                Picker(selection: tracked($draft.defaultRootContainerOrientation, onEdit)) {
                    Text("Auto").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                } label: {
                    SettingHelpLabel(title: "Orientation", topic: .defaultOrientation)
                }
            }
            SettingsGroup("Normalization", footer: "Normalizations keep the window tree tidy. Turning them off gives you full manual control of the tree.") {
                Toggle(isOn: tracked($draft.enableNormalizationFlattenContainers, onEdit)) {
                    SettingHelpLabel(title: "Flatten containers", topic: .flattenContainers)
                }
                Toggle(isOn: tracked($draft.enableNormalizationOppositeOrientationForNestedContainers, onEdit)) {
                    SettingHelpLabel(title: "Opposite orientation for nested containers", topic: .oppositeOrientation)
                }
                Toggle(isOn: tracked($draft.enableNormalizationBinaryTree, onEdit)) {
                    SettingHelpLabel(title: "Binary tree", topic: .binaryTree)
                }
            }
            SettingsGroup("Accordion") {
                Stepper(value: tracked($draft.accordionPadding, onEdit), in: 0 ... 200, step: 5) {
                    SettingHelpLabel(title: "Padding: \(draft.accordionPadding)", topic: .accordionPadding)
                }
            }
        }
    }
}

@MainActor
struct FocusSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(
                "Focus follows app activation",
                footer: "'Smart' switches the focused workspace on a cross-workspace app activation only when it looks user-initiated. This option is specific to AeroSpace-edge.",
            ) {
                Picker(selection: tracked($draft.focusFollowsAppActivation, onEdit)) {
                    Text("Always").tag(FocusFollowsAppActivation.always)
                    Text("Smart").tag(FocusFollowsAppActivation.smart)
                } label: {
                    SettingHelpLabel(title: "Behavior", topic: .focusActivation)
                }
                .pickerStyle(.radioGroup)
            }
            SettingsGroup("New windows") {
                Toggle(isOn: tracked($draft.newWindowPreventFlicker, onEdit)) {
                    SettingHelpLabel(title: "Prevent flicker when a new window appears", topic: .newWindowFlicker)
                }
            }
        }
    }
}

@MainActor
struct WindowBorderSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Focused window border", footer: "This option group is specific to AeroSpace-edge.") {
                Toggle(isOn: tracked($draft.focusedWindowBorder, onEdit)) {
                    SettingHelpLabel(title: "Draw a border around the focused window", topic: .focusedWindowBorder)
                }
                Group {
                    colorRow
                    Stepper(value: tracked($draft.focusedWindowBorderWidth, onEdit), in: 0 ... 40) {
                        SettingHelpLabel(title: "Width: \(draft.focusedWindowBorderWidth)", topic: .borderWidth)
                    }
                    Stepper(value: tracked($draft.focusedWindowBorderRadius, onEdit), in: 0 ... 60) {
                        SettingHelpLabel(title: "Corner radius: \(draft.focusedWindowBorderRadius)", topic: .borderRadius)
                    }
                    Stepper(value: tracked($draft.focusedWindowBorderInset, onEdit), in: -40 ... 40) {
                        SettingHelpLabel(title: "Inset: \(draft.focusedWindowBorderInset)", topic: .borderInset)
                    }
                    HStack {
                        SettingHelpLabel(title: "Opacity: \(draft.focusedWindowBorderOpacity)%", topic: .borderOpacity)
                        Slider(value: Binding(
                            get: { Double(draft.focusedWindowBorderOpacity) },
                            set: { draft.focusedWindowBorderOpacity = Int($0.rounded()); onEdit() },
                        ), in: 0 ... 100)
                    }
                }
                .disabled(!draft.focusedWindowBorder)
            }
        }
    }

    /// The colour is a `0xAARRGGBB` string in the config. A value the picker can't
    /// represent is shown as text rather than silently rewritten.
    @ViewBuilder
    private var colorRow: some View {
        HStack {
            if let color = Color(aeroSpaceHex: draft.focusedWindowBorderColor) {
                ColorPicker(selection: Binding(
                    get: { color },
                    set: { draft.focusedWindowBorderColor = $0.aeroSpaceHex; onEdit() },
                )) {
                    SettingHelpLabel(title: "Color", topic: .borderColor)
                }
            } else {
                SettingHelpLabel(title: "Color", topic: .borderColor)
                TextField("Color (0xAARRGGBB)", text: tracked($draft.focusedWindowBorderColor, onEdit))
            }
            Text(draft.focusedWindowBorderColor).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}
