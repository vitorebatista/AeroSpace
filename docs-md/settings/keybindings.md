# Keybindings

**Where:** menu bar → **Settings…** → **Keybindings**

![The Keybindings destination, showing raw binding-mode TOML with fragment validation](../assets/settings-keybindings.jpg)

Bindings are AeroSpace's command DSL, not a fixed set of values, so this pane is a raw TOML
editor rather than a form.

## What the pane owns

Every `[mode]` / `[mode.*]` table in your config. Each binding maps a key combination to one
command string, or to an array of command strings, and `[mode.main.binding]` must exist. See
[Binding modes](../guide.md#binding-modes) for how modes are declared and switched,
[`mode`](../commands/mode.md), and the [command index](../aerospace-edge.md).

One thing worth knowing while typing into this pane: a binding key containing TOML
punctuation has to be quoted, e.g. `'alt-custom.key' = 'focus left'`.

## Validation

The status line under the editor is **advisory**: it only tells you that this pane's own
text parses on its own. When it checks, it silently prepends your current
[Key Mapping](key-mapping.md) preset and notation overrides, so custom notation validates
the way it will in the real document.

Cross-section conflicts and the complete file are checked by **Save**, and Save's result is
the authoritative one.

## Preservation

Editing this pane replaces the complete family of mode tables on Save. Comments inside that
family survive only if they are still present in the text you edited — which they are unless
you delete them, since the pane is seeded with the real source.
