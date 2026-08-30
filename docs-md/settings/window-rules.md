# Window Rules

**Where:** menu bar → **Settings…** → **Window Rules**

![The Window Rules destination, showing raw on-window-detected TOML with fragment validation](../assets/settings-window-rules.jpg)

Rules that run once, when a window is first detected. Edited as raw TOML, because a rule's
`run` is the command DSL rather than a fixed set of values.

## What the pane owns

Every `[[on-window-detected]]` table in your config.

```toml
[[on-window-detected]]
if.app-id = 'com.apple.systempreferences'
if.window-title-regex-substring = 'Settings'
run = 'layout floating'

[[on-window-detected]]
if.app-name-regex-substring = 'slack'
run = ['move-node-to-workspace S', 'layout tiling']
```

Supported matchers:

| Matcher | Matches |
|---|---|
| `app-id` | The app's exact bundle id |
| `app-id-regex-substring` | A regex searched inside the bundle id |
| `app-name-regex-substring` | A regex searched inside the app name |
| `window-title-regex-substring` | A regex searched inside the window title |
| `workspace` | The workspace the window would land on |
| `during-aerospace-startup` | Whether the window was found during startup |

`run` is mandatory and is a command string or an array of them. See
[on-window-detected callbacks](../guide.md#on-window-detected-callback).

## Validation and preservation

The status line only checks that this pane's text parses on its own; **Save** validates the
whole file and is authoritative. Editing the pane replaces the complete rule family on Save.
