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
                Toggle("Start AeroSpace at login", isOn: tracked($draft.startAtLogin, onEdit))
                Toggle("Reload the config automatically when the file changes", isOn: tracked($draft.autoReloadConfig, onEdit))
            }
            SettingsGroup("macOS integration") {
                Toggle("Automatically unhide macOS hidden apps", isOn: tracked($draft.automaticallyUnhideMacosHiddenApps, onEdit))
            }
            SettingsGroup("Config version", footer: "Only versions AeroSpace understands are accepted; an unknown value is rejected when you save.") {
                Stepper("config-version: \(draft.configVersion)", value: tracked($draft.configVersion, onEdit), in: 1 ... 9)
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
                Picker("Layout", selection: tracked($draft.defaultRootContainerLayout, onEdit)) {
                    Text("Tiles").tag(Layout.tiles)
                    Text("Accordion").tag(Layout.accordion)
                }
                Picker("Orientation", selection: tracked($draft.defaultRootContainerOrientation, onEdit)) {
                    Text("Auto").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                }
            }
            SettingsGroup("Normalization", footer: "Normalizations keep the window tree tidy. Turning them off gives you full manual control of the tree.") {
                Toggle("Flatten containers", isOn: tracked($draft.enableNormalizationFlattenContainers, onEdit))
                Toggle("Opposite orientation for nested containers", isOn: tracked($draft.enableNormalizationOppositeOrientationForNestedContainers, onEdit))
                Toggle("Binary tree", isOn: tracked($draft.enableNormalizationBinaryTree, onEdit))
            }
            SettingsGroup("Accordion") {
                Stepper("Padding: \(draft.accordionPadding)", value: tracked($draft.accordionPadding, onEdit), in: 0 ... 200, step: 5)
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
                Picker("Behavior", selection: tracked($draft.focusFollowsAppActivation, onEdit)) {
                    Text("Always").tag(FocusFollowsAppActivation.always)
                    Text("Smart").tag(FocusFollowsAppActivation.smart)
                }
                .pickerStyle(.radioGroup)
            }
            SettingsGroup("New windows") {
                Toggle("Prevent flicker when a new window appears", isOn: tracked($draft.newWindowPreventFlicker, onEdit))
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
                Toggle("Draw a border around the focused window", isOn: tracked($draft.focusedWindowBorder, onEdit))
                Group {
                    colorRow
                    Stepper("Width: \(draft.focusedWindowBorderWidth)", value: tracked($draft.focusedWindowBorderWidth, onEdit), in: 0 ... 40)
                    Stepper("Corner radius: \(draft.focusedWindowBorderRadius)", value: tracked($draft.focusedWindowBorderRadius, onEdit), in: 0 ... 60)
                    Stepper("Inset: \(draft.focusedWindowBorderInset)", value: tracked($draft.focusedWindowBorderInset, onEdit), in: -40 ... 40)
                    HStack {
                        Text("Opacity: \(draft.focusedWindowBorderOpacity)%")
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
                ColorPicker("Color", selection: Binding(
                    get: { color },
                    set: { draft.focusedWindowBorderColor = $0.aeroSpaceHex; onEdit() },
                ))
            } else {
                TextField("Color (0xAARRGGBB)", text: tracked($draft.focusedWindowBorderColor, onEdit))
            }
            Text(draft.focusedWindowBorderColor).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}
