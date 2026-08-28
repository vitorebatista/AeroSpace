---
title: fullscreen
description: Toggle the fullscreen mode for the focused window
section: 1
---

# aerospace fullscreen

Toggle the fullscreen mode for the focused window

## Synopsis

```synopsis
aerospace fullscreen [-h|--help]     [--window-id <window-id>] [--no-outer-gaps]
aerospace fullscreen [-h|--help] on  [--window-id <window-id>] [--no-outer-gaps] [--fail-if-noop]
aerospace fullscreen [-h|--help] off [--window-id <window-id>] [--fail-if-noop]
```

## Description

Switching to a different tiling window within the same workspace while the current focused window is in fullscreen mode results in the fullscreen window exiting fullscreen mode.

## Options

`-h`, `--help`

: Print help

`--no-outer-gaps`

: Remove the outer gaps when in fullscreen mode

`--fail-if-noop`

: Exit with non-zero exit code if already fullscreen or already not fullscreen

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

## Arguments

on, off

: `on` means enter fullscreen mode. `off` means exit fullscreen mode. Toggle between the two if not specified
