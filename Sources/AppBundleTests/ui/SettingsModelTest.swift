@testable import AppBundle
import Common
import XCTest

/// Covers `SettingsModel.rawExecConfig`, the one place the settings window has to recover
/// state the parsed `Config` cannot give back: `Config.execConfig` holds the *expanded*
/// environment, and `parseEnvVariables` has already interpolated every `$VAR`.
///
/// Each case here used to come back wrong from a hand-written lexer over the raw file text,
/// and — this is the point — wrong in a way that still rendered as valid TOML with a valid
/// value, so `save()`'s parse-the-candidate-first safety net could not catch any of them.
@MainActor
final class SettingsModelTest: XCTestCase {
    func testInheritEnvVarsWithATrailingComment() {
        let raw = SettingsModel.rawExecConfig(from: "[exec]\ninherit-env-vars = true  # keep my PATH\n")
        assertEquals(raw.inheritEnvVariables, true)
    }

    func testEnvVarWithATrailingComment() {
        let raw = SettingsModel.rawExecConfig(from: """
            [exec.env-vars]
            PATH = '/opt/homebrew/bin' # my path
            """)
        assertEquals(raw.overriddenVars["PATH"], "/opt/homebrew/bin")
    }

    func testDottedKeyFormIsSeen() {
        // No `[exec]` header at all. Missing this used to leave the draft on the default
        // `true`, after which the writer deleted the dotted key and wrote nothing back.
        let raw = SettingsModel.rawExecConfig(from: "exec.inherit-env-vars = false\n")
        assertEquals(raw.inheritEnvVariables, false)
    }

    func testDottedEnvVarKeyIsSeen() {
        let raw = SettingsModel.rawExecConfig(from: "exec.env-vars.FOO = 'bar'\n")
        assertEquals(raw.overriddenVars["FOO"], "bar")
    }

    func testQuotedEnvVarKeyIsSeenAsOneName() {
        // A dot in a quoted TOML key is part of the environment variable's name, not a
        // nested table. This is the spelling ConfigTomlWriter emits for UI input such as
        // "MY.PATH", so recovering it correctly is required before the user edits [exec].
        let raw = SettingsModel.rawExecConfig(from: "[exec.env-vars]\n'MY.PATH' = 'bin'\n")
        assertEquals(raw.overriddenVars, ["MY.PATH": "bin"])
    }

    func testValuesAreNotInterpolated() {
        // `$VAR` has to come back exactly as written: this value is destined to be written
        // straight back into the user's file, not to be executed.
        let raw = SettingsModel.rawExecConfig(from: "[exec.env-vars]\nPATH = '/my/bin:${PATH}'\n")
        assertEquals(raw.overriddenVars["PATH"], "/my/bin:${PATH}")
    }

    func testEscapesInABasicStringAreResolved() {
        let raw = SettingsModel.rawExecConfig(from: #"""
        [exec.env-vars]
        QUOTED = "a\"b"
        """#)
        assertEquals(raw.overriddenVars["QUOTED"], #"a"b"#)
    }

    func testDefaultsWhenThereIsNoExecTable() {
        let raw = SettingsModel.rawExecConfig(from: "start-at-login = true\n")
        assertEquals(raw.inheritEnvVariables, true)
        assertEquals(raw.overriddenVars, [:])
    }

    func testUnparseableConfigFallsBackToDefaults() {
        let raw = SettingsModel.rawExecConfig(from: "this is not toml [[[\n")
        assertEquals(raw.inheritEnvVariables, true)
        assertEquals(raw.overriddenVars, [:])
    }
}
