---
title: focus-back-and-forth
description: Switch between the current and previously focused elements back and forth
section: 1
---

# aerospace-edge focus-back-and-forth

Switch between the current and previously focused elements back and forth

## Synopsis

```synopsis
aerospace-edge focus-back-and-forth [-h|--help]
```

## Description

Switch between the current and previously focused elements back and forth. The element is either a window or an empty workspace.

AeroSpace stores only one previously focused window in history, which means that if you close the previous window, `focus-back-and-forth` has no window to switch focus to. In that case, the command will exit with non-zero exit code.

That’s why it may be preferred to combine `focus-back-and-forth` with `workspace-back-and-forth`:  

    aerospace-edge focus-back-and-forth || aerospace-edge workspace-back-and-forth

Also see: [workspace-back-and-forth](workspace-back-and-forth.md)

## Options

`-h`, `--help`

: Print help
