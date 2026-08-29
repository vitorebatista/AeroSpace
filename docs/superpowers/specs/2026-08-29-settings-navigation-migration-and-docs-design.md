# Settings navigation, config migration, and documentation design

Date: 2026-08-29
Status: Approved

## Objective

Make the Settings window the single home for application and configuration settings, and make upgrading a config from version 1 to version 2 a safe, explicit migration rather than a scalar edit.

The change also adds a dedicated Settings page to the documentation site. That page explains every section and option with screenshots, TOML keys, allowed values, effects, safety behavior, and migration/recovery instructions.

## Scope

This design covers three connected changes:

1. Flatten the menu-bar menu. `Enable`/`Disable`, `Settings…`, and `Quit` are direct items. The nested `Settings` menu is removed.
2. Move the actions formerly inside the nested menu into a new `Application` section in the Settings window.
3. Introduce a transactional, versioned migration path for `config-version = 1` to `config-version = 2`, including a byte-identical backup and a visible result message.

It also covers the user-facing documentation and the test matrix required for these behaviors.

## Menu and Settings navigation

### Menu-bar menu

After the workspace list, the only application actions at the top level are:

1. `Enable` or `Disable`
2. `Settings…`
3. `Quit AeroSpace-edge`

There is no `Settings -> Settings…` nesting.

### Application section

The Settings sidebar gains an `Application` destination. It contains:

- **Configuration file**
  - Open the resolved config in the selected text editor.
  - Reload the active config.
- **Menu bar appearance**
  - Every existing experimental menu-bar style.
  - The existing warning that these styles have no stability guarantee and require macOS 14 or later.
- **Updates**
  - Check for updates.
  - Current version and git identification.
  - Copy version information.

These application actions do not make the config draft dirty. Config-specific sections continue to use the existing Save/Revert footer.

## Migration trigger and user experience

### Trigger

A migration is required only when the loaded config has effective version 1 and the draft is changed to version 2.

Omitting `config-version` is effective version 1. Merely opening Settings or saving unrelated edits while remaining on version 1 does not migrate and does not create a backup.

Downgrading from version 2 to version 1 is not part of this migration. The UI must not present it as the inverse of the upgrade. If downgrade remains selectable, it requires a separate warning and uses the normal validated save path; it never deletes an existing backup.

### Before Save

When version 2 is selected from a loaded version-1 config, the Config version group shows:

- that an upgrade migration will occur on Save;
- that version 2 requires an explicit persistent workspace list;
- the backup naming convention;
- that no file changes occur until Save.

Save presents a migration confirmation. The confirmation names the source and target versions and explains the derived `persistent-workspaces` change.

### Success

After a successful write and reload, Settings displays:

`Migrated to config version 2. Backup: <absolute path>`

The path is selectable and exposed to accessibility. A reveal/open action may be provided if it uses existing platform behavior without complicating the save transaction.

### Failure

- Candidate validation failure: no backup and no write.
- Backup failure: no write.
- Real-file write failure: backup remains and the original config remains unchanged; if the platform reports a failure after replacing the target, restore the original bytes from the backup before returning the error.
- Reload failure: migrated file and backup remain; Settings reports the error and the backup path.

## Versioned migration architecture

### ConfigMigrator

Introduce a pure migration component with an interface shaped like:

```swift
ConfigMigrator.migrate(text: String, from: Int, to: Int) -> Result<MigrationCandidate, MigrationError>
```

`MigrationCandidate` contains:

- migrated TOML text;
- source and target versions;
- a concise list of semantic changes;
- the persistent workspace list materialized by the v1-to-v2 step.

The migrator has ordered steps. The first step is `1 -> 2`. Future config versions add another step without changing the save transaction.

The migrator is pure: it parses and transforms text but does not read or write files, create backups, reload AeroSpace, show alerts, or use SwiftUI.

### Version 1 to version 2 step

The official version-2 semantic change is that `persistent-workspaces` becomes explicit and its fallback changes from an inferred list to an empty list.

