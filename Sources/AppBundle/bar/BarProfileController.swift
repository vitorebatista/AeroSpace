import Foundation

/// Switches the bar's profile when focus crosses into a workspace another profile owns.
///
/// The generated config carries no profile logic and no dispatcher script. AeroSpace-edge
/// already knows which workspace is focused, so it pushes the answer instead of making a
/// shell script infer it: a Lua config has to subscribe to workspace events and hold its own
/// notion of the active profile, and here both the inference and the state machine disappear.
///
/// The push itself is `BarBackend.applyLive` between two drafts that differ only in
/// `activeProfileName`, so a profile switch and a drag in the Settings window are the same
/// diff through the same plan. There is no second path for the bar to drift along.
@MainActor
final class BarProfileController {
    static let shared = BarProfileController()

    private let configUrl: URL
    private let backend: any BarBackend
    private let textReader: (URL) -> String?
    private let modificationDate: (URL) -> Date?

    private var draft = BarDraft()
    /// The `bar.toml` mtime `draft` was read at. A save from the Settings window rewrites the
    /// file and reloads sketchybar, so a changed mtime means both the profiles and the bar on
    /// screen are new — re-read, and push from the no-profile baseline a fresh reload leaves.
    private var loadedAt: Date?
    private var hasLoaded = false
    /// The profile the bar is showing. `nil` is the no-profile state, which is what a
    /// generated config renders, so it is also the right baseline after a reload.
    private var showing: String?
    /// Forces the next push even where the profile has not changed.
    private var needsPush = true
    private var pushTask: Task<Void, Never>?

    init(
        configUrl: URL = BarSettingsModel.defaultConfigUrl,
        backend: any BarBackend = SketchybarBackend(),
        textReader: @escaping (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) },
        modificationDate: @escaping (URL) -> Date? = {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        },
    ) {
        self.configUrl = configUrl
        self.backend = backend
        self.textReader = textReader
        self.modificationDate = modificationDate
    }

    /// Something other than this controller moved the bar — a Settings save, a manual reload,
    /// a discarded live preview. The state it is in is no longer known, so the next workspace
    /// change re-pushes from scratch rather than diffing against a stale baseline.
    func invalidate() {
        showing = nil
        needsPush = true
    }

    /// Called on every focused-workspace change. Cheap and silent in the overwhelmingly common
    /// case: no `bar.toml`, no profiles, or a workspace the active profile already owns.
    func workspaceDidChange(to workspace: String) {
        reloadIfChanged()
        guard !draft.profiles.isEmpty, backend.isAvailable else { return }
        let target = draft.profile(forWorkspace: workspace)?.name
        guard needsPush || target != showing else { return }
        let inFlight = pushTask
        pushTask = Task { [weak self] in
            // Serialised: a second workspace change arriving mid-push has to diff from where
            // that push left the bar, not from where it started.
            await inFlight?.value
            await self?.push(to: target)
        }
    }

    /// Awaits the in-flight push. Only the tests need it — nothing in the app waits on the bar.
    func flushPush() async { await pushTask?.value }

    private func push(to target: String?) async {
        // Re-checked here rather than only at the call site: the push this one queued behind
        // may already have put the bar where this one was going.
        guard needsPush || target != showing else { return }
        var previous = draft
        previous.activeProfileName = showing
        var next = draft
        next.activeProfileName = target
        let backend = self.backend
        do {
            // Off the MainActor for the same reason the Settings preview is: the push spawns a
            // sketchybar process, and a workspace switch must not wait on one.
            try await Task.detached { try backend.applyLive(from: previous, to: next) }.value
            showing = target
            needsPush = false
        } catch {
            // The bar is now in a state matching neither side, so the baseline is deliberately
            // left where it was and `needsPush` stands: the next change re-pushes in full.
        }
    }

    private func reloadIfChanged() {
        let date = modificationDate(configUrl)
        guard !hasLoaded || date != loadedAt else { return }
        hasLoaded = true
        loadedAt = date
        // A file that stopped parsing keeps the last good profiles rather than silently
        // dropping every override: the Settings page is where a parse error gets reported.
        if case .success(let loaded) = BarTomlDocument(textReader(configUrl) ?? "").draft() { draft = loaded }
        invalidate()
    }
}
