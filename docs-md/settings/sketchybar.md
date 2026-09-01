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

Everything on this page except the status readouts and **Reload** writes a `bar.toml` key.
Nothing is written until you press **Save** in the window footer; **Revert** re-reads the file.
While sketchybar is running your edits *are* pushed to the bar on screen as you make them — see
[Live preview](#live-preview) — but never to a file.

Regions of `bar.toml` this page did not touch — comments, key order, keys it does not model —
come back byte for byte, in the same way `~/.aerospace-edge.toml` does. The exceptions are the
`[[item]]` and `[[profile]]` regions: an edit to either is a change to an ordered array, so the
region is regenerated whole and comments inside it are not preserved. Keys inside
`[item.settings]` survive regardless, including keys this release does not recognise.

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

### Theme

**Apply theme** sets all seven colours below at once, and the focused window's border with
them. Themes shipped: **Default**, **Tokyo Night**, **Gruvbox Dark**, **Nord**,
**Catppuccin Mocha**, **Light**.

A theme is a palette, not a stored setting. There is no `theme` key in `bar.toml`: which theme
is in effect is worked out from the colours, so the row reads **Custom** the moment you change
one of them and nothing goes on claiming a theme it no longer matches.

The window border is the one part of a theme that is **not** in `bar.toml` —
`focused-window-border-color` belongs to your AeroSpace config. **Save on this page therefore
writes both files.** Half a theme on disk is worse than none, so Save and Revert here act on
whichever of the two has unsaved changes. If you have edits pending on other Settings pages,
those are saved too.

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

### Layout strip

Above the lists is a strip of chips — one per item, in three drop zones laid out the way the
bar is. Drag a chip onto another chip to drop it in front of that one, or onto a zone's empty
space to append it to the end of that position. A drag between zones moves the item's
`cluster`; a drag within one reorders it.

The strip and the lists edit the same array, so they can never show different orders. It is a
**schematic**, not a rendering: it says what sits where, not what sketchybar will draw. Nothing
here reproduces sketchybar's fonts, padding or metrics — the preview below is the real bar.

A chip drawn with a dashed orange outline will not render yet: either it is a **privileged**
item waiting on a helper binary that ships in a later release, or it is an item whose `id` this
release does not recognise. It still drags, and its place in the bar is still written to
`bar.toml`.

**Order is document order.** A list's order is the order its items are drawn in, and it is the
order the `[[item]]` tables appear in `bar.toml`. There is no index key to keep consistent.
Drag a row inside its list to reorder it, or drag its chip in the strip above.

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
| Privileged | `volume`, `brightness`, `bluetooth` | AppleScript; `brightness`; `blueutil` |
| macOS | `apple-menu`, `secure-input` | AppleScript |
| Escape hatch | `custom` | a script of your own |

`floats` is worth calling out: macOS z-orders windows per application, so a floating window
sinks behind whichever app is focused next and cannot be raised by ordinary means. The item
appears while the focused workspace holds floating windows, and clicking it focuses the next
one. It is the way back to a sunken float.

`custom` is why a fixed catalog is not a ceiling: it takes a script path, an update frequency
and a list of events, and is generated as an ordinary sketchybar item.

### Items that need a command

Three items reach past what AeroSpace-edge and a shell can answer on their own.

| Item | Needs | Install | Without it |
|---|---|---|---|
| `volume` | nothing — AppleScript | — | always works |
| `brightness` | the `brightness` command | `brew install brightness` | a comment in the generated config |
| `bluetooth` | the `blueutil` command | `brew install blueutil` | a comment in the generated config |

**Nothing is bundled.** Shipping an executable inside the app would put a second binary through
codesigning and the fork's release pinning for one item's worth of capability, so these are
ordinary Homebrew installs, found on `PATH` the same way sketchybar itself is. The **Status**
group lists any that are missing, with the command that installs them.

An item whose command is missing is **still addable**: `bar.toml` travels between machines, and
the one that renders it may not be the one you are editing on. It simply does not reach the
generated config — a comment naming the tool goes where the item would have been, exactly as it
does for a `custom` item with no script path.

- **Volume** reads and sets the output volume through AppleScript. Click toggles mute; scroll
  changes the level by `step`. It follows sketchybar's own `volume_change` event, so it costs
  nothing between changes.
- **Brightness** goes through the `brightness` command over the ordinary hardware range.
  Scroll changes it by `step`, never below 1% — a display at zero is a display you cannot find
  the item on to scroll back up. There is no brightness event, so it polls on `update-freq`.
- **Bluetooth** shows the controller's power state and toggles the radio on click. It needs
  `blueutil` for both: the power state used to be readable from
  `/Library/Preferences/com.apple.Bluetooth`, and on current macOS that key is simply gone.
  `system_profiler SPBluetoothDataType` still answers and takes over a second, which is not a
  price a bar item can pay on a timer.

A scroll is read for its **direction only**. sketchybar reports the raw wheel delta, and that
differs by an order of magnitude between a mouse and a trackpad; how far one notch goes is the
item's `step`.

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

## Profiles

A profile is a named group of workspaces with its own set of bar items. Focus a workspace the
profile owns and the bar becomes that profile's bar.

```toml
[[profile]]
name = 'Work'
workspaces = ['1', '2', 'C']
hide = ['weather']

[[profile]]
name = 'Play'
workspaces = ['9']
show = ['cpu']
```

Items are still declared once, in `[[item]]`. A profile lists only the exceptions, so a shared
item such as the clock is never repeated per profile.

### Workspaces

`profile.workspaces` — the workspaces this profile owns, typed **comma-separated** and stored
as a TOML list. Names are matched exactly as they are written in `~/.aerospace-edge.toml`.

A workspace listed by two profiles belongs to the first one written. A workspace **no** profile
names belongs to every profile: its bar draws everything any profile would draw.

While a profile is active the **Workspaces** item lists only that profile's workspaces, so the
bar shows the group rather than every workspace on the machine.

### Items drawn

One switch per item, writing `profile.show` and `profile.hide`.

- Every item is drawn unless a profile **hides** it. Turning a switch off writes the item to
  that profile's `hide`.
- **Showing** an item in one profile makes it opt-in *everywhere*: it then appears only in the
  profiles that list it under `show`. That is how an item belongs to a single profile without
  every other profile having to hide it.
- Turning off the last profile that showed an item makes it an ordinary item again, and it goes
  back to being drawn everywhere.

Two items with the same `id` — two `custom` scripts, say — share one switch. `bar.toml` gives an
item no identity beyond its id.

### How switching works

AeroSpace-edge already knows which workspace is focused, so it pushes the switch itself: when
focus crosses into a workspace another profile owns, it sends one sketchybar command turning
the differing items' `drawing` on and off. The generated `sketchybarrc` contains **no profile
logic and no dispatcher script**, and a Lua config's usual workspace-event subscription and
active-profile state machine are not needed.

The generated file always describes the *shared* bar — the generator cannot know which
workspace is focused — and the active profile is pushed over the top of it at startup and on
every crossing.

While the Settings window is open the bar shows every item, whichever profile you are in, so
you can see what you are editing. It returns to the profile on the next workspace change.

## Status

Not config options — nothing here touches your TOML.

### sketchybar

Whether sketchybar is installed, and the path of the `bar.toml` this page writes. Without
sketchybar the page still edits and saves; it just tells you that nothing renders yet. Install
it with `brew install sketchybar`.

Any [item command](#items-that-need-a-command) that is not installed is listed here with the
command that installs it.

### Live preview

While sketchybar is running, every edit on this page is pushed straight to the bar at the top
of the screen — a drag reorders the real items, a colour change repaints the real bar. **No
file is written.** This is why the strip is schematic: fidelity comes from the renderer that is
already drawing, so there is no second implementation of sketchybar's metrics to drift.

Edits are coalesced, so a drag costs a couple of sketchybar calls rather than one per frame,
and the state you stop on is always the state left on screen.

The readout says which of three things is happening:

- **Edits move the running bar as you drag** — the preview is live.
- **Not live** — sketchybar isn't installed or isn't running. The chips still drag and the page
  still saves; only the push is skipped.
- **Preview unavailable** — a push failed. Your edits are untouched and Save still applies them;
  only the on-screen preview stopped following.

Live editing leaves the running bar in a state that matches **no file**. AeroSpace-edge puts it
back for you:

- **Revert** reloads sketchybar from the last saved `bar.toml`, then re-reads the form from it.
  The bar on screen and the file agree again.
- **Closing the window with unsaved edits** does the same restore to the bar.
- **Save** writes the files and reloads from them, which reconciles the preview with disk by
  construction — there is nothing to undo.

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
