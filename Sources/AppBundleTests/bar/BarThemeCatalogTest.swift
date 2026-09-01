@testable import AppBundle
import XCTest

final class BarThemeCatalogTest: XCTestCase {
    /// Without this a fresh `bar.toml` would read "Custom", which says the user chose
    /// something when they chose nothing.
    func testDefaultThemeIsExactlyTheModelsDefaults() {
        assertEquals(BarThemeCatalog.theme(named: "Default")?.colors, BarColors())
        assertEquals(BarThemeCatalog.matching(BarColors())?.name, "Default")
    }

    func testEveryThemeIsNamedOnceAndRoundTripsThroughTheMatcher() {
        assertEquals(Set(BarThemeCatalog.themes.map(\.name)).count, BarThemeCatalog.themes.count)
        for theme in BarThemeCatalog.themes {
            assertEquals(BarThemeCatalog.matching(theme.colors)?.name, theme.name)
            assertEquals(BarThemeCatalog.theme(named: theme.name), theme)
        }
    }

    /// Every colour a theme carries is written straight into a file another program parses, so
    /// a typo in one is a bar that does not draw rather than a compile error.
    func testEveryThemeColourIsAWellFormedArgb() {
        for theme in BarThemeCatalog.themes {
            let colors = theme.colors
            let values = [
                colors.background, colors.border, colors.label, colors.icon,
                colors.accent, colors.popupBackground, colors.popupBorder,
                theme.windowBorderColor,
            ]
            for value in values {
                XCTAssertTrue(
                    value.hasPrefix("0x") && value.count == 10
                        && value.dropFirst(2).allSatisfy(\.isHexDigit),
                    "\(theme.name) has \(value), which is not 0xAARRGGBB",
                )
            }
        }
    }

    /// A theme with no palette of its own is a menu entry that does nothing.
    func testNoTwoThemesSharePalette() {
        assertEquals(Set(BarThemeCatalog.themes.map(\.colors.background)).count, BarThemeCatalog.themes.count)
    }

    /// Applying a theme is what the picker does; nothing else about the draft may move.
    func testApplyingAThemeChangesTheColoursAndNothingElse() {
        var draft = BarDraft()
        draft.items = [BarItem(id: "clock", cluster: .right)]
        draft.geometry.height = 44
        var themed = draft
        themed.colors = BarThemeCatalog.theme(named: "Nord")!.colors

        assertEquals(themed.items, draft.items)
        assertEquals(themed.geometry, draft.geometry)
        assertEquals(BarThemeCatalog.matching(themed.colors)?.name, "Nord")
    }
}
