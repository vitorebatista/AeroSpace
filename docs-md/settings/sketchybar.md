# Sketchybar

**Where:** menu bar → **Settings…** → **Sketchybar**

Compose a status bar from a catalog of items — no sketchybar config written by hand.

[sketchybar](https://github.com/FelixKratz/SketchyBar) stays what it is: a separate Homebrew
install that AeroSpace-edge *configures* rather than replaces. This page does not draw a bar;
it writes a description of one and generates sketchybar's config from it.

## The two files

```
~/.config/aerospace/bar.toml        source of truth — yours, hand-editable
        │  generated on every Save
        ▼
~/.config/sketchybar/sketchybarrc   generated, overwritten, never read back
```

`bar.toml` is a config file, not an app preference: like `~/.aerospace-edge.toml` it travels
between machines and is meaningful on any of them. It is **not** part of your AeroSpace config
— it has its own `version` integer and its own schema, so a new catalog item is never a change
to the window manager's config language. `XDG_CONFIG_HOME` is honoured if it is set.

Everything on this page except the status readout and **Reload** writes a `bar.toml` key.
Nothing is written until you press **Save** in the window footer; **Revert** re-reads the file.

Regions of `bar.toml` this page did not touch — comments, key order, keys it does not model —
come back byte for byte, in the same way `~/.aerospace-edge.toml` does. The one exception is
the `[[item]]` region: an item edit is a change to an ordered array, so that region is
regenerated whole and comments inside it are not preserved. Keys inside `[item.settings]`
survive regardless, including keys this release does not recognise.

If `bar.toml` does not parse, the page shows the parser's message and refuses to save. Writing
a defaulted form over a file that could not be read would destroy it. Fix the file in an
editor and press **Revert**.

## Bar

Geometry of the bar itself, in points. A margin, a y-offset and a corner radius together are
what make a bar look detached from the top of the screen rather than glued to it.

### Height

**TOML** `bar.height` · **values** integer, `0…200` in the UI · **default** `32`

### Margin

Empty space left around the bar.

**TOML** `bar.margin` · **values** integer, `0…100` in the UI · **default** `8`

### Y offset

Distance from the top of the screen. `0` puts the bar flush against the menu bar.

**TOML** `bar.y-offset` · **values** integer, `-100…100` in the UI · **default** `6`

### Corner radius

Rounds the bar's corners. Only visible when the bar is inset by a margin.

**TOML** `bar.corner-radius` · **values** integer, `0…60` in the UI · **default** `10`

### Border width

Outline thickness, drawn in the border colour. `0` removes the outline.

**TOML** `bar.border-width` · **values** integer, `0…20` in the UI · **default** `1`

### Padding

Space between the bar's own edge and its first and last item. Left and right are independent.

**TOML** `bar.padding-left`, `bar.padding-right` · **values** integer, `0…100` in the UI ·
**default** `1` and `0`

## Colours

Every colour is a `0xAARRGGBB` string — alpha, red, green, blue — which is sketchybar's own
spelling and the same one `focused-window-border-color` uses. The colour well writes back
exactly that representation. A value the picker cannot represent stays a plain text field
instead of being silently rewritten.

| Control | TOML | Default |
|---|---|---|
| Background | `bar.colors.background` | `0xb3202020` |
| Border | `bar.colors.border` | `0x35e2e2e3` |
| Label | `bar.colors.label` | `0xffeeeeee` |
| Icon | `bar.colors.icon` | `0xffeeeeee` |
| Accent | `bar.colors.accent` | `0xff717ebb` |
| Popup background | `bar.colors.popup-background` | `0xc02c2e34` |
| Popup border | `bar.colors.popup-border` | `0xff7f8490` |

Examples: `0xb3202020` is near-black at 70% alpha, `0xffeeeeee` is opaque near-white,
`0x80ffffff` is white at 50% alpha.

## Items

Three lists, one per position on the bar: **Left**, **Centre**, **Right**. These are
sketchybar's own three positions.

**Order is document order.** A list's order is the order its items are drawn in, and it is the
order the `[[item]]` tables appear in `bar.toml`. There is no index key to keep consistent.
Drag a row inside its list to reorder it.

**Add item** lists the whole catalog, grouped. Adding an item appends it to the end of that
list, seeded with the catalog's defaults so the file states what is in effect rather than
implying it. The minus button removes a row; the disclosure triangle opens that item's own
settings.

**TOML** `item`, `item.id`, `item.cluster` — one `[[item]]` table per row:

```toml
[[item]]
id = 'workspaces'
cluster = 'left'

[item.settings]
show-app-icons = true
per-monitor = true
```

`cluster` is `left`, `center` or `right`.

### The catalog

| Group | Items | Needs |
|---|---|---|
| AeroSpace | `workspaces`, `front-app`, `mode`, `floats` | the `aerospace-edge` CLI |
| System | `battery`, `clock`, `cpu`, `network`, `weather` | shell built-ins and `/usr/sbin` tools |
| Privileged | `volume`, `brightness`, `bluetooth` | a bundled helper binary — **not in this release** |
| macOS | `apple-menu`, `secure-input` | AppleScript |
| Escape hatch | `custom` | a script of your own |

`floats` is worth calling out: macOS z-orders windows per application, so a floating window
sinks behind whichever app is focused next and cannot be raised by ordinary means. The item
appears while the focused workspace holds floating windows, and clicking it focuses the next
one. It is the way back to a sunken float.

`custom` is why a fixed catalog is not a ceiling: it takes a script path, an update frequency
and a list of events, and is generated as an ordinary sketchybar item.

**Privileged items are listed but disabled.** They need a helper binary that ships in a later
release. They stay in the picker so their place in the bar is known, rather than being
silently missing; hovering one explains why it will not take a click.

### Item settings

Each row opens onto the keys that item accepts, written under its own `[item.settings]` table.
The controls come from the catalog, so each one carries its own help — hover the ⓘ for the
key's meaning, its default, and worked examples for the ones you have to type.

A few worth knowing:

- **Clock → Format** (`format`) is a strftime string passed to `date`, e.g.
  `%a %d %b %H:%M` → `Mon 31 Aug 22:15`, `%H:%M` → `22:15`.
- **Custom script → Events** (`events`) is typed **comma-separated** in the UI and stored as a
  TOML list, e.g. `front_app_switched, space_change, system_woke`.
- **Workspaces → Focused colour** (`focused-color`) is a `0xAARRGGBB` string like every other
  colour here.

**Keys this release does not recognise are kept.** A key written by a newer AeroSpace-edge, or
by your own hand, is listed under the item as unrecognised and written back unchanged rather
than dropped. The same is true of an entire item whose `id` is not in the catalog.

## Status

Not config options — nothing here touches your TOML.

### sketchybar

Whether sketchybar is installed, and the path of the `bar.toml` this page writes. Without
sketchybar the page still edits and saves; it just tells you that nothing renders yet. Install
it with `brew install sketchybar`.

### Reload sketchybar

Regenerates sketchybar's config from the **last saved** `bar.toml` and reloads it — not from
unsaved edits. Save already does this; use the button after starting sketchybar by hand, or
when something else has overwritten its config.

## Takeover and backup

Sketchybar users already have a config, often a large one. This page never destroys it
silently. On a Save that would write `~/.config/sketchybar/sketchybarrc`:

- **The file doesn't exist** → it is created.
- **The file was generated by AeroSpace-edge** (it carries the `aerospace-edge-generated:`
  marker in its header) → it is overwritten without ceremony. This is the steady state.
- **The file is yours** → it is copied to
  `~/.config/sketchybar/sketchybarrc.backup-<yyyy-MM-dd-HHmmss>` first, and the Status group
  reports the backup path. **That message stays until you dismiss it**, because it names the
  only remaining copy of your config.

Only `sketchybarrc` is claimed. A Lua setup's `*.lua` files and `helpers/` beside it are left
untouched, so restoring the backup gets your whole setup back.

A failed reload is reported but nothing is rolled back: what is on disk is correct, and the
**Reload sketchybar** button retries it. A failed *write* stops before sketchybar is touched,
so the bar is never reloaded from a draft that was not saved.
