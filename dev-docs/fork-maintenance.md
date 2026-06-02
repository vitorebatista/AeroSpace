# Fork maintenance

This is a maintainer note for the `vitorebatista/AeroSpace` fork. It documents how to build fork
releases and how to sequence the backport PRs. All credit for AeroSpace belongs to
[@nikitabobko](https://github.com/nikitabobko) and contributors.

## Upstream base

This fork is branched from upstream `main` at commit `63e0976b`. Backports listed in
[`CHANGELOG-FORK.md`](../CHANGELOG-FORK.md) are PRs that are already implemented upstream but not
yet merged into an upstream release.

## Building your own release

Build a fork release with a version string that clearly marks it as a fork build, so the version
shown in the menu bar and by `aerospace --version` is unambiguous. Use the upstream beta base
version plus a `-fork.N` suffix:

```bash
./build-release.sh --build-version "0.19.2-Beta-fork.1" --codesign-identity -
```

- Bump `N` (`fork.2`, `fork.3`, ...) each time more PRs are merged into the fork.
- The output archive is written to `.release/AeroSpace-v<version>.zip`.
- Do **not** use `script/publish-release.sh` — it pushes tags to the upstream repo, which is not
  what we want for a fork build.

## Merge order

Some backport PRs touch the same files and must be sequenced (merge the first, then rebase the
second on top before merging):

- Fork PRs **#3** and **#6** both modify `Sources/AppBundle/tree/MacApp.swift`. Merge **#3** (the
  `ThreadGuardedValue` crash fix) first, then rebase **#6** (the GTK3 redraw fix) on top.
- Fork PRs **#14** and **#15** both edit the on-window-detected matcher parser. Sequence them and
  rebase the second one on the first before merging.

## CI

The existing `.github/workflows/build.yml` workflow will verify builds across macOS versions once
GitHub Actions is enabled on the fork. Do not modify workflow files as part of the docs PRs.
