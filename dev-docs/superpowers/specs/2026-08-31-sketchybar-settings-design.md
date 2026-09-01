# Sketchybar management in the Settings window

Date: 2026-08-31
Status: Draft — under review

## Objective

Give the Settings window a `Sketchybar` destination that composes a status bar from a
catalog of items, orders them by dragging, and manages their colors, padding and icons —
without the user writing a line of sketchybar config.

The page owns a declarative bar description and generates sketchybar's config from it.
Sketchybar itself stays what it is today: a separate Homebrew install that AeroSpace-edge
configures but does not replace. This is deliberate. AeroSpace-edge does not gain a status
bar renderer, a widget runtime, or responsibility for drawing pixels at the top of the
screen; it gains a config generator and a controller.

## Scope

The work is four features and is specified in stages. This document specifies **stage 1**
in full and names the rest so their boundaries are fixed now rather than discovered later.

1. **Stage 1 (this spec).** The `bar.toml` model, the item catalog, the config generator,
   the takeover/backup behavior, and a Settings page that edits the model as ordered lists.
2. **Stage 2.** The chip strip: three drop zones with drag-and-drop, and live push to a
   running sketchybar so the real bar updates as the user drags.
3. **Stage 3.** Profiles — named workspace groups with per-profile item overrides.
4. **Stage 4.** Helper binaries for volume, brightness and bluetooth, and the theme
   switcher covering bar and window-border colors.

Stage 1 is user-visible and shippable on its own: a user can build a working bar from the
catalog and save it. Stages 2–4 each add capability to a page that already works.

Sections below marked **(stage N)** describe a later stage's contract where stage 1 has to
be built so as not to preclude it. Everything else is stage 1.

## File ownership

Three files, with one direction of flow between them.

```
~/.config/aerospace/bar.toml        source of truth, app-owned, hand-editable
        │
        ▼  generation
~/.config/sketchybar/sketchybarrc   generated, app-owned, never read back
        │
        ▼  sketchybar reads it
   the bar on screen
```

### Why not `~/.aerospace.toml`

The bar description is not AeroSpace configuration. Putting it in the main config would
roughly double `ConfigTomlWriter.ConfigDraft`, pull a bar schema into the `config-version`
compatibility surface, and mean that every future catalog item is a change to the window
manager's config language. `bar.toml` is a separate document with a separate version
integer, parsed with the TOML decoder the project already links.

Like `~/.aerospace.toml`, `bar.toml` travels between machines and is meaningful on any of
them, so it is a config file and not a `UserDefaults` app preference.

### Why the generated file is shell, not Lua

Sketchybar's native config language is a shell script of `sketchybar` invocations. The
user's existing configuration may be Lua via SbarLua, but a *generated* config has no
reason to require luarocks, a Lua interpreter, and a C module. The generator emits
`#!/bin/sh`, which sketchybar runs with no dependency beyond itself.

### The managed header

Every generated `sketchybarrc` begins with:

```sh
#!/bin/sh
# Managed by AeroSpace-edge. Generated from ~/.config/aerospace/bar.toml.
# Edits to this file are overwritten on the next save.
# aerospace-edge-generated: 1
```

The `aerospace-edge-generated:` line is the marker the takeover check reads. Its integer is
the generator format version, so a future generator can recognise a file it wrote under an
older scheme.

## Takeover and backup

Sketchybar users have an existing config. The user driving this design has 3,485 lines of
Lua. The page must never destroy it silently.

On the first save that would write `sketchybarrc`:

- **File absent.** Write it. Report that the config was created.
- **File present with the marker.** Overwrite without ceremony. This is the steady state.
- **File present without the marker.** Copy it to
  `~/.config/sketchybar/sketchybarrc.backup-<yyyy-MM-dd-HHmmss>`, then write. Report the
  backup path in the Settings status line, and keep reporting it until the user dismisses
  it.

`SettingsModel` already does exactly this for config-version migration through its injected
`backupCreator`, and the same seam is used here rather than a second backup implementation.

A Lua config typically also has `~/.config/sketchybar/*.lua` and `helpers/` beside it. Those
are left untouched. Only `sketchybarrc` is claimed, so a user who reverts by restoring the
backup gets their whole setup back.

