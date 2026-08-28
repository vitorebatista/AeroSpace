import AppKit
import Common

/// App ids of other AeroSpace builds that manage windows. Two of them running at once means two window
/// managers moving the same windows and racing for the same hotkeys, so AeroSpace-edge refuses to start
/// while one of them is up.
///
/// Deliberately a fixed list of *AeroSpace* builds rather than "any tiling window manager": those are the
/// ones that share this app's config, keybindings and window-management model, and the ones a user is
/// realistically switching between. yabai/Amethyst users know what they're doing.
let conflictingAeroSpaceAppIds: [String] = [
    "bobko.aerospace", // upstream AeroSpace
    "bobko.aerospace.debug", // upstream AeroSpace, debug build
]

/// The decidable part of the check, kept free of AppKit so it can be tested.
/// Our own app id is never a conflict — a second instance of the same bundle is macOS's problem, not ours.
func conflictingAppIds(among runningAppIds: [String]) -> [String] {
    runningAppIds.filter { $0 != aeroSpaceAppId && conflictingAeroSpaceAppIds.contains($0) }
}

/// Blocks startup while another AeroSpace is running: alerts, offers to quit it, and re-checks until it's
/// gone or the user quits us instead. Returns only once nothing conflicting is left.
@MainActor
func checkNoConflictingAeroSpaceIsRunning() async {
    if serverArgs.isReadOnly { return } // --read-only doesn't manage windows, so it can coexist
    while true {
        let conflicting = runningConflictingApps()
        if conflicting.isEmpty { return }
        // The app is an agent (LSUIElement), so it isn't frontmost and the alert would open behind
        // whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        switch presentConflictAlert(conflicting) {
            case .alertFirstButtonReturn:
                for app in conflicting { app.terminate() }
                await waitForTermination(of: conflicting)
            // "Quit" (or the alert being dismissed any other way) means the user wants to keep the app
            // that's already running.
            default: terminateApp()
        }
    }
}

@MainActor
private func runningConflictingApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { app in
        guard let id = app.bundleIdentifier else { return false }
        return !conflictingAppIds(among: [id]).isEmpty
    }
}

@MainActor
private func presentConflictAlert(_ apps: [NSRunningApplication]) -> NSApplication.ModalResponse {
    let otherName = apps.compactMap(\.localizedName).first ?? "AeroSpace"
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "\(otherName) is already running"
    alert.informativeText = """
        \(aeroSpaceAppName) and \(otherName) are both tiling window managers. Running them at the same \
        time means two window managers moving the same windows and competing for the same keyboard \
        shortcuts, so only one can run.

        Quit \(otherName) to continue, or quit \(aeroSpaceAppName) and keep using the one already running.
        """
    alert.addButton(withTitle: "Quit \(otherName) and Continue")
    alert.addButton(withTitle: "Quit \(aeroSpaceAppName)")
    return alert.runModal()
}

/// `terminate()` is a request, not an order — the other app may take a moment, or refuse (an unsaved
/// dialog, a hung process). Give it a few seconds; the caller re-checks and re-alerts if it's still there.
@MainActor
private func waitForTermination(of apps: [NSRunningApplication]) async {
    for _ in 0 ..< 50 {
        if apps.allSatisfy(\.isTerminated) { return }
        try? await Task.sleep(for: .milliseconds(100))
    }
}
