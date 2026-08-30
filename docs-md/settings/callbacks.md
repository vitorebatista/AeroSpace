# Callbacks

**Where:** menu bar → **Settings…** → **Callbacks**

![The Callbacks destination, showing raw lifecycle callback TOML with fragment validation](../assets/settings-callbacks.jpg)

Commands AeroSpace-edge runs on lifecycle events. Raw TOML, for the same reason as the other
two raw panes: the values are the command DSL.

## What the pane owns

Exactly these five keys:

| Key | Runs when |
|---|---|
| `after-startup-command` | AeroSpace-edge has finished starting |
| `on-focus-changed` | Focus moves to another window |
| `on-mode-changed` | The active binding mode changes |
| `on-focused-monitor-changed` | Focus moves to another monitor |
| `exec-on-workspace-change` | The focused workspace changes |

```toml
after-startup-command = 'exec-and-forget /opt/homebrew/bin/sketchybar'
on-focus-changed = ['move-mouse window-lazy-center']
exec-on-workspace-change = ['/bin/bash', '-c', 'echo $AEROSPACE_FOCUSED_WORKSPACE']
```

Each value is a command string or an array of them, and the parser's fallback for all five
is an empty command list. See [Callbacks](../guide.md#callbacks).

The deprecated `after-login-command` is **not** edited here. It is preserved byte-for-byte
wherever it already is in your file.

## Preservation

Saving this pane removes those five keys from wherever they currently sit and reinserts them
together as the block you edited. Comments and interleaved keys around their old positions
survive only if you carried them into the pane.

Validation, as with the other raw panes, is advisory here and authoritative in **Save**.
