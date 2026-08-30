# Application

**Where:** menu bar → **Settings…** → **Application**

The only destination that does not edit your config. Every control here acts immediately and
leaves the TOML untouched — using them never dirties a draft you have in progress.

## Configuration file

| Control | What it does |
|---|---|
| **Open config in editor** | Opens the resolved config in your default editor. If you have no custom config yet, the bundled default is copied to `~/.aerospace-edge.toml` first, and *that* is opened. |
| **Reload config** | Re-parses the active file and refreshes window-management state — identical to [`reload-config`](../commands/reload-config.md). |

## Menu bar appearance

Chooses how workspaces are drawn in the menu bar:

- Monospaced font *(default)*
- System font
- Square images
- i3 style grouped
- i3 style ordered

This is an app preference, not a config key: it is stored outside your TOML and applies
immediately. The experimental styles require macOS 14 or later and carry no stability
guarantee.

## Updates

| Control | What it does |
|---|---|
| **Check Now** | Runs the update check. |
| **Copy Version Info** | Copies the app name, version and full git hash to the clipboard — the thing to paste into a bug report. |

The line beside **Copy Version Info** shows the short form of the same identification.
