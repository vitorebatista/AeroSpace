# CLAUDE.md

Guidance for Claude Code (and other AI agents) working in this repository.

## What this repo is

AeroSpace is an i3-like tiling window manager for macOS, written in Swift. This
repository is a **maintained fork of [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)**
that backports upstream bug fixes and small features not yet merged upstream. See
[`CHANGELOG-FORK.md`](./CHANGELOG-FORK.md) for what has been backported and
[`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) for fork/release workflow.

It is a client/server app: the `aerospace-edge` CLI (client) talks to `AeroSpace-edge.app`
(server) over a UNIX socket. See [`dev-docs/architecture.md`](./dev-docs/architecture.md)
for the layout and [`dev-docs/development.md`](./dev-docs/development.md) for the full
local build setup (Xcode, swiftly, codesign certificate, etc.).

## Source layout

- `Sources/AppBundle/` — the server (`AeroSpace-edge.app`); an SPM library. Most logic lives here:
  `command/` (command impls), `config/` (TOML config parsing), `tree/` (window/workspace
  tree model), `layout/` (tiling/layout engine), `ui/` (menu bar SwiftUI), `mouse/`.
- `Sources/Cli/` — the `aerospace-edge` CLI client (pure SPM).
- `Sources/Common/` — code shared between client and server, mainly command-line arg
  parsing (`cmdArgs/`) and utilities.
- `Sources/AppBundleTests/` — tests (XCTest), mirrors the `AppBundle` structure.
- `docs-md/` — Markdown sources for the website (Material for MkDocs) and man pages.
- `docs/config-examples/` — TOML configs shipped with the app and asserted on in tests.
- `grammar/` — shell-completion grammar and the command BNF grammar.

## Build & test commands

Always run scripts from the repo root. They `source ./script/setup.sh`, which uses
`swiftly` to pin the Swift toolchain to `.swift-version`.

- **Debug build (compile check):** `./script/build-debug.sh -Xswiftc -warnings-as-errors`
  Builds the app + the `AppBundleTests` target via SPM into `.debug/`. The
  `-Xswiftc -warnings-as-errors` flag is the project's bar — **warnings are errors**.
- **Run tests:** `./script/swift-test.sh`
  Runs `swift test`. Rely on the **exit code** and the `✅ Swift tests have passed
  successfully` line. The script filters XCTest's per-case output, so a
  `Test run with 0 tests in 0 suites passed` line (from the Swift Testing framework) is
  normal and does NOT mean tests didn't run. To confirm a specific new test executes:
  `swift test --filter <TestName>`.
- **Full check (what CI runs):** `./script/test.sh` — debug build (warnings-as-errors) + tests +
  `aerospace-edge -h/--help/--version` smoke checks + lint + `script/generate.sh` + a clean-tree check.
- **Format:** `./script/format.sh` (swiftformat). **Lint:** `./script/lint.sh`.
- **Release build:** `./script/build-release.sh --build-version <ver> --codesign-identity aerospace-codesign-certificate`
  (Xcode-based, outputs `.release/AeroSpace-edge-v<ver>.zip`). Do NOT use
  `script/publish-release.sh` in this fork — it pushes tags to the upstream repo.
  **Never release with `--codesign-identity -`.** Ad-hoc signatures have no certificate, so the
  designated requirement is the literal binary hash and macOS drops every user's Accessibility
  grant on each update. `script/create-codesign-certificate.sh` creates the certificate; see
  "Signing identity" in `dev-docs/fork-maintenance.md`. CI is the one exception (no keychain).
- **Debug .app bundle** (to actually run the UI, not just compile): `script/build-debug.sh` produces an
  SPM binary, not a bundle. For a runnable app, `xcodebuild -configuration Debug` produces
  `AeroSpace-edge-Debug.app` with bundle id `vitorebatista.aerospace-edge.debug` — a *separate*
  app from the release install, with its own Accessibility grant and its own menu-bar item, so it
  can be tested without uninstalling anything. Launch the executable inside the bundle directly
  (`.../Contents/MacOS/AeroSpace-edge-Debug`) if you want its `print` output: a bundle launched
  via `open` sends stdout and stderr to /dev/null.

A change is only "done" when `./script/build-debug.sh -Xswiftc -warnings-as-errors` **and**
`./script/swift-test.sh` both pass with a clean working tree afterward.

## Generated files — never hand-edit

Some tracked source files are generated and have a `Generated` suffix:

- `Sources/Common/cmdHelpGenerated.swift` — generated from the ` ```synopsis ` fenced block
  of `docs-md/commands/*.md` by `./script/generate-cmd-help.sh`.
- `Sources/Cli/subcommandDescriptionsGenerated.swift` — generated from the `description:`
  frontmatter key in `docs-md/commands/*.md` (regenerated automatically by `script/build-debug.sh`).
- `Sources/Common/versionGenerated.swift`, `Sources/Common/gitHashGenerated.swift` — generated.
- `ShellParserGenerated/` — generated from the ANTLR grammar (`grammar/ShellLexer.g4`,
  `grammar/ShellParser.g4`) via `./script/generate-shell-parser.sh` (needs antlr).

To change command help text, edit the ` ```synopsis ` block in the command's `.md` page and
run `./script/generate-cmd-help.sh` (pure bash/awk, no external deps) — do not edit the
generated `.swift` by hand. `script/build-debug.sh` reproduces the generated files
deterministically, so a correct edit leaves the tree clean.

## Code conventions

- **Swift 6.3**, strict concurrency, and **`-strict-memory-safety` is enabled**. Reads of
  certain unsafe values need an explicit `unsafe` marker (e.g. `return unsafe _value`)
  that plain upstream code may omit — add it when the compiler requires it.
- **Command results** use the fork's result types: return `.succ` / `.fail(io.err("..."))`
  and `BinaryExitCode` rather than bare `Bool`. Match surrounding code.
- **Tests** live in `Sources/AppBundleTests` (XCTest). Window-classification tests are
  **data-driven**: fixtures in `axDumps/*.json5` carry the expected result inline (e.g.
  `"Aero.AxUiElementWindowType": "popup"`), and `AxWindowKindTest` iterates all of them.
  Prefer adding/adjusting an `axDumps` fixture over a synthetic mock when representing a
  real window kind — this is the maintainer-preferred convention.
- **App Intents live in `Sources/AeroSpaceApp/`, not `AppBundle`.** Xcode's metadata processor
  has to see them in the app target; across the package boundary extraction needs
  `AppIntentsPackage` conformance and is markedly more fragile. Keep them thin shells over
  `runAeroSpaceCommandFromAppIntent`.
- **Raw TOML is edited through `TomlTextEditor`, not SwiftUI's `TextEditor`.** `TextEditor`
  carries no per-range attributes on the macOS versions this app supports, so syntax colouring
  needs the `NSTextView` wrapper. `tomlTokens` is a pure function — colouring never parses, never
  rejects, and never blocks a save.
- Keep changes atomic and scoped. Stick to existing structure; don't refactor unrelated
  code "along the way" (see `CONTRIBUTING.md`).

## Documentation is part of the change (Command checklist)

When a change adds or modifies a **command, CLI flag, config option, or format variable**,
update the user-facing docs in the SAME change. From `dev-docs/architecture.md`:

- [ ] `docs-md/commands/<command>.md` — the ` ```synopsis ` block **and** the description
      body / examples for the new flag or subcommand.
- [ ] `mkdocs.yml` nav + the card list in `docs-md/index.md` if the command list itself changes.
- [ ] `docs-md/guide.md` and/or `docs/config-examples/default-config.toml` for new config
      options or user-visible behavior.
- [ ] `grammar/commands-bnf-grammar.txt` for shell completion.
- [ ] Regenerate generated files (`./script/generate-cmd-help.sh`; `script/build-debug.sh` handles
      `subcommandDescriptionsGenerated.swift`).
- [ ] Consider whether `--window-id` and/or `--workspace` flags make sense for the command.
- [ ] Add/extend tests in `Sources/AppBundleTests` where the behavior is unit-testable; if
      it's purely runtime/Accessibility-API behavior, say so explicitly rather than faking a test.

Keep doc wording consistent with the actual parser (e.g. if an option splits on commas, the
docs must say "comma-separated", not "space-separated").

## Settings window checklist

The Settings window (`Sources/AppBundle/ui/settings/`) is a fork-original feature and its own
documentation surface. When adding or changing a control:

- [ ] Give it a `SettingHelpTopic` in `SettingsHelp.swift` and label it with `SettingHelpLabel`.
      Every control gets one — `SettingsHelpTest` enforces summary, details and TOML keys.
- [ ] Name the **TOML key(s)** the control writes. A control with no TOML key is an *app
      preference* (menu-bar style/position) or an immediate action (open config, crash reports);
      those are listed explicitly in `SettingsHelpTest.appPreferenceTopics`, and their popover
      says "Not a config option". Anything else missing a key fails the test.
- [ ] If the user has to type a **structure** (a mapping, a list, a colour, a monitor pattern),
      fill `examples:` with concrete correct lines. They appear in the hover tooltip *and* the
      popover. A description of a format is not a format.
- [ ] A new sidebar destination needs: a `SettingsCategory` case, a `systemImage`, a branch in
      `docsUrl`, a page at `docs-md/settings/<page>.md`, a `mkdocs.yml` nav entry, and a row in
      the table in `docs-md/settings/index.md`. `SettingsHelpTest` asserts every `docsUrl` lands
      on a file that exists.
- [ ] Decide **config vs app preference** deliberately. The TOML travels between machines and is
      shared; anything meaningful only on one screen or one machine (menu-bar item position) is an
      app preference in `ExperimentalUISettings`, stored in `UserDefaults`, and must not dirty the
      config draft.

### Menu-bar item facts worth knowing

- macOS persists a status item's position per app under `NSStatusItem Preferred Position Item-0`
  in the app's own defaults domain (points from the right edge; bigger is further left), and
  restores it at launch. A new bundle id on a full menu bar gets parked past the notch, where it
  is invisible and undraggable. `applyMenuBarItemPosition()` rewrites that key in
  `initAppBundle()` — **before** the scene builds, because nothing can move the item once
  `MenuBarExtra` has created it.
- `Item-0` is the autosave name SwiftUI generates for a single `MenuBarExtra`; there is no API to
  ask for it. A second `MenuBarExtra` silently breaks the pinning.
- The menu lists workspaces from `TrayMenuModel`, which merges live workspaces (`Workspace.all`)
  with the names `workspaceNamesMentionedIn(config)` returns. `Workspace.all` holds only live
  workspaces, so on `config-version = 2` a workspace that exists solely in a binding is not there
  — that merge is what makes it reachable under "New".

## Fork workflow

- The fork sits on a fixed upstream **base commit** (`63e0976b`) plus a curated set of backported
  PRs — it does **not** blindly track upstream `main`. Backport branches are `port/<upstream-PR-or-slug>`,
  branched off `origin/main`; each opens one PR against the fork's `main`.
- **Updating the fork from upstream → read [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) FIRST.**
  It is the single source of truth for syncs: it lists what's already ported (so you skip re-triage),
  the current upstream sync point, the exact env-specific commands, conflict/merge strategy, the lean
  release build, and how to cut a `-fork.N` release. It's written to make a sync fast and low-token.
- When porting an upstream PR, fetch its real diff via
  `gh api repos/nikitabobko/AeroSpace/pulls/<N> -H "Accept: application/vnd.github.v3.diff"`
  (the `gh pr diff` output is reformatted in this environment and won't `git apply`); cherry-pick
  upstream `main` commits directly via the `upstream` remote.
- Preserve upstream attribution and the MIT license (`Copyright (c) 2023 Nikita Bobko`).
