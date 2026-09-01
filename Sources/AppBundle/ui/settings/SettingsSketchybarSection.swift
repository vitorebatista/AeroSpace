import AppKit
import SwiftUI

/// The Sketchybar destination: it edits `bar.toml`, not `~/.aerospace-edge.toml`, so it binds
/// to `BarSettingsModel` instead of the draft every other section shares.
@MainActor
struct SettingsSketchybarSection: View {
    @ObservedObject var model: BarSettingsModel
    /// Which rows are open, by position in `draft.items`. Positions move under a reorder and
    /// an insertion, and nothing about a row survives one identifiably, so the set is dropped
    /// whenever the list changes rather than left pointing at a different item.
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .unreadable(let message) = model.mode {
                unreadable(message)
            } else {
                barGroup
                coloursGroup
                itemsGroup
                statusGroup
            }
        }
        .onChange(of: model.loadGeneration) { _ in expanded = [] }
    }

    /// Writes are dropped while a save is in flight, for the same reason `SettingsView` drops
    /// them: `save()` finishes with a `load()` that reseeds the draft from disk.
    private var draft: Binding<BarDraft> {
        Binding(get: { model.draft }, set: { if !model.isSaving { model.draft = $0 } })
    }

    private func onEdit() { model.markEdited() }

    @ViewBuilder
    private func unreadable(_ message: String) -> some View {
        SettingsGroup("bar.toml doesn't parse", footer: "Saving is disabled until it does — writing this form over a file that couldn't be read would destroy it. Fix the file in an editor, then press Revert.") {
            Text(message).font(.caption.monospaced()).textSelection(.enabled)
            Text(model.configUrl.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    // MARK: - Bar

    private var barGroup: some View {
        SettingsGroup("Bar", footer: "The bar itself, in points. A margin, a y-offset and a corner radius together are what make it float rather than sit flush against the top of the screen.") {
            stepper("Height", .barHeight, draft.geometry.height, 0 ... 200)
            stepper("Margin", .barMargin, draft.geometry.margin, 0 ... 100)
            stepper("Y offset", .barYOffset, draft.geometry.yOffset, -100 ... 100)
            stepper("Corner radius", .barCornerRadius, draft.geometry.cornerRadius, 0 ... 60)
            stepper("Border width", .barBorderWidth, draft.geometry.borderWidth, 0 ... 20)
            HStack {
                SettingHelpLabel(title: "Padding", topic: .barPadding)
                Spacer()
                Stepper("Left: \(model.draft.geometry.paddingLeft)", value: tracked(draft.geometry.paddingLeft, onEdit), in: 0 ... 100)
                Stepper("Right: \(model.draft.geometry.paddingRight)", value: tracked(draft.geometry.paddingRight, onEdit), in: 0 ... 100)
            }
        }
    }

    private func stepper(_ title: String, _ topic: SettingHelpTopic, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: tracked(value, onEdit), in: range) {
            SettingHelpLabel(title: "\(title): \(value.wrappedValue)", topic: topic)
        }
    }

    private var coloursGroup: some View {
        SettingsGroup("Colours", footer: "Stored as 0xAARRGGBB, sketchybar's own spelling. A value the picker can't represent stays a text field rather than being rewritten.") {
            colourRow("Background", .barBackgroundColor, draft.colors.background)
            colourRow("Border", .barBorderColor, draft.colors.border)
            colourRow("Label", .barLabelColor, draft.colors.label)
            colourRow("Icon", .barIconColor, draft.colors.icon)
            colourRow("Accent", .barAccentColor, draft.colors.accent)
            colourRow("Popup background", .barPopupBackgroundColor, draft.colors.popupBackground)
            colourRow("Popup border", .barPopupBorderColor, draft.colors.popupBorder)
        }
    }

    @ViewBuilder
    private func colourRow(_ title: String, _ topic: SettingHelpTopic, _ value: Binding<String>) -> some View {
        HStack {
            if let colour = Color(aeroSpaceHex: value.wrappedValue) {
                ColorPicker(selection: Binding(
                    get: { colour },
                    set: { value.wrappedValue = $0.aeroSpaceHex; onEdit() },
                )) {
                    SettingHelpLabel(title: title, topic: topic)
                }
            } else {
                SettingHelpLabel(title: title, topic: topic)
                TextField("0xAARRGGBB", text: tracked(value, onEdit))
            }
            Text(value.wrappedValue).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    // MARK: - Items

    private var itemsGroup: some View {
        SettingsGroup("Items", footer: "One list per position on the bar. Drag inside a list to reorder it — that order is the order the items are drawn in, and it is the order they are written to bar.toml.") {
            SettingHelpLabel(title: "Bar items", topic: .barItems)
            ForEach(BarCluster.allCases, id: \.self) { cluster in clusterList(cluster) }
        }
    }

    @ViewBuilder
    private func clusterList(_ cluster: BarCluster) -> some View {
        let positions = model.draft.positions(in: cluster)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.clusterTitle(cluster)).font(.subheadline.weight(.semibold))
                Spacer()
                addMenu(for: cluster)
            }
            if positions.isEmpty {
                Text("Nothing here yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(positions, id: \.self) { position in itemRow(position) }
                        .onMove { offsets, destination in
                            draft.wrappedValue.move(in: cluster, fromOffsets: offsets, toOffset: destination)
                            expanded = []
                            onEdit()
                        }
                }
                .frame(height: listHeight(positions))
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.vertical, 4)
    }

    /// The list can't size itself: it is inside the window's own `ScrollView`, which offers it
    /// unbounded height. Row heights are the AppKit list's, and an open row adds its settings.
    private func listHeight(_ positions: [Int]) -> CGFloat {
        let openRows = positions.count(where: { expanded.contains($0) })
        return min(max(CGFloat(positions.count) * 30 + CGFloat(openRows) * 130 + 12, 48), 460)
    }

    private func addMenu(for cluster: BarCluster) -> some View {
        Menu("Add item") {
            ForEach(BarItemGroup.allCases, id: \.self) { group in
                Section(group.displayName) {
                    ForEach(BarCatalog.items(in: group)) { item in
                        Button(item.displayName) {
                            draft.wrappedValue.add(item, to: cluster)
                            expanded = []
                            onEdit()
                        }
                        .disabled(!item.isAvailable)
                        // Unavailable items stay listed so their place in the bar is known; the
                        // note is the only thing that says why the row won't take a click.
                        .help(Self.availabilityNote(item) ?? item.summary)
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func itemRow(_ position: Int) -> some View {
        let item = model.draft.items.getOrNil(atIndex: position)
        let catalogItem = item.flatMap { BarCatalog.item(id: $0.id) }
        DisclosureGroup(isExpanded: expansion(of: position)) {
            settingsEditor(position, catalogItem)
        } label: {
            HStack(spacing: 6) {
                if let symbol = catalogItem?.icons.first(where: { $0.font == .sfSymbols })?.name {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
                Text(catalogItem?.displayName ?? item?.id ?? "")
                if catalogItem == nil {
                    Text("unrecognised").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button(role: .destructive) {
                    draft.wrappedValue.items.remove(at: position)
                    expanded = []
                    onEdit()
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(catalogItem?.displayName ?? item?.id ?? "item")")
            }
        }
    }

    private func expansion(of position: Int) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(position) },
            set: { isExpanded in
                if isExpanded { expanded.insert(position) } else { expanded.remove(position) }
            },
        )
    }

    @ViewBuilder
    private func settingsEditor(_ position: Int, _ catalogItem: BarCatalogItem?) -> some View {
        let unrecognised = model.draft.unrecognisedSettings(at: position)
        VStack(alignment: .leading, spacing: 6) {
            if let catalogItem {
                Text(catalogItem.summary).font(.caption).foregroundStyle(.secondary)
                ForEach(catalogItem.settings, id: \.key) { key in settingControl(position, catalogItem, key) }
            } else {
                Text("This item isn't in the catalog. Its keys are kept exactly as written, so a newer AeroSpace-edge — or your own hand edit — still reads it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !unrecognised.isEmpty {
                Divider()
                Text("Keys this release doesn't recognise. They are kept as written:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(unrecognised) { setting in
                    Text("\(setting.key) = \(setting.value.toml)").font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func settingControl(_ position: Int, _ catalogItem: BarCatalogItem, _ key: BarSettingKey) -> some View {
        let help = SettingHelpContent.barItemSetting(catalogItem, key)
        switch key.type {
            case .bool:
                Toggle(isOn: boolBinding(position, key)) { SettingHelpLabel(title: key.displayName, content: help) }
            case .int(let minimum, let maximum):
                Stepper(value: intBinding(position, key), in: minimum ... maximum) {
                    SettingHelpLabel(title: "\(key.displayName): \(intBinding(position, key).wrappedValue)", content: help)
                }
            case .string:
                HStack {
                    SettingHelpLabel(title: key.displayName, content: help)
                    TextField(key.displayName, text: stringBinding(position, key))
                }
            case .stringList:
                HStack {
                    SettingHelpLabel(title: key.displayName, content: help)
                    TextField("comma-separated", text: stringListBinding(position, key))
                }
            case .enumeration(let cases):
                Picker(selection: stringBinding(position, key)) {
                    ForEach(cases, id: \.self) { Text($0).tag($0) }
                } label: {
                    SettingHelpLabel(title: key.displayName, content: help)
                }
                .pickerStyle(.menu)
                .fixedSize()
        }
    }

    private func boolBinding(_ position: Int, _ key: BarSettingKey) -> Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = model.draft.settingValue(at: position, key) { return value }
                if case .bool(let value) = key.defaultValue { return value }
                return false
            },
            set: { commit(position, key, .bool($0)) },
        )
    }

    private func intBinding(_ position: Int, _ key: BarSettingKey) -> Binding<Int> {
        Binding(
            get: {
                if case .int(let value) = model.draft.settingValue(at: position, key) { return value }
                if case .int(let value) = key.defaultValue { return value }
                return 0
            },
            set: { commit(position, key, .int($0)) },
        )
    }

    private func stringBinding(_ position: Int, _ key: BarSettingKey) -> Binding<String> {
        Binding(
            get: {
                if case .string(let value) = model.draft.settingValue(at: position, key) { return value }
                if case .string(let value) = key.defaultValue { return value }
                return ""
            },
            set: { commit(position, key, .string($0)) },
        )
    }

    /// A list is edited as one comma-separated field, so the docs say comma-separated and the
    /// placeholder does too. Empty entries are dropped rather than written as `''`.
    private func stringListBinding(_ position: Int, _ key: BarSettingKey) -> Binding<String> {
        Binding(
            get: {
                guard case .array(let values) = model.draft.settingValue(at: position, key) else { return "" }
                return values.map { if case .string(let value) = $0 { value } else { $0.toml } }.joined(separator: ", ")
            },
            set: { text in
                let values = text.split(separator: ",")
                    .map { BarSettingValue.string($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { if case .string(let value) = $0 { !value.isEmpty } else { true } }
                commit(position, key, .array(values))
            },
        )
    }

    private func commit(_ position: Int, _ key: BarSettingKey, _ value: BarSettingValue) {
        guard !model.isSaving else { return }
        model.draft.setSettingValue(at: position, key.key, value)
        onEdit()
    }

    private static func clusterTitle(_ cluster: BarCluster) -> String {
        switch cluster {
            case .left: "Left"
            case .center: "Centre"
            case .right: "Right"
        }
    }

    private static func availabilityNote(_ item: BarCatalogItem) -> String? {
        guard case .unavailable(let note) = item.availability else { return nil }
        return note
    }

    // MARK: - Status

    private var statusGroup: some View {
        SettingsGroup("Status", footer: "bar.toml is the source of truth and is yours to hand-edit. sketchybar's own config is generated from it and overwritten on every save.") {
            HStack {
                SettingHelpLabel(title: "sketchybar", topic: .sketchybarStatus)
                Spacer()
                if model.isBackendAvailable {
                    Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                } else {
                    Label("Not installed — nothing renders yet", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Text("Config file").foregroundStyle(.secondary)
                Spacer()
                Text(model.configUrl.path).font(.caption.monospaced()).textSelection(.enabled)
            }
            if model.willCreateConfig {
                Text("Saving will create this file.").font(.caption).foregroundStyle(.secondary)
            }
            if let backup = model.takeoverBackupUrl { takeoverNotice(backup) }
            if let status = model.status { statusLine(status) }
            HStack {
                SettingHelpLabel(title: "Reload sketchybar", topic: .sketchybarReload)
                Spacer()
                Button("Reload") { Task { await model.reloadBar() } }
                    .disabled(!model.isBackendAvailable || model.isSaving)
            }
        }
    }

    /// Stays on screen until it is dismissed: it names the only copy of a config the user may
    /// have spent years on, and a status line that scrolled away would take the path with it.
    private func takeoverNotice(_ backup: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Your own sketchybar config was moved aside.", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.caption).foregroundStyle(.orange)
            Text(backup.path).font(.caption.monospaced()).textSelection(.enabled)
            HStack {
                Button("Reveal Backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                Button("Dismiss") { model.dismissTakeoverNotice() }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func statusLine(_ status: BarSettingsStatus) -> some View {
        switch status {
            case .saved(let message):
                Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
        }
    }
}
