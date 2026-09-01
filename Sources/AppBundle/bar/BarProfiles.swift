/// Resolving which items a profile draws.
///
/// Pure, and deliberately apart from both the view and the generator: this is the rule that
/// decides what disappears from the user's bar when they change workspace, and it is the one
/// part of profiles worth testing on its own.
extension BarDraft {
    /// The profile the bar is currently showing, if `activeProfileName` names one. A name
    /// that matches nothing resolves to the no-profile state, which draws everything any
    /// profile would.
    var activeProfile: BarProfile? { profiles.first { $0.name == activeProfileName } }

    /// The profile that owns `workspace`. The first match wins, so a workspace listed twice
    /// belongs to whichever profile is written first — the same document-order rule items
    /// already follow.
    ///
    /// `nil` when no profile names it: a workspace no profile claims belongs to every
    /// profile.
    func profile(forWorkspace workspace: String) -> BarProfile? {
        profiles.first { $0.workspaces.contains(workspace) }
    }

    /// Item ids some profile lists under `show`.
    ///
    /// Naming an item in one profile's `show` is what makes it opt-in: it then appears only
    /// in the profiles that name it. Without that, `show` would be redundant — every item is
    /// drawn unless hidden — and an item wanted on exactly one bar would have to be listed
    /// under `hide` in every other profile.
    var optInItemIds: Set<String> { Set(profiles.flatMap(\.show)) }

    /// Whether the item with this catalog id is drawn while `profile` is active.
    ///
    /// `nil` is the no-profile state, which is not "nothing is drawn": a workspace no profile
    /// names belongs to every profile, so it draws what any profile would.
    func isItemVisible(_ id: String, in profile: BarProfile?) -> Bool {
        guard !profiles.isEmpty else { return true }
        guard let profile else { return profiles.contains { isItemVisible(id, in: $0) } }
        if profile.show.contains(id) { return true }
        return !optInItemIds.contains(id) && !profile.hide.contains(id)
    }

    func isItemVisible(_ id: String) -> Bool { isItemVisible(id, in: activeProfile) }
}

// MARK: - Edits

extension BarDraft {
    mutating func addProfile() {
        var name = "Profile"
        var suffix = 2
        while profiles.contains(where: { $0.name == name }) {
            name = "Profile \(suffix)"
            suffix += 1
        }
        profiles.append(BarProfile(name: name))
    }

    /// Sets whether one profile draws an item.
    ///
    /// The toggle writes `hide` for an item that is drawn by default and `show` for one that
    /// is opt-in, so the file keeps listing only the exceptions. Turning off the last profile
    /// that showed an opt-in item stops it being opt-in, and it goes back to being drawn
    /// everywhere — the rule above, seen from the other side.
    mutating func setItemVisible(_ id: String, inProfileAt index: Int, _ visible: Bool) {
        guard profiles.indices.contains(index) else { return }
        profiles[index].show.removeAll { $0 == id }
        profiles[index].hide.removeAll { $0 == id }
        if visible {
            if optInItemIds.contains(id) { profiles[index].show.append(id) }
        } else if !optInItemIds.contains(id) {
            profiles[index].hide.append(id)
        }
    }
}
