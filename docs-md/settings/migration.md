# Config version migration

**Where it starts:** menu bar → **Settings…** → **[General](general.md#config-version)** →
**Config version**

Version 1 *infers* your persistent workspaces. Version 2 changes that fallback to an empty
list, so the old behaviour has to be written down explicitly. Turning a loaded version 1
config into a version 2 config is therefore a migration, not a value change — and Settings
treats it as one.

## What does and does not start a migration

A migration begins **only** when a loaded, effectively-version-1 draft is set to version 2
and you confirm the Save.

None of these migrate anything or create a backup:

- Opening Settings on a version 1 config.
- Saving unrelated edits to a version 1 config.
- Omitting `config-version` (that *is* version 1, it is not a change).

Before you press Save, the General pane replaces its usual help text with a warning that the
Save will materialize `persistent-workspaces`, create a byte-identical backup, and change
nothing until you confirm. If an external edit to the file is also detected, that
confirmation comes first.

## How the workspace list is derived

Deterministically, in this order:

1. Scan every binding mode **in TOML source order**.
2. Add the targets of `workspace <name>` and `move-node-to-workspace <name>` in the order
   they are encountered; the first occurrence of a name wins.
3. Append workspaces that appear only in `workspace-to-monitor-force-assignment`, in source
   order.

So this version 1 config:

```toml
# config-version omitted, which means version 1
[mode.main.binding]
alt-2 = 'workspace 2'
alt-1 = 'workspace 1'
alt-a = 'move-node-to-workspace A'

[workspace-to-monitor-force-assignment]
Z = 'secondary'
```

migrates to the semantically equivalent:

```toml
config-version = 2
persistent-workspaces = ['2', '1', 'A', 'Z']
```

Nothing else is migration-owned. Every source region outside those two keys stays
byte-identical, and other form edits you made before the same Save are applied only after the
migrated baseline exists.

## The backup

A successful migration first writes a byte-identical copy beside the *resolved* target:

```text
<filename>.backup-v1-YYYYMMDD-HHmmss
```

A name collision gets `-2`, `-3`, and so on — an existing backup is never overwritten. After
the Save, Settings shows the exact path as selectable text:

```text
Migrated to config version 2. Backup: /absolute/path/to/config.toml.backup-v1-20260829-203000
```

**Reveal Backup** opens that file in Finder.

## Restoring from the backup

For a regular file, copy the backup back over the target and reload:

```sh
cp '/absolute/path/config.toml.backup-v1-20260829-203000' '/absolute/path/config.toml'
aerospace-edge reload-config
```

For a symlinked config, copy onto the **resolved target** shown beside the backup, not onto
the symlink path — that keeps the symlink itself intact.

## Failure guarantees

The ordering is deliberate, so you always know what state you are in:

| If this fails | State afterwards |
|---|---|
| Candidate validation | No backup, no write. Your file is untouched. |
| Creating the backup | No write. Your file is untouched. |
| Writing the real target | The original bytes are restored from the backup, and the backup remains. |
| Reloading after a successful write | The migrated file and the backup both remain; the error includes the backup path. |
