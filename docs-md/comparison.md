---
title: Comparison
description: How AeroSpace-edge compares to AeroSpace, yabai, Amethyst, Rectangle and the tiling built into macOS
---

# How AeroSpace-edge compares

Every tool below is good at something, and the right pick depends on what you value. This page is
about **structural** differences — the things that follow from how each tool is built, and that no
amount of polish will change.

| | AeroSpace-edge | AeroSpace | yabai | Amethyst | Rectangle | macOS built-in |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Tiling model** | tree | tree | BSP tree | preset layouts | manual snap | manual snap |
| **Layout persists** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Needs SIP disabled** | never | never | for parts | never | never | — |
| **Private APIs** | ❌ | ❌ | ✅ | ❌ | ❌ | — |
| **Workspaces** | emulated, unlimited | emulated, unlimited | native Spaces | native Spaces | none | native Spaces |
| **Config** | TOML file | TOML file | shell script | GUI | GUI | System Settings |
| **Built-in keybindings** | ✅ | ✅ | needs `skhd` | ✅ | ✅ | fixed set |
| **Scriptable CLI** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Shortcuts / Spotlight** | ✅ | ❌ | ❌ | ❌ | ❌ | — |
| **macOS Focus filters** | ✅ | ❌ | ❌ | ❌ | ❌ | — |
| **Native Settings UI** | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **License** | MIT | MIT | MIT | MIT | MIT | closed |

## What the rows mean

### SIP and private APIs

yabai's most-wanted features — window opacity, borders, moving windows between Spaces without focus
changes — require partially disabling System Integrity Protection and injecting a scripting addition
into Dock. That is a genuine security and stability tradeoff, and it tends to break on macOS updates
until the addition is repatched.

AeroSpace-edge works entirely through the public Accessibility API. There is nothing to disable and
nothing to re-patch after an OS update. The cost is honest: some things yabai can do are simply not
reachable this way.

### Emulated workspaces

Native macOS Spaces come with a slow switch animation you cannot disable, a hard cap of 16, no way to
create, delete or reorder them from a hotkey, and [no public API at
all](guide.md#emulation-of-virtual-workspaces). Any tool built on Spaces inherits all of that.

AeroSpace reimplements workspaces instead — inactive workspaces park their windows off-screen. The
result is instant switching, no cap, workspaces assignable to monitors, and a model the CLI can drive.

### Focus filters have no workaround

macOS Focus filters are reachable **only** through App Intents, which means only an app bundle can
register one. A window manager driven by an external hotkey daemon has no way in. This isn't a feature
the others haven't gotten to yet — it's one their architecture can't reach.

See [Shortcuts, Spotlight and Focus filters](guide.md#shortcuts-spotlight-and-focus-filters).

### Against upstream AeroSpace

The tiling is the same tiling — that's the point, and it's why your `~/.aerospace.toml` works
unchanged. What differs is release cadence, [what's already fixed](index.md#whats-already-fixed-here),
and the native integrations written here: the Settings window, and Shortcuts / Spotlight / Focus
filter support.

## Pick something else if

- **You want opacity, borders and per-Space rules** and don't mind disabling SIP — use
  [yabai](https://github.com/koekeishiya/yabai). It does things this can't.
- **You want tiling with zero configuration** — use [Amethyst](https://github.com/ianyh/Amethyst).
  Install, and it tiles.
- **You only ever wanted to throw a window to half the screen** — use
  [Rectangle](https://rectangleapp.com), or the tiling already built into macOS. Both are free and one
  is already installed.

!!! note "Keeping this honest"

    This is a snapshot, and other projects move too. If a row is out of date, please
    [open an issue](https://github.com/vitorebatista/AeroSpace-edge/issues) — a comparison table that
    flatters us by being wrong is worth nothing.
