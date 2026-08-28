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
}
