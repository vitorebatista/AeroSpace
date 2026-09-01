/// Which font sketchybar has to be told to draw an icon with. The catalog carries this per icon
/// rather than per item because one item can offer icons from both sets, and the page has to be
/// able to warn about a font the user has not installed before the bar renders a blank glyph.
enum BarIconFont: String, CaseIterable, Sendable {
    case sfSymbols = "sf-symbols"
    case sketchybarAppFont = "sketchybar-app-font"

    /// The family that goes into sketchybar's `icon.font`. Style and size are the generator's.
    var fontFamily: String {
        switch self {
            case .sfSymbols: "SF Pro"
            case .sketchybarAppFont: "sketchybar-app-font"
        }
    }

    /// How to obtain the font, for the warning the page shows when it is missing. SF Pro ships
    /// with macOS, so it never needs one.
    var installHint: String? {
        switch self {
            case .sfSymbols: nil
            case .sketchybarAppFont: "brew install --cask font-sketchybar-app-font"
        }
    }
}

/// One entry of an item's fixed icon choice list.
///
/// The catalog names the icon instead of carrying its glyph: an SF Symbols name for `.sfSymbols`,
/// a `sketchybar-app-font` ligature name for `.sketchybarAppFont`. Resolving a name to the
/// character sketchybar draws needs the font anyway, so the font travels with the name.
struct BarIcon: Equatable, Sendable {
    let name: String
    let displayName: String
    let font: BarIconFont
}

enum BarSettingType: Equatable, Sendable {
    case bool
    case int(min: Int, max: Int)
    case string
    case stringList
    case enumeration([String])
}

/// One key an item accepts in its `[item.settings]` table.
struct BarSettingKey: Equatable, Sendable {
    let key: String
    let displayName: String
    let summary: String
    let type: BarSettingType
    let defaultValue: BarSettingValue
    /// Concrete correct lines, for the keys where the user has to type a structure — a strftime
    /// format, an event list, a colour. A description of a format is not a format.
    let examples: [String]

    /// Whether the user types the value rather than flipping a switch or picking a case. These are
    /// the keys that are useless without an example.
    var isStructural: Bool {
        switch type {
            case .string, .stringList: true
            case .bool, .int, .enumeration: false
        }
    }

    static func bool(_ key: String, _ displayName: String, _ summary: String, default value: Bool) -> Self {
        Self(key: key, displayName: displayName, summary: summary, type: .bool, defaultValue: .bool(value), examples: [])
    }

    static func int(_ key: String, _ displayName: String, _ summary: String, min: Int, max: Int, default value: Int) -> Self {
        Self(key: key, displayName: displayName, summary: summary, type: .int(min: min, max: max), defaultValue: .int(value), examples: [])
    }

    static func string(_ key: String, _ displayName: String, _ summary: String, default value: String, examples: [String]) -> Self {
        Self(key: key, displayName: displayName, summary: summary, type: .string, defaultValue: .string(value), examples: examples)
    }

    static func stringList(_ key: String, _ displayName: String, _ summary: String, default value: [String], examples: [String]) -> Self {
        Self(key: key, displayName: displayName, summary: summary, type: .stringList, defaultValue: .array(value.map { .string($0) }), examples: examples)
    }

    static func choice(_ key: String, _ displayName: String, _ summary: String, cases: [String], default value: String) -> Self {
        Self(key: key, displayName: displayName, summary: summary, type: .enumeration(cases), defaultValue: .string(value), examples: [])
    }
}

/// What has to exist on the machine for an item to produce anything.
enum BarItemRequirement: Equatable, Sendable {
    case aerospaceCli
    case shell
    /// A bundled helper binary that does not ship yet. See `BarCatalogItem.availability`.
    case helperBinary
    case appleScript
    case userScript
}

enum BarItemAvailability: Equatable, Sendable {
    case available
    case unavailable(note: String)
}

enum BarItemGroup: String, CaseIterable, Sendable {
    case aerospace
    case system
    case privileged
    case macos
    case escapeHatch

    var displayName: String {
        switch self {
            case .aerospace: "AeroSpace"
            case .system: "System"
            case .privileged: "Privileged"
            case .macos: "macOS"
            case .escapeHatch: "Escape hatch"
        }
    }
}

