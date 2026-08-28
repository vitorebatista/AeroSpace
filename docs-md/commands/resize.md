---
title: resize
description: Resize the focused window
section: 1
---

# aerospace resize

Resize the focused window

## Synopsis

```synopsis
aerospace resize [-h|--help] [--window-id <window-id>] (smart|smart-opposite|width|height) [+|-]<number>
```

## Description

The dimension to resize is chosen by the first argument

- `width` changes width

- `height` changes height

- `smart` changes width if the parent has horizontal orientation, and it changes height if the parent has vertical orientation

- `smart-opposite` resizes the opposite axis of smart

Second argument controls how much the size changes

- If the `<number>` is prefixed with `+` then the dimension is increased

- If the `<number>` is prefixed with `-` then the dimension is decreased

- If the `<number>` is prefixed with neither `+` nor `-` then the command changes the absolute value of the dimension

`resize` also works on floating windows. Floating windows are kept within their monitor, and are recentered as needed so they stay fully visible after resizing.

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).
