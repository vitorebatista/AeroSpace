---
title: reload-config
description: Reload currently active config
section: 1
---

# aerospace reload-config

Reload currently active config

## Synopsis

```synopsis
aerospace reload-config [-h|--help] [--no-gui] [--dry-run]
```

## Description

If the config contains errors they will be printed to stdout, and GUI will open to show the errors.

## Options

`-h`, `--help`

: Print help

`--no-gui`

: Don’t open GUI to show error. Only use stdout to report errors

`--dry-run`

: Validate the config and show errors (if any) but don’t reload the config

## Exit Codes

0

: Success. The config is reloaded successfully.

non-zero exit code

: Failure. The config contains errors.
