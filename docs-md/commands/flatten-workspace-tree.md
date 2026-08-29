---
title: flatten-workspace-tree
description: Flatten the tree of the focused workspace
section: 1
---

# aerospace flatten-workspace-tree

Flatten the tree of the focused workspace

## Synopsis

```synopsis
aerospace flatten-workspace-tree [-h|--help] [--workspace <workspace>]
```

## Description

The command is useful when you messed up with your layout, and it’s easier to "reset" it and start again.

## Options

`-h`, `--help`

: Print help

`--workspace <workspace>`

: Act on the specified workspace instead of the focused workspace. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).
