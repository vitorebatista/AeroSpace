# Menu Bar

**Where:** menu bar → **Settings…** → **Menu Bar**

How workspaces are drawn in the menu-bar item. Like [Application](application.md), this
destination does not edit your config: the choice is an app preference stored outside your TOML,
and it applies the moment you pick it — using it never dirties a draft you have in progress.

## Menu bar appearance

| Style | What it looks like |
|---|---|
| **Monospaced font** *(default)* | Workspace names in a fixed-width font, so the item stops shifting as you switch. |
| **System font** | The same names in the system font. |
| **Square images** | Each workspace as a small square. |
| **i3 style grouped** | i3-like, with the focused and visible workspaces grouped ahead of the rest. |
| **i3 style ordered** | i3-like, in a fixed alphabetical order — nothing moves when focus does. |

The experimental styles require macOS 14 or later and carry no stability guarantee.

## Position

| Control | What it does |
|---|---|
| **Distance from the right edge** | Where the menu-bar item sits, in points from the right edge. Bigger moves it further left. `0` *(default)* leaves the position to macOS. |

macOS stores a status item's position per app and restores it on every launch, so an item that once
landed badly — behind the notch, or off in the strip where app menus are drawn, which is where a
freshly installed app goes when the menu bar is full — stays there. Setting a value here re-pins the
item at startup instead.

It applies **at startup only**: while the app is running the position belongs to macOS, so ⌘-dragging
the item still works and wins until the next launch. As a sanity check, an item at `400` on a
1512-point-wide display sits at x ≈ 1112 — left of the Control Center cluster and clear of the notch.
Values much past ~600 on that display put it back under the notch.
