---
title: workspace
description: Focus the specified workspace
section: 1
---

# aerospace workspace

Focus the specified workspace

## Synopsis

```synopsis
aerospace workspace [-h|--help] [--auto-back-and-forth] [--fail-if-noop] <workspace-name>
aerospace workspace [-h|--help] [--wrap-around] [--stdin|--no-stdin] (next|prev)
```

## Description

**1. <workspace-name> syntax**

Focus the specified workspace

**2. (next|prev) syntax**

Focuses next or previous workspace in **the list**.

- If `--stdin` is specified, then **the list** is taken from stdin

- Otherwise, **the list** is defined as all workspaces on focused monitor in alphabetical order

## Options

`-h`, `--help`

: Print help

`--wrap-around`

: Make it possible to jump between first and last workspaces using `(next|prev)`

`--auto-back-and-forth`

: Automatic `back-and-forth` when switching to already focused workspace. Incompatible with `--fail-if-noop`

`--fail-if-noop`

: Exit with non-zero exit code if switch to the already focused workspace. Incompatible with `--auto-back-and-forth`

`--stdin`

: Read the list of workspaces from stdin. Incompatible with `--no-stdin`

`--no-stdin`

: Ignore the list of workspaces from stdin, even if provided. Incompatible with `--stdin`

## Examples

- Go to the next non empty workspace on the focused monitor:  
  `aerospace list-workspaces --monitor focused --empty no | aerospace workspace --stdin next`
