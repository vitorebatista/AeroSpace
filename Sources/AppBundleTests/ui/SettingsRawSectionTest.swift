@testable import AppBundle
import Common
import XCTest

/// Covers the pure parse-feedback logic behind the settings window's three raw-TOML
/// panes (Keybindings, Window rules, Callbacks).
///
/// This is the fix for a real defect: the Keybindings pane's text only ever contains
/// `[mode.*]` tables — never `[key-mapping]` — so parsing it in isolation resolves key
/// notations against the default preset with no custom overrides. The three preset maps
/// in `keysMap.swift` all share the same notation-string set (only the physical key
/// differs), so a plain dvorak/colemak notation is unaffected either way — but a custom
/// notation from `[key-mapping.key-notation-to-key-code]` is not in *any* preset's map,
/// so a binding that uses one is falsely rejected unless the override table comes along
/// with it. `keybindingsPreamble` supplies both; these tests pin that a binding using a
/// real custom notation is accepted once the matching override is in the preamble, and
/// that genuine garbage still fails.
@MainActor
final class SettingsRawSectionTest: XCTestCase {
    func testCustomNotationWithoutPreambleFalselyFailsToParse() {
        // "zz" isn't a notation any preset knows about on its own.
        let text = "[mode.main.binding]\nalt-zz = 'focus left'\n"
        assertFail(parseRawSectionFragment(preamble: "", text: text))
    }

    func testCustomNotationWithMatchingOverrideInPreambleParses() {
        let text = "[mode.main.binding]\nalt-zz = 'focus left'\n"
        let preamble = keybindingsPreamble(preset: .qwerty, notationOverrides: ["zz": "a"])
        assertSucc(parseRawSectionFragment(preamble: preamble, text: text))
    }

    func testGenuineGarbageStillFailsWithPreamble() {
        let text = "[mode.main.binding]\nalt-h = 'no-such-command'\n"
        let preamble = keybindingsPreamble(preset: .dvorak, notationOverrides: [:])
        assertFail(parseRawSectionFragment(preamble: preamble, text: text))
    }

    func testWindowRulesFragmentIsSelfContained() {
        let text = """
            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            run = 'move-node-to-workspace F'
            """
        assertSucc(parseRawSectionFragment(preamble: "", text: text))
    }

    func testCallbacksFragmentIsSelfContained() {
        let text = "after-startup-command = 'workspace 1'\n"
        assertSucc(parseRawSectionFragment(preamble: "", text: text))
    }

    func testKeybindingsPreambleSpellsPresetAsTomlLiteralString() {
        assertEquals(keybindingsPreamble(preset: .colemak, notationOverrides: [:]), "[key-mapping]\npreset = 'colemak'\n")
    }

    func testKeybindingsPreambleIncludesNotationOverridesTable() {
        assertEquals(
            keybindingsPreamble(preset: .qwerty, notationOverrides: ["zz": "a"]),
            "[key-mapping]\npreset = 'qwerty'\n\n[key-mapping.key-notation-to-key-code]\nzz = 'a'\n",
        )
    }

    func testKeybindingsPreambleQuotesANotationThatIsNotABareTomlKey() {
        // A dot is valid in AeroSpace notation (only whitespace and `-` are forbidden),
        // but TOML would otherwise parse it as a nested key and produce a false error in
        // the Keybindings pane. The saved config already quotes this case; the preamble
        // must do the same.
        let text = "[mode.main.binding]\\nalt-custom.key = 'focus left'\\n"
        let preamble = keybindingsPreamble(preset: .qwerty, notationOverrides: ["custom.key": "a"])
        assertEquals(preamble, "[key-mapping]\\npreset = 'qwerty'\\n\\n[key-mapping.key-notation-to-key-code]\\n'custom.key' = 'a'\\n")
        assertSucc(parseRawSectionFragment(preamble: preamble, text: text))
    }
}