## `bar.toml`

```toml
# Managed by AeroSpace-edge. Regions the Settings window did not touch are
# preserved byte-for-byte, in the same way ~/.aerospace.toml is.
version = 1

[bar]
height = 32
margin = 8
y-offset = 6
corner-radius = 10
border-width = 1
padding-left = 1
padding-right = 0

[bar.colors]
background = '0xb3202020'
border = '0x35e2e2e3'
label = '0xffeeeeee'
icon = '0xffeeeeee'
accent = '0xff717ebb'
popup-background = '0xc02c2e34'
popup-border = '0xff7f8490'

[[item]]
id = 'workspaces'
cluster = 'left'
[item.settings]
show-app-icons = true
per-monitor = true

[[item]]
id = 'clock'
cluster = 'right'
[item.settings]
format = '%a %d %b %H:%M'
```

**Ordering is document order.** The position of an item within its cluster is the order of
its `[[item]]` table among the entries sharing that `cluster`. There is no index field to
keep consistent, and a drag in the UI is a reordering of the array. `cluster` is
`left`, `center` or `right`, mapping to sketchybar's own three positions.

`[item.settings]` is a per-item table whose keys are defined by the catalog entry, not by
this schema. An unknown key is preserved on save and reported in the UI as unrecognised
rather than dropped — the same tolerance the main config editor extends to blocks it does
not model.

Colors are `0xAARRGGBB` strings, matching sketchybar's own format and the existing
`focused-window-border-color` convention in `~/.aerospace.toml`.

### Profiles (stage 3)

Profiles are additive to the schema above and change nothing already written:

```toml
[[profile]]
name = 'Work'
workspaces = ['1', '2', '3', 'C', 'S']
show = ['meeting', 'cpu']
hide = ['media']
```

A profile owns a set of workspaces and overrides the visibility of named items. Items are
global and declared once; `show` and `hide` list only the exceptions, so shared items such
as the clock are never repeated per profile. A workspace named by no profile belongs to
every profile.

## The catalog

The catalog is a fixed table compiled into the app, versioned with the generator. Each entry
declares an id, a display name, a default cluster, the icons it can use, the settings keys
it accepts, and its runtime requirement.

| Group | Items | Requires |
| --- | --- | --- |
| AeroSpace | `workspaces`, `front-app`, `mode`, `floats` | the `aerospace` CLI |
| System | `battery`, `clock`, `cpu`, `network`, `weather` | shell built-ins and `/usr/sbin` tools |
| Privileged | `volume`, `brightness`, `bluetooth` | a bundled helper binary (stage 4) |
| macOS | `apple-menu`, `secure-input` | AppleScript |
| Escape hatch | `custom` | a user-supplied script path |

`floats` is worth naming explicitly because it is not a generic status item: macOS z-orders
windows per application, so a floating window sinks behind whichever app is focused next and
cannot be raised without a private window-level call. The item appears only while the
focused workspace holds floating windows, and clicking it focuses the next one. It is the
only way back to a sunken float.

`custom` exists so the catalog being fixed is not a ceiling. It takes a script path, an
update frequency, and a list of events to subscribe to, and is generated as an ordinary
sketchybar item.

**Icons** are chosen from a fixed list per item, drawn from the sfsymbols and
`sketchybar-app-font` sets. The catalog names which font each icon needs so the generator
can emit the right `icon.font`, and the page can warn when a required font is not installed.

**Privileged items are unavailable until stage 4** and are listed in the catalog as such:
visible in the picker, disabled, with a popover explaining that they need a helper binary
that ships in a later release. They are not silently missing.

## The backend boundary

Everything above this line — `bar.toml`, the catalog, item settings, the Settings page,
the help topics, the documentation — is independent of how the bar is actually drawn. Only
the renderer differs. That boundary is made explicit rather than left implicit:

```
BarDraft ──▶ BarBackend
              ├─ SketchybarBackend   generate a config, --reload, live push
              └─ (a native renderer, if one is ever warranted)
```

`BarBackend` is the protocol the Settings page talks to. It answers whether it is available,
applies a saved draft, and — for stage 2 — applies an individual mutation for live preview.
It is the only component that knows sketchybar exists.

