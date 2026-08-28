= Settings window design

Date: 2026-08-28
Status: approved design, ready for implementation planning

== Goal

Give AeroSpace-edge a GUI settings surface so a user never has to open
`~/.aerospace-edge.toml` in a text editor to change a setting. Every option the
config parser accepts is reachable from the window. Saving rewrites the config
file in place — preserving comments, key order, and unknown keys — validates the
result with the real parser, and reloads the config.

== Non-goals

* No GUI command builder for the AeroSpace command DSL. Keybindings, window
  rules, and callbacks are edited as raw TOML text inside the window (decision
  taken during brainstorming; a form for the DSL is most of the work and worse
  than a text editor for the people who use it).
* No live-apply-as-you-type. There is an explicit Save.
* No new settings-schema abstraction layer. The option list is a flat literal
  table read by the views.
* No changes to the config file format, the parser, or any command.

== Option inventory

`Sources/AppBundle/config/parseConfig.swift`'s `configParser` is the
authoritative list; it covers every option `docs/guide.adoc` documents. Verified
2026-08-28: no documented option is missing from it, and no option in it is
undocumented.

=== Form-driven (structured)

[cols="1,1,1"]
|===
| TOML key | Control | Notes

| `config-version` | stepper (int) | shown read-mostly, in General
| `start-at-login` | toggle |
| `auto-reload-config` | toggle |
| `automatically-unhide-macos-hidden-apps` | toggle |
| `default-root-container-layout` | picker | `tiles` / `accordion`
| `default-root-container-orientation` | picker | `horizontal` / `vertical` / `auto`
| `enable-normalization-flatten-containers` | toggle |
| `enable-normalization-opposite-orientation-for-nested-containers` | toggle |
| `enable-normalization-binary-tree` | toggle |
| `accordion-padding` | stepper (int) |
| `focus-follows-app-activation` | picker | `always` / `smart` (fork-only)
| `new-window-prevent-flicker` | toggle |
| `focused-window-border` | toggle | gates the 5 below (fork-only group)
| `focused-window-border-color` | colour picker | serialised back as `0xAARRGGBB`
| `focused-window-border-width` | stepper (int) |
| `focused-window-border-opacity` | slider (int, 0–100) |
| `focused-window-border-radius` | stepper (int) |
| `focused-window-border-inset` | stepper (int) |
| `gaps.inner.{vertical,horizontal}` | int + per-monitor rows | `DynamicConfigValue<Int>`
| `gaps.outer.{left,right,top,bottom}` | int + per-monitor rows | `DynamicConfigValue<Int>`
| `persistent-workspaces` | ordered string list | add / remove / reorder
| `workspace-to-monitor-force-assignment` | rows: workspace -> monitor descriptions | monitor description is `main`, `secondary`, a sequence number, or a regex pattern
| `key-mapping.preset` | picker | `qwerty` / `dvorak` / `colemak`
| `key-mapping.key-notation-to-key-code` | rows: notation -> key code | notation must contain no whitespace and no `-`
| `exec.inherit-env-vars` | toggle |
| `exec.env-vars` | rows: name -> value | `PWD` is rejected by the parser; the UI blocks it too
|===

Deprecated keys — `after-login-command`,
`non-empty-workspaces-root-containers-layout-on-startup`,
`indent-for-nested-containers-with-the-same-orientation` — get no control. If
present in the file they are preserved untouched like any other unknown block.

=== Raw-TOML panes (command DSL)

[cols="1,1"]
|===
| Pane | Owns these blocks

| Keybindings | every `[mode.*]` / `[mode.*.binding]` table
| Window rules | every `[[on-window-detected]]` array-of-tables entry
| Callbacks | `after-startup-command`, `on-focus-changed`, `on-mode-changed`, `on-focused-monitor-changed`, `exec-on-workspace-change`
|===

Each pane is a monospaced `TextEditor` seeded with the exact source text of its
blocks, with a parse-status line beneath it.

== Architecture

Three units, each usable and testable on its own.

=== 1. `TomlBlockDocument` — pure text model

`Sources/AppBundle/config/TomlBlockDocument.swift`. No dependency on SwiftUI or
on `Config`.

Parses config text into an ordered `[Block]`. A block is either:

* `keyValue(key: String, text: String)` — a top-level `key = value` line, plus
  any continuation lines of a multi-line array/inline table
* `table(header: String, text: String)` — a `[table]` or `[[array.of.tables]]`
  header and everything up to the next top-level header
* `trivia(text: String)` — leading comments and blank lines, attached as their
  own block before the block they precede

This is a line-oriented scan, not a TOML parser: TOML guarantees that a line
starting with `[` at bracket depth zero opens a table, and that a top-level key
starts at the beginning of a line. Values are never interpreted — they are
carried as verbatim text. That is what makes round-tripping exact and keeps the
unit small.

API:

* `init(_ text: String)`
* `func render() -> String` — joins blocks; for unmodified input, byte-identical
  to the input
* `func text(forKeyValue key: String) -> String?` and
  `func text(forTablesMatching: (String) -> Bool) -> String`
* `mutating func set(key: String, tomlValue: String)` — replaces the value of an
  existing `keyValue` block in place, or appends a new block at the end of the
  top-level key region (before the first table header, so the file stays valid
  TOML)
* `mutating func remove(key: String)` — used when a form control returns to its
  default and the key was absent originally
* `mutating func replaceTables(matching: (String) -> Bool, with text: String)` —
  splices a raw pane's text over the span its blocks occupy, preserving position

Value serialisation is a handful of tiny helpers next to it (`Bool`, `Int`,
`String`, string array, per-monitor array). Nothing generic — each is two lines.

