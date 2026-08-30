# Settings navigation, v1→v2 migration, and documentation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Settings the single application/configuration surface, migrate config version 1 to 2 transactionally with a byte-identical backup, and publish a screenshot-rich Settings guide.

**Architecture:** Keep source-preserving TOML edits in `TomlBlockDocument`; add a pure, ordered `ConfigMigrator`; keep backup/write/reload orchestration in `SettingsModel`; expose migration confirmation and result state in SwiftUI; document the exact UI and recovery flow in MkDocs. A migration first materializes v1 semantics, then applies the user's other draft edits relative to that migrated baseline.

**Tech stack:** Swift 6.3, SwiftUI/AppKit, TOMLDecoder, XCTest, MkDocs Material, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-29-settings-navigation-migration-and-docs-design.md`

## Global constraints

- Never commit the user's `~/.aerospace.toml` or its absolute path.
- Never rewrite config regions unrelated to an edited setting or migration-owned key.
- Resolve symlinks before backup/write; preserve the symlink and target permissions.
- Validate the complete candidate before creating a backup or touching the real target.
- Use `apply_patch` for source edits. Do not run repo-wide `./format.sh`.
- Every implementation task starts with a failing focused test and ends with a focused test, warnings-as-errors build, and scoped commit.
- The PR remains draft until the GUI checklist, real-file dry run, docs build, and full suite pass.

## File map

| Path | Responsibility |
|---|---|
| `Sources/AppBundle/config/ConfigMigrator.swift` | Pure ordered migration and semantic verification. |
| `Sources/AppBundle/config/TomlBlockDocument.swift` | Source-order access to table entries; surgical writes. |
| `Sources/AppBundle/config/ConfigTomlWriter.swift` | Draft equality and post-migration application of user edits. |
| `Sources/AppBundle/ui/settings/SettingsModel.swift` | Migration detection, validation, backup/write/reload transaction, status. |
| `Sources/AppBundle/ui/settings/SettingsWindow.swift` | Confirmation sequence and migration success presentation. |
| `Sources/AppBundle/ui/settings/SettingsSections.swift` | Version migration explanation and Application section. |
| `Sources/AppBundle/ui/MenuBar.swift` | Flat top-level actions. |
| `Sources/AppBundleTests/config/ConfigMigratorTest.swift` | Pure migration, ordering, preservation, and opt-in real-file dry run. |
| `Sources/AppBundleTests/config/ConfigMigrationBackupTest.swift` | Backup name/content/collision/symlink/permissions behavior. |
| `Sources/AppBundleTests/config/fixtures/config-v1-comprehensive.toml` | Every documented/parser-owned family. |
| `Sources/AppBundleTests/config/fixtures/config-v1-current-shape.toml` | Sanitized equivalent of the active v1 config structure. |
| `Sources/AppBundleTests/ui/MenuBarTest.swift` | Top-level action inventory. |
| `Sources/AppBundleTests/ui/SettingsModelTest.swift` | Save transaction and migration state. |
| `docs-md/settings.md` | Dedicated website guide. |
| `docs-md/assets/settings-*.jpg` | Twelve refreshed Settings screenshots. |
| `docs-md/guide.md`, `mkdocs.yml`, `CHANGELOG-FORK.md` | Links, navigation, release note. |

## Task 1: Finish the flat menu and Application destination

**Files:**
- Modify: `Sources/AppBundle/ui/MenuBar.swift`
- Modify: `Sources/AppBundle/ui/ExperimentalUISettings.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsWindow.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsSections.swift`
- Modify: `Sources/AeroSpaceApp/AeroSpaceApp.swift`
- Test: `Sources/AppBundleTests/ui/MenuBarTest.swift`

- [x] Add failing tests asserting `menuBarPrimaryActions == [.toggleEnabled, .settings, .quit]` and that `.application` is a sidebar destination.
- [x] Remove the nested Settings submenu and keep direct Enable/Disable, Settings…, Quit actions.
- [x] Add Application UI for config-file actions, menu-bar appearance, and update actions without dirtying the config draft.
- [x] Pass `TrayMenuModel` into the Settings scene.
- [x] Run `swift test --filter MenuBarTest`.
- [x] Run `./build-debug.sh -Xswiftc -warnings-as-errors` and `./swift-test.sh`.
- [x] Commit as `feat(settings): move application actions into settings window`.

Acceptance: clicking Settings opens the modal directly; no `Settings → Settings…` nesting remains; application-only actions never enable Save.

## Task 2: Add source-ordered v1→v2 migration

**Files:**
- Create: `Sources/AppBundle/config/ConfigMigrator.swift`
- Modify: `Sources/AppBundle/config/TomlBlockDocument.swift`
- Modify: `Sources/AppBundle/config/ConfigTomlWriter.swift`
- Create: `Sources/AppBundleTests/config/ConfigMigratorTest.swift`

### Interface

```swift
struct ConfigMigrationCandidate: Equatable {
    let text: String
    let fromVersion: Int
    let toVersion: Int
    let semanticChanges: [String]
    let persistentWorkspaces: [String]
}

