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
    /// The workspace that had focus when this was written. ``focusedWorkspaceDefaultsKey`` holds a
    /// fresher copy of the same thing and wins at startup; this field survives as the fallback for
    /// the first launch after upgrading, when the defaults key does not exist yet.
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
/// Where the focused workspace is remembered, separately from the layout snapshot below.
///
/// The snapshot is debounced, so quitting right after a workspace switch — or crashing inside
/// that window — loses the switch. A single string is cheap enough to write eagerly, so focus
/// gets its own store and is never more than one switch stale.
let focusedWorkspaceDefaultsKey = "last-focused-workspace"

@MainActor func storedFocusedWorkspace() -> String? {
    UserDefaults.standard.string(forKey: focusedWorkspaceDefaultsKey)
}

@MainActor func storeFocusedWorkspace(_ name: String) {
    UserDefaults.standard.setValue(name, forKey: focusedWorkspaceDefaultsKey)
    // Flush now rather than at the next checkpoint: the whole point is to survive an immediate quit.
    UserDefaults.standard.synchronize()
}

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
///
/// ``storedFocusedWorkspace()`` has to be read by the caller *before* the first refresh session and
/// passed in as `focusedWorkspaceAtLaunch`: startup and this function both focus workspaces, and
/// both writes land on the same key, so reading it any later reads back whatever startup picked
/// rather than where the user left off.
@MainActor func restorePersistedLayout(focusedWorkspaceAtLaunch: String?) async throws {
    guard !isUnitTest, !serverArgs.isReadOnly else { return }
    let decoded = persistedLayoutUrl
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(PersistedLayout.self, from: $0) }
    // A missing, unreadable or older-shaped file only costs the window replay. Focus restore below
    // still runs off the remembered name — which is the half a version bump must not throw away.
    let persisted = decoded?.version == PersistedLayout.currentVersion ? decoded : nil

    if let persisted {
        let mapping = await resolveWindows(persisted)
        // Focus is restored even when no window matched: the windows may all be gone, but "the
        // workspace I was on" is still meaningful and is the part a restart most visibly loses.
        if !mapping.isEmpty {
            try await applyFrozenWorld(persisted.world) { mapping[$0.id] }
        }
    }
    if let name = workspaceToFocusAtStartup(
        remembered: focusedWorkspaceAtLaunch,
        persisted: persisted?.focusedWorkspace,
        existing: Workspace.all.map(\.name) + Array(workspaceNamesMentionedIn(config)),
    ) {
        _ = Workspace.get(byName: name).focusWorkspace()
    }
}

/// The workspace to land on at startup, or nil to keep whatever startup already focused.
///
/// `remembered` outranks `persisted` because it is written on every workspace switch while the
/// layout snapshot is debounced, so it is never the staler of the two.
///
/// `existing` is every workspace the config can account for — live ones plus the ones named only
/// by a binding, which on `config-version = 2` are not objects until first visited. A name outside
/// that set is ignored rather than recreated: the config really has dropped that workspace between
/// runs, and materializing it would resurrect it as a side effect of a restart.
func workspaceToFocusAtStartup(remembered: String? = nil, persisted: String?, existing: [String]) -> String? {
    [remembered, persisted].compactMap { $0 }.first { existing.contains($0) }
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