struct BarCatalogItem: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let summary: String
    let group: BarItemGroup
    let defaultCluster: BarCluster
    let icons: [BarIcon]
    let settings: [BarSettingKey]
    let requirement: BarItemRequirement

    /// Derived rather than declared, so an item cannot be listed in a state this release cannot
    /// honour: the helper binary the privileged items need lands in a later stage, and until it
    /// does they are shown disabled rather than left out of the picker.
    var availability: BarItemAvailability {
        requirement == .helperBinary
            ? .unavailable(note: "Needs a helper binary that ships in a later release. The item is listed so its place in the bar is known, but it cannot be added yet.")
            : .available
    }

    var isAvailable: Bool { availability == .available }

    func setting(_ key: String) -> BarSettingKey? { settings.first { $0.key == key } }
}

/// The fixed, compiled-in table of items a bar can be built from, versioned with the generator.
///
/// `bar.toml` names an entry by `id` and every generated sketchybar item name derives from it, so
/// an id is a stable identifier and never a label: renaming one breaks users' files, renaming a
/// `displayName` does not.
enum BarCatalog {
    /// Generated item names are namespaced, so a leftover item from the user's previous config can
    /// never collide with a generated one and a live `--remove` can never delete something the app
    /// did not create.
    static let namePrefix = "aerospace."

    static func sketchybarName(for id: String) -> String { namePrefix + id }

