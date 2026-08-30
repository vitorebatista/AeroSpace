---
title: enable-normalization
description: Set or clear a per-workspace override for a refresh-time normalization
section: 1
---

# aerospace-edge enable-normalization

Set or clear a per-workspace override for a refresh-time normalization

## Synopsis

```synopsis
aerospace-edge enable-normalization [-h|--help] [--workspace <workspace>] <kind> on [--fail-if-noop]
aerospace-edge enable-normalization [-h|--help] [--workspace <workspace>] <kind> off [--fail-if-noop]
aerospace-edge enable-normalization [-h|--help] [--workspace <workspace>] <kind> toggle
aerospace-edge enable-normalization [-h|--help] [--workspace <workspace>] <kind> reset
```

## Description

The override is scoped to a single workspace (the focused workspace by default, or the workspace named by `--workspace`) and lives as long as the workspace itself: AeroSpace destroys workspaces that become empty and invisible (unless they are listed in `persistent-workspaces`), and the override is destroyed with them. Overrides are not persisted across AeroSpace restarts. Setting an override on a workspace that would be destroyed immediately is an error.

`<kind>` is one of `flatten-containers`, `opposite-orientation-for-nested-containers` (the suffix of the corresponding `enable-normalization-<kebab-name>` global config key).

- `on` sets the workspace override to true regardless of the global config.

- `off` sets the workspace override to false regardless of the global config.

- `toggle` flips the current effective value (override if set, otherwise global config).

- `reset` clears the workspace override so the workspace falls back to the global config value.

`on`, `off`, and `toggle` all install an override, even when the resulting value coincides with the global config. While the override is set, later changes to the global config key (including `aerospace-edge reload-config`) have no effect on that workspace until you run `reset`.

See the broader normalization-framework discussion in [issue #260](https://github.com/nikitabobko/AeroSpace/issues/260).

## Options

`-h`, `--help`

: Print help

`--fail-if-noop`

: Exit with non-zero exit code if the override is already in the requested state. Only valid with `on` or `off`.

`--workspace <workspace>`

: Act on the specified workspace instead of the focused workspace. The flag takes precedence over `AEROSPACE_WINDOW_ID` and `AEROSPACE_WORKSPACE` [environment variables](../guide.md#environment-variables).
