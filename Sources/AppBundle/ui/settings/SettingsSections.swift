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
                    Version 2 is current. On version 1, 'persistent-workspaces' is rejected \
                    and AeroSpace instead derives the workspace list from your bindings and \
                    monitor assignments — so switching down loses the explicit list, and \
                    switching up starts with whatever list it had derived.
                    """,
            ) {
                Picker(selection: tracked($draft.configVersion, onEdit)) {
                    Text("2 (current)").tag(2)
                    Text("1 (legacy)").tag(1)
                } label: {
                    SettingHelpLabel(title: "Config version", topic: .configVersion)
                }
                .pickerStyle(.radioGroup)
            }
        }
    }
}

@MainActor
struct ApplicationSection: View {
    @ObservedObject var viewModel: TrayMenuModel

    private var shortIdentification: String {
        "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
    }

    private var identification: String {
        "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Configuration file") {
                openConfigButton()
                reloadConfigButton()
            }
            SettingsGroup(
                "Menu bar appearance",
                footer: "Experimental styles require macOS 14 or later and have no stability guarantees.",
            ) {
                let color = AppearanceTheme.current == .dark ? Color.white : Color.black
                ForEach(MenuBarStyle.allCases) { style in
                    MenuBarStyleButton(style: style, color: color).environmentObject(viewModel)
                }
            }
            SettingsGroup("Updates") {
                Button("Check Now") { Task { await runCheckForUpdatesFlow() } }
                HStack {
                    Text(shortIdentification).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Version Info") { identification.copyToClipboard() }
                }
            }
        }
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
