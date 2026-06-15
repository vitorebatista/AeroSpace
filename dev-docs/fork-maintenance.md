# Fork maintenance

Maintainer runbook for the `vitorebatista/AeroSpace` fork. All credit for AeroSpace belongs to
[@nikitabobko](https://github.com/nikitabobko) and contributors. MIT license + attribution preserved.

> **For AI agents / future sessions:** this file is the single source of truth for "update my fork
> from upstream." Read it first. It tells you what's already ported (so you don't re-triage), the
> exact commands that work **in this environment**, and the env-specific gotchas. Follow it instead
> of re-discovering everything.

## The fork model

- The fork does **not** blindly track upstream `main`. It sits on a fixed **upstream base commit**
  plus a curated set of **backported bug fixes / small features**, each merged as its own PR.
- We intentionally **skip** large refactors and features that would conflict with the curated
  backports (see "Deliberately not ported" below).
- `origin` = `vitorebatista/AeroSpace` (the fork). `upstream` = `nikitabobko/AeroSpace`.
  If `upstream` is missing: `git remote add upstream https://github.com/nikitabobko/AeroSpace.git`

## Sync state (update this section every sync)

- **Upstream base commit:** `63e0976b` (the fork branched from upstream `main` here).
- **Last upstream review point:** upstream `main` @ `a60f9630` (2026-06-14), 45 open upstream PRs,
  reviewed 2026-06-15. New work after this point is what a future sync should look at.
  (Previous point: `a1465c23`, 2026-06-10, reviewed 2026-06-12.) The 2026-06-15 sync found
  **nothing new in default scope** — the only standalone bug fix in the delta (Outlook reminders →
  popups, `a60f9630`, which closes upstream #2103) is already ported (fork PR #1); everything else
  new was a large refactor or a feature depending on one (see skip list below).
- **Released:** `v0.20.3-Beta-fork.2` (28 backports total). See [`CHANGELOG-FORK.md`](../CHANGELOG-FORK.md).

### Already backported — DO NOT re-port these
Upstream PRs (by upstream number): 2103, 2081, 2012, 2024, 2098, 2052, 1944, 1926, 1953, 1529,
2097, 2080, 1156, 2082, 1665, 1708, 1778, 1932, 2085, 1344, 2083, 1349, 2109, 2116, 2107.
Upstream `main` commits cherry-picked: `19b5999d` (swap MRU), `8b236f1b` (die deadlock),
`a0f17f88` (parseConfig exception).

### Deliberately NOT ported (skip unless explicitly requested)
- Upstream PR **#2114** "Add sticky window support" — duplicate of our `layout sticky` (PR #2083/#21).
- Upstream PR **#2108** "cycle window size at edge" — conflicts; not requested.
- Large upstream-`main` refactors after our base: the `on-window-detected[*].if` type change
  (TOML table → arbitrary command), the `InterVar` → typed-enum refactor, the
  `ConfigParseError` → `ConfigParseDiagnostic` rework, the Swift bump. These conflict with several
  curated backports. Pulling them in = a **full resync milestone**, not a quick PR — only do it if
  the user explicitly asks to "track upstream main."
- Upstream-`main` refactor chain merged 2026-06-10..06-14 (reviewed 2026-06-15, all part of the
  "track upstream main" milestone, not quick PRs):
  - `4242863b`/`cf6244e7`/`61f0eac9`/`cd64d085` — `ParseConfigResult.errors` → `ConfigParseDiagnostic`
    + readConfig return-type rework (the same family as the `ConfigParseDiagnostic` item above).
  - `317b8d38`/`175b88f6` — ReloadConfigCommand drops `Task.startUnstructured` (absent in fork).
  - `890ec336` — config "warnings mechanism".
  - `a0e43e55`/`6a118fe3` — `test` operator-syntax change + new `test-not` subcommand (breaking
    config-syntax change).
  - `5e37ec0a`/`90347dbb`/`f1f50259` — tree-structure refactor (FloatingWindowsContainer,
    TilingContainerParentCases) — 21-file refactor.
- Upstream **`layout --root` / `--workspace` / empty-workspace** feature set (`11ba9150`, `91064acc`,
  `bb1e5429`, completion fix `4ad2a573`) — features whose semantics sit on top of the `5e37ec0a` tree
  refactor above; can't be cleanly backported without dragging in the refactor. Skipped 2026-06-15
  (not requested). Revisit if/when a full resync happens.
- Upstream CI / build-docs / test-infra commits (`e82b4644`/`78e6dd80`/`ebef281e` GH Actions,
  `2f4d5039`, `c28d3469`, `d07cfee4`, `6ec50638`, `e47d5989`, `abd944d7`, `e063e2fe`) — upstream-only
  tooling or docs for skipped features; nothing to port.

## Updating the fork from upstream — step by step

### 1. Find what's new (cheap; no code changes)
```bash
git fetch upstream --quiet
# New commits on upstream main since our base (already-ported shas are listed above — ignore them):
git log --oneline 63e0976b..upstream/main
# New OPEN upstream PRs (compare numbers against "Already backported" + "Not ported" lists above):
gh pr list --repo nikitabobko/AeroSpace --state open --limit 100 \
  --json number,title,createdAt,isDraft --jq 'sort_by(.createdAt)[] | "\(.number)\t\(.createdAt[0:10])\t\(.title)"'
```
Classify the delta as bug-fix / safe-small-feature / large-feature / docs / obsolete. Default scope
is **bug fixes + safe small features**; confirm scope with the user before porting features.

### 2. Port each item on its own branch off `origin/main`
```bash
git checkout -B port/<slug> origin/main
```
- **From an upstream PR:** get the diff via the GitHub API (NOT `gh pr diff` — it is reformatted in
  this environment and won't `git apply`):
  ```bash
  gh api repos/nikitabobko/AeroSpace/pulls/<N> -H "Accept: application/vnd.github.v3.diff" > /tmp/<N>.diff
  git apply --3way /tmp/<N>.diff      # on conflict: git apply --reject, then re-implement by hand
  ```
- **From an upstream `main` commit:** `git cherry-pick <sha>` (works because `upstream` is fetched).

### 3. Adapt to fork conventions (these differ from upstream)
- **`-strict-memory-safety` is on** → some reads need an explicit `unsafe` marker (e.g.
  `return unsafe _value`) that upstream omits. Add it when the compiler demands.
- **Command results** use `.succ` / `.fail(io.err("..."))` / `BinaryExitCode`, not bare `Bool`.
- **`terminationHandler`** is non-optional in the fork; there is no `Task.startUnstructured`.
- **Window-classification tests are data-driven**: add an `axDumps/*.json5` fixture with the
  expected result inline (e.g. `"Aero.AxUiElementWindowType": "popup"`) rather than a synthetic mock.
- **Generated files** (`cmdHelpGenerated.swift`, `subcommandDescriptionsGenerated.swift`) come from
  `docs/aerospace-*.adoc`. Edit the `.adoc`, then `./script/generate-cmd-help.sh` (build-debug
  regenerates `subcommandDescriptions`). Never hand-edit the generated `.swift`.
- **Docs are part of the change** (see CLAUDE.md command checklist): new flag/command/config/format
  var → update the relevant `.adoc` + `docs/guide.adoc`/`default-config.toml` + the `<event>`/rule in
  `grammar/commands-bnf-grammar.txt`.

### 4. Verify every branch (the bar)
```bash
./build-debug.sh -Xswiftc -warnings-as-errors    # must exit 0 (warnings are errors)
./swift-test.sh                                   # rely on exit 0 + "✅ Swift tests have passed"
```
The "Test run with 0 tests in 0 suites passed" line is normal (Swift Testing framework); XCTest pass
lines are filtered by the script. IDE/SourceKit diagnostics often lag and show false errors after a
merge — trust the `-warnings-as-errors` build, not the diagnostics.

### 5. Open one PR per fix
```bash
git push -u origin port/<slug>
gh pr create --repo vitorebatista/AeroSpace --base main --head port/<slug> --title "..." --body "..."
```
gh's default repo is the fork (`gh repo set-default vitorebatista/AeroSpace` if ever needed) — always
pass `--repo vitorebatista/AeroSpace` to be safe. PR body: summary + `Ports nikitabobko/AeroSpace#<N>`
(or `Backports upstream commit <sha>`) + test/doc coverage + caveats.

### 6. Merge (local merge train — handles the many shared-file conflicts efficiently)
Merging one-by-one on GitHub triggers cascading rebases. Instead, integrate locally in dependency
order, then push (GitHub auto-marks each PR "Merged" once its branch tip is in `main`):
```bash
git checkout main && git reset --hard origin/main
git merge --no-ff --no-edit origin/port/<slug> -m "Merge pull request #<forkN> from vitorebatista/port/<slug>" -m "<title>"
# ... repeat per branch; merge independent ones first, file-sharing ones adjacently.
```
- **Additive config conflicts** (two PRs both add fields to `Config.swift`/`parseConfig.swift`/
  `ConfigTest.swift`/`default-config.toml`, empty diff3 base) → resolve by **union** (keep both
  sides). Watch for a function whose closing `}` lived in the shared post-conflict region (union can
  drop one brace — add it back; the build will flag it).
- After all merges: one final `./build-debug.sh -Xswiftc -warnings-as-errors` + `./swift-test.sh`,
  confirm no conflict markers (`git grep -nE '^(<<<<<<<|>>>>>>>)' -- . ':!docs/superpowers'`), then
  `git push origin main`.

## Building a release binary (what actually works in this environment)

`./build-release.sh` **fails here** on optional packaging extras (not the app): `build-docs.sh`
needs Ruby-under-`mise` on PATH, `build-shell-completion.sh` needs `fish` + `bash >= 5` — none are
installed. Two workarounds:

**A. Make the official script work** (if you want man pages + completions): `brew install fish bash`,
and add a `mise` shim so the docs step's rubygems plugin finds it:
```bash
printf "exec '/opt/homebrew/bin/mise' \"\$@\"\n" > .deps/bin/mise && chmod +x .deps/bin/mise
NUKE_PATH=1 PATH="$PWD/.deps/bin:/opt/homebrew/bin:/bin:/usr/bin" \
  ./build-release.sh --build-version "0.20.3-Beta-fork.N" --codesign-identity -
```

**B. Lean build (recommended — app + CLI, no man pages/completions).** Put the steps in a script and
run it with `zsh script.sh`, because the interactive shell hook rewrites `rm`/`ls`/etc. (e.g. it turns
`rm -rf` into GNU-flagged `rm` that fails on macOS); running inside a script file bypasses the rewrite.
The script (see git history of `/tmp/lean-release2.sh` pattern) does, with
`NUKE_PATH=1 PATH="$PWD/.deps/bin:/opt/homebrew/bin:/bin:/usr/bin"`:
1. `./generate.sh --ignore-shell-parser --ignore-cmd-help --build-version "0.20.3-Beta-fork.N" --codesign-identity - --generate-git-hash`
2. `swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors`
3. `xcrun xcodebuild clean build -scheme AeroSpace -destination "generic/platform=macOS" -configuration Release -derivedDataPath .xcode-build`
4. `git checkout .` (restores generated files + `project.pbxproj` that xcodegen/version-stamping dirtied)
5. assemble `.release/AeroSpace-v<ver>/` = `AeroSpace.app` (from `.xcode-build/Build/Products/Release/`)
   + `bin/aerospace` (`codesign -s - --force`) + `legal/`, then `zip -qr`.
- The app is codesigned ad-hoc by xcodebuild (`--codesign-identity -`); both binaries come out universal.
- **Verify** baked-in version WITHOUT running the CLI (it can hang in non-interactive shells):
  `plutil -extract CFBundleShortVersionString raw .release/AeroSpace.app/Contents/Info.plist` and
  `strings .release/aerospace | grep <ver>`.

## Creating the GitHub release
```bash
gh release create "v0.20.3-Beta-fork.N" ".release/AeroSpace-v0.20.3-Beta-fork.N.zip" \
  --repo vitorebatista/AeroSpace --target main --prerelease \
  --title "AeroSpace v0.20.3-Beta-fork.N" --notes-file <notes.md>
```
- Version scheme: upstream beta base + `-fork.N`; bump `N` each release. The version shows in the
  menu bar and `aerospace --version`.
- Do **not** use `script/publish-release.sh` (it pushes tags to the upstream repo).
- After releasing, **update the "Sync state" section above** and append to `CHANGELOG-FORK.md`.

## CI
`.github/workflows/build.yml` verifies builds across macOS versions once GitHub Actions is enabled on
the fork. `close-third-party-issues.yml` is upstream-only tooling — safe to disable on the fork.
