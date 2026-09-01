import OrderedCollections

/// The editable model of `~/.config/aerospace/bar.toml`.
///
/// Deliberately not part of `Config`: the bar description is not window-manager
/// configuration, it has its own `version` integer, and every future catalog item would
/// otherwise be a change to the window manager's config language.
///
/// Every stored property has a default, so a `bar.toml` that omits a key still loads and
/// so a later stage adding a field — `profiles`, stage 3 — is a source-compatible change
/// rather than a break at every construction site.
struct BarDraft: Equatable, Sendable {
    /// The schema version written into new files. Bumped when a change would stop an
    /// older app from reading the document.
    static let currentVersion = 1

    var version: Int = currentVersion
    /// The `[bar]` table.
    var geometry: BarGeometry = BarGeometry()
    /// The `[bar.colors]` table.
    var colors: BarColors = BarColors()
    /// Every `[[item]]`, in document order. Position within a cluster is the order of the
    /// entries sharing that cluster; there is no index field to keep consistent, and a
    /// drag in the UI is a reordering of this array.
    var items: [BarItem] = []
    /// Every `[[profile]]`, in document order. The first one naming a workspace owns it.
    var profiles: [BarProfile] = []
    /// Which profile the bar is showing right now. Focus state, not file state: it is
    /// resolved from the focused workspace, never read from or written to `bar.toml`.
    ///
    /// It lives on the draft so that a profile switch is the same push as an edit — two
    /// drafts differing only in this field diff into exactly the show/hide commands, and
    /// `BarLiveDiff` needs no profile-specific path.
    var activeProfileName: String?

    func items(in cluster: BarCluster) -> [BarItem] { items.filter { $0.cluster == cluster } }
}

/// A named group of workspaces with per-item visibility overrides.
///
/// Items are declared once, globally, in `items`. A profile only lists the exceptions, so
/// a shared item such as the clock is never repeated per profile.
struct BarProfile: Equatable, Sendable {
    var name: String = ""
    /// The workspaces this profile owns. A workspace no profile names belongs to every
    /// profile.
    var workspaces: [String] = []
    /// Item ids this profile draws. Naming an item here makes it opt-in *everywhere*: it is
    /// then hidden in every profile that does not name it. That is what lets one item belong
    /// to one profile without every other profile having to list it under `hide`.
    var show: [String] = []
    /// Item ids this profile hides that would otherwise be drawn.
    var hide: [String] = []
}

struct BarGeometry: Equatable, Sendable {
    var height: Int = 32
    var margin: Int = 8
    var yOffset: Int = 6
    var cornerRadius: Int = 10
    var borderWidth: Int = 1
    var paddingLeft: Int = 1
    var paddingRight: Int = 0
}

/// `0xAARRGGBB` strings, matching sketchybar's own format and the
/// `focused-window-border-color` convention in `~/.aerospace.toml`. Held as written so
/// that a hand-edited spelling survives a save untouched.
struct BarColors: Equatable, Sendable {
    var background: String = "0xb3202020"
    var border: String = "0x35e2e2e3"
    var label: String = "0xffeeeeee"
    var icon: String = "0xffeeeeee"
    var accent: String = "0xff717ebb"
    var popupBackground: String = "0xc02c2e34"
    var popupBorder: String = "0xff7f8490"
}

struct BarItem: Equatable, Sendable {
    /// The catalog entry this item instantiates, e.g. `workspaces` or `clock`.
    var id: String
    var cluster: BarCluster
    /// The `[item.settings]` table. Ordered, and holding values this model does not
    /// interpret, so that a key written by a newer catalog — or by hand — survives a save
    /// by an older app in the position the user put it, instead of being dropped.
    var settings: OrderedDictionary<String, BarSettingValue> = [:]
}

/// A TOML scalar or array, carried through the model uninterpreted. The catalog, not this
/// type, decides which keys an item accepts and what they mean.
enum BarSettingValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([BarSettingValue])

    var toml: String {
        switch self {
            case .bool(let value): TomlValue.of(value)
            case .int(let value): TomlValue.of(value)
            // Swift always renders a finite Double with a decimal point, which is what
            // keeps `2.0` from reading back as an integer.
            case .double(let value): String(value)
            case .string(let value): TomlValue.of(value)
            case .array(let values): TomlValue.array(values.map(\.toml))
        }
    }
}
