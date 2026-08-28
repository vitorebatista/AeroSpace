<div align="center">

<img src="./docs/assets/edge-logo.svg" width="120" alt="AeroSpace-edge">

# AeroSpace‑edge

**AeroSpace, with upstream's fixes already in.**

[![latest release](https://img.shields.io/github/v/release/vitorebatista/AeroSpace-edge?include_prereleases&label=release&color=6366F1)](https://github.com/vitorebatista/AeroSpace-edge/releases/latest)
[![license](https://img.shields.io/badge/license-MIT-22D3EE)](./LICENSE)
[![upstream](https://img.shields.io/badge/upstream-nikitabobko%2FAeroSpace-A855F7)](https://github.com/nikitabobko/AeroSpace)

</div>

---

## What this is

[AeroSpace](https://github.com/nikitabobko/AeroSpace) is an i3-like tiling window manager for macOS,
written by [@nikitabobko](https://github.com/nikitabobko). It's excellent. This is **not** a competitor
to it, a rewrite of it, or a place to get support for it.

It's a **build of AeroSpace that ships fixes before upstream cuts a release.** Upstream merges and
reviews at its own pace, and plenty of good work — bug fixes, small quality-of-life additions — sits in
merged commits or open pull requests for months before it reaches a tagged build. This fork picks that
work up early.

The recipe hasn't changed since day one:

- Pinned to upstream `main` at commit [`63e0976b`](https://github.com/nikitabobko/AeroSpace/commit/63e0976b).
- **52 upstream fixes and features** backported on top, each one its own reviewed pull request,
  each one build- and test-verified before it lands.
- Large refactors and breaking config changes are deliberately left out — they're what makes forks rot.
- Everything that got pulled in is listed, with its upstream origin, in
  [`CHANGELOG-FORK.md`](./CHANGELOG-FORK.md).

Nine releases so far. Current: **v0.20.3-Beta-fork.9**.

## Why you might want it

Grab a release if any of these have bitten you:

| | |
|---|---|
| **Crashes** | `is already unbound` when two `focus` commands race · `EXC_BAD_ACCESS` during display reconfiguration · `ThreadGuardedValue` crash · `die`/`dieT` deadlock |
| **Windows in the wrong place** | native tabs (Finder, Ghostty, Fork) leaving phantom tiles · windows flashing tiled before a floating rule applies · floating windows misplaced after screen wake · Emacs / Outlook / Codex / iTerm2 Settings popups mis-detected |
| **Layout math** | `balance-sizes` throwing away container weights, so a later `resize` made windows jump |
| **CLI** | `layout sticky` · `list-windows --sort` · `enable-normalization` per workspace · `summon-workspace --when-visible` · `debug-windows --app-bundle-id` · resizable floating windows |
| **Integrations** | the socket protocol handshake modern clients expect (AeroKit, aerospace-swipe, the upstream cask CLI) |

And one thing that has no upstream equivalent, written here:

- **`focus-follows-app-activation = 'always' \| 'smart'`** — `smart` stops apps that raise themselves
  from dragging you across workspaces, unless a click preceded the activation.
  ⚠️ `smart` currently has a [known regression](./CHANGELOG-FORK.md); the default `'always'` is the
  upstream behavior and is safe.

## Install

Download the latest zip from [**Releases**](https://github.com/vitorebatista/AeroSpace-edge/releases/latest),
then:

```bash
unzip AeroSpace-v0.20.3-Beta-fork.9.zip
mv AeroSpace-v*/AeroSpace.app /Applications/
cp  AeroSpace-v*/bin/aerospace /usr/local/bin/   # or anywhere on your PATH
open -a /Applications/AeroSpace.app
```

Both binaries are universal (arm64 + x86_64). Your existing `~/.aerospace.toml` works as-is —
this fork adds config options, it never renames or removes them.

There's no Homebrew cask, and there won't be one. Upstream's cask installs upstream's builds, which
is the right default for almost everyone.

### The one thing that will surprise you

**Every release is signed ad-hoc, so macOS revokes the Accessibility grant on each upgrade.** The app
notices its own permission is gone, clears its TCC entry, and exits at launch. It looks like a crash.
It isn't.

After replacing the app: **System Settings → Privacy & Security → Accessibility**, switch AeroSpace
back on (add `/Applications/AeroSpace.app` with **+** if the row disappeared), then launch it again.
Expect this on every upgrade.

Confirm you're on the right build:

```bash
aerospace --version   # client and server should both report ...-fork.N
```

## Documentation

The fork doesn't maintain its own manual — upstream's docs are the docs, and they're good:

- [Guide](https://nikitabobko.github.io/AeroSpace/guide) ·
  [Commands](https://nikitabobko.github.io/AeroSpace/commands) ·
  [Goodies](https://nikitabobko.github.io/AeroSpace/goodies)

Anything this fork adds on top is documented in [`CHANGELOG-FORK.md`](./CHANGELOG-FORK.md), and in the
`.adoc` sources under [`docs/`](./docs) which ship with the fork's own additions folded in.

## How it's kept current

Upstream is checked periodically. Each pass looks only at what's new since the last recorded sync
point, triages it, and backports what clears the bar:

- ✅ Bug fixes, crash fixes, window-detection fixes.
- ✅ Small, additive features — a new flag, a new config key, a new subscribe event.
- ❌ Large refactors, breaking config-syntax changes, anything that would conflict with the
  backports already carried.

Each backport gets its own branch and pull request, is adapted to this tree's conventions where it
differs from upstream, and has to pass `./build-debug.sh -Xswiftc -warnings-as-errors` **and**
`./swift-test.sh` before merging. Nothing lands untested, and nothing lands as a bulk merge.

The full state — sync point, everything already ported, everything deliberately skipped and why — is
in [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md).

## Contributions are genuinely welcome

This fork exists because someone wanted a fix sooner. If that's you, say so — the bar for "worth
carrying" is low, and requests shape what gets picked up next.

- **Spotted an upstream PR or commit you want early?** Open an issue with the number. That's the single
  most useful thing you can send, and it's usually a quick turnaround.
- **Found a bug?** Open an issue here — but first check whether it reproduces on an
  [upstream release](https://github.com/nikitabobko/AeroSpace/releases). If it does, it belongs
  upstream; that's where it gets fixed for everyone.
- **Want to send code?** PRs against `main` are welcome. One change per PR, keep the upstream
  attribution intact, and make sure the build and tests pass.
- **Ideas that don't exist upstream** are fair game too. `focus-follows-app-activation` started as one.

New ideas, better implementations, corrections to something here — all of it is open. Nothing about
this fork is settled.

## Building from source

```bash
./build-debug.sh -Xswiftc -warnings-as-errors   # warnings are errors
./swift-test.sh                                  # XCTest suite
./test.sh                                        # everything CI runs
```

Setup details are in [`dev-docs/development.md`](./dev-docs/development.md); the layout of the codebase
is in [`dev-docs/architecture.md`](./dev-docs/architecture.md). Release builds in this fork use the lean
path documented in [`dev-docs/fork-maintenance.md`](./dev-docs/fork-maintenance.md) — the upstream
release script needs docs tooling that isn't required here.

## macOS support

| | Ventura 13 | Sonoma 14 | Sequoia 15 | Tahoe 26 |
|---|:---:|:---:|:---:|:---:|
| Release binary runs | ✅ | ✅ | ✅ | ✅ |
| Debug build from source | — | ✅ | ✅ | ✅ |
| Release build from source (Xcode 26+) | — | — | ✅ | ✅ |

## Credit

**AeroSpace is [@nikitabobko](https://github.com/nikitabobko)'s work**, along with everyone who has
contributed to it. Every backport here links the upstream pull request or commit it came from, because
that's where the engineering happened. This fork just refuses to wait for the tag.

If AeroSpace is useful to you, [sponsor the person who wrote it](https://github.com/sponsors/nikitabobko).

## License

MIT, unchanged from upstream — `Copyright (c) 2023 Nikita Bobko`. See [`LICENSE`](./LICENSE).

> **Not affiliated with, endorsed by, or supported by the upstream project.** These are unofficial
> builds. Don't report problems with them to upstream — bring them
> [here](https://github.com/vitorebatista/AeroSpace-edge/issues) instead.
