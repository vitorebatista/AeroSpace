# Fork Changelog

This fork backports upstream pull requests that are already implemented in
[nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) but not yet merged into an
upstream release. The base for all of these backports is upstream `main` at commit `63e0976b`.

Each entry links the original upstream PR (where all credit belongs) and the corresponding fork
PR that backports it. This fork is not an official release and is not affiliated with or endorsed
by the upstream maintainer.

## Versioning

AeroSpace-edge versions itself independently of upstream, as `1.MINOR[.PATCH]`:

- **minor** — new behavior: upstream backports (the usual case) or a fork-original feature.
- **patch** — a fix, docs, or packaging change that adds no new behavior.
- **major** — reserved for a breaking change to config syntax or the CLI.

The upstream commit this fork is based on (`63e0976b`) is recorded here and in
[`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) rather than in the version string.

> **Renumbered 2026-08-27.** Releases 1 through 10 were originally published as
> `v0.20.3-Beta-fork.1` … `v0.20.3-Beta-fork.10` and have been retagged to `v1.1` … `v1.10`.
> The old tags are gone, so links to them no longer resolve. The build attached to each release
> older than 1.10 still reports its original `0.20.3-Beta-fork.N` version string internally —
> only 1.10 was rebuilt under the new scheme.

## v1.14 (2026-08-28)

**Settings window.** AeroSpace-edge can now edit its own config from a GUI, reachable from
Settings → **Settings…** in the menu bar menu. It edits the same config file the fork
already resolves at startup (`~/.aerospace-edge.toml`, or the `XDG_CONFIG_HOME` equivalent)
in place, rather than being a separate config store. Fork-only; no upstream equivalent.

- **Save validates before it writes.** The rendered document is checked with the same
  parser AeroSpace uses at startup; if the result wouldn't load, nothing is written and the
  error is shown in the window instead.
- **Form controls for options with a fixed set of values,** covering general, layout, gaps,
  focus, window border, workspaces/monitors, key mapping, and exec settings.
- **Keybindings, window rules, and callbacks are edited as TOML text** in their own
  sections, since the AeroSpace command DSL isn't a fixed set of values — each pane gives
  advisory parse feedback as you type, with the caveat that it's checked as a fragment and
  Save validates the whole file.
- **Comments, key order, and unknown keys survive a save,** with one exception: the
  `gaps`, `key-mapping`, `exec`, and `workspace-to-monitor-force-assignment` tables —
  including their sub-tables (`[gaps.inner]`, `[key-mapping.key-notation-to-key-code]`,
  `[exec.env-vars]`, and similar) — are regenerated in full whenever a value in them
  changes, so comments written there don't survive.
- **Degrades safely when it can't edit normally:** an unparseable config opens as a single
  raw editor over the whole file with the parse error shown, and if several config files
  exist at once the window refuses to write anything rather than guess which one you meant.

## v1.13 (2026-08-28)

Menu-bar menu reorganised. With 35 configured workspaces and ~10 in use, the old menu listed all 35 at
the top level, so "Quit" and everything else sat below a 25-item wall of empty workspaces.

- **Only workspaces in use are listed.** Empty ones move into a **New** submenu. "In use" means has
  windows, is visible on a monitor, or is focused — a workspace you're looking at stays put even when
  empty, instead of vanishing into a submenu as its last window closes.
- **New "Settings" submenu** holds Enable/Disable, Open config, Reload config, Experimental UI Settings,
  and Check for Updates.
- **"Sponsor AeroSpace on GitHub" removed** from the menu. The sponsor link is still in the README —
  support for upstream belongs there, not in a menu the user opens dozens of times a day.
- **"Copy to clipboard" moved** out of the top level into Check for Updates → **Copy Version Info**,
  next to the version it copies.

Top level is now: version, workspaces in use, New, Settings, Quit.

## v1.12 (2026-08-27)

- **"Check for Updates…" in the menu bar.** Finds the newest release, shows what changed, and on
  confirmation downloads it, verifies it, replaces the app (and the CLI, where it's writable) in place,
  and relaunches. Fork-only; no upstream equivalent.
  - Versions compare component-wise and numerically, so 1.10 correctly sorts after 1.9 — a string
    comparison would have told every 1.10+ user to "update" back to 1.9 forever.
  - It reads the full release list rather than GitHub's `/releases/latest`, which skips prereleases:
    every AeroSpace-edge release is a prerelease, so that endpoint would report "no updates" forever.
  - Downloads are restricted to HTTPS on GitHub's own hosts, re-checked after redirects, and the
    unpacked payload is rejected unless its bundle id and version match the release it claims to be —
    the app is replacing its own bundle with this, so it's a trust boundary.
  - Because builds are ad-hoc signed, macOS revokes Accessibility whenever the app is replaced. The
    updater says so up front instead of leaving the user with an app that appears to quit on launch.
    A paid Apple Developer ID would remove that step.

## v1.11 (2026-08-27)

- **Refuses to start while another AeroSpace is running.** Two tiling window managers on the same
  keybindings fight over the same windows, so on startup AeroSpace-edge looks for a running upstream
  AeroSpace (`bobko.aerospace`, or its debug build) and blocks with a dialog: quit the other one and
  continue, or quit AeroSpace-edge and keep what's already running. It re-checks after quitting the
  other app, so a refused or slow quit re-prompts instead of starting anyway. The check runs before the
  Accessibility prompt — a window-manager conflict is the more useful thing to be told about — and is
  skipped under `--read-only`, which doesn't manage windows. Fork-only; no upstream equivalent.

## v1.10 (2026-08-27)

No upstream backports in this one. The fork becomes **its own app**, so it can be installed and tried
side by side with an upstream AeroSpace install instead of replacing it.

- App is now `AeroSpace-edge.app` (debug: `AeroSpace-edge-Debug.app`), bundle id
  `vitorebatista.aerospace-edge`, CLI `aerospace-edge`. Separate Spotlight entry, separate icon,
  separate Accessibility grant, separate `start-at-login` registration.
- Socket moves with the bundle id — `/tmp/vitorebatista.aerospace-edge-${USER}.sock`. Third-party
  socket clients pointed at the fork need this path; upstream's socket is untouched, so both servers
  can be installed at once (run one at a time — two window managers on the same keybindings fight).
- **Config falls back to upstream's.** With no `~/.aerospace-edge.toml` (or
  `${XDG_CONFIG_HOME}/aerospace-edge/aerospace-edge.toml`), the fork reads `~/.aerospace.toml` /
  `${XDG_CONFIG_HOME}/aerospace/aerospace.toml`, so a comparison runs on the very same config. Create
  the edge-specific file only for fork-only options that upstream would refuse to parse. The fork's own
  config wins when present; having both is not an "ambiguous config" error. Covered by `ConfigFileTest`.
- The legacy LaunchAgent cleanup is now scoped to the fork's own id — it will not delete a co-installed
  upstream AeroSpace's `bobko.aerospace.plist`.
- New logo and app icon; repo renamed to `vitorebatista/AeroSpace-edge`; README rewritten.
- Release zips are now `AeroSpace-edge-v<ver>.zip` and ship `legal/` (LICENSE + third-party licenses),
  which the 1.9 zip was missing.

Upgrading from 1.9 or earlier: the old `AeroSpace.app` and `aerospace` CLI are a *different app* to
macOS now. Delete them if you don't want both, and grant Accessibility to `AeroSpace-edge.app`.

## v1.9 (2026-08-27)

New backports since 1.8 (delta past upstream review point `d56e1637`; 2 new upstream-`main`
commits — both skipped, see below — and 17 new open upstream PRs triaged). Bug fixes only, plus one
tree-model fix; no new features.

- Fix iTerm2 Settings window detection — the Settings window has no fullscreen button, so the
  iTerm2 heuristic classified it as not-a-window; windows whose `AXIdentifier` is
  `mainPreferencesWindow` are now exempt from that check. Covered by a new `axDumps` fixture.
  (Upstream [nikitabobko/AeroSpace#2244](https://github.com/nikitabobko/AeroSpace/pull/2244); fork PR #55)
- Fix crash: cache `isUnitTest` instead of calling `NSClassFromString` on a hot path — the ObjC
  class lookup ran on every `mainMonitor` / `monitors` access and could crash with `EXC_BAD_ACCESS`
  inside dyld during display reconfiguration.
  (Upstream [nikitabobko/AeroSpace#2232](https://github.com/nikitabobko/AeroSpace/pull/2232); fork PR #56)
  - Fork adaptation: comment references the fork's `mainMonitor` / `monitors` (upstream has since
    renamed them to `mainMonitorInfo` / `monitorInfos`).
- `balance-sizes`: preserve the container's total weight instead of resetting every child to the
  constant `1`. A `resize` later in the same binding's command list no longer works against a total
  that doesn't match the monitor, so windows stop jumping.
  (Upstream [nikitabobko/AeroSpace#2211](https://github.com/nikitabobko/AeroSpace/pull/2211),
  upstream issue [#1837](https://github.com/nikitabobko/AeroSpace/issues/1837); fork PR #57)
  - Fork adaptation: tests rewritten against the fork's test API (direct command construction
    instead of upstream's `parseCommand` helper).
- `FocusCommand`: fix the `is already unbound` crash when two `focus` commands race —
  `makeFloatingWindowsSeenAsTiling` awaits `getCenter()` twice, and a concurrent `focus` could
  unbind the window in between. Both suspension points now re-validate the window.
  (Upstream [nikitabobko/AeroSpace#2228](https://github.com/nikitabobko/AeroSpace/pull/2228),
  upstream issue [#1311](https://github.com/nikitabobko/AeroSpace/issues/1311); fork PR #58)
  - Fork adaptations: floating windows are direct children of `Workspace` here (upstream's
    `floatingWindowsContainer` refactor isn't ported), so the guard is `window.parent === workspace`;
    tests use `Task { @MainActor in }` instead of upstream's `Task.startUnstructured`.
- Insert replaced native-tab windows into their old tree slot — apps that fold native tabs into one
  titlebar (Finder, Ghostty, Fork) keep the old tab's AX object alive but drop it from `AXWindows`,
  so switching tabs left a phantom tile and re-placed the visible tab via `on-window-detected`/MRU.
  The stale window is now retired and the replacement spliced into the exact slot (parent, index,
  weight, floating size, fullscreen state, cached geometry).
  (Upstream [nikitabobko/AeroSpace#2225](https://github.com/nikitabobko/AeroSpace/pull/2225); fork PR #59)
  - Fork adaptations: the fork's `getFocusedWindow()` / `runInLoop` take no `CancellationMode` and
    guard on `threadGuardedOrNil` (AX-destroy-race hardening, fork PR #43), so the new logic sits
    inside those guards and uses the unwrapped `axApp`.

Notable skips this cycle: upstream PRs #2238 / #2245 patch `mouse/focusFollowsMouse.swift`, which
this fork never ported; #2220 is a duplicate of #2024, already in the fork; #2213 removes
`lastNativeFocusedWindowId`, which the #2225 backport above depends on. Six feature PRs
(#2207, #2217, #2229, #2240, #2241, #2242) were deferred — this fork's bar is bug fixes plus small
safe features, and none were requested.

## v1.8 (2026-07-24)

- Socket protocol versions handshake — the server now answers the 4-byte protocol-version
  handshake modern upstream clients perform on connect, instead of deadlocking on it. Fixes
  third-party socket clients (AeroKit, aerospace-swipe, the upstream Homebrew-cask CLI)
  hanging or degrading to CLI shelling against the fork server. Also ports the guide's new
  "Socket protocol" documentation section.
  (Backports upstream commit [`8413641c`](https://github.com/nikitabobko/AeroSpace/commit/8413641c),
  upstream issue [#1513](https://github.com/nikitabobko/AeroSpace/issues/1513); fork PR #54)
  - Fork adaptations: upstream's `getIgnoringErrorsOrNil()` → the fork's `Result.getOrNil()`;
    upstream's `EvalCommandTest` tweak dropped (eval command family not ported).

## v1.7 (2026-07-24)

- New fork feature: `focus-follows-app-activation = 'always'|'smart'` config option — `smart`
  suppresses cross-workspace workspace switches caused by apps activating themselves (focus
  stealing) unless the activation was preceded by a mouse click. No upstream equivalent;
  i3 precedent: `focus_on_window_activation`. (fork PR #53)
- **KNOWN ISSUE with `smart` (field report 2026-07-24, unfixed):** windows moved to another
  workspace can reappear on the current workspace. Suspected: the suppression heuristic can't
  tell a keyboard-driven `move-node-to-workspace` (window left natively focused cross-workspace,
  no click) from a focus steal, and after suppressing it never re-layouts the offender's
  workspace, so a self-raised/re-positioned window gets re-filed into the visible workspace.
  Keep the default `'always'` until fixed. Fix direction: exempt AeroSpace-initiated commands
  from suppression + force-layout the offender's workspace after suppressing.

## v1.6 (2026-07-18)

New backports since 1.5 (delta past upstream review point `d56e1637`; no new upstream-`main` commits, three new open PRs triaged):

- Add `debug-windows --app-bundle-id <id>` to dump unregistered AX windows — upstream [nikitabobko/AeroSpace#2184](https://github.com/nikitabobko/AeroSpace/pull/2184) (fork PR #51)
- Add `enable-normalization` command for per-workspace normalization overrides — upstream [nikitabobko/AeroSpace#2190](https://github.com/nikitabobko/AeroSpace/pull/2190) (fork PR #52)
- Add AeroKit to the trackpad-gestures goodies list (docs) — upstream [nikitabobko/AeroSpace#2188](https://github.com/nikitabobko/AeroSpace/pull/2188) (fork PR #50)

## v1.5 (2026-07-14)

New backports since 1.4 (delta past upstream review point `649301b2`):

- Fix wisprFlow popup detection — upstream commits [`4a3aab24`](https://github.com/nikitabobko/AeroSpace/commit/4a3aab24) + [`d56e1637`](https://github.com/nikitabobko/AeroSpace/commit/d56e1637) (fork PR #46)
- Ignore windows with `kCGNullWindowID` window-id — upstream commit [`0f6b2e78`](https://github.com/nikitabobko/AeroSpace/commit/0f6b2e78) (fork PR #47)
- Add `window-closed` subscribe event — upstream [nikitabobko/AeroSpace#2181](https://github.com/nikitabobko/AeroSpace/pull/2181) (fork PR #48)
- Fix Device Hub (Xcode 27) compact-view flicker when tiled — upstream [nikitabobko/AeroSpace#2167](https://github.com/nikitabobko/AeroSpace/pull/2167) (fork PR #49)

## v1.4 (2026-07-10)

New backports since 1.3 (delta past upstream review point `fb8b1df6`):

- Fix menu-bar clicks stealing focus when "Displays have separate spaces" is off — upstream commit [`cfd4eab2`](https://github.com/nikitabobko/AeroSpace/commit/cfd4eab2) (fork PR #39)
- Add `window-moved-to-workspace` subscribe event — upstream [nikitabobko/AeroSpace#2162](https://github.com/nikitabobko/AeroSpace/pull/2162) (fork PR #40)
- FocusCommand: don't insert floating windows between accordion children — upstream commit [`8c3efca2`](https://github.com/nikitabobko/AeroSpace/commit/8c3efca2) (fork PR #41)
- Fix floating windows nudged off right/bottom edges on workspace unhide — upstream commit [`649301b2`](https://github.com/nikitabobko/AeroSpace/commit/649301b2) (fork PR #42)
- MacApp: fix AX-object destroy race + wipPids spin in `getOrRegister` — upstream commits [`dd6b927a`](https://github.com/nikitabobko/AeroSpace/commit/dd6b927a) + [`1e6ce27e`](https://github.com/nikitabobko/AeroSpace/commit/1e6ce27e) (fork PR #43)
- Fix cross-workspace focus races — upstream [nikitabobko/AeroSpace#2165](https://github.com/nikitabobko/AeroSpace/pull/2165) (fork PR #44)

## v1.3 (2026-06-29)

New backports since 1.2 (delta past upstream review point `a60f9630`):

- Fix Codex window classification (pet window → popup) — upstream commits [`82c4a405`](https://github.com/nikitabobko/AeroSpace/commit/82c4a405) + [`cb347265`](https://github.com/nikitabobko/AeroSpace/commit/cb347265) (fork PR #33)
- Fix `workspace next/prev` when current workspace isn't in the `--stdin` list — upstream commit [`6a2a126d`](https://github.com/nikitabobko/AeroSpace/commit/6a2a126d) (fork PR #34)
- Fix self-conflicting focus env vars in `exec-on-workspace-change` callback — upstream commit [`dd61a340`](https://github.com/nikitabobko/AeroSpace/commit/dd61a340) (fork PR #35)
- Document `AEROSPACE_WINDOW_ID` / `AEROSPACE_WORKSPACE` env variables — upstream commit [`3e381925`](https://github.com/nikitabobko/AeroSpace/commit/3e381925) (fork PR #36)
- Add binary-tree (BSP) normalization (`enable-normalization-binary-tree`) — upstream [nikitabobko/AeroSpace#2135](https://github.com/nikitabobko/AeroSpace/pull/2135) (fork PR #37)

## v1.2 (2026-06-12)

Backported since 1.1 — 3 newly-merged upstream `main` bug-fix commits + 3 feature PRs:

- Fix MRU bug after `swap` command — upstream commit [`19b5999d`](https://github.com/nikitabobko/AeroSpace/commit/19b5999d) (fork PR #25)
- Fix deadlock in `dieT`/`die` functions — upstream commit [`8b236f1b`](https://github.com/nikitabobko/AeroSpace/commit/8b236f1b) (fork PR #26)
- parseConfig: don't silently swallow `String.init` exceptions — upstream commit [`a0f17f88`](https://github.com/nikitabobko/AeroSpace/commit/a0f17f88) (fork PR #27)
- `new-window-prevent-flicker` config option — upstream [nikitabobko/AeroSpace#2109](https://github.com/nikitabobko/AeroSpace/pull/2109) (fork PR #28)
- `workspace-layout-changed` subscribe event — upstream [nikitabobko/AeroSpace#2116](https://github.com/nikitabobko/AeroSpace/pull/2116) (fork PR #29)
- Native focused-window border — upstream [nikitabobko/AeroSpace#2107](https://github.com/nikitabobko/AeroSpace/pull/2107) (fork PR #30)

## v1.1 (initial — 22 backports)

## Crash & stability

- Fix `ThreadGuardedValue` crash — upstream [nikitabobko/AeroSpace#2012](https://github.com/nikitabobko/AeroSpace/pull/2012) (fork PR #3)
- Normalize the tree after `flatten-workspace-tree` — upstream [nikitabobko/AeroSpace#1953](https://github.com/nikitabobko/AeroSpace/pull/1953) (fork PR #9)

## Window detection / popups

- Detect Outlook popups correctly — upstream [nikitabobko/AeroSpace#2103](https://github.com/nikitabobko/AeroSpace/pull/2103) (fork PR #1)
- Treat Emacs popups as floating — upstream [nikitabobko/AeroSpace#2081](https://github.com/nikitabobko/AeroSpace/pull/2081) (fork PR #2)
- Re-float windows correctly after screen wake — upstream [nikitabobko/AeroSpace#2098](https://github.com/nikitabobko/AeroSpace/pull/2098) (fork PR #5)

## Rendering / display

- Fix tiling flash on window creation — upstream [nikitabobko/AeroSpace#2024](https://github.com/nikitabobko/AeroSpace/pull/2024) (fork PR #4)
- Fix GTK3 black window redraw — upstream [nikitabobko/AeroSpace#2052](https://github.com/nikitabobko/AeroSpace/pull/2052) (fork PR #6)

## UI / menu bar

- Sort workspaces consistently in the menu bar UI — upstream [nikitabobko/AeroSpace#1926](https://github.com/nikitabobko/AeroSpace/pull/1926) (fork PR #8)

## CLI commands & flags

- `move-workspace-to-monitor` improvements — upstream [nikitabobko/AeroSpace#1944](https://github.com/nikitabobko/AeroSpace/pull/1944) (fork PR #7)
- Better stdin error message — upstream [nikitabobko/AeroSpace#1529](https://github.com/nikitabobko/AeroSpace/pull/1529) (fork PR #10)
- Add `create-implicit-container-or-fail` — upstream [nikitabobko/AeroSpace#2097](https://github.com/nikitabobko/AeroSpace/pull/2097) (fork PR #11)
- Support `layout --root` — upstream [nikitabobko/AeroSpace#2080](https://github.com/nikitabobko/AeroSpace/pull/2080) (fork PR #12)
- Allow resizing floating windows — upstream [nikitabobko/AeroSpace#1156](https://github.com/nikitabobko/AeroSpace/pull/1156) (fork PR #13)
- Add `list-windows --sort` — upstream [nikitabobko/AeroSpace#1932](https://github.com/nikitabobko/AeroSpace/pull/1932) (fork PR #18)
- Support `layout sticky` — upstream [nikitabobko/AeroSpace#2083](https://github.com/nikitabobko/AeroSpace/pull/2083) (fork PR #21)
- Add `summon-workspace --when-visible` — upstream [nikitabobko/AeroSpace#1349](https://github.com/nikitabobko/AeroSpace/pull/1349) (fork PR #22)

## on-window-detected matchers

- Substring matching for `app-id-regex` — upstream [nikitabobko/AeroSpace#2082](https://github.com/nikitabobko/AeroSpace/pull/2082) (fork PR #14)
- Allow an array of `app-id` matchers — upstream [nikitabobko/AeroSpace#1665](https://github.com/nikitabobko/AeroSpace/pull/1665) (fork PR #15)

## Format variables

- Add `%{all}` format variable — upstream [nikitabobko/AeroSpace#1708](https://github.com/nikitabobko/AeroSpace/pull/1708) (fork PR #16)
- Add orientation format variables — upstream [nikitabobko/AeroSpace#1778](https://github.com/nikitabobko/AeroSpace/pull/1778) (fork PR #17)

## Performance

- Throttle app registration — upstream [nikitabobko/AeroSpace#2085](https://github.com/nikitabobko/AeroSpace/pull/2085) (fork PR #19)

## Documentation

- Add KeePassXC docs note — upstream [nikitabobko/AeroSpace#1344](https://github.com/nikitabobko/AeroSpace/pull/1344) (fork PR #20)

## Versioning

This fork does not publish official releases. To build your own fork release with a clearly marked
version string, see [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md).
