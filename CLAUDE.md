# CLAUDE.md

Guidance for Claude Code (and other AI agents) working in this repository.

## What this repo is

AeroSpace is an i3-like tiling window manager for macOS, written in Swift. This
repository is a **maintained fork of [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)**
that backports upstream bug fixes and small features not yet merged upstream. See
[`CHANGELOG-FORK.md`](./CHANGELOG-FORK.md) for what has been backported and
[`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) for fork/release workflow.

It is a client/server app: the `aerospace` CLI (client) talks to `AeroSpace.app`
(server) over a UNIX socket. See [`dev-docs/architecture.md`](./dev-docs/architecture.md)
for the layout and [`dev-docs/development.md`](./dev-docs/development.md) for the full
local build setup (Xcode, swiftly, codesign certificate, etc.).

## Source layout

- `Sources/AppBundle/` — the server (`AeroSpace.app`); an SPM library. Most logic lives here:
  `command/` (command impls), `config/` (TOML config parsing), `tree/` (window/workspace
  tree model), `layout/` (tiling/layout engine), `ui/` (menu bar SwiftUI), `mouse/`.
- `Sources/Cli/` — the `aerospace` CLI client (pure SPM).
- `Sources/Common/` — code shared between client and server, mainly command-line arg
  parsing (`cmdArgs/`) and utilities.
- `Sources/AppBundleTests/` — tests (XCTest), mirrors the `AppBundle` structure.
- `docs/` — Asciidoc (`.adoc`) sources for the website and man pages.
- `grammar/` — shell-completion grammar and the command BNF grammar.

## Build & test commands

Always run scripts from the repo root. They `source ./script/setup.sh`, which uses
`swiftly` to pin the Swift toolchain to `.swift-version`.

- **Debug build (compile check):** `./build-debug.sh -Xswiftc -warnings-as-errors`
  Builds the app + the `AppBundleTests` target via SPM into `.debug/`. The
  `-Xswiftc -warnings-as-errors` flag is the project's bar — **warnings are errors**.
- **Run tests:** `./swift-test.sh`
  Runs `swift test`. Rely on the **exit code** and the `✅ Swift tests have passed
  successfully` line. The script filters XCTest's per-case output, so a
  `Test run with 0 tests in 0 suites passed` line (from the Swift Testing framework) is
  normal and does NOT mean tests didn't run. To confirm a specific new test executes:
  `swift test --filter <TestName>`.
- **Full check (what CI runs):** `./test.sh` — debug build (warnings-as-errors) + tests +
  `aerospace -h/--help/--version` smoke checks + lint + `generate.sh` + a clean-tree check.
- **Format:** `./format.sh` (swiftformat). **Lint:** `./lint.sh`.
- **Release build:** `./build-release.sh --build-version <ver> --codesign-identity -`
  (Xcode-based, outputs `.release/AeroSpace-v<ver>.zip`). Do NOT use
  `script/publish-release.sh` in this fork — it pushes tags to the upstream repo.

A change is only "done" when `./build-debug.sh -Xswiftc -warnings-as-errors` **and**
`./swift-test.sh` both pass with a clean working tree afterward.

## Generated files — never hand-edit

Some tracked source files are generated and have a `Generated` suffix:

- `Sources/Common/cmdHelpGenerated.swift` — generated from the `tag::synopsis` blocks of
  `docs/aerospace-*.adoc` by `./script/generate-cmd-help.sh`.
- `Sources/Cli/subcommandDescriptionsGenerated.swift` — generated from `:manpurpose:` in
  `docs/aerospace-*.adoc` (regenerated automatically by `build-debug.sh`).
- `Sources/Common/versionGenerated.swift`, `Sources/Common/gitHashGenerated.swift` — generated.
- `ShellParserGenerated/` — generated from the ANTLR grammar (`grammar/ShellLexer.g4`,
  `grammar/ShellParser.g4`) via `./script/generate-shell-parser.sh` (needs antlr).

To change command help text, edit the `.adoc` synopsis and run
`./script/generate-cmd-help.sh` (pure bash/sed, no external deps) — do not edit the
generated `.swift` by hand. `build-debug.sh` reproduces the generated files
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
- Keep changes atomic and scoped. Stick to existing structure; don't refactor unrelated
  code "along the way" (see `CONTRIBUTING.md`).

## Documentation is part of the change (Command checklist)

When a change adds or modifies a **command, CLI flag, config option, or format variable**,
update the user-facing docs in the SAME change. From `dev-docs/architecture.md`:

- [ ] `docs/aerospace-<command>.adoc` — synopsis (`tag::synopsis`) **and** the description
      body / examples for the new flag or subcommand.
- [ ] `docs/commands.adoc` if the command list itself changes.
- [ ] `docs/guide.adoc` and/or `docs/config-examples/default-config.toml` for new config
      options or user-visible behavior.
- [ ] `grammar/commands-bnf-grammar.txt` for shell completion.
- [ ] Regenerate generated files (`./script/generate-cmd-help.sh`; `build-debug.sh` handles
      `subcommandDescriptionsGenerated.swift`).
- [ ] Consider whether `--window-id` and/or `--workspace` flags make sense for the command.
- [ ] Add/extend tests in `Sources/AppBundleTests` where the behavior is unit-testable; if
      it's purely runtime/Accessibility-API behavior, say so explicitly rather than faking a test.

Keep doc wording consistent with the actual parser (e.g. if an option splits on commas, the
docs must say "comma-separated", not "space-separated").

## Fork workflow

- This fork's `main` tracks upstream `main`. Backport branches are named `port/<upstream-PR>-<slug>`
  and branch off `origin/main`; each opens one PR against this fork's `main`.
- When porting an upstream PR, fetch its real diff via
  `gh api repos/nikitabobko/AeroSpace/pulls/<N> -H "Accept: application/vnd.github.v3.diff"`
  (the `gh pr diff` output is reformatted in some environments and won't `git apply`).
- Preserve upstream attribution and the MIT license (`Copyright (c) 2023 Nikita Bobko`).
- See `dev-docs/fork-maintenance.md` for versioning (`-fork.N` suffix) and merge-order notes.
