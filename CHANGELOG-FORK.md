# Fork Changelog

This fork backports upstream pull requests that are already implemented in
[nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) but not yet merged into an
upstream release. The base for all of these backports is upstream `main` at commit `63e0976b`.

Each entry links the original upstream PR (where all credit belongs) and the corresponding fork
PR that backports it. This fork is not an official release and is not affiliated with or endorsed
by the upstream maintainer.

## v0.20.3-Beta-fork.5 (2026-07-14)

New backports since fork.4 (delta past upstream review point `649301b2`):

- Fix wisprFlow popup detection — upstream commits [`4a3aab24`](https://github.com/nikitabobko/AeroSpace/commit/4a3aab24) + [`d56e1637`](https://github.com/nikitabobko/AeroSpace/commit/d56e1637) (fork PR #46)
- Ignore windows with `kCGNullWindowID` window-id — upstream commit [`0f6b2e78`](https://github.com/nikitabobko/AeroSpace/commit/0f6b2e78) (fork PR #47)
- Add `window-closed` subscribe event — upstream [nikitabobko/AeroSpace#2181](https://github.com/nikitabobko/AeroSpace/pull/2181) (fork PR #48)
- Fix Device Hub (Xcode 27) compact-view flicker when tiled — upstream [nikitabobko/AeroSpace#2167](https://github.com/nikitabobko/AeroSpace/pull/2167) (fork PR #49)

## v0.20.3-Beta-fork.4 (2026-07-10)

New backports since fork.3 (delta past upstream review point `fb8b1df6`):

- Fix menu-bar clicks stealing focus when "Displays have separate spaces" is off — upstream commit [`cfd4eab2`](https://github.com/nikitabobko/AeroSpace/commit/cfd4eab2) (fork PR #39)
- Add `window-moved-to-workspace` subscribe event — upstream [nikitabobko/AeroSpace#2162](https://github.com/nikitabobko/AeroSpace/pull/2162) (fork PR #40)
- FocusCommand: don't insert floating windows between accordion children — upstream commit [`8c3efca2`](https://github.com/nikitabobko/AeroSpace/commit/8c3efca2) (fork PR #41)
- Fix floating windows nudged off right/bottom edges on workspace unhide — upstream commit [`649301b2`](https://github.com/nikitabobko/AeroSpace/commit/649301b2) (fork PR #42)
- MacApp: fix AX-object destroy race + wipPids spin in `getOrRegister` — upstream commits [`dd6b927a`](https://github.com/nikitabobko/AeroSpace/commit/dd6b927a) + [`1e6ce27e`](https://github.com/nikitabobko/AeroSpace/commit/1e6ce27e) (fork PR #43)
- Fix cross-workspace focus races — upstream [nikitabobko/AeroSpace#2165](https://github.com/nikitabobko/AeroSpace/pull/2165) (fork PR #44)

## v0.20.3-Beta-fork.3 (2026-06-29)

New backports since fork.2 (delta past upstream review point `a60f9630`):

- Fix Codex window classification (pet window → popup) — upstream commits [`82c4a405`](https://github.com/nikitabobko/AeroSpace/commit/82c4a405) + [`cb347265`](https://github.com/nikitabobko/AeroSpace/commit/cb347265) (fork PR #33)
- Fix `workspace next/prev` when current workspace isn't in the `--stdin` list — upstream commit [`6a2a126d`](https://github.com/nikitabobko/AeroSpace/commit/6a2a126d) (fork PR #34)
- Fix self-conflicting focus env vars in `exec-on-workspace-change` callback — upstream commit [`dd61a340`](https://github.com/nikitabobko/AeroSpace/commit/dd61a340) (fork PR #35)
- Document `AEROSPACE_WINDOW_ID` / `AEROSPACE_WORKSPACE` env variables — upstream commit [`3e381925`](https://github.com/nikitabobko/AeroSpace/commit/3e381925) (fork PR #36)
- Add binary-tree (BSP) normalization (`enable-normalization-binary-tree`) — upstream [nikitabobko/AeroSpace#2135](https://github.com/nikitabobko/AeroSpace/pull/2135) (fork PR #37)

## v0.20.3-Beta-fork.2 (2026-06-12)

Backported since fork.1 — 3 newly-merged upstream `main` bug-fix commits + 3 feature PRs:

- Fix MRU bug after `swap` command — upstream commit [`19b5999d`](https://github.com/nikitabobko/AeroSpace/commit/19b5999d) (fork PR #25)
- Fix deadlock in `dieT`/`die` functions — upstream commit [`8b236f1b`](https://github.com/nikitabobko/AeroSpace/commit/8b236f1b) (fork PR #26)
- parseConfig: don't silently swallow `String.init` exceptions — upstream commit [`a0f17f88`](https://github.com/nikitabobko/AeroSpace/commit/a0f17f88) (fork PR #27)
- `new-window-prevent-flicker` config option — upstream [nikitabobko/AeroSpace#2109](https://github.com/nikitabobko/AeroSpace/pull/2109) (fork PR #28)
- `workspace-layout-changed` subscribe event — upstream [nikitabobko/AeroSpace#2116](https://github.com/nikitabobko/AeroSpace/pull/2116) (fork PR #29)
- Native focused-window border — upstream [nikitabobko/AeroSpace#2107](https://github.com/nikitabobko/AeroSpace/pull/2107) (fork PR #30)

## v0.20.3-Beta-fork.1 (initial — 22 backports)

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
