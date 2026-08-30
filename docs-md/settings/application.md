# Application

**Where:** menu bar → **Settings…** → **Application**

One of the two destinations that do not edit your config (see also
[Menu Bar](menu-bar.md)). Every control here acts immediately and
leaves the TOML untouched — using them never dirties a draft you have in progress.

## Configuration file

| Control | What it does |
|---|---|
| **Open config in editor** | Opens the resolved config in your default editor. If you have no custom config yet, the bundled default is copied to `~/.aerospace-edge.toml` first, and *that* is opened. |
| **Reload config** | Re-parses the active file and refreshes window-management state — identical to [`reload-config`](../commands/reload-config.md). |

## Diagnostics

| Control | What it does |
|---|---|
| **Show Crash Reports** | Selects this app's crash reports in Finder — `~/Library/Logs/DiagnosticReports/AeroSpace-edge-*.ips`, written by macOS, not by AeroSpace-edge. With none written yet it just opens the folder. |

Attach the newest report to a bug report or pull request: it names the code that crashed, which
is where a fix starts.

## Version

| Control | What it does |
|---|---|
| **Copy Version Info** | Copies the app name, version and full git hash to the clipboard — the thing to paste into a bug report. |

The line beside **Copy Version Info** shows the short form of the same identification.

**Check for Updates…** is not here: it lives in the Settings window footer, next to **Revert**
and **Save**, so it is one click away from every destination.
