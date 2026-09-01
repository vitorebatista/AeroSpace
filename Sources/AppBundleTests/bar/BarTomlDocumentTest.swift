@testable import AppBundle
import Common
import XCTest

final class BarTomlDocumentTest: XCTestCase {
    /// A file that exercises everything the writer must not disturb: comments in three
    /// positions, a key the app does not model in `[bar]` and another in
    /// `[item.settings]`, and a `[[profile]]` block belonging to a stage the app does not
    /// implement yet.
    private let sample = """
        # Managed by AeroSpace-edge.
        version = 1

        [bar]
        height = 32 # a bit taller than the notch
        margin = 8
        blur-radius = 20

        [bar.colors]
        background = '0xb3202020'
        accent = '0xff717ebb'

        [[item]]
        id = 'workspaces'
        cluster = 'left'

        [item.settings]
        show-app-icons = true
        per-monitor = true
        unknown-future-key = 'kept'

        # the clock goes last
        [[item]]
        id = 'clock'
        cluster = 'right'

        [item.settings]
        format = '%a %d %b %H:%M'

        [[item]]
        id = 'front-app'
        cluster = 'left'

        [[profile]]
        name = 'Work'
        workspaces = ['1', '2']

        """

    func testRoundTripWithNoEditsIsByteIdentical() {
        var doc = BarTomlDocument(sample)
        let draft = draftOrFail(doc)
        doc.apply(draft, original: draft)
        assertEquals(doc.render(), sample)
    }

    func testUnmodelledKeysAreReadAndNotDropped() {
        let draft = draftOrFail(BarTomlDocument(sample))
        assertEquals(Array(draft.items[0].settings.keys), ["show-app-icons", "per-monitor", "unknown-future-key"])
        assertEquals(draft.items[0].settings["unknown-future-key"], .string("kept"))
        assertEquals(draft.items[0].settings["show-app-icons"], .bool(true))
        assertEquals(draft.items[1].settings["format"], .string("%a %d %b %H:%M"))
        assertEquals(draft.items[2].settings.isEmpty, true)
    }

    func testReadsModelledValuesAndDefaultsForAbsentKeys() {
        let draft = draftOrFail(BarTomlDocument(sample))
        assertEquals(draft.version, 1)
        assertEquals(draft.geometry.height, 32)
        assertEquals(draft.geometry.margin, 8)
        assertEquals(draft.geometry.yOffset, BarGeometry().yOffset) // absent from the file
        assertEquals(draft.colors.background, "0xb3202020")
        assertEquals(draft.colors.label, BarColors().label) // absent from the file
    }

    func testClusterOrderingIsDocumentOrder() {
        let draft = draftOrFail(BarTomlDocument(sample))
        assertEquals(draft.items.map(\.id), ["workspaces", "clock", "front-app"])
        assertEquals(draft.items(in: .left).map(\.id), ["workspaces", "front-app"])
        assertEquals(draft.items(in: .center).map(\.id), [])
        assertEquals(draft.items(in: .right).map(\.id), ["clock"])
    }

    func testEditingOneColorLeavesEveryOtherRegionByteIdentical() {
        var doc = BarTomlDocument(sample)
        let original = draftOrFail(doc)
        var draft = original
        draft.colors.accent = "0xff00ff00"
        doc.apply(draft, original: original)
        assertEquals(
            doc.render(),
            sample.replacingOccurrences(of: "accent = '0xff717ebb'", with: "accent = '0xff00ff00'"),
        )
    }

    func testEditingAValueKeepsItsTrailingComment() {
        var doc = BarTomlDocument(sample)
        let original = draftOrFail(doc)
        var draft = original
        draft.geometry.height = 40
        doc.apply(draft, original: original)
        assertEquals(
            doc.render(),
            sample.replacingOccurrences(of: "height = 32 #", with: "height = 40 #"),
        )
    }

    func testWritingAnAbsentKeyAppendsItToItsOwnTable() {
        var doc = BarTomlDocument(sample)
        let original = draftOrFail(doc)
        var draft = original
        draft.geometry.yOffset = 12
        draft.colors.label = "0xffffffff"
        doc.apply(draft, original: original)
        assertEquals(
            doc.render(),
            sample
                .replacingOccurrences(of: "blur-radius = 20", with: "blur-radius = 20\ny-offset = 12")
                .replacingOccurrences(of: "accent = '0xff717ebb'", with: "accent = '0xff717ebb'\nlabel = '0xffffffff'"),
        )
    }

