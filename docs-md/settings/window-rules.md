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
run = 'layout floating'
```

`run` is mandatory and is a command string or an array of them. Every supported `if.*`
matcher, how multiple rules are ordered, and `check-further-callbacks` are documented in
[the 'on-window-detected' callback](../guide.md#on-window-detected-callback) — including
the ways to find an app's `app-id`.

## Validation and preservation

The status line only checks that this pane's text parses on its own; **Save** validates the
whole file and is authoritative. Editing the pane replaces the complete rule family on Save.
