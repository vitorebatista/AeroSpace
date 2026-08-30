# Startup Performance — Plan

Design record: [`../specs/2026-08-30-startup-performance-design.md`](../specs/2026-08-30-startup-performance-design.md).
Measurement procedures: [`dev-docs/startup-benchmarking.md`](../../../dev-docs/startup-benchmarking.md).
Baseline numbers: [`dev-docs/benchmarks/2026-08-30-startup-performance.md`](../../../dev-docs/benchmarks/2026-08-30-startup-performance.md).

## Done

- [x] Profile the launch sequence and identify the cost as Accessibility
      round-trips serialized on the main actor, not CPU or allocation.
- [x] Signpost `startup.config` and `startup.restorePersistedLayout`. Do not
      wrap the two refresh session functions — they already emit their own.
- [x] Concurrent AX prefetch (`MacWindow.prefetchAxSnapshots`) feeding the
      unchanged serial registration loop in `refresh()`.
- [x] Skip the discarded rect read when parking a tiling window in a hide corner.
- [x] Enumerate the window-level cache at most once per refresh session.
- [x] Debug build with `-Xswiftc -warnings-as-errors`, full Swift suite, and
      `lint.sh` all passing.

## Reverted

- [x] Skipping the follow-up refresh after the startup light session, and the
      `shouldScheduleFollowUpRefresh` helper and tests introduced for it. It
      dropped windows that appeared while `restorePersistedLayout()` was awaiting,
      and had no measurable benefit. Rationale in the design record.
- [x] `script/benchmark-startup.sh`. Its CSV was never the source of any reported
      number, and an `xctrace --launch --time-limit` recording cannot measure
      launch duration — the time limit kills the target, so the trace duration is
      the time limit.

## Open

- [ ] Re-measure on the three-display machine using Points of Interest signposts.
      This is the only procedure that can see the refresh path; readiness/CPU/RSS
      sampling is blind to it and its run-to-run spread exceeds the effect size.
- [ ] `on-window-detected` matching reads each window's title over AX, once per
      candidate callback, inside the serial registration loop. If a config with
      many callbacks shows up in the signpost trace, that read is the next thing
      to hoist into the prefetch phase.
