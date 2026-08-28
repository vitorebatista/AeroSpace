@testable import AppBundle
import Common
import XCTest

@MainActor
final class ConfigTomlWriterTest: XCTestCase {
    /// Applies a draft to an empty document, re-parses the result with the real parser,
    /// and returns the parsed config. Fails the test if the output does not parse.
    private func roundTrip(_ mutate: (inout ConfigTomlWriter.ConfigDraft) -> Void) -> Config {
        var draft = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: TomlBlockDocument(""))
        mutate(&draft)
        var document = TomlBlockDocument("")
        ConfigTomlWriter.apply(draft, to: &document)
        let text = document.render()
        let (parsed, errors) = parseConfig(text)
        assertEquals(errors, [], additionalMsg: "generated config did not parse:\n\(text)")
        return parsed
    }

    func testScalarsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.startAtLogin = true
            draft.autoReloadConfig = true
            draft.automaticallyUnhideMacosHiddenApps = true
            draft.enableNormalizationFlattenContainers = false
            draft.enableNormalizationOppositeOrientationForNestedContainers = false
            draft.enableNormalizationBinaryTree = true
            draft.defaultRootContainerLayout = .accordion
            draft.defaultRootContainerOrientation = .vertical
            draft.accordionPadding = 45
            draft.focusFollowsAppActivation = .smart
            draft.newWindowPreventFlicker = true
            draft.configVersion = 2
        }
        assertEquals(parsed.startAtLogin, true)
        assertEquals(parsed.autoReloadConfig, true)
        assertEquals(parsed.automaticallyUnhideMacosHiddenApps, true)
        assertEquals(parsed.enableNormalizationFlattenContainers, false)
        assertEquals(parsed.enableNormalizationOppositeOrientationForNestedContainers, false)
        assertEquals(parsed.enableNormalizationBinaryTree, true)
        assertEquals(parsed.defaultRootContainerLayout, .accordion)
        assertEquals(parsed.defaultRootContainerOrientation, .vertical)
        assertEquals(parsed.accordionPadding, 45)
        assertEquals(parsed.focusFollowsAppActivation, .smart)
        assertEquals(parsed.newWindowPreventFlicker, true)
        assertEquals(parsed.configVersion, 2)
    }

    func testWindowBorderRoundTrips() {
        let parsed = roundTrip { draft in
            draft.focusedWindowBorder = true
            draft.focusedWindowBorderColor = "0xff123456"
            draft.focusedWindowBorderWidth = 6
            draft.focusedWindowBorderOpacity = 80
            draft.focusedWindowBorderRadius = 12
            draft.focusedWindowBorderInset = 2
        }
        assertEquals(parsed.focusedWindowBorder, true)
        assertEquals(parsed.focusedWindowBorderColor, "0xff123456")
        assertEquals(parsed.focusedWindowBorderWidth, 6)
        assertEquals(parsed.focusedWindowBorderOpacity, 80)
        assertEquals(parsed.focusedWindowBorderRadius, 12)
        assertEquals(parsed.focusedWindowBorderInset, 2)
    }

    func testPersistentWorkspacesRoundTrips() {
        let parsed = roundTrip { draft in draft.persistentWorkspaces = ["1", "web", "it's"] }
        assertEquals(Array(parsed.persistentWorkspaces), ["1", "web", "it's"])
    }

    func testPersistentWorkspacesIsGatedOnConfigVersion() {
        // Negative branch: a genuine config-version <= 1 file — the realistic case, where
        // the key is simply absent and config-version defaults to 1 — with a workspace
        // binding, so the parser itself derives a non-empty `persistentWorkspaces`
        // (parseConfig.swift's config-version <= 1 branch) exactly the way `SettingsModel`
        // will see it at runtime. Without the gate, `apply` would write
        // `persistent-workspaces = [...]` into this v1 file, and the parser rejects that
        // key outright ("This config option is only available since 'config-version = 2'").
        let text = "[mode.main.binding]\nalt-1 = 'workspace 1'\n"
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfig(text)
        assertEquals(errors, [])
        assertEquals(config.configVersion, 1)
        assertEquals(Array(config.persistentWorkspaces), ["1"])

        var draft = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = true // an unrelated edit, the way a real save would make one
        ConfigTomlWriter.apply(draft, to: &document)

        let rendered = document.render()
        assertEquals(rendered.contains("persistent-workspaces"), false, additionalMsg: rendered)
        let (_, reErrors) = parseConfig(rendered)
        assertEquals(reErrors, [], additionalMsg: rendered)

        // The gate's other half: a v1 file that already spells out `persistent-workspaces`
        // (already invalid on its own, since the parser rejects that combination) stays
        // writable rather than being silently dropped by the settings window.
        var alreadyPresentDocument = TomlBlockDocument("persistent-workspaces = ['1']\n")
        var alreadyPresentDraft = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: alreadyPresentDocument)
        alreadyPresentDraft.configVersion = 1
        alreadyPresentDraft.persistentWorkspaces = ["1", "2"]
        ConfigTomlWriter.apply(alreadyPresentDraft, to: &alreadyPresentDocument)
        assertEquals(alreadyPresentDocument.render(), "persistent-workspaces = ['1', '2']\n")
    }

    func testConstantGapsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(inner: .init(vertical: 5, horizontal: 6), outer: .init(left: 1, bottom: 2, top: 3, right: 4))
        }
        assertEquals(parsed.gaps.inner.vertical, .constant(5))
        assertEquals(parsed.gaps.outer.top, .constant(3))
    }

    func testPerMonitorGapsRoundTrip() {
        let pattern = MonitorDescription.pattern("Dell.*")!
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(
                inner: .init(vertical: .constant(5), horizontal: .constant(6)),
                outer: .init(
                    left: .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8),
                    bottom: .constant(2), top: .constant(3),
                    right: .perMonitor([PerMonitorValue(description: pattern, value: 12)], default: 4),
                ),
            )
        }
        assertEquals(parsed.gaps.outer.left, .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8))
        // A monitor *pattern* on the left of a per-monitor entry needs quoting, unlike
        // `main` / `secondary` / a sequence number.
        assertEquals(parsed.gaps.outer.right, .perMonitor([PerMonitorValue(description: pattern, value: 12)], default: 4))
    }

    func testKeyMappingRoundTrips() {
        let parsed = roundTrip { draft in
            draft.keyMappingPreset = .dvorak
            draft.keyNotationToKeyCode = ["q": "quote"]
        }
        // An override wins over the preset (KeyMapping.resolve() is
        // getKeysPreset(preset) + rawKeyNotationToKeyCode).
        assertEquals(parsed.keyMapping.resolve()["q"], keyNotationToKeyCode["quote"])
        // The preset itself round-trips too — 's' differs between qwerty and dvorak.
        assertEquals(parsed.keyMapping.resolve()["s"], getKeysPreset(.dvorak)["s"])
    }

    func testExecRoundTrips() {
        let parsed = roundTrip { draft in
            draft.inheritEnvVars = false
            draft.envVars = ["MY_VAR": "hello"]
        }
        assertEquals(parsed.execConfig.envVariables["MY_VAR"], "hello")
        assertEquals(parsed.execConfig.envVariables["AEROSPACE_INHERITED_TEST_ENV"], nil)
    }

    func testWorkspaceToMonitorAssignmentRoundTrips() {
        let pattern = MonitorDescription.pattern("Dell.*")!
        let parsed = roundTrip { draft in
            draft.workspaceToMonitorForceAssignment = [
                "1": [.main],
                "2": [.secondary, .sequenceNumber(3)],
                "3": [pattern],
            ]
        }
        assertEquals(parsed.workspaceToMonitorForceAssignment["1"], [.main])
        assertEquals(parsed.workspaceToMonitorForceAssignment["2"], [.secondary, .sequenceNumber(3)])
        assertEquals(parsed.workspaceToMonitorForceAssignment["3"], [pattern])
    }

    func testRawPanesAreSpliced() {
        let parsed = roundTrip { draft in
            draft.rawKeybindings = "[mode.main.binding]\nalt-h = 'focus left'\n"
            draft.rawWindowRules = "[[on-window-detected]]\nif.app-id = 'com.apple.finder'\nrun = ['layout floating']\n"
            draft.rawCallbacks = "on-focus-changed = ['move-mouse window-lazy-center']\n"
        }
        assertEquals(parsed.modes[mainModeId]?.bindings.isEmpty, false)
        assertEquals(parsed.onWindowDetected.count, 1)
        assertEquals(parsed.onFocusChanged.count, 1)
    }

    func testDefaultsAreNotWrittenWhenAbsentFromTheFile() {
        // A user's file that sets nothing must stay minimal after an unrelated edit.
        //
        // Deviation from the brief, reconfirmed after the round-1 review (see the fix
        // report): built from `Config()`, not `defaultConfig`. `defaultConfig` (the parsed
        // docs/config-examples/default-config.toml) explicitly sets BOTH `config-version =
        // 2` AND a full `persistent-workspaces` list, beyond `Config()`'s bare defaults.
        // Critical 2's fix (gating `persistent-workspaces` on config-version >= 2) only
        // silences the second of those — `config-version` itself still differs from
        // `ConfigDraft.defaults` (built from `Config()`) regardless, so `setOrOmit` still
        // writes `config-version = 2` unconditionally even with Critical 2 fixed. This is
        // independent of Critical 2: `configVersion`'s `isDefault` check never involves the
        // version gate at all. Verified empirically: reverting to `defaultConfig` here,
        // with Critical 2's fix in place, still fails with exactly `config-version = 2`
        // appended (persistent-workspaces no longer appears). See the fix report for the
        // full trace. `Config()` is the only source consistent with this test's own intent
        // ("stays minimal") and with how the type is used for real (Task 5 always builds
        // the draft from the Config parsed from the SAME document).
        var document = TomlBlockDocument("start-at-login = false\n")
        var draft = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, to: &document)
        assertEquals(document.render(), "start-at-login = true\n")
    }

    func testRevertingAnOptionToItsDefaultStillPersistsWhenAlreadyPresent() {
        // The `isDefault && already present` branch of `setOrOmit`: turning a toggle back
        // to its default value must still overwrite the existing line, not leave the old
        // value or silently drop the key.
        //
        // Built from `Config()`, not `defaultConfig` — same reasoning as
        // `testDefaultsAreNotWrittenWhenAbsentFromTheFile` above: `defaultConfig` sets
        // `config-version` / `persistent-workspaces` beyond `Config()`'s bare defaults,
        // which would leak into this near-empty document's exact-equality assertion too.
        var document = TomlBlockDocument("start-at-login = true\n")
        var draft = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = false
        ConfigTomlWriter.apply(draft, to: &document)
        assertEquals(document.render(), "start-at-login = false\n")
    }

    func testRegeneratingATableRemovesItsExistingSubTables() {
        // `[exec]` and `[exec.env-vars]` are separate top-level blocks (each `[header]`
        // line splits into its own block). Regenerating `[exec]` must remove the stale
        // `[exec.env-vars]` too, or the freshly-generated `[exec]` body (which re-emits
        // its own `[exec.env-vars]`) duplicates the table and the result fails to parse.
        var document = TomlBlockDocument("[exec]\ninherit-env-vars = false\n\n[exec.env-vars]\nFOO = 'bar'\n")
        var draft = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: document)
        draft.inheritEnvVars = false
        draft.envVars = ["FOO": "bar", "BAZ": "qux"]
        ConfigTomlWriter.apply(draft, to: &document)
        let text = document.render()
        assertEquals(text.components(separatedBy: "[exec.env-vars]").count - 1, 1, additionalMsg: text)
        let (parsed, errors) = parseConfig(text)
        assertEquals(errors, [], additionalMsg: text)
        assertEquals(parsed.execConfig.envVariables["FOO"], "bar")
        assertEquals(parsed.execConfig.envVariables["BAZ"], "qux")
    }

    func testCommentsOutsideRegeneratedTablesSurvive() {
        var document = TomlBlockDocument("# my note\nstart-at-login = false\n\n[mode.main.binding]\nalt-h = 'focus left'\n")
        var draft = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, to: &document)
        assertEquals(document.render().contains("# my note"), true)
        assertEquals(document.render().contains("alt-h = 'focus left'"), true)
    }

    func testAppliedToDefaultConfigStillParses() {
        let text = try! String(
            contentsOf: projectRoot.appending(component: "docs/config-examples/default-config.toml"),
            encoding: .utf8,
        )
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfig(text)
        assertEquals(errors, [])
        var draft = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        draft.accordionPadding = 99
        draft.gaps = draft.gaps.copy(\.inner.vertical, .constant(7))
        ConfigTomlWriter.apply(draft, to: &document)
        let (reparsed, reErrors) = parseConfig(document.render())
        assertEquals(reErrors, [], additionalMsg: document.render())
        assertEquals(reparsed.accordionPadding, 99)
        assertEquals(reparsed.gaps.inner.vertical, .constant(7))
        // The bindings the default config ships with must survive an unrelated edit.
        assertEquals(reparsed.modes[mainModeId]?.bindings.count, config.modes[mainModeId]?.bindings.count)
    }
}