=== 2. `SettingsModel` — draft state

`Sources/AppBundle/ui/settings/SettingsModel.swift`, `@MainActor`,
`ObservableObject`.

Holds: the source config URL, the file's modification date at load time, a
`TomlBlockDocument`, the parsed `Config` the form binds to, the three raw pane
strings, and `isDirty` / `errorMessage`.

`load()` reads the config file (resolved by the existing `findCustomConfigUrl()`)
and parses it both ways: through `parseConfig` for the form values and through
`TomlBlockDocument` for the text. When no custom config exists, it loads the
bundled `default-config.toml` text and remembers that the first save must create
`~/.aerospace-edge.toml`.

Each form control binds to a computed `Binding` that writes the typed value into
the draft `Config` and calls `document.set(key:tomlValue:)`. Keys absent from the
file and left at their default stay absent — the window does not bloat the config
with every default on first save.

=== 3. Views

`Sources/AppBundle/ui/settings/`:

* `SettingsWindow.swift` — the `Scene` (id `settingsWindowId`), a
  `NavigationSplitView` with a category sidebar and a Save / Revert footer
* `SettingsSections.swift` — the form sections: General, Layout, Gaps, Focus,
  Window Border, Workspaces & Monitors, Key Mapping, Exec
* `SettingsRawSection.swift` — the shared raw-TOML pane view, used three times

`MenuBar.swift` gains a `Settings…` item under the existing `Settings` group
label that calls `openWindow(id: settingsWindowId)`, alongside the existing
`Open config` and `Reload config` items, which stay.

macOS convention is a settings *window* rather than a sheet; nothing about the
feature requires it to be truly modal.

== Save flow

. `document.render()` produces candidate text.
. Write candidate to a temp file in `FileManager.default.temporaryDirectory`.
. `readConfig(forceConfigUrl: tempUrl)` — the real parser, the real error
  messages. On `.failure`, show the message in the window footer, keep the window
  open, keep the draft, delete the temp file, stop.
. Compare the config file's current modification date against the one captured at
  load. If it changed, ask before overwriting (Overwrite / Reload and discard my
  changes / Cancel).
. Write candidate text to the real config URL, creating
  `~/.aerospace-edge.toml` if no custom config existed.
. `try await reloadConfig()`.
. Reset `isDirty`, re-capture the modification date, re-`load()` so the document
  and form reflect exactly what is on disk.

Validating a temp file before touching the real one means a bad edit can never
leave the user with a config AeroSpace refuses to load. Reusing `readConfig`
rather than re-implementing validation means the window can never disagree with
the parser.

`auto-reload-config` users will see the file watcher fire on the write; the
subsequent explicit `reloadConfig()` is idempotent, so this is harmless.

== Edge cases

* *Ambiguous config* (`findCustomConfigUrl()` returns `.ambiguousConfigError`) —
  the window opens read-only with the existing ambiguity message and a button to
  reveal the candidates in Finder. It must not guess which file to write.
* *Unparseable config on open* — the form cannot be populated. Open with only the
  raw panes available, seeded from the whole file text, plus the parse error. The
  block document does not need a valid TOML to split blocks.
* *Config edited externally while the window is open* — handled by the
  modification-date check at step 4, not by watching. No live merge.
* *Raw pane containing keys that belong to another pane* — the validation step
  catches duplicate-key TOML syntax errors; no extra checking in the UI.
* *Colour round-trip* — `focused-window-border-color` is a `String` in `Config`,
  parsed elsewhere. The picker converts to and from `0xAARRGGBB`; a value the
  picker cannot represent is shown in a text field instead of being silently
  rewritten.

== Testing

`Sources/AppBundleTests/config/TomlBlockDocumentTest.swift` — the block document
is pure logic and carries the whole test burden:

* round-trip: `TomlBlockDocument(text).render() == text` for
  `docs/config-examples/default-config.toml` and every file in
  `docs/config-examples/`
* `set` on an existing scalar replaces only that value; comments on the same and
  surrounding lines survive
* `set` on an absent key appends it before the first table header
* `remove` on an absent key is a no-op
* `replaceTables` over `[mode.*]` splices in place and leaves neighbouring
  tables and their comments untouched
* an unknown top-level key and an unknown table survive a `set` on an unrelated
  key

Value serialisation helpers get one assertion each.

The SwiftUI layer and the save flow's file I/O are runtime behaviour, tested by
hand rather than faked — stated explicitly rather than papered over with a mock.

== Documentation

No command, flag, config option, or format variable changes, so most of the
`CLAUDE.md` command checklist does not apply. What does:

* `docs/guide.adoc` — a short subsection under configuring AeroSpace noting the
  settings window, that it writes the same config file, and that keybindings and
  callbacks are edited as TOML inside it
* `CHANGELOG-FORK.md` — a fork-feature entry

== File map

New:

* `Sources/AppBundle/config/TomlBlockDocument.swift`
* `Sources/AppBundle/ui/settings/SettingsModel.swift`
* `Sources/AppBundle/ui/settings/SettingsWindow.swift`
* `Sources/AppBundle/ui/settings/SettingsSections.swift`
* `Sources/AppBundle/ui/settings/SettingsRawSection.swift`
* `Sources/AppBundleTests/config/TomlBlockDocumentTest.swift`

Modified:

* `Sources/AppBundle/ui/MenuBar.swift` — the `Settings…` item
* `Sources/AeroSpaceApp/AeroSpaceApp.swift` — register the settings scene
* `docs/guide.adoc`, `CHANGELOG-FORK.md`

Done means `./build-debug.sh -Xswiftc -warnings-as-errors` and `./swift-test.sh`
both pass with a clean tree afterwards.
