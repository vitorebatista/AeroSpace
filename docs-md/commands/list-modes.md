---
title: list-modes
description: Print a list of modes currently specified in the configuration
section: 1
---

# aerospace list-modes

Print a list of modes currently specified in the configuration

## Synopsis

```synopsis
aerospace list-modes [-h|--help] [--current] [--count] [--json]
```

## Description

See [the guide](../guide.md#binding-modes) for documentation about binding modes

## Options

`-h`, `--help`

: Print help

`--current`

: Only print the currently active mode. Incompatible with `--count`

`--count`

: Output only the number of modes. Incompatible with `--current`, `--json`

`--json`

: Output in JSON format. Incompatible with `--count`