enum ConfigMigrationError: Error, Equatable {
    case unsupportedPath(from: Int, to: Int)
    case invalidSource([String])
    case invalidCandidate([String])
    case semanticMismatch(String)
}

@MainActor enum ConfigMigrator {
    static func migrate(text: String, from: Int, to: Int)
        -> Result<ConfigMigrationCandidate, ConfigMigrationError>
}
```

- [ ] Write RED tests for omitted `config-version`, explicit v1, unsupported paths, invalid source, deterministic workspace order, and no rewrite outside `config-version`/`persistent-workspaces`.
- [ ] Add `TomlBlockDocument.keyValueTexts(inTableMatching:) -> [(table: String, text: String)]`. It must reuse the existing multiline/string scanner and return entries in byte/source order.
- [ ] For every `mode.*.binding` entry, parse a synthetic one-binding document with the source key-mapping preamble, inspect the real parsed commands, and collect `workspace`/`move-node-to-workspace` targets. First occurrence wins.
- [ ] Append assignment-only workspace names by parsing each `workspace-to-monitor-force-assignment` entry in source order. Fail with `.semanticMismatch` if the ordered set does not equal the v1 parser's derived membership.
- [ ] Implement step `1 -> 2` with only:

```swift
document.set(key: "config-version", tomlValue: TomlValue.of(2))
document.set(
    key: "persistent-workspaces",
    tomlValue: TomlValue.array(orderedPersistentWorkspaces)
)
```

- [ ] Parse the candidate with `parseConfig`; require zero errors and equal normalized `ConfigDraft` values except version and persistent-workspace ordering.
- [ ] Make `ConfigTomlWriter.ConfigDraft` `Equatable`; normalize persistent workspace membership before semantic comparison.
- [ ] Run `swift test --filter ConfigMigratorTest`; expected GREEN.
- [ ] Run warnings-as-errors build; commit `feat(config): migrate version 1 configs to version 2`.

Acceptance: a v1 config becomes valid v2, preserves all existing block bytes/order, and emits workspaces in binding-then-assignment source order.

## Task 3: Pin every documented option and the active-config shape

**Files:**
- Create: `Sources/AppBundleTests/config/fixtures/config-v1-comprehensive.toml`
- Create: `Sources/AppBundleTests/config/fixtures/config-v1-current-shape.toml`
- Modify: `Sources/AppBundleTests/config/ConfigMigratorTest.swift`

- [ ] Build the comprehensive fixture with all scalar options, callbacks, layouts, normalization, key mapping and custom notation, constant/per-monitor gaps, raw exec and interpolation, multiline command, all binding modes, persistent workspace-producing commands, monitor assignments, window rules, comments, quoted keys, and raw DSL arrays.
- [ ] Build the sanitized current-shape fixture with numeric then letter workspaces, service mode, multiline AppleScript, per-monitor top gap, commented assignments, and `${PATH}` interpolation. Use no personal app names, paths, bundle IDs, or commands.
- [ ] Add a fixture assertion table that checks every `ConfigDraft` field before/after migration. Only `configVersion` changes; persistent workspace membership is equal.
- [ ] Assert every original `TomlBlock` other than migration-owned keys appears byte-identically and in the same order after migration.
- [ ] Add opt-in read-only test support:

```swift
guard let path = ProcessInfo.processInfo.environment["AEROSPACE_MIGRATION_DRY_RUN"] else {
    throw XCTSkip("Set AEROSPACE_MIGRATION_DRY_RUN to inspect a local config")
}
```

The test reads, migrates in memory, prints only key names/workspace list/diff summary, validates the candidate, and never writes.
- [ ] Run both fixture tests and the opt-in test against a copied/read-only path to the active config.
- [ ] Commit `test(config): cover all documented v1 migration shapes`.

Acceptance: the sanitized fixture covers the documentation inventory, and the real-file dry run reports a valid candidate with no filesystem mutation.

## Task 4: Add byte-identical backup and transaction integration

**Files:**
- Create: `Sources/AppBundle/config/ConfigMigrationBackup.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsModel.swift`
- Create: `Sources/AppBundleTests/config/ConfigMigrationBackupTest.swift`
- Modify: `Sources/AppBundleTests/ui/SettingsModelTest.swift`

### Interface

```swift
struct ConfigMigrationBackup: Equatable {
    let url: URL

