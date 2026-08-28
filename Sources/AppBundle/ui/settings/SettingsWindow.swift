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
            TextEditor(text: Binding(get: { model.wholeFileText }, set: { guard !model.isSaving else { return }; model.wholeFileText = $0; markDirty() }))
                .font(.system(size: 12).monospaced())
        }
        .padding()
    }

    /// The draft binding every section edits through.
    ///
    /// Writes are dropped while a save is in flight: `save()` suspends across the config
    /// reload with this window still live, and finishes with a `load()` that reseeds the
    /// draft from disk — so an edit landing in that gap would be silently thrown away.
    /// Freezing the form (and both footer buttons) for the duration makes that impossible
    /// rather than invisible.
    private var draft: Binding<ConfigTomlWriter.ConfigDraft> {
        Binding(get: { model.draft }, set: { if !model.isSaving { model.draft = $0 } })
    }

    @ViewBuilder
    private func section(for category: SettingsCategory) -> some View {
        switch category {
            case .general: GeneralSection(draft: draft, onEdit: markDirty)
            case .layout: LayoutSection(draft: draft, onEdit: markDirty)
            case .focus: FocusSection(draft: draft, onEdit: markDirty)
            case .windowBorder: WindowBorderSection(draft: draft, onEdit: markDirty)
            case .gaps: GapsSection(draft: draft, loadGeneration: model.loadGeneration, onEdit: markDirty)
            case .workspaces: WorkspacesSection(draft: draft, onEdit: markDirty)
            case .keyMapping: KeyMappingSection(draft: draft, onEdit: markDirty)
            case .exec: ExecSection(draft: draft, onEdit: markDirty)
            case .keybindings:
                SettingsRawSection(
                    title: "Keybindings",
                    help: "Binding modes and their key bindings, as TOML. Each binding maps a key combination to one or more AeroSpace commands.",
                    docsHint: "Tables: [mode.<name>.binding]. Example: alt-h = 'focus left'",
                    text: draft.rawKeybindings,
                    preamble: keybindingsPreamble(preset: model.draft.keyMappingPreset, notationOverrides: model.draft.keyNotationToKeyCode),
                    onEdit: markDirty,
                )
            case .windowRules:
                SettingsRawSection(
                    title: "Window rules",
                    help: "Rules run when a window is first detected. Matchers: app-id, app-id-regex-substring, app-name-regex-substring, window-title-regex-substring, workspace, during-aerospace-startup.",
                    docsHint: "Tables: [[on-window-detected]] with an 'if' matcher and a mandatory 'run'.",
                    text: draft.rawWindowRules,
                    onEdit: markDirty,
                )
            case .callbacks:
                SettingsRawSection(
                    title: "Callbacks",
                    help: "Commands AeroSpace runs on lifecycle events.",
                    docsHint: "Keys: " + ConfigTomlWriter.callbackKeys.joined(separator: ", "),
                    text: draft.rawCallbacks,
                    onEdit: markDirty,
                )
        }
    }

    private func markDirty() {
        guard !model.isSaving else { return }
        model.isDirty = true
        model.status = nil
    }

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
                Button("Revert") { model.revert() }.disabled(!model.isDirty || model.isSaving)
                Button("Save") {
                    if model.externallyModified { showOverwriteAlert = true } else { Task { await model.save() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isDirty || model.isSaving)
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
        //
        // The search resumes past what was just substituted rather than restarting from
        // the beginning: `realPath` is the user's own config path and could itself contain
        // the marker, and re-finding it every pass would spin here forever — on the
        // MainActor, i.e. a hung app.
        var searchFrom = result.startIndex
        while let markerRange = result.range(of: "aerospace-settings-", range: searchFrom ..< result.endIndex) {
            var start = markerRange.lowerBound
            while start > result.startIndex {
                let prev = result.index(before: start)
                if result[prev].isWhitespace || result[prev] == "\"" || result[prev] == "'" { break }
                start = prev
            }
            guard let tomlRange = result.range(of: ".toml", range: markerRange.upperBound ..< result.endIndex) else { break }
            // Mutating invalidates every index into `result`, so carry the resume point
            // across as an offset and recompute it afterwards.
            let resumeOffset = result.distance(from: result.startIndex, to: start) + realPath.count
            result.replaceSubrange(start ..< tomlRange.upperBound, with: realPath)
            searchFrom = result.index(result.startIndex, offsetBy: resumeOffset, limitedBy: result.endIndex) ?? result.endIndex
        }
        return result
    }
}