The step therefore:

1. Parses the original text with the real config parser under effective version 1.
2. Rejects a source that does not parse cleanly.
3. Captures the exact v1 `persistentWorkspaces` semantics before changing the version.
4. Sets `config-version = 2`.
5. Writes `persistent-workspaces` explicitly using the captured v1 semantics.
6. Parses the candidate with the real parser and requires zero errors.
7. Verifies the semantic equivalence invariant described below.

No other key or table is rewritten by the migration.

### Workspace ordering

The v1 parser derives persistent workspace membership from:

- `workspace <name>` commands in every binding mode;
- `move-node-to-workspace <name>` commands in every binding mode;
- keys in `workspace-to-monitor-force-assignment`.

Membership must match the real v1 parser. Output order must be deterministic and user-friendly:

1. workspace names encountered in TOML binding source order;
2. then assignment-only workspace names in TOML source order;
3. first occurrence wins.

The migrator must not use dictionary iteration order from parsed modes or assignments to decide emitted order.

For the current user config, this produces numeric workspaces in source order followed by letter workspaces in source order, without the shuffled order currently visible when the v1 derived set is exposed directly by dictionary-backed parser structures.

### Semantic equivalence invariant

After migration, all documented behavior is equal to the v1 source except:

- `configVersion` is 2 instead of 1;
- `persistentWorkspaces` is now authored explicitly but has identical membership.

The migration also preserves source regions byte for byte except for insertion/replacement of:

- `config-version`;
- `persistent-workspaces`.

This covers known, unknown, deprecated, and future keys: an unknown region is carried as source text even when the current model does not understand it.

## Backup transaction

### Path

The write target is resolved through symlinks first. The backup is created beside that real target:

`<filename>.backup-v1-YYYYMMDD-HHmmss`

Example:

`/Users/example/.aerospace.toml.backup-v1-20260829-203000`

If that name already exists, append a deterministic numeric suffix rather than overwriting a backup.

### Contents and metadata

The backup contains the exact original bytes. The migration preserves the original target's POSIX permissions. Saving through a symlink updates the target while retaining the symlink itself.

### Ordering

The save transaction is:

1. render migration candidate in memory;
2. write candidate to a temporary file;
3. validate with the real parser;
4. create the byte-identical backup;
5. atomically write the real target, preserving permissions and symlink behavior;
6. reload within the existing refresh session;
7. reload Settings state;
8. publish migration success and backup path.

Backup creation must succeed before step 5.

## Current config validation

The active base file inspected during design is `~/.aerospace.toml`. It is a regular file and omits `config-version`, so it has effective version 1.

It exercises important migration shapes:

- startup and callback command arrays;
- normalization and layout scalars;
- fork-specific focus behavior;
- key mapping;
- constant and per-monitor gaps;
- raw exec environment with `${PATH}` interpolation;
- a multiline literal command;
- main and service binding modes;
- numeric and letter workspace commands;
- window-detected rules;
- a workspace-to-monitor table containing commented examples.

The personal file is never committed. Tests use a sanitized fixture with equivalent structures. A local, read-only migration simulation runs against the real file and reports the proposed diff and derived workspace list without creating a backup or changing the file.

## Complete option inventory and tests

The migration suite must include a comprehensive fixture spanning every parser-owned family and every Settings-owned field.

### Top-level and scalar options

- `config-version`
- `after-login-command` (deprecated but preserved)
- `after-startup-command`
- `on-focus-changed`
- `on-mode-changed`
- `on-focused-monitor-changed`
- `exec-on-workspace-change`
- `start-at-login`
- `auto-reload-config`
- `automatically-unhide-macos-hidden-apps`
- `enable-normalization-flatten-containers`
- `enable-normalization-opposite-orientation-for-nested-containers`
- `enable-normalization-binary-tree`
- `default-root-container-layout`
- `default-root-container-orientation`
- `accordion-padding`
- `focus-follows-app-activation`
- `new-window-prevent-flicker`
- focused-window border enabled, color, width, opacity, radius, and inset
- `persistent-workspaces`

