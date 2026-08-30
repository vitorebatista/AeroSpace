---
title: enable
description: Temporarily disable window management
section: 1
---

# aerospace-edge enable

Temporarily disable window management

## Synopsis

```synopsis
aerospace-edge enable [-h|--help] toggle
aerospace-edge enable [-h|--help] on [--fail-if-noop]
aerospace-edge enable [-h|--help] off [--fail-if-noop]
```

## Description

When you disable AeroSpace, windows from currently invisible workspaces will be placed to the visible area of the screen

Key events are not intercepted when AeroSpace is disabled

## Options

`-h`, `--help`

: Print help

`--fail-if-noop`

: Exit with non-zero exit code if already in the requested mode
