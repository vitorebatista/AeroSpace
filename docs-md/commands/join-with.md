---
title: join-with
description: Put the focused window and the nearest node in the specified direction under a common parent container
section: 1
---

# aerospace-edge join-with

Put the focused window and the nearest node in the specified direction under a common parent container

## Synopsis

```synopsis
aerospace-edge join-with [-h|--help] [--window-id <window-id>] (left|down|up|right)
```

## Description

## Examples

Given this layout

    h_tiles
    ├── window 1
    ├── window 2 (focused)
    └── window 3

`join-with right` will result in the following layout

    h_tiles
    ├── window 1
    └── v_tiles
        ├── window 2 (focused)
        └── window 3

!!! note

    `join-with` is a high-level replacement for i3’s [split command](https://i3wm.org/docs/userguide.html#_splitting_containers). There is an observation that the only reason why you might want to split a node is to put several windows under a common "umbrella" parent. Unlike `split`, `join-with` can be used with [`enable-normalization-flatten-containers`](../guide.md#normalization)

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).
