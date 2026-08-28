import Common
import Foundation
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Divider()
        if let token: RunSessionGuard = .isServerEnabled {
            // Persistent workspaces first (in config order), then the rest alphabetically.
            let sorted = sortWorkspacesForMenuBar(viewModel.workspaces, persistentWorkspaces: config.persistentWorkspaces)
            let (inUse, available) = partitionWorkspacesForMenuBar(sorted)

            Text("Workspaces:")
            ForEach(inUse, id: \.name) { workspace in
                workspaceButton(workspace, token: token)
            }
            // Empty workspaces go behind a submenu: with 10 configured workspaces and 2 in use, the
            // other 8 are just distance between the pointer and everything below them.
            if !available.isEmpty {
                Menu {
                    ForEach(available, id: \.name) { workspace in
                        workspaceButton(workspace, token: token)
                    }
                } label: {
                    Text("New")
                }
            }
            Divider()
        }
        Menu {
            Button(viewModel.isEnabled ? "Disable" : "Enable") {
                Task {
                    try await runLightSession(.menuBarButton, .forceRun) { () throws in
                        _ = try await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                            .run(.defaultEnv, .emptyStdin)
                    }
                }
            }.keyboardShortcut("E", modifiers: .command)
            openConfigButton()
            reloadConfigButton()
            getExperimentalUISettingsMenu(viewModel: viewModel)
            Menu {
                Button("Check Now") { Task { await runCheckForUpdatesFlow() } }
                Divider()
                Text(shortIdentification)
                Button("Copy Version Info") { identification.copyToClipboard() }
                    .keyboardShortcut("C", modifiers: .command)
            } label: {
                Text("Check for Updates")
            }
        } label: {
            Text("Settings")
        }
        Button("Quit \(aeroSpaceAppName)") {
            terminationHandler.beforeTermination()
            terminateApp()
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        if viewModel.isEnabled {
            MenuBarLabel().environmentObject(viewModel)
        } else {
            Image(systemName: "pause.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

@MainActor @ViewBuilder
func workspaceButton(_ workspace: WorkspaceViewModel, token: RunSessionGuard) -> some View {
    Button {
        Task {
            try await runLightSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
        }
    } label: {
        Toggle(isOn: .constant(workspace.isFocused)) {
            Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
        }
    }
}

/// Splits workspaces into the ones the menu shows directly and the ones hidden behind "New".
///
/// "In use" is deliberately wider than "has windows": a workspace that's on screen, or focused, belongs
/// at the top level even while empty — it's where the user already is, and having it disappear into a
/// submenu the moment its last window closes would be disorienting.
/// Relative order within each group is preserved, so the caller's sort still decides ordering.
func partitionWorkspacesForMenuBar(
    _ workspaces: [WorkspaceViewModel],
) -> (inUse: [WorkspaceViewModel], available: [WorkspaceViewModel]) {
    var inUse: [WorkspaceViewModel] = []
    var available: [WorkspaceViewModel] = []
    for workspace in workspaces {
        switch !workspace.isEffectivelyEmpty || workspace.isVisible || workspace.isFocused {
            case true: inUse.append(workspace)
            case false: available.append(workspace)
        }
    }
    return (inUse, available)
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button("Open config in '\(editor.lastPathComponent)'") {
        let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        switch findCustomConfigUrl() {
            case .file(let url):
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
        }
    }.keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            Task {
                try await runLightSession(.menuBarButton, token) { _ = try await reloadConfig() }
            }
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

/// Orders workspaces for the menu bar: persistent workspaces first (in `persistentWorkspaces`
/// config order), followed by all remaining workspaces sorted alphabetically by name.
/// Pure function extracted from the menu bar view so the ordering is unit-testable.
func sortWorkspacesForMenuBar(_ workspaces: [WorkspaceViewModel], persistentWorkspaces: some Sequence<String>) -> [WorkspaceViewModel] {
    // Build a lookup of persistent workspace name -> position in the config order.
    let persistentOrderIndex: [String: Int] =
        Dictionary(uniqueKeysWithValues: persistentWorkspaces.enumerated().map { ($0.element, $0.offset) })

    return workspaces.sorted { a, b in
        let ia = persistentOrderIndex[a.name]
        let ib = persistentOrderIndex[b.name]

        if let ia, let ib {
            return ia < ib                // both are in persistent list
        } else if ia != nil {
            return true                   // only a is in persistent list
        } else if ib != nil {
            return false                  // only b is in persistent list
        } else {
            return a.name < b.name        // neither is in persistent list
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
