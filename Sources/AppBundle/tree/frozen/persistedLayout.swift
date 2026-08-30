import AppKit
import Common
import Foundation

/// Window placement that outlives the AeroSpace process.
///
/// ``closedWindowsCache`` already models "put every window back where it was", but only in memory,
/// so restarting AeroSpace (or recovering from a crash) dropped every window into whatever workspace
/// happened to be active. This writes the same ``FrozenWorld`` to disk on a debounce and replays it
/// once, at startup, after the first refresh session has discovered the live windows.
///
/// Windows are matched back by WindowServer id, which stays valid for as long as the window itself
/// lives — so it survives an AeroSpace restart but not a reboot or an app relaunch. `identities`
/// carries an app-bundle-id + title for each window so those cases can still be matched by name.
private struct PersistedLayout: Codable {
    /// Bumped when the shape below changes, so an old file is discarded rather than misread.
    static let currentVersion = 2
    var version: Int = currentVersion
    let world: FrozenWorld
    let identities: [WindowIdentity]
    /// The workspace that had focus when this was written. Restoring windows without it drops you
    /// on whichever workspace happened to sort first, which is never where you left off.
    let focusedWorkspace: String?
}

private struct WindowIdentity: Codable {
    let windowId: UInt32
    let appBundleId: String
    let title: String
}

private let persistedLayoutUrl: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
    .appendingPathComponent(aeroSpaceAppName, isDirectory: true)
    .appendingPathComponent("window-layout.json", isDirectory: false)

// ponytail: 2s is long enough that a burst of commands writes once, short enough that a crash
// loses at most the last couple of seconds of placement.
private let persistDebounce: Duration = .seconds(2)
@MainActor private var persistTask: Task<Void, Never>? = nil

/// Records the current placement shortly after the layout settles. Called from
/// ``resetClosedWindowsCache``, which already fires on every command and mouse manipulation that can
/// move a window.
@MainActor func scheduleLayoutPersist() {
    guard !isUnitTest, !serverArgs.isReadOnly else { return }
    persistTask?.cancel()
    persistTask = Task { @MainActor in
        // A cancelled sleep throws, which is exactly the "another change arrived, skip this write" path.
        guard (try? await Task.sleep(for: persistDebounce)) != nil else { return }
        await persistLayoutNow()
    }
}

@MainActor private func persistLayoutNow() async {
    guard let url = persistedLayoutUrl else { return }
    let allWs = Workspace.all
    let windowIds = allWs.flatMap { collectAllWindowIds(workspace: $0) }.toSet()
    let world = FrozenWorld(
        workspaces: allWs.map { FrozenWorkspace($0) },
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: windowIds,
    )
    var identities: [WindowIdentity] = []
    for id in windowIds.sorted() {
        guard let window = Window.get(byId: id), let bundleId = window.app.rawAppBundleId else { continue }
        guard let title = try? await window.title else { continue }
        identities.append(WindowIdentity(windowId: id, appBundleId: bundleId, title: title))
    }
    let payload = PersistedLayout(world: world, identities: identities, focusedWorkspace: focus.workspace.name)
    // Best effort throughout: a state file that can't be written must never take the WM down.
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)
    } catch {
        // Nothing actionable for the user - the next change tries again.
    }
}

/// Replays the persisted placement. Call once at startup, after windows have been discovered.
@MainActor func restorePersistedLayout() async throws {
    guard !isUnitTest, !serverArgs.isReadOnly else { return }
    guard let url = persistedLayoutUrl, let data = try? Data(contentsOf: url) else { return }
    guard let persisted = try? JSONDecoder().decode(PersistedLayout.self, from: data),
          persisted.version == PersistedLayout.currentVersion
    else { return }

    let mapping = await resolveWindows(persisted)
    // Focus is restored even when no window matched: the windows may all be gone, but "the
    // workspace I was on" is still meaningful and is the part a restart most visibly loses.
    if !mapping.isEmpty {
        try await applyFrozenWorld(persisted.world) { mapping[$0.id] }
    }
    if let name = workspaceToFocusAtStartup(persisted: persisted.focusedWorkspace, existing: Workspace.all.map(\.name)) {
        _ = Workspace.get(byName: name).focusWorkspace()
    }
}

/// The workspace to land on at startup, or nil to keep whatever startup already focused.
///
/// A persisted name that no longer exists is ignored rather than recreated: the config may have
/// dropped that workspace between runs, and materializing it would resurrect it as a side effect
/// of a restart.
func workspaceToFocusAtStartup(persisted: String?, existing: [String]) -> String? {
    guard let persisted, existing.contains(persisted) else { return nil }
    return persisted
}

/// Maps each persisted window id onto a live window: same id first, then app-bundle-id + title among
/// the windows no persisted entry has claimed yet.
@MainActor private func resolveWindows(_ persisted: PersistedLayout) async -> [UInt32: Window] {
    var mapping: [UInt32: Window] = [:]
    var claimed: Set<UInt32> = []
    for id in persisted.world.windowIds {
        guard let window = Window.get(byId: id) else { continue }
        mapping[id] = window
        claimed.insert(window.windowId)
    }

    let unresolved = persisted.identities.filter { mapping[$0.windowId] == nil }
    guard !unresolved.isEmpty else { return mapping }

    // Group the still-unclaimed live windows by identity. Several windows of one app can share a
    // title (two empty Brave windows, say); they're interchangeable for placement purposes, so
    // handing them out in order is as good as any other pairing.
    var candidates: [String: [Window]] = [:]
    for window in MacWindow.allWindowsMap.values where !claimed.contains(window.windowId) {
        guard let bundleId = window.app.rawAppBundleId else { continue }
        guard let title = try? await window.title else { continue }
        candidates[identityKey(bundleId, title), default: []].append(window)
    }
    for identity in unresolved {
        let key = identityKey(identity.appBundleId, identity.title)
        guard let window = candidates[key]?.popLast() else { continue }
        mapping[identity.windowId] = window
    }
    return mapping
}

private func identityKey(_ bundleId: String, _ title: String) -> String { bundleId + "\u{0}" + title }
