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

    func testConstantGapsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(inner: .init(vertical: 5, horizontal: 6), outer: .init(left: 1, bottom: 2, top: 3, right: 4))
        }
        assertEquals(parsed.gaps.inner.vertical, .constant(5))
        assertEquals(parsed.gaps.outer.top, .constant(3))
    }

    func testPerMonitorGapsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(
                inner: .init(vertical: .constant(5), horizontal: .constant(6)),
                outer: .init(
                    left: .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8),
                    bottom: .constant(2), top: .constant(3), right: .constant(4),
                ),
            )
        }
        assertEquals(parsed.gaps.outer.left, .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8))
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
        let parsed = roundTrip { draft in
            draft.workspaceToMonitorForceAssignment = ["1": [.main], "2": [.secondary, .sequenceNumber(3)]]
        }
        assertEquals(parsed.workspaceToMonitorForceAssignment["1"], [.main])
        assertEquals(parsed.workspaceToMonitorForceAssignment["2"], [.secondary, .sequenceNumber(3)])
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
        // Deviation from the brief: built from `Config()`, not `defaultConfig`. The shipped
        // default-config.toml explicitly overrides `config-version` (2) and
        // `persistent-workspaces` (a full list) beyond `Config()`'s bare defaults, which is
        // inconsistent with the near-empty `document` below. In real usage the draft's source
        // `Config` always comes from parsing the SAME document being edited, so this mismatch
        // cannot occur there; using `defaultConfig` here would only be consistent if the
        // document were `default-config.toml`'s own text.
        var document = TomlBlockDocument("start-at-login = false\n")
        var draft = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: document)
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, to: &document)
        assertEquals(document.render(), "start-at-login = true\n")
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
