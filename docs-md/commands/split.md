---
title: split
description: Split focused window
section: 1
---

# aerospace-edge split

Split focused window

## Synopsis

```synopsis
aerospace-edge split [-h|--help] [--window-id <window-id>] (horizontal|vertical|opposite)
```

## Description

`split` command exists solely for compatibility with i3. Unless you’re hardcore i3 user who knows what they are doing, it’s recommended to use `join-with`

**If the parent of focused window contains more than one child**, then the command

1.  Creates a new tiling container

2.  Replaces the focused window with the container

3.  Puts the focused window into the container as its only child

The argument configures orientation of the newly created container. `opposite` means opposite orientation compared to the parent container.

**If the parent of the focused window contains only a single child** (the window itself), then `split` command changes the orientation of the parent container

!!! info

    `split` command has no effect on workspaces where the `enable-normalization-flatten-containers` normalization is in effect. Consider using `join-with` if you want to keep `enable-normalization-flatten-containers` enabled. Alternatively, disable the normalization on a single workspace with `aerospace-edge enable-normalization --workspace <workspace> flatten-containers off`

## Options

`-h`, `--help`

: Print help

`--window-id <window-id>`

: Act on the specified window instead of the focused window. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).