    static let items: [BarCatalogItem] = [
        BarCatalogItem(
            id: "workspaces",
            displayName: "Workspaces",
            summary: "The workspace strip, highlighting the focused workspace.",
            group: .aerospace,
            defaultCluster: .left,
            icons: [
                BarIcon(name: "square.grid.2x2", displayName: "Grid", font: .sfSymbols),
                BarIcon(name: "circle.grid.2x2", displayName: "Dots", font: .sfSymbols),
                BarIcon(name: "rectangle.3.group", displayName: "Panels", font: .sfSymbols),
            ],
            settings: [
                .bool("show-app-icons", "Show app icons", "Draw an icon per application open in the workspace. Needs the sketchybar-app-font.", default: true),
                .bool("per-monitor", "Per monitor", "Show only the workspaces assigned to the display the bar is on.", default: true),
                .bool("hide-empty", "Hide empty workspaces", "Omit workspaces with no windows unless they are focused.", default: true),
                .string(
                    "focused-color",
                    "Focused colour",
                    "The colour of the focused workspace, as 0xAARRGGBB.",
                    default: "0xff717ebb",
                    examples: [
                        "0xff717ebb  the default accent",
                        "0xffff7f00  opaque orange",
                        "0x80ffffff  white at 50% alpha",
                    ],
                ),
            ],
            requirement: .aerospaceCli,
        ),
        BarCatalogItem(
            id: "front-app",
            displayName: "Front app",
            summary: "The name of the focused application.",
            group: .aerospace,
            defaultCluster: .center,
            icons: [
                BarIcon(name: "macwindow", displayName: "Window", font: .sfSymbols),
                BarIcon(name: "app.badge", displayName: "App badge", font: .sfSymbols),
                BarIcon(name: "app.icon", displayName: "The app's own icon", font: .sketchybarAppFont),
            ],
            settings: [
                .bool("show-icon", "Show icon", "Draw the icon beside the application name.", default: true),
                .int("max-length", "Maximum length", "Truncate the name past this many characters. Zero leaves it untruncated.", min: 0, max: 120, default: 0),
            ],
            requirement: .aerospaceCli,
        ),
        BarCatalogItem(
            id: "mode",
            displayName: "Binding mode",
            summary: "The active binding mode, for configs that use more than one.",
            group: .aerospace,
            defaultCluster: .left,
            icons: [
                BarIcon(name: "keyboard", displayName: "Keyboard", font: .sfSymbols),
                BarIcon(name: "command", displayName: "Command", font: .sfSymbols),
            ],
            settings: [
                .bool("hide-in-main", "Hide in main mode", "Show the item only while a mode other than `main` is active.", default: true),
                .string(
                    "label-format",
                    "Label format",
                    "How the mode name is drawn. `%s` is replaced by the mode name.",
                    default: "[%s]",
                    examples: [
                        "[%s]  [service]",
                        "%s  service",
                        "-- %s --  -- service --",
                    ],
                ),
            ],
            requirement: .aerospaceCli,
        ),
        BarCatalogItem(
            id: "floats",
            displayName: "Floating windows",
            summary: "Appears while the focused workspace holds floating windows; clicking focuses the next one. macOS z-orders windows per application, so a float sinks behind the next focused app and this is the way back to it.",
            group: .aerospace,
            defaultCluster: .left,
            icons: [
                BarIcon(name: "macwindow.on.rectangle", displayName: "Floating window", font: .sfSymbols),
                BarIcon(name: "rectangle.on.rectangle", displayName: "Stacked", font: .sfSymbols),
            ],
            settings: [
                .bool("show-count", "Show count", "Draw how many floating windows the workspace holds.", default: true),
                .bool("hide-when-empty", "Hide when empty", "Remove the item while the focused workspace has no floating windows.", default: true),
            ],
            requirement: .aerospaceCli,
        ),
        BarCatalogItem(
            id: "battery",
            displayName: "Battery",
            summary: "Charge level and charging state.",
            group: .system,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "battery.100", displayName: "Battery", font: .sfSymbols),
                BarIcon(name: "bolt.fill", displayName: "Bolt", font: .sfSymbols),
            ],
            settings: [
                .bool("show-percentage", "Show percentage", "Draw the charge as a number beside the icon.", default: true),
                .int("warn-below", "Warn below", "Percentage under which the item switches to its warning colour.", min: 0, max: 100, default: 20),
                .int("update-freq", "Update every", "Seconds between refreshes.", min: 1, max: 3600, default: 120),
            ],
            requirement: .shell,
        ),
        BarCatalogItem(
            id: "clock",
            displayName: "Clock",
            summary: "The date and time, in a format you choose.",
            group: .system,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "clock", displayName: "Clock", font: .sfSymbols),
                BarIcon(name: "calendar", displayName: "Calendar", font: .sfSymbols),
            ],
            settings: [
                .string(
                    "format",
                    "Format",
                    "A strftime format string, passed to `date`.",
                    default: "%a %d %b %H:%M",
                    examples: [
                        "%a %d %b %H:%M  Mon 31 Aug 22:15",
                        "%H:%M  22:15",
                        "%Y-%m-%d %H:%M:%S  2026-08-31 22:15:04",
                    ],
                ),
                .int("update-freq", "Update every", "Seconds between refreshes. Use 1 when the format shows seconds.", min: 1, max: 3600, default: 30),
            ],
            requirement: .shell,
        ),
        BarCatalogItem(
            id: "cpu",
            displayName: "CPU",
            summary: "Processor load across all cores.",
            group: .system,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "cpu", displayName: "CPU", font: .sfSymbols),
                BarIcon(name: "chart.bar", displayName: "Chart", font: .sfSymbols),
            ],
            settings: [
                .bool("show-graph", "Show graph", "Draw a rolling graph behind the label.", default: false),
                .int("warn-above", "Warn above", "Load percentage over which the item switches to its warning colour.", min: 0, max: 100, default: 85),
                .int("update-freq", "Update every", "Seconds between refreshes.", min: 1, max: 3600, default: 5),
            ],
            requirement: .shell,
        ),
        BarCatalogItem(
            id: "network",
            displayName: "Network",
            summary: "The active connection, and optionally its throughput.",
            group: .system,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "wifi", displayName: "Wi-Fi", font: .sfSymbols),
                BarIcon(name: "network", displayName: "Globe", font: .sfSymbols),
                BarIcon(name: "arrow.up.arrow.down", displayName: "Throughput", font: .sfSymbols),
            ],
            settings: [
                .bool("show-ssid", "Show network name", "Draw the SSID of the joined Wi-Fi network.", default: true),
                .bool("show-throughput", "Show throughput", "Draw upload and download rates.", default: false),
                .int("update-freq", "Update every", "Seconds between refreshes.", min: 1, max: 3600, default: 5),
            ],
            requirement: .shell,
        ),
        BarCatalogItem(
            id: "weather",
            displayName: "Weather",
            summary: "Current conditions for one location.",
            group: .system,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "cloud.sun", displayName: "Cloud and sun", font: .sfSymbols),
                BarIcon(name: "thermometer.medium", displayName: "Thermometer", font: .sfSymbols),
            ],
            settings: [
                .string(
                    "location",
                    "Location",
                    "The place to report on. `auto` resolves it from the current time zone.",
                    default: "auto",
                    examples: [
                        "auto  resolve from the current time zone",
                        "Lisbon,PT  city and ISO country code",
                        "38.72,-9.14  latitude and longitude",
                    ],
                ),
                .choice("units", "Units", "Which unit system the temperature is reported in.", cases: ["metric", "imperial"], default: "metric"),
                .int("update-freq", "Update every", "Seconds between refreshes. Weather services rate-limit, so keep this generous.", min: 60, max: 86400, default: 900),
            ],
            requirement: .shell,
        ),
        BarCatalogItem(
            id: "volume",
            displayName: "Volume",
            summary: "Output volume, with a slider in the popup.",
            group: .privileged,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "speaker.wave.2", displayName: "Speaker", font: .sfSymbols),
                BarIcon(name: "speaker.slash", displayName: "Muted", font: .sfSymbols),
            ],
            settings: [
                .bool("show-percentage", "Show percentage", "Draw the level as a number beside the icon.", default: true),
                .bool("show-slider", "Show slider", "Open a slider when the item is clicked.", default: true),
            ],
            requirement: .helperBinary,
        ),
        BarCatalogItem(
            id: "brightness",
            displayName: "Brightness",
            summary: "Display brightness, over the ordinary hardware range.",
            group: .privileged,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "sun.max", displayName: "Sun", font: .sfSymbols),
                BarIcon(name: "sun.min", displayName: "Dim sun", font: .sfSymbols),
            ],
            settings: [
                .bool("show-percentage", "Show percentage", "Draw the level as a number beside the icon.", default: false),
                .int("step", "Scroll step", "Percentage points a scroll over the item changes brightness by.", min: 1, max: 50, default: 5),
            ],
            requirement: .helperBinary,
        ),
        BarCatalogItem(
            id: "bluetooth",
            displayName: "Bluetooth",
            summary: "Bluetooth power state and connected devices.",
            group: .privileged,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "dot.radiowaves.right", displayName: "Radiowaves", font: .sfSymbols),
                BarIcon(name: "antenna.radiowaves.left.and.right", displayName: "Antenna", font: .sfSymbols),
            ],
            settings: [
                .bool("show-battery", "Show device battery", "Draw the charge of connected devices that report one.", default: true),
                .bool("hide-when-off", "Hide when off", "Remove the item while Bluetooth is powered down.", default: true),
            ],
            requirement: .helperBinary,
        ),
        BarCatalogItem(
            id: "apple-menu",
            displayName: "Apple menu",
            summary: "An Apple logo that opens the Apple menu.",
            group: .macos,
            defaultCluster: .left,
            icons: [
                BarIcon(name: "apple.logo", displayName: "Apple logo", font: .sfSymbols),
            ],
            settings: [
                .bool("show-label", "Show label", "Draw a text label beside the logo.", default: false),
                .choice("click-action", "On click", "What clicking the item opens.", cases: ["apple-menu", "about-this-mac", "system-settings"], default: "apple-menu"),
            ],
            requirement: .appleScript,
        ),
        BarCatalogItem(
            id: "secure-input",
            displayName: "Secure input",
            summary: "Warns while an app holds secure keyboard entry, which blocks every hotkey on the machine.",
            group: .macos,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "lock.shield", displayName: "Shield", font: .sfSymbols),
                BarIcon(name: "lock", displayName: "Lock", font: .sfSymbols),
            ],
            settings: [
                .bool("hide-when-inactive", "Hide when inactive", "Remove the item while no app holds secure input.", default: true),
                .bool("show-process", "Show holding process", "Draw the name of the app holding secure input.", default: true),
            ],
            requirement: .appleScript,
        ),
        BarCatalogItem(
            id: "custom",
            displayName: "Custom script",
            summary: "Runs a script of your own and draws what it prints, so the fixed catalog is not a ceiling.",
            group: .escapeHatch,
            defaultCluster: .right,
            icons: [
                BarIcon(name: "terminal", displayName: "Terminal", font: .sfSymbols),
                BarIcon(name: "gearshape", displayName: "Gear", font: .sfSymbols),
                BarIcon(name: "star", displayName: "Star", font: .sfSymbols),
            ],
            settings: [
                .string(
                    "script",
                    "Script",
                    "Path to an executable script. It is run as the sketchybar item's script.",
                    default: "",
                    examples: [
                        "~/.config/sketchybar/plugins/vpn.sh",
                        "/opt/homebrew/bin/my-status --oneline",
                    ],
                ),
                .int("update-freq", "Update every", "Seconds between runs. Zero runs the script only on the events below.", min: 0, max: 86400, default: 60),
                .stringList(
                    "events",
                    "Events",
                    "sketchybar events the item subscribes to, each re-running the script.",
                    default: [],
                    examples: [
                        "front_app_switched  the focused application changed",
                        "space_change  the macOS Space changed",
                        "system_woke  the machine woke from sleep",
                        "aerospace_workspace_change  triggered by exec-on-workspace-change",
                    ],
                ),
            ],
            requirement: .userScript,
        ),
    ]

    static func item(id: String) -> BarCatalogItem? { items.first { $0.id == id } }

    static func items(in group: BarItemGroup) -> [BarCatalogItem] { items.filter { $0.group == group } }
}