    func testEditingAnItemRegeneratesOnlyThatRegion() {
        var doc = BarTomlDocument(sample)
        let original = draftOrFail(doc)
        var draft = original
        draft.items.swapAt(0, 1) // the drag a user would do: clock moves ahead of workspaces
        doc.apply(draft, original: original)

        let rendered = doc.render()
        // The unknown settings key survives a regeneration, and so does everything outside
        // the item region.
        assertTrue(rendered.contains("unknown-future-key = 'kept'"))
        assertTrue(rendered.contains("# Managed by AeroSpace-edge.\nversion = 1\n"))
        assertTrue(rendered.contains("height = 32 # a bit taller than the notch"))
        assertTrue(rendered.contains("[[profile]]\nname = 'Work'\nworkspaces = ['1', '2']\n"))

        let reparsed = draftOrFail(BarTomlDocument(rendered))
        assertEquals(reparsed.items.map(\.id), ["clock", "workspaces", "front-app"])
        assertEquals(reparsed.items, draft.items)
    }

    func testEditingAFileWithNoBarTableAppendsTheTables() {
        var doc = BarTomlDocument("version = 1\n")
        let original = draftOrFail(doc)
        var draft = original
        draft.geometry.height = 44
        doc.apply(draft, original: original)
        assertEquals(draftOrFail(BarTomlDocument(doc.render())).geometry.height, 44)
        assertTrue(doc.render().hasPrefix("version = 1\n"))
    }

    func testAppliedValuesSurviveAReparse() {
        var doc = BarTomlDocument(sample)
        let original = draftOrFail(doc)
        var draft = original
        draft.version = 2
        draft.geometry.cornerRadius = 3
        draft.colors.popupBorder = "0xff000000"
        draft.items.append(BarItem(id: "cpu", cluster: .center, settings: ["interval": .int(5), "graph": .bool(false)]))
        doc.apply(draft, original: original)
        assertEquals(draftOrFail(BarTomlDocument(doc.render())), draft)
    }

    func testSyntaxErrorIsReportedAndDoesNotProduceDefaults() {
        let doc = BarTomlDocument("version = \n[bar\n")
        assertFail(doc.draft())
        switch doc.draft() {
            case .success(let draft): XCTFail("Expected a failure, got \(draft)")
            case .failure(let error):
                guard case .syntax = error else { return XCTFail("Expected a syntax error, got \(error)") }
                assertTrue(error.description.contains("Failed to parse bar.toml"))
        }
        // The unparseable text is still carried verbatim, so nothing is lost by reading it.
        assertEquals(doc.render(), "version = \n[bar\n")
    }

    func testUnknownClusterIsReportedWithTheAcceptedValues() {
        let doc = BarTomlDocument("[[item]]\nid = 'clock'\ncluster = 'middle'\n")
        switch doc.draft() {
            case .success(let draft): XCTFail("Expected a failure, got \(draft)")
            case .failure(let error):
                assertEquals(
                    error.description,
                    "item[0] ('clock') has unknown cluster 'middle'. Expected one of: left, center, right",
                )
        }
    }

    func testWrongValueTypesAreReported() {
        assertFail(BarTomlDocument("[bar]\nheight = 'tall'\n").draft(), .semantic("bar.height must be an integer, got String"))
        assertFail(BarTomlDocument("[[item]]\ncluster = 'left'\n").draft(), .semantic("item[0] must have a non-empty string 'id'"))
        assertFail(
            BarTomlDocument("[[item]]\nid = 'clock'\ncluster = 'right'\n[item.settings]\nnested = { a = 1 }\n").draft(),
            .semantic("item[0].settings.nested has unsupported type Dictionary<String, Any>. Expected a string, number, boolean, or a list of those"),
        )
    }

    private func draftOrFail(_ doc: BarTomlDocument, file: String = #filePath, line: Int = #line) -> BarDraft {
        switch doc.draft() {
            case .success(let draft): return draft
            case .failure(let error):
                failExpectedActual("a parsed BarDraft", error.description, file: file, line: line)
                return BarDraft()
        }
    }
}
