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
