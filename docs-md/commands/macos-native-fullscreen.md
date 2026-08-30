---
title: macos-native-fullscreen
description: Toggle macOS fullscreen for the focused window
section: 1
---

# aerospace-edge macos-native-fullscreen

Toggle macOS fullscreen for the focused window

## Synopsis

```synopsis
aerospace-edge macos-native-fullscreen [-h|--help] [--window-id <window-id>]
aerospace-edge macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] on
aerospace-edge macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] off
```

## Description

## Options

`-h`, `--help`

: Print help

`--fail-if-noop`

: Exit with non-zero exit code if already fullscreen or already not fullscreen

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).

## Arguments

on, off

: `on` means enter fullscreen mode. `off` means exit fullscreen mode. Toggle between the two if not specified
