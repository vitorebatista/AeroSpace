import AppBundle
import AppIntents

// App Intents live in the app target (not in the AppBundle library) so that Xcode's App Intents
// metadata processor can see them directly. Extracting metadata across a Swift package boundary
// additionally requires AppIntentsPackage conformance and is markedly more fragile.
//
// Everything here is a thin shell over `runAeroSpaceCommandFromAppIntent`. Keep it that way: the
// command layer is the single source of truth, and these types exist only to describe it to
// Shortcuts, Spotlight and Focus filters.

enum AeroSpaceIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case commandFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
            case .commandFailed(let message): "\(message)"
        }
    }
}

/// Offers the currently existing workspaces as autocomplete in the Shortcuts and Focus filter UI.
struct WorkspaceOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        await appIntentWorkspaceSuggestions()
    }
}

/// The escape hatch: runs any command exactly as the CLI would.
/// Every command the CLI gains is automatically available here, with no work.
struct RunAeroSpaceCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Command"
    // periphery:ignore - satisfies the AppIntent requirement, which has a default impl
    static let description = IntentDescription(
        "Runs any AeroSpace command, using the same syntax as the command line. For example: 'workspace 3', 'layout tiles', 'move-node-to-workspace 2'.",
        categoryName: "Window Management",
    )
    // Agent app with no main window - bringing it to the front would only steal focus from the
    // window the user is trying to manage.
    static let openAppWhenRun = false

    @Parameter(title: "Command", default: "workspace 1")
    var command: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        switch await runAeroSpaceCommandFromAppIntent(command) {
            case .success(let stdout): return .result(value: stdout)
            case .failure(let message): throw AeroSpaceIntentError.commandFailed(message)
        }
    }
}

/// The common case, spelled out so it's discoverable in Shortcuts and phrasable in Spotlight
/// without the user having to know the command syntax.
struct FocusWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Focus Workspace"
    // periphery:ignore - satisfies the AppIntent requirement, which has a default impl
    static let description = IntentDescription(
        "Switches to the given AeroSpace workspace.",
        categoryName: "Window Management",
    )
    static let openAppWhenRun = false

    @Parameter(title: "Workspace", optionsProvider: WorkspaceOptionsProvider())
    var workspace: String

    static var parameterSummary: some ParameterSummary {
        Summary("Focus workspace \(\.$workspace)")
    }

    func perform() async throws -> some IntentResult {
        switch await runAeroSpaceCommandFromAppIntent("workspace \(workspace)") {
            case .success: return .result()
            case .failure(let message): throw AeroSpaceIntentError.commandFailed(message)
        }
    }
}

/// Ties a workspace to a macOS Focus mode: turning on "Work" switches to the workspace you picked,
/// and macOS restores the previous one when the Focus ends.
///
/// This is the one integration the rest of the category can't offer - Focus filters are only
/// reachable through App Intents, so a WM driven purely by a hotkey daemon has no way in.
struct WorkspaceFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Switch Workspace"
    // periphery:ignore - satisfies the AppIntent requirement, which has a default impl
    static let description = IntentDescription(
        "Switches to a chosen AeroSpace workspace when this Focus turns on.",
    )

    @Parameter(title: "Workspace", optionsProvider: WorkspaceOptionsProvider())
    var workspace: String?

    var displayRepresentation: DisplayRepresentation {
        guard let workspace else {
            return DisplayRepresentation(title: "No workspace")
        }
        return DisplayRepresentation(title: "Workspace \(workspace)")
    }

    func perform() async throws -> some IntentResult {
        guard let workspace else { return .result() }
        // A Focus filter firing is not a user-facing command invocation: if the workspace was
        // renamed or removed since the filter was configured, silently do nothing rather than
        // pushing a system error at someone who merely started their workday.
        _ = await runAeroSpaceCommandFromAppIntent("workspace \(workspace)")
        return .result()
    }
}

struct AeroSpaceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FocusWorkspaceIntent(),
            phrases: [
                "Focus \(.applicationName) workspace",
                "Switch \(.applicationName) workspace",
            ],
        )
        AppShortcut(
            intent: RunAeroSpaceCommandIntent(),
            phrases: [
                "Run \(.applicationName) command",
            ],
        )
    }
}
