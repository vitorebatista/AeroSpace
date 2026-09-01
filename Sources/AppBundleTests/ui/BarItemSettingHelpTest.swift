@testable import AppBundle
import XCTest

/// The Sketchybar page's item controls are generated from `BarCatalog`, so `SettingsHelpTest`
/// — which walks the fixed `SettingHelpTopic` list — cannot see them. This applies the same
/// rules to the generated half: every control explains itself, names the `bar.toml` key it
/// writes, and shows a worked example wherever the user has to type a structure.
final class BarItemSettingHelpTest: XCTestCase {
    func testEverySettingNamesItsTomlKeyAndExplainsItself() {
        for item in BarCatalog.items {
            for key in item.settings {
                let content = SettingHelpContent.barItemSetting(item, key)
                XCTAssertFalse(content.summary.isEmpty, "\(item.id).\(key.key) needs a summary")
                XCTAssertFalse(content.details.isEmpty, "\(item.id).\(key.key) needs details")
                assertEquals(content.tomlKeys, ["item.settings.\(key.key)"])
                XCTAssertTrue(content.details.contains(item.displayName), "\(item.id).\(key.key) doesn't say which item it belongs to")
            }
        }
    }

    func testEverySettingTheUserHasToTypeShowsAWorkedExample() {
        for item in BarCatalog.items {
            for key in item.settings where key.isStructural {
                let content = SettingHelpContent.barItemSetting(item, key)
                XCTAssertFalse(content.examples.isEmpty, "\(item.id).\(key.key) is free-form and shows no example")
                XCTAssertTrue(
                    content.examples.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                    "\(item.id).\(key.key) has an empty example",
                )
            }
        }
    }

    func testTheTooltipCarriesTheCatalogsExamples() {
        let clock = BarCatalog.item(id: "clock").orDie()
        let content = SettingHelpContent.barItemSetting(clock, clock.setting("format").orDie())
        for example in content.examples {
            XCTAssertTrue(content.tooltip.contains(example), "Tooltip drops example: \(example)")
        }
    }

    /// The Sketchybar destination's own fixed controls, checked here rather than left to the
    /// bare "has a TOML key" rule: a bar key that named the wrong table would still pass that.
    func testTheBarsOwnControlsNameBarTomlKeys() {
        let topics: [SettingHelpTopic] = [
            .barHeight, .barMargin, .barYOffset, .barCornerRadius, .barBorderWidth, .barPadding,
            .barBackgroundColor, .barBorderColor, .barLabelColor, .barIconColor, .barAccentColor,
            .barPopupBackgroundColor, .barPopupBorderColor,
        ]
        for topic in topics {
            XCTAssertTrue(
                topic.content.tomlKeys.allSatisfy { $0.hasPrefix("bar.") },
                "\(topic) names a key outside [bar]: \(topic.content.tomlKeys)",
            )
        }
        assertEquals(SettingHelpTopic.barPadding.content.tomlKeys, ["bar.padding-left", "bar.padding-right"])
        assertEquals(SettingHelpTopic.barItems.content.tomlKeys, ["item", "item.id", "item.cluster"])
    }

    /// A colour is typed, not picked, whenever the picker can't represent the current value.
    func testEveryColourControlShowsAConcreteColourValue() {
        let colours: [SettingHelpTopic] = [
            .barBackgroundColor, .barBorderColor, .barLabelColor, .barIconColor, .barAccentColor,
            .barPopupBackgroundColor, .barPopupBorderColor,
        ]
        for topic in colours {
            XCTAssertTrue(
                topic.content.examples.contains { $0.hasPrefix("0x") },
                "\(topic) describes the format instead of showing one",
            )
        }
    }
}
