---
title: Home
description: An i3-like tiling window manager for macOS
hide:
  - toc
---

<div class="edge-hero" markdown>
![AeroSpace](assets/edge-logo.svg){ .off-glb }
<div markdown>
# AeroSpace

An i3-like tiling window manager for macOS — no SIP disabling required.
</div>
</div>

This is a maintained fork of [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)
that backports upstream bug fixes and small features not yet merged upstream.

## Install

```shell
brew install --cask nikitabobko/tap/aerospace
```

Then read the [Guide](guide.md) to configure it, or jump straight to a command below.

## Commands

<div class="edge-cards" markdown>

[<code>aerospace balance-sizes</code><span>Balance sizes of all windows in the current workspace</span>](commands/balance-sizes.md)

[<code>aerospace close-all-windows-but-current</code><span>On the focused workspace, close all windows but current</span>](commands/close-all-windows-but-current.md)

[<code>aerospace close</code><span>Close the focused window</span>](commands/close.md)

[<code>aerospace config</code><span>Query AeroSpace config options</span>](commands/config.md)

[<code>aerospace debug-windows</code><span>Interactive command to record Accessibility API debug information to create bug reports</span>](commands/debug-windows.md)

[<code>aerospace enable-normalization</code><span>Set or clear a per-workspace override for a refresh-time normalization</span>](commands/enable-normalization.md)

[<code>aerospace enable</code><span>Temporarily disable window management</span>](commands/enable.md)

[<code>aerospace exec-and-forget</code><span>Run /bin/bash -c '<bash-script>'</span>](commands/exec-and-forget.md)

[<code>aerospace false</code><span>Return false value</span>](commands/false.md)

[<code>aerospace flatten-workspace-tree</code><span>Flatten the tree of the focused workspace</span>](commands/flatten-workspace-tree.md)

[<code>aerospace focus-back-and-forth</code><span>Switch between the current and previously focused elements back and forth</span>](commands/focus-back-and-forth.md)

[<code>aerospace focus-monitor</code><span>Focus monitor by relative direction, by order, or by pattern</span>](commands/focus-monitor.md)

[<code>aerospace focus</code><span>Set focus to a window.</span>](commands/focus.md)

[<code>aerospace fullscreen</code><span>Toggle the fullscreen mode for the focused window</span>](commands/fullscreen.md)

[<code>aerospace join-with</code><span>Put the focused window and the nearest node in the specified direction under a common parent container</span>](commands/join-with.md)

[<code>aerospace layout</code><span>Change layout of the focused window or workspace root to the given layout</span>](commands/layout.md)

[<code>aerospace list-apps</code><span>Print the list of running applications that appears in the Dock and may have a user interface</span>](commands/list-apps.md)

[<code>aerospace list-exec-env-vars</code><span>List environment variables that exec-* commands and callbacks are run with</span>](commands/list-exec-env-vars.md)

[<code>aerospace list-modes</code><span>Print a list of modes currently specified in the configuration</span>](commands/list-modes.md)

[<code>aerospace list-monitors</code><span>Print monitors that satisfy conditions</span>](commands/list-monitors.md)

[<code>aerospace list-windows</code><span>Print windows that satisfy conditions</span>](commands/list-windows.md)

[<code>aerospace list-workspaces</code><span>Print workspaces that satisfy conditions</span>](commands/list-workspaces.md)

[<code>aerospace macos-native-fullscreen</code><span>Toggle macOS fullscreen for the focused window</span>](commands/macos-native-fullscreen.md)

[<code>aerospace macos-native-minimize</code><span>Minimize focused window</span>](commands/macos-native-minimize.md)

[<code>aerospace mode</code><span>Activate the specified binding mode</span>](commands/mode.md)

[<code>aerospace move-mouse</code><span>Move mouse to the requested position</span>](commands/move-mouse.md)

[<code>aerospace move-node-to-monitor</code><span>Move window to monitor targeted by relative direction, by order, or by pattern</span>](commands/move-node-to-monitor.md)

[<code>aerospace move-node-to-workspace</code><span>Move the focused window to the specified workspace</span>](commands/move-node-to-workspace.md)

[<code>aerospace move-workspace-to-monitor</code><span>Move workspace to monitor targeted by relative direction, by order, or by pattern.</span>](commands/move-workspace-to-monitor.md)

[<code>aerospace move</code><span>Move the focused window in the given direction</span>](commands/move.md)

[<code>aerospace reload-config</code><span>Reload currently active config</span>](commands/reload-config.md)

[<code>aerospace resize</code><span>Resize the focused window</span>](commands/resize.md)

[<code>aerospace split</code><span>Split focused window</span>](commands/split.md)

[<code>aerospace subscribe</code><span>Subscribe to AeroSpace events and receive notifications via socket</span>](commands/subscribe.md)

[<code>aerospace summon-workspace</code><span>Move the requested workspace to the focused monitor.</span>](commands/summon-workspace.md)

[<code>aerospace swap</code><span>Swaps the focused window with another window.</span>](commands/swap.md)

[<code>aerospace test</code><span>Condition evaluation utility</span>](commands/test.md)

[<code>aerospace trigger-binding</code><span>Trigger AeroSpace binding as if it was pressed by user</span>](commands/trigger-binding.md)

[<code>aerospace true</code><span>Return true value</span>](commands/true.md)

[<code>aerospace volume</code><span>Manipulate volume</span>](commands/volume.md)

[<code>aerospace workspace-back-and-forth</code><span>Switch between the focused workspace and previously focused workspace back and forth</span>](commands/workspace-back-and-forth.md)

[<code>aerospace workspace</code><span>Focus the specified workspace</span>](commands/workspace.md)

</div>
