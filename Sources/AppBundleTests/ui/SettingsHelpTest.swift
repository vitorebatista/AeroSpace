@testable import AppBundle
import XCTest

final class SettingsHelpTest: XCTestCase {
    /// The controls that are deliberately not config options: app preferences and immediate
    /// actions. Everything else must name the TOML key it writes.
    private static let appPreferenceTopics: Set<SettingHelpTopic> = [
        .menuBarStyle, .menuBarItemPosition, .openConfig, .reloadConfig, .crashReports, .versionInfo,
        .sketchybarStatus, .sketchybarReload,
    ]

    func testAppPreferencesAreExactlyTheTopicsWithoutTomlKeys() {
        let withoutKeys = Set(SettingHelpTopic.allCases.filter { $0.content.tomlKeys.isEmpty })
        assertEquals(withoutKeys.sorted { $0.rawValue < $1.rawValue }, Self.appPreferenceTopics.sorted { $0.rawValue < $1.rawValue })
    }

    func testEveryTopicProvidesUsefulUserFacingHelp() {
        for topic in SettingHelpTopic.allCases {
            let content = topic.content
            XCTAssertFalse(content.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Missing summary for \(topic)")
            XCTAssertFalse(content.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Missing details for \(topic)")
            XCTAssertTrue(content.tomlKeys.allSatisfy { !$0.isEmpty }, "Empty TOML key for \(topic)")
            XCTAssertTrue(
                !content.tomlKeys.isEmpty || Self.appPreferenceTopics.contains(topic),
                "Missing TOML key for \(topic) — add it, or list the topic as an app preference",
            )
        }
    }

    /// Anything the user has to type a *structure* into, rather than pick or toggle, has to show
    /// what that structure looks like.
    func testFreeFormControlsShowExamples() {
        let topics: [SettingHelpTopic] = [
            .keyNotationOverrides,
            .envVarOverrides,
            .persistentWorkspaces,
            .workspaceMonitorAssignment,
            .perMonitorGaps,
            .borderColor,
        ]
        for topic in topics {
            XCTAssertFalse(topic.content.examples.isEmpty, "Missing examples for \(topic)")
            XCTAssertTrue(
                topic.content.examples.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                "Empty example for \(topic)",
            )
        }
    }

    func testTheTooltipCarriesTheExamples() {
        let content = SettingHelpTopic.envVarOverrides.content
        XCTAssertTrue(content.tooltip.contains(content.summary))
        for example in content.examples {
            XCTAssertTrue(content.tooltip.contains(example), "Tooltip drops example: \(example)")
        }
        // A plain switch has nothing to show, and its tooltip stays the bare summary.
        assertEquals(SettingHelpTopic.startAtLogin.content.tooltip, SettingHelpTopic.startAtLogin.content.summary)
    }

    /// The link in each destination has to land on a page that exists — the docs are a separate
    /// tree, so a renamed page would otherwise 404 silently.
    @MainActor
    func testEveryDestinationLinksToAPageThatExists() {
        for category in SettingsCategory.allCases {
            let page = category.docsUrl.lastPathComponent
            let file = projectRoot.appending(component: "docs-md/settings/\(page).md")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: file.path),
                "\(category) links to a missing docs page: \(file.path)",
            )
        }
    }

    func testCompoundControlsNameEveryTomlKeyTheyChange() {
        assertEquals(SettingHelpTopic.innerGaps.content.tomlKeys, ["gaps.inner.horizontal", "gaps.inner.vertical"])
        assertEquals(SettingHelpTopic.outerGaps.content.tomlKeys, [
            "gaps.outer.left", "gaps.outer.right", "gaps.outer.top", "gaps.outer.bottom",
        ])
        assertEquals(SettingHelpTopic.focusedWindowBorder.content.tomlKeys, [
            "focused-window-border",
            "focused-window-border-color",
            "focused-window-border-width",
            "focused-window-border-opacity",
            "focused-window-border-radius",
            "focused-window-border-inset",
        ])
    }

    func testSpatialOptionsHaveAVisualExplanation() {
        let topics: [SettingHelpTopic] = [
            .defaultLayout,
            .defaultOrientation,
            .flattenContainers,
            .oppositeOrientation,
            .binaryTree,
            .accordionPadding,
            .innerGaps,
            .outerGaps,
            .perMonitorGaps,
            .focusActivation,
            .focusedWindowBorder,
            .workspaceMonitorAssignment,
        ]
        for topic in topics {
            XCTAssertNotNil(topic.content.visual, "Missing visual explanation for \(topic)")
        }
    }

    func testConfigVersionHelpExplainsMigrationAndRecoveryBeforeSaving() {
        let details = SettingsMigrationCopy.pending

        for expected in [
            "Version 1",
            "Version 2",
            "materializes",
            "persistent-workspaces",
            "backup-v1-YYYYMMDD-HHmmss",
            "No files change until Save",
        ] {
            XCTAssertTrue(details.contains(expected), "Missing migration guidance: \(expected)")
        }
    }

    func testConfigVersionHelpDescribesMigrationConditionallyWhenNoneIsPending() {
        let details = SettingsMigrationCopy.configVersionHelp(migrationPending: false)
        let pendingDetails = SettingsMigrationCopy.configVersionHelp(migrationPending: true)

        XCTAssertEqual(SettingHelpTopic.configVersion.content.details, details)
        XCTAssertEqual(pendingDetails, SettingsMigrationCopy.pending)
        XCTAssertNotEqual(details, pendingDetails)
        XCTAssertFalse(details.contains("This is a migration"))
        XCTAssertFalse(details.contains("No files change until Save"))
        XCTAssertTrue(details.contains("If you change a loaded Version 1 config to Version 2"))
    }
}
