---
title: close
description: Close the focused window
section: 1
---

# aerospace-edge close

Close the focused window

## Synopsis

```synopsis
aerospace-edge close [-h|--help] [--quit-if-last-window] [--window-id <window-id>]
```

## Description

Normally, you don’t need to use this command, because macOS offers its own `cmd+w` binding. You might want to use the command from CLI for scripting purposes

## Options

`-h`, `--help`

: Print help

`--quit-if-last-window`

: Quit the app instead of closing if it’s the last window of the app

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).
