/// A named palette for the two surfaces AeroSpace-edge paints: the bar and the focused
/// window's border.
///
/// The border is part of the theme rather than a separate choice because a bar in one palette
/// and a border in another is the state nobody picks on purpose, and it is the state a user
/// lands in every time they change one and forget the other.
struct BarTheme: Equatable, Identifiable, Sendable {
    let name: String
    let colors: BarColors
    /// What `focused-window-border-color` in `~/.aerospace-edge.toml` becomes. The one key of
    /// a theme that is not in `bar.toml`.
    let windowBorderColor: String

    var id: String { name }
}

/// The compiled-in themes.
///
/// There is no `theme` key in `bar.toml`. A stored name would go on claiming a theme from the
/// moment the user nudged a single colour, so which theme is in effect is *derived* from the
/// palette and the picker reads "Custom" whenever it matches none.
enum BarThemeCatalog {
    static let themes: [BarTheme] = [
        BarTheme(
            name: "Default",
            // Exactly `BarColors()`, so a file that has never been themed shows this rather
            // than "Custom". `BarThemeCatalogTest` holds the two together.
            colors: BarColors(),
            windowBorderColor: "0xff12B981",
        ),
        BarTheme(
            name: "Tokyo Night",
            colors: BarColors(
                background: "0xb31a1b26",
                border: "0x35414868",
                label: "0xffc0caf5",
                icon: "0xffc0caf5",
                accent: "0xff7aa2f7",
                popupBackground: "0xc024283b",
                popupBorder: "0xff414868",
            ),
            windowBorderColor: "0xff7aa2f7",
        ),
        BarTheme(
            name: "Gruvbox Dark",
            colors: BarColors(
                background: "0xb3282828",
                border: "0x35504945",
                label: "0xffebdbb2",
                icon: "0xffebdbb2",
                accent: "0xfffabd2f",
                popupBackground: "0xc03c3836",
                popupBorder: "0xff504945",
            ),
            windowBorderColor: "0xfffabd2f",
        ),
        BarTheme(
            name: "Nord",
            colors: BarColors(
                background: "0xb32e3440",
                border: "0x354c566a",
                label: "0xffeceff4",
                icon: "0xffeceff4",
                accent: "0xff88c0d0",
                popupBackground: "0xc03b4252",
                popupBorder: "0xff4c566a",
            ),
            windowBorderColor: "0xff88c0d0",
        ),
        BarTheme(
            name: "Catppuccin Mocha",
            colors: BarColors(
                background: "0xb31e1e2e",
                border: "0x3545475a",
                label: "0xffcdd6f4",
                icon: "0xffcdd6f4",
                accent: "0xffcba6f7",
                popupBackground: "0xc0313244",
                popupBorder: "0xff45475a",
            ),
            windowBorderColor: "0xffcba6f7",
        ),
        BarTheme(
            // The one light palette. Its background is nearly opaque on purpose: a light bar
            // at the dark themes' alpha reads as grey over most wallpapers.
            name: "Light",
            colors: BarColors(
                background: "0xe6f5f5f7",
                border: "0x60d2d2d7",
                label: "0xff1d1d1f",
                icon: "0xff1d1d1f",
                accent: "0xff0a84ff",
                popupBackground: "0xf0ffffff",
                popupBorder: "0xffd2d2d7",
            ),
            windowBorderColor: "0xff0a84ff",
        ),
    ]

    /// The theme whose palette these colours are, if any. The bar's own palette decides it —
    /// the window border does not, because it lives in a different file that may not have been
    /// saved yet.
    static func matching(_ colors: BarColors) -> BarTheme? {
        themes.first { $0.colors == colors }
    }

    static func theme(named name: String) -> BarTheme? {
        themes.first { $0.name == name }
    }
}
