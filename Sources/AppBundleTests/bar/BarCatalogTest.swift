@testable import AppBundle
import XCTest

final class BarCatalogTest: XCTestCase {
    func testIdsAreUniqueAndFileFormatSafe() {
        // An id is written into bar.toml and into the generated sketchybar item name, so it has to
        // survive both without quoting.
        let ids = BarCatalog.items.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "catalog ids must be unique")
        for id in ids {
            XCTAssertNotNil(
                id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression),
                "'\(id)' must be lowercase-hyphenated",
            )
        }
    }

    func testEveryItemIsDescribedAndPlaced() {
        for item in BarCatalog.items {
            XCTAssertFalse(item.displayName.isEmpty, "\(item.id) needs a display name")
            XCTAssertFalse(item.summary.isEmpty, "\(item.id) needs a summary")
            XCTAssertTrue(
                BarCluster.allCases.contains(item.defaultCluster),
                "\(item.id) has an unknown default cluster",
            )
            XCTAssertEqual(BarCatalog.item(id: item.id), item)
        }
    }

    func testEveryItemOffersAtLeastOneIconAndEveryIconNamesAFont() {
        for item in BarCatalog.items {
            XCTAssertFalse(item.icons.isEmpty, "\(item.id) needs at least one icon")
            for icon in item.icons {
                XCTAssertFalse(icon.name.isEmpty, "\(item.id) has an unnamed icon")
                XCTAssertFalse(icon.displayName.isEmpty, "\(item.id) icon '\(icon.name)' needs a display name")
                XCTAssertFalse(
                    icon.font.fontFamily.isEmpty,
                    "\(item.id) icon '\(icon.name)' must name the font sketchybar draws it with",
                )
            }
            let names = item.icons.map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "\(item.id) lists an icon twice")
        }
    }

    func testOnlyAFontTheUserHasToInstallCarriesAnInstallHint() {
        // The hint is the actionable half of the missing-font warning, so a font that has to be
        // installed must carry one and a font macOS ships must not claim otherwise.
        XCTAssertNil(BarIconFont.sfSymbols.installHint, "SF Pro ships with macOS")
        XCTAssertEqual(BarIconFont.sketchybarAppFont.installHint?.isEmpty, false)
        for font in BarIconFont.allCases {
            XCTAssertFalse(font.fontFamily.isEmpty, "\(font.rawValue) must name a family for icon.font")
        }
    }

    func testEverySettingDefaultMatchesItsDeclaredType() {
        for item in BarCatalog.items {
            let keys = item.settings.map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, "\(item.id) declares a settings key twice")
            for setting in item.settings {
                let at = "\(item.id).\(setting.key)"
                XCTAssertNotNil(
                    setting.key.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression),
                    "\(at) must be lowercase-hyphenated",
                )
                XCTAssertFalse(setting.displayName.isEmpty, "\(at) needs a display name")
                XCTAssertFalse(setting.summary.isEmpty, "\(at) needs a summary")

                switch (setting.type, setting.defaultValue) {
                    case (.bool, .bool), (.string, .string):
                        break
                    case (.stringList, .array(let values)):
                        XCTAssertTrue(
                            values.allSatisfy { if case .string = $0 { true } else { false } },
                            "\(at) declares a string list but defaults to a non-string element",
                        )
                    case (.int(let min, let max), .int(let value)):
                        XCTAssertLessThan(min, max, "\(at) has an empty range")
                        XCTAssertTrue((min ... max).contains(value), "\(at) defaults to \(value), outside \(min)...\(max)")
                    case (.enumeration(let cases), .string(let value)):
                        XCTAssertFalse(cases.isEmpty, "\(at) is an enum with no cases")
                        XCTAssertEqual(Set(cases).count, cases.count, "\(at) lists a case twice")
                        XCTAssertTrue(cases.contains(value), "\(at) defaults to '\(value)', which is not one of \(cases)")
                    default:
                        XCTFail("\(at) defaults to a value of a different type than it declares")
                }
            }
        }
    }

    func testEveryStructuralSettingShowsConcreteExamples() {
        for item in BarCatalog.items {
            for setting in item.settings where setting.isStructural {
                XCTAssertFalse(
                    setting.examples.isEmpty,
                    "\(item.id).\(setting.key) is typed by hand, so it needs examples — a description of a format is not a format",
                )
                for example in setting.examples {
                    XCTAssertFalse(example.isEmpty, "\(item.id).\(setting.key) has an empty example")
                }
            }
            for setting in item.settings where !setting.isStructural {
                XCTAssertTrue(
                    setting.examples.isEmpty,
                    "\(item.id).\(setting.key) is a switch or a picker; examples belong on the keys the user types",
                )
            }
        }
    }

    func testPrivilegedItemsAreVisibleButDisabledAndEverythingElseIsAvailable() {
        for item in BarCatalog.items {
            if item.requirement == .helperBinary {
                guard case .unavailable(let note) = item.availability else {
                    XCTFail("\(item.id) needs a helper binary that does not ship yet, so it must be listed as unavailable")
                    continue
                }
                XCTAssertFalse(note.isEmpty, "\(item.id) must explain why it is disabled")
            } else {
                XCTAssertEqual(item.availability, .available, "\(item.id) has no unshipped dependency")
            }
        }
        XCTAssertEqual(
            BarCatalog.items(in: .privileged).map(\.id),
            ["volume", "brightness", "bluetooth"],
            "the privileged group is the set awaiting the helper binary",
        )
        XCTAssertFalse(BarCatalog.items.filter { !$0.isAvailable }.isEmpty)
    }

    func testCatalogCoversEveryGroupTheSpecNames() {
        for group in BarItemGroup.allCases {
            XCTAssertFalse(BarCatalog.items(in: group).isEmpty, "\(group.displayName) has no items")
        }
        XCTAssertEqual(
            BarCatalog.items.map(\.id),
            [
                "workspaces", "front-app", "mode", "floats",
                "battery", "clock", "cpu", "network", "weather",
                "volume", "brightness", "bluetooth",
                "apple-menu", "secure-input",
                "custom",
            ],
        )
        for cluster in BarCluster.allCases {
            XCTAssertFalse(
                BarCatalog.items.filter { $0.defaultCluster == cluster }.isEmpty,
                "no item defaults to the \(cluster.rawValue) cluster",
            )
        }
    }

    func testGeneratedNamesAreNamespaced() {
        for item in BarCatalog.items {
            XCTAssertEqual(BarCatalog.sketchybarName(for: item.id), "aerospace." + item.id)
        }
    }

    func testCustomItemTakesAScriptAnUpdateFrequencyAndEvents() {
        guard let custom = BarCatalog.item(id: "custom") else { return XCTFail("the escape hatch is missing") }
        XCTAssertEqual(custom.requirement, .userScript)
        XCTAssertEqual(custom.settings.map(\.key), ["script", "update-freq", "events"])
        XCTAssertEqual(custom.setting("events")?.type, .stringList)
    }
}
