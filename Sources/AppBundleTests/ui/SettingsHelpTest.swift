@testable import AppBundle
import XCTest

final class SettingsHelpTest: XCTestCase {
    func testEveryTopicProvidesUsefulUserFacingHelp() {
        for topic in SettingHelpTopic.allCases {
            let content = topic.content
            XCTAssertFalse(content.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Missing summary for \(topic)")
            XCTAssertFalse(content.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Missing details for \(topic)")
            XCTAssertFalse(content.tomlKeys.isEmpty, "Missing TOML key for \(topic)")
            XCTAssertTrue(content.tomlKeys.allSatisfy { !$0.isEmpty }, "Empty TOML key for \(topic)")
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
        let details = SettingHelpTopic.configVersion.content.details

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
}
