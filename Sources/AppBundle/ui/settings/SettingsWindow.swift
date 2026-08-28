import Common
import SwiftUI

public let settingsWindowId = "\(aeroSpaceAppName).settings"

@MainActor
public func getSettingsWindow(model: SettingsModel) -> some Scene {
    // SwiftUI.Window because AeroSpace already has a class called Window
    SwiftUI.Window("\(aeroSpaceAppName) Settings", id: settingsWindowId) {
        SettingsView(model: model)
            .onAppear {
                // Without this an accessory-mode app's window can't receive keyboard input
                NSApp.setActivationPolicy(.accessory)
                model.load()
            }
    }
    .windowResizability(.contentMinSize)
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case layout = "Layout"
    case gaps = "Gaps"
    case focus = "Focus"
    case windowBorder = "Window Border"
    case workspaces = "Workspaces & Monitors"
    case keyMapping = "Key Mapping"
    case exec = "Exec"
    case keybindings = "Keybindings"
    case windowRules = "Window Rules"
    case callbacks = "Callbacks"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
            case .general: "gearshape"
            case .layout: "square.grid.2x2"
            case .gaps: "rectangle.split.3x1"
            case .focus: "scope"
            case .windowBorder: "rectangle.dashed"
            case .workspaces: "display.2"
            case .keyMapping: "keyboard"
            case .exec: "terminal"
            case .keybindings: "command"
            case .windowRules: "macwindow.badge.plus"
            case .callbacks: "arrow.triangle.branch"
        }
    }
}

@MainActor
struct SettingsView: View {
    @StateObject private var model: SettingsModel
    @State private var selection: SettingsCategory = .general
    @State private var showOverwriteAlert = false

    init(model: SettingsModel) { self._model = .init(wrappedValue: model) }

    var body: some View {
        VStack(spacing: 0) {
            switch model.mode {
                case .readOnly(let reason):
                    ScrollView { Text(reason).font(.body.monospaced()).padding() }
                case .rawOnly(let parseError):
                    rawOnlyBody(parseError: parseError)
                case .form:
                    NavigationSplitView {
                        List(SettingsCategory.allCases, selection: $selection) { category in
                            NavigationLink(value: category) {
                                Label(category.rawValue, systemImage: category.systemImage)
                            }
                        }
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
                    } detail: {
                        ScrollView { section(for: selection).padding() }
                    }
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func rawOnlyBody(parseError: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This config doesn't parse, so only raw editing is available.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(parseError).font(.caption.monospaced()).textSelection(.enabled)
            TextEditor(text: Binding(get: { model.wholeFileText }, set: { model.wholeFileText = $0; markDirty() }))
                .font(.system(size: 12).monospaced())
        }
        .padding()
    }

    @ViewBuilder
    private func section(for category: SettingsCategory) -> some View {
        switch category {
            case .general: GeneralSection(draft: $model.draft, onEdit: markDirty)
            case .layout: LayoutSection(draft: $model.draft, onEdit: markDirty)
            case .focus: FocusSection(draft: $model.draft, onEdit: markDirty)
            case .windowBorder: WindowBorderSection(draft: $model.draft, onEdit: markDirty)
            case .gaps: GapsSection(draft: $model.draft, loadGeneration: model.loadGeneration, onEdit: markDirty)
            case .workspaces: WorkspacesSection(draft: $model.draft, onEdit: markDirty)
            case .keyMapping: KeyMappingSection(draft: $model.draft, onEdit: markDirty)
            case .exec: ExecSection(draft: $model.draft, onEdit: markDirty)
            // Added in Task 8
            default: Text("Not implemented yet").foregroundStyle(.secondary)
        }
    }

    private func markDirty() { model.isDirty = true; model.status = nil }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .error(let message) = model.status {
                ScrollView {
                    Text(displayableErrorMessage(message))
                        .font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            HStack {
                if model.willCreateConfig {
                    Text("Saving will create ~/\(configDotfileName)").font(.caption).foregroundStyle(.secondary)
                } else if case .saved = model.status {
                    Label("Saved and reloaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("Revert") { model.revert() }.disabled(!model.isDirty)
                Button("Save") {
                    if model.externallyModified { showOverwriteAlert = true } else { Task { await model.save() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isDirty)
            }
        }
        .padding()
        .alert("The config file changed on disk", isPresented: $showOverwriteAlert) {
            Button("Overwrite") { Task { await model.save() } }
            Button("Discard my changes") { model.load() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone or something edited the config after this window opened. Overwriting will lose those edits.")
        }
    }

    /// `SettingsModel.save()` validates against a temp file and its error message embeds
    /// that temp file's path (e.g. `/var/folders/.../aerospace-settings-<uuid>.toml`), which
    /// is meaningless to the user. Substitute the real config path instead.
    private func displayableErrorMessage(_ message: String) -> String {
        guard let realPath = model.targetUrl?.path else { return message }
        var result = message
        // Replace every occurrence of the temp validation path with the real config path.
        // The marker "aerospace-settings-" is unique to the temp file name minted in
        // `SettingsModel.save()`; walk outward from it to the surrounding path boundaries.
        while let markerRange = result.range(of: "aerospace-settings-") {
            var start = markerRange.lowerBound
            while start > result.startIndex {
                let prev = result.index(before: start)
                if result[prev].isWhitespace || result[prev] == "\"" || result[prev] == "'" { break }
                start = prev
            }
            guard let tomlRange = result.range(of: ".toml", range: markerRange.upperBound..<result.endIndex) else { break }
            result.replaceSubrange(start ..< tomlRange.upperBound, with: realPath)
        }
        return result
    }
}
