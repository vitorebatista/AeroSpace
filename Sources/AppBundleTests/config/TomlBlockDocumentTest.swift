@testable import AppBundle
import Common
import XCTest

final class TomlBlockDocumentTest: XCTestCase {
    func testRoundTripDefaultConfig() {
        for name in ["default-config.toml", "i3-like-config-example.toml"] {
            let text = try! String(
                contentsOf: projectRoot.appending(component: "docs/config-examples/\(name)"),
                encoding: .utf8,
            )
            assertEquals(TomlBlockDocument(text).render(), text)
        }
    }

    func testRoundTripTrickyValues() {
        let text = """
            # leading comment
            start-at-login = true

            after-startup-command = [
                'exec-and-forget echo "a # not-a-comment"',
                'exec-and-forget echo [not-a-header]',
            ]

            [gaps]
            inner.horizontal = 10 # trailing comment

            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            run = ['layout floating']

            """
        assertEquals(TomlBlockDocument(text).render(), text)
    }

    func testBlockSplitting() {
        let doc = TomlBlockDocument(
            """
            a = 1
            # comment about the table
            [gaps]
            inner.vertical = 2
            """,
        )
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .keyValue(key: "a", text: "a = 1\n"))
        assertEquals(doc.blocks[1], .trivia(text: "# comment about the table\n"))
        assertEquals(
            doc.blocks[2],
            .table(name: "gaps", text: "[gaps]\ninner.vertical = 2"),
        )
    }

    func testTrailingCommentsInATableBecomeTrivia() {
        // A comment run at the end of a table body is split out, so that replacing the
        // table does not swallow a comment that visually belongs to what follows.
        let doc = TomlBlockDocument(
            """
            [gaps]
            inner.vertical = 2

            # about the next thing
            [exec]
            inherit-env-vars = true
            """,
        )
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .table(name: "gaps", text: "[gaps]\ninner.vertical = 2\n"))
        assertEquals(doc.blocks[1], .trivia(text: "\n# about the next thing\n"))
        assertEquals(doc.blocks[2], .table(name: "exec", text: "[exec]\ninherit-env-vars = true"))
    }

    func testArrayOfTablesName() {
        let doc = TomlBlockDocument("[[on-window-detected]]\nrun = ['layout floating']\n")
        assertEquals(doc.blocks.count, 1)
        assertEquals(doc.blocks[0].name, "on-window-detected")
    }

    func testEmptyInput() {
        assertEquals(TomlBlockDocument("").render(), "")
        assertEquals(TomlBlockDocument("").blocks.count, 0)
    }

    func testSetExistingKeyPreservesEverythingElse() {
        var doc = TomlBlockDocument(
            """
            # top comment
            start-at-login = false
            accordion-padding = 30 # why 30

            [gaps]
            inner.vertical = 2
            """,
        )
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(
            doc.render(),
            """
            # top comment
            start-at-login = true
            accordion-padding = 30 # why 30

            [gaps]
            inner.vertical = 2
            """,
        )
    }

    func testSetPreservesTrailingCommentOnTheSameLine() {
        var doc = TomlBlockDocument("accordion-padding = 30 # why 30\n")
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(doc.render(), "accordion-padding = 45 # why 30\n")
    }

    func testSetAbsentKeyIsInsertedBeforeTheFirstTableHeader() {
        var doc = TomlBlockDocument(
            """
            start-at-login = true

            [gaps]
            inner.vertical = 2
            """,
        )
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(
            doc.render(),
            """
            start-at-login = true
            accordion-padding = 45

            [gaps]
            inner.vertical = 2
            """,
        )
    }

    func testSetAbsentKeyInAFileWithNoTables() {
        var doc = TomlBlockDocument("start-at-login = true\n")
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(doc.render(), "start-at-login = true\naccordion-padding = 45\n")
    }

    func testSetAbsentKeyInAnEmptyDocument() {
        var doc = TomlBlockDocument("")
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(doc.render(), "start-at-login = true\n")
    }

    func testSetMultiLineValueIsReplacedWholesale() {
        var doc = TomlBlockDocument(
            """
            persistent-workspaces = [
                '1',
                '2',
            ]
            start-at-login = true
            """,
        )
        doc.set(key: "persistent-workspaces", tomlValue: "['1', '2', '3']")
        assertEquals(
            doc.render(),
            """
            persistent-workspaces = ['1', '2', '3']
            start-at-login = true
            """,
        )
    }

    func testRemoveKey() {
        var doc = TomlBlockDocument("a = 1\nb = 2\n")
        doc.remove(key: "a")
        assertEquals(doc.render(), "b = 2\n")
        doc.remove(key: "nonexistent") // no-op
        assertEquals(doc.render(), "b = 2\n")
    }

    func testUnknownKeysAndTablesSurviveASet() {
        let text = """
            some-future-option = 'hello'
            start-at-login = false

            [some.future.table]
            x = 1
            """
        var doc = TomlBlockDocument(text)
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(doc.render(), text.replacingOccurrences(of: "start-at-login = false", with: "start-at-login = true"))
    }

    func testValueSerialisers() {
        assertEquals(TomlValue.of(true), "true")
        assertEquals(TomlValue.of(42), "42")
        assertEquals(TomlValue.of("plain"), "'plain'")
        assertEquals(TomlValue.of("it's"), "\"it's\"")
        assertEquals(TomlValue.of("say \"hi\""), "'say \"hi\"'")
        assertEquals(TomlValue.array([TomlValue.of("1"), TomlValue.of("2")]), "['1', '2']")
        assertEquals(TomlValue.array([]), "[]")
    }
}
