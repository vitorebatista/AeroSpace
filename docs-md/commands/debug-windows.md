---
title: debug-windows
description: Interactive command to record Accessibility API debug information to create bug reports
section: 1
---

# aerospace debug-windows

Interactive command to record Accessibility API debug information to create bug reports

## Synopsis

```synopsis
aerospace debug-windows [-h|--help] [--window-id <window-id>]
aerospace debug-windows [-h|--help] --app-bundle-id <app-bundle-id>
```

## Description

Use this command output to report bug reports about incorrect windows handling (e.g. some windows are floated when they shouldn’t).

The intended usage is the following:

1.  Run the command to start the debug session recording

2.  Focus problematic window or make the window appear.

3.  Run the command one more time to stop the debug session recording and print the results

If the problematic window can’t be focused, or if AeroSpace doesn’t detect the window at all, use `--app-bundle-id` flag to dump debug information about all AX windows of the application, including AX windows that are not treated as windows from AeroSpace perspective. You can get the app-bundle-id of running applications with `aerospace list-apps` command.

`debug-windows` command is **not stable API**. Please **don’t rely on** the command existence and output format. The only intended use case is to report bugs about incorrect windows handling.

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Print debug information of the specified window right away. Usage of this flag disables interactive mode.

`--app-bundle-id <app-bundle-id>`

: Print debug information of all AX windows of the specified application right away, including AX windows that are not treated as windows from AeroSpace perspective. Usage of this flag disables interactive mode.