    static func create(
        forResolvedTarget target: URL,
        fromVersion: Int,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> ConfigMigrationBackup
}
```

- [ ] Write RED tests for exact bytes, `backup-v1-YYYYMMDD-HHmmss`, collision suffixes `-2`, symlink target placement, and source permissions.
- [ ] Implement backup using `Data(contentsOf:)` plus an exclusive destination selection; never overwrite an existing backup.
- [ ] Add `SettingsStatus.migrated(backupUrl: URL)` and `SettingsModel.requiresVersionMigration`.
- [ ] In `save()`, when loaded v1/draft v2:
  1. migrate the original document;
  2. parse a migrated baseline draft;
  3. if the user did not edit persistent workspaces, use the migrator's source-ordered list;
  4. apply all other draft edits relative to the migrated baseline;
  5. write/validate the temp candidate;
  6. create the backup beside `writeUrl`;
  7. atomically write while restoring permissions;
  8. reload in the refresh session;
  9. `load()` and publish `.migrated(backupUrl:)`.
- [ ] If candidate validation or backup creation fails, assert the target bytes and backup directory are unchanged.
- [ ] If real write fails after backup, restore exact original bytes from the backup before returning an error.
- [ ] Assert saving unrelated edits while staying v1 creates no backup.
- [ ] Assert symlink remains a symlink, target changes, backup is beside target, and mode bits remain unchanged.
- [ ] Run focused backup/model tests, full tests, build; commit `feat(settings): back up configs during version migration`.

Acceptance: no migration write can occur without a validated candidate and successful backup; success exposes the exact absolute backup path.

## Task 5: Add migration confirmation and recovery UI

**Files:**
- Modify: `Sources/AppBundle/ui/settings/SettingsWindow.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsSections.swift`
- Modify: `Sources/AppBundle/ui/settings/SettingsHelp.swift`
- Modify: `Sources/AppBundleTests/ui/SettingsHelpTest.swift`

- [ ] Add RED presentation tests for migration copy/help inventory.
- [ ] Replace independent save alerts with a sequence: external-change confirmation first, then migration confirmation, then `save()`.
- [ ] In General/Config version, show v1 and v2 as explicit choices with explanatory text; do not present version 2 as a harmless numeric increment.
- [ ] When migration is pending, show source/target versions, explicit persistent workspace materialization, backup naming, and “nothing changes until Save”.
- [ ] Render `.migrated` as selectable text with the absolute path and an AppKit “Reveal Backup” action.
- [ ] Keep all bindings and Save/Revert disabled while `isSaving`.
- [ ] Run focused tests/build; commit `feat(settings): confirm migrations and reveal their backups`.

Acceptance: the user explicitly confirms migration, understands the semantic change, and can locate the exact backup after success.

## Task 6: Publish the dedicated Settings guide and screenshots

**Files:**
- Create: `docs-md/settings.md`
- Modify: `docs-md/guide.md`
- Modify: `mkdocs.yml`
- Modify: `CHANGELOG-FORK.md`
- Replace/add: `docs-md/assets/settings-application.jpg` and all eleven existing `settings-*.jpg`

- [ ] Add top-level `Settings: settings.md` immediately after Guide in `mkdocs.yml`.
- [ ] Add opening/closing, target-file resolution, no-custom-config first save, ambiguous-config read-only mode, raw-only recovery, dirty/external-change/save behavior, symlink behavior, validation, and backup recovery.
- [ ] Add one section per sidebar destination: Application, General, Layout, Gaps, Focus, Window Border, Workspaces, Key Mapping, Exec, Keybindings, Window Rules, Callbacks.
- [ ] For every structured option include UI label, TOML key, type/allowed values, default, exact effect, version constraints, reload/runtime effect, tooltip/visual interpretation, and preservation caveat.
- [ ] For raw panes state that live validation is fragment-only and full Save validation is authoritative.
- [ ] Add a migration walkthrough: warning, derived workspace order, backup filename/path, successful status, restore command, and failure guarantees.
- [ ] Launch the Debug app with representative non-personal fixture data and capture all twelve panes at consistent window size/scale. Do not synthesize UI screenshots.
- [ ] Give each image descriptive alt text, caption, and numbered callouts explained directly below it.
- [ ] Link the existing Guide section to the dedicated page and update the fork changelog.
- [ ] Run `mkdocs build --strict -d .site` and check every asset link; commit `docs: add the complete Settings guide`.

Acceptance: the published site has a first-class Settings page whose screenshots and option tables match the current UI exactly.

## Task 7: Final validation and draft PR update

**Files:** only fixes discovered by validation; update the PR body/checklist.

- [ ] Run `./build-debug.sh -Xswiftc -warnings-as-errors`.
- [ ] Run `./swift-test.sh` and record the XCTest count/zero failures.
- [ ] Run `mkdocs build --strict -d .site`.
- [ ] Run targeted SwiftFormat lint only on branch-owned Swift files; classify repo-main findings separately.
- [ ] Run the opt-in real-config dry run and confirm `git status --short` is unchanged afterward.
- [ ] GUI checklist on MacBook: direct menu, all 12 panes, all tooltips/diagrams, migration warning, Save freeze, backup reveal, symlink save, immediate relayout, Revert, raw-only recovery, ambiguous-config mode.
- [ ] Inspect the real migration diff: only `config-version` and `persistent-workspaces` plus intentionally edited UI fields may differ.
- [ ] Push commits to `feat/settings-navigation-migration-docs` and revise draft PR #62 with test evidence, screenshots, backup example, remaining manual items, and explicit dependency on PR #61 until it merges.
- [ ] Request whole-branch review. Resolve Critical/Important findings; rerun all gates.
- [ ] Mark ready for review only after PR #61 is merged and GitHub reports a clean, mergeable diff against `main`.

## Plan self-review checklist

- [x] Every approved spec section maps to a task.
- [x] Migration ordering does not rely on dictionary iteration.
- [x] Other edits made in the same Save are applied after migration against a migrated baseline.
- [x] Candidate validation precedes backup; backup precedes real write.
- [x] Symlink, permissions, collision, restore, and no-backup-on-normal-save cases are explicit.
- [x] Comprehensive and real-file read-only validation are separate.
- [x] All twelve screenshots and every Settings destination are named.
- [x] No placeholder, TODO, “similar”, or omitted implementation step remains.
