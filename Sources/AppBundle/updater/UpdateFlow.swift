import AppKit
import Common
import Foundation

/// The whole "Check for Updates…" interaction: check, tell the user, install if they say so.
@MainActor
func runCheckForUpdatesFlow() async {
    NSApp.activate(ignoringOtherApps: true) // agent app: alerts would otherwise open behind everything
    switch await checkForUpdate() {
        case .upToDate(let current):
            informational("You're up to date", "\(aeroSpaceAppName) \(current) is the newest release.")
        case .notApplicable(let reason):
            informational("No update check", reason)
        case .failed(let reason):
            warning("Couldn't check for updates", reason)
        case .updateAvailable(let release):
            if askToInstall(release) { await install(release) }
    }
}

@MainActor
private func askToInstall(_ release: GitHubRelease) -> Bool {
    let alert = NSAlert()
    alert.messageText = "\(aeroSpaceAppName) \(release.version) is available"
    alert.informativeText = """
        You're running \(aeroSpaceAppVersion).

        \(release.notes.firstLines(12))

        Installing replaces the app and relaunches it. Releases are signed with a stable identity, so \
        macOS normally keeps the Accessibility permission. If it does ask again, grant it in System \
        Settings → Privacy & Security → Accessibility.
        """
    alert.addButton(withTitle: "Install and Relaunch")
    alert.addButton(withTitle: "Later")
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
private func install(_ release: GitHubRelease) async {
    do {
        try await downloadAndInstall(release)
    } catch {
        warning("Update failed", "\(error)\n\nYour current installation hasn't been changed.")
        return
    }
    let alert = NSAlert()
    alert.messageText = "\(aeroSpaceAppName) \(release.version) installed"
    alert.informativeText = """
        \(aeroSpaceAppName) will now quit and reopen.

        If macOS asks for Accessibility again on launch, grant it in System Settings → Privacy & Security \
        → Accessibility, and the window manager starts back up.
        """
    alert.addButton(withTitle: "Relaunch")
    _ = alert.runModal()
    relaunchAfterExit()
    terminateApp()
}

@MainActor
private func informational(_ title: String, _ body: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = body
    alert.runModal()
}

@MainActor
private func warning(_ title: String, _ body: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = body
    alert.runModal()
}

extension String {
    /// Release notes are markdown of arbitrary length; an alert is not a document viewer.
    func firstLines(_ limit: Int) -> String {
        let lines = split(separator: "\n", omittingEmptySubsequences: false)
        return lines.count <= limit
            ? trimmingCharacters(in: .whitespacesAndNewlines)
            : lines.prefix(limit).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n…"
    }
}