This is not a prediction that a native bar will be built. It is an acknowledgement that the
question is open, that the evidence to settle it does not exist yet, and that the cost of
keeping it open is one protocol declaration. Two observations frame the eventual decision:

- Stages 1 and 2 are largely overhead that exists only because there is a foreign process to
  configure. Config generation, the marker header, takeover, item namespacing, live-push
  IPC and scratch-state reconciliation would all be deleted by a native renderer, and the
  hardest problem in this design — preview fidelity — would not exist, because the preview
  would be the renderer.
- Against that: a *configurable* bar is a substantially larger product than a fixed one, and
  it would make AeroSpace-edge permanently a status-bar project as well as a window manager,
  in a fork whose maintenance case rests on staying cheap to sync with upstream.

**The trigger to revisit is a catalog item sketchybar cannot express.** That is evidence.
Until one appears, a native renderer is a rewrite justified by taste, and the boundary below
costs nothing to maintain in the meantime.

One argument that does *not* survive stage 1 and should not be reached for later: memory.
The generated config is `sh`, so SbarLua never loads and the Lua interpreter process — the
largest single process in a hand-written Lua setup — disappears as soon as this ships.
Sketchybar itself is comparatively small.

## Generation: the sketchybar backend

`BarConfigGenerator` is a pure function from a parsed `BarDraft` to the bytes of
`sketchybarrc`, and is the substance of `SketchybarBackend`. It performs no I/O, reads no
environment, and resolves no paths itself — absolute paths to bundled helpers are passed in.
This is what makes it testable against golden files, and it is the component that carries
the most risk of silent breakage, so it is the component that must be trivially testable.

Emission order is fixed and deterministic:

1. Header and marker.
2. `sketchybar --bar` from `[bar]` and `[bar.colors]`.
3. `sketchybar --default` for the shared label/icon font and color.
4. Items, in cluster order `left`, `center`, `right`, and document order within each.
   Each item emits its `--add`, then `--set`, then `--subscribe` if it takes events.
5. Brackets, for items the catalog groups visually.
6. A final `sketchybar --update`.

**Item names are namespaced `aerospace.<id>`.** A leftover item from a user's previous
config can then never collide with a generated one, and `--remove` during live editing
(stage 2) can never delete something the app did not create.

## The Settings page

A new `SettingsCategory.sketchybar` destination, placed after `Menu Bar` in the sidebar,
with the `menubar.rectangle` system image.

### Stage 1 layout

Three sections, following the existing `SettingsListSections` patterns:

- **Bar** — height, margin, y-offset, corner radius, border width, padding. Colors as
  color wells, using `SettingsColorUtils` for the `0xAARRGGBB` round trip.
- **Items** — three reorderable lists, one per cluster, with an `Add item` menu sourced from
  the catalog. Each row expands to that item's settings, built from its catalog entry.
  Reordering is SwiftUI's list `onMove`; there is no visual bar rendering in stage 1.
- **Status** — whether sketchybar is installed and running, the resolved config path, and
  the takeover/backup message when one applies.

Save and Revert use the existing footer. Save writes `bar.toml` atomically through the
model's `atomicWriter` seam, generates `sketchybarrc` atomically, and then runs
`sketchybar --reload`. A failure to reload is reported but does not roll back the files;
the config on disk is correct and the user can reload manually.

If sketchybar is not installed, the page still edits and saves. It reports that nothing will
render until sketchybar is installed, and does not attempt the reload.

### Chip strip and live push (stage 2)

The three lists gain a strip above them: one chip per item in three drop zones. Dragging a
chip between or within zones mutates the same ordered arrays the lists edit.

While sketchybar is running, each mutation is pushed immediately to the running bar rather
than rendered locally: a reorder becomes `sketchybar --reorder aerospace.a aerospace.b …`,
an add becomes `--add` plus `--set`, a removal becomes `--remove`, and a color or padding
change becomes `--set` or `--bar`. The bar at the top of the screen is the preview.

This is the reason the page does not contain a sketchybar layout engine. Fidelity comes
from the renderer that is already running, and there is no second implementation of
sketchybar's padding and font metrics to drift out of sync.