### Structured families

- all six constant gaps;
- per-monitor gaps using main, secondary, sequence number, and regex descriptions;
- `key-mapping.preset` and custom notation mapping;
- `exec.inherit-env-vars` and `exec.env-vars`, including interpolation and quoted/special keys;
- `workspace-to-monitor-force-assignment`, including priority lists;
- multiple binding modes, simple commands, command arrays, multiline strings, and custom notation;
- `[[on-window-detected]]` with every supported matcher shape and command arrays;
- callback arrays.

### Preservation and file-shape cases

- comments attached to keys and tables;
- unknown top-level keys and unknown tables;
- TOML quoted keys;
- multiline basic and literal strings;
- LF and CRLF;
- final line with and without a terminator;
- regular file and symlink target;
- original file permissions;
- duplicate backup-name collision;
- invalid source, invalid candidate, backup failure, write failure, and reload failure.

### Required assertions

- The migration's candidate parses as version 2.
- Persistent workspace membership matches v1 behavior.
- Output order follows source order and is deterministic.
- Every other semantic field is unchanged.
- Every source block outside `config-version` and `persistent-workspaces` is byte-identical.
- Normal saves that do not cross versions create no backup.
- A failed transaction never modifies the real config.

## Documentation site

### Dedicated page

Add `docs-md/settings.md` and a top-level `Settings` entry in `mkdocs.yml` navigation. The existing Guide section links to the dedicated page rather than duplicating all details.

### Page structure

1. Opening Settings directly from the menu bar.
2. Source-of-truth and safe-save model.
3. General.
4. Layout.
5. Gaps.
6. Focus.
7. Window Border.
8. Workspaces & Monitors.
9. Key Mapping.
10. Exec.
11. Keybindings raw TOML.
12. Window Rules raw TOML.
13. Callbacks raw TOML.
14. Application.
15. Config version migration and backup recovery.
16. Invalid-config raw recovery.
17. External-change, ambiguous-location, first-save, and symlink behavior.

### Screenshots

Use the existing eleven screenshots and add a twelfth screenshot for Application. Refresh screenshots whose navigation changes after adding Application. Each image has:

- meaningful alt text;
- a caption explaining what is visible;
- a following option table so the information is accessible without the image.

### Option tables

Every structured option documents:

- UI label;
- TOML key or table;
- accepted values and range;
- default/fallback;
- practical effect;
- whether it is upstream or AeroSpace-edge-specific;
- whether a save rewrites a whole table family;
- related Guide/command links.

Raw sections document syntax, ownership boundaries, fragment validation, full-file Save validation, and examples.

### Migration documentation

The page includes:

- why v2 exists;
- what changes from v1;
- a before/after example;
- backup naming and exact location behavior;
- how to restore with regular files and symlinks;
- failure guarantees;
- the post-save success message.

## Accessibility

- `Settings…` is a direct menu item with the existing keyboard behavior.
- Application controls have labels and help text.
- Migration warnings and the backup path are exposed to VoiceOver.
- Screenshots are supplementary; every option is described in text.
- Status is not conveyed by color alone.

## Non-goals

- Automatically migrating when the app starts.
- Modifying a config merely because Settings was opened.
- Canonically reformatting the whole TOML document.
- Treating v2-to-v1 as an automatic reversible migration.
- Committing the user's personal configuration.
- Replacing raw DSL editors with structured command builders.

## Completion criteria

- The menu has no nested Settings submenu.
- Application actions are available in the Settings window.
- A v1-to-v2 Save cannot lose derived persistent workspace behavior.
- The original config is backed up before the real write.
- Success identifies the backup path.
- Failures preserve the original file.
- The comprehensive migration fixture and sanitized current-config fixture pass.
- A local read-only simulation against the actual current config reports only the intended changes.
- The dedicated Settings documentation page builds with all screenshots, option tables, and migration recovery instructions.
- Debug build, full Swift tests, documentation build, and release CI checks pass.