Live push puts the running bar into a **scratch state** that does not match any file. The
page tracks that state and restores it on exit: cancelling, reverting, or closing the window
with unsaved changes regenerates from the last-saved `bar.toml` and reloads. Saving writes
the files and reloads, which reconciles scratch state with disk by construction.

With sketchybar not running, the chips still drag and the strip still reorders; only the
push is skipped.

### Profile runtime (stage 3)

The generated config contains no profile logic and no dispatcher script. AeroSpace-edge
knows which workspace is focused, so it drives profile switching directly: on a focus change
that crosses into a workspace belonging to a different profile, it runs a single
`sketchybar --set` batch toggling `drawing` on the items the two profiles differ by, and
sets the workspace item's filter.

This is a simplification over the shape a Lua config is forced into. A Lua implementation
must subscribe to workspace events, hold its own notion of the active profile, and infer
switches from focus. The app *is* the source of focus truth and can push the answer, so the
inference and the state machine both disappear.

## Documentation

Per the Settings window checklist in `CLAUDE.md`, the new destination requires all of:

- `docs-md/settings/sketchybar.md`, documenting every control, its `bar.toml` key, allowed
  values, and the takeover/backup behavior.
- A `mkdocs.yml` nav entry and a row in the table in `docs-md/settings/index.md`.
- A `SettingHelpTopic` for every control in `SettingsHelp.swift`, labelled with
  `SettingHelpLabel`.

Two of this page's controls are genuinely not config options and must be listed in
`SettingsHelpTest.appPreferenceTopics` rather than given a TOML key: the install/running
status readout and the manual `Reload sketchybar` action. Everything else names a
`bar.toml` key.

Items whose settings are a structure — the `clock` format string, `custom`'s event list,
every color — must fill `examples:` with concrete correct lines, not a description of the
format.

## Testing

- **`BarConfigGeneratorTest`** — golden files. A set of `bar.toml` inputs and their exact
  expected `sketchybarrc` bytes, covering an empty bar, one item per catalog group, all
  three clusters, and a `custom` item. This is the highest-value test in the change: the
  generator is a pure function, needs no sketchybar, and is where a regression would
  otherwise reach the user's screen before it reached a test.
- **`BarTomlDocumentTest`** — round trip. Parsing a `bar.toml` and writing it back with no
  edits produces identical bytes, including unrecognised keys and comments.
- **`BarCatalogTest`** — every catalog entry has a help topic, at least one icon, a valid
  default cluster, and settings keys that the generator handles. Mirrors how
  `SettingsHelpTest` already polices the Settings window.
- **`SettingsHelpTest`** — extended for the new category, which its existing assertions
  cover once the docs page exists: every control has a topic, every topic has a TOML key or
  is declared an app preference, and `docsUrl` resolves to a file that exists.
- **Takeover** — `SettingsModel`-level tests over the injected `backupCreator` and
  `atomicWriter`: marker absent creates a backup, marker present does not, and a failed
  backup aborts the save without writing.

**Not unit-tested, deliberately:** the live-push path and the profile-switch push are IPC
against a running sketchybar process. They are runtime behavior with no seam that a test
could observe without a real bar on a real screen, and faking one would test the fake.
Stage 2 and stage 3 carry a manual verification checklist instead.

## Out of scope

- **Replacing sketchybar.** No stage in this document draws a bar. `BarBackend` keeps a
  native renderer possible without committing to one; see "The backend boundary" for the
  evidence that would justify revisiting it.
- **Importing an existing config.** Parsing a user's Lua or shell config into `bar.toml` is
  not attempted. Takeover backs the old config up; it does not read it.
- **Wallpaper.** The stage 4 theme switcher covers bar colors and the window-border color.
  Wallpaper is a separate concern with its own file management and its own permissions, and
  it is not part of this page.
- **Brightness below the hardware minimum.** Scaling display gamma to dim past zero is a
  global mutation of the display that must be restored on crash and on uninstall. The
  `brightness` item in stage 4 covers the ordinary DisplayServices range only.
- **Per-display bar configuration.** One bar description applies to every display. The
  existing per-monitor gap syntax in `~/.aerospace.toml` is not mirrored here.
