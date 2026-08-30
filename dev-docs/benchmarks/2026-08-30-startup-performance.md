# Startup Performance — 2026-08-30

## What was measured

A manual local comparison on one MacBook Pro, macOS 26.5.1, Swift 6.3.3, one
native plus two external displays, same AeroSpace config throughout. Each sample
launched the debug app, polled `list-monitors` every 100 ms until it responded,
sampled that PID's CPU and RSS, and then stopped only that PID.

### Baseline samples (unchanged build)

| Run | Ready poll | CPU | RSS KiB |
| --- | ---: | ---: | ---: |
| 1 | 5 | 42.2% | 84,496 |
| 2 | 3 | 27.9% | 84,272 |
| 3 | 3 | 24.6% | 84,592 |
| 4 | 3 | 31.5% | 84,528 |
| 5 | 3 | 29.1% | 87,968 |
| 6 | 3 | 28.9% | 84,400 |
| 7 | 3 | 29.7% | 84,320 |

Median: ready poll 3 (≤0.3 s), CPU 29.1%, RSS 84,496 KiB.

## What this metric can and cannot show

The CPU column spans 24.6%–42.2% across seven runs of the *same* build. Any
change smaller than that spread is unreadable here. More importantly, socket
readiness happens before window layout settles, so this measurement is blind to
the refresh path — which is where all the cost being removed below lives.

An earlier revision of this branch reported a -0.7% CPU / -0.1% RSS "improvement"
against this baseline. That is noise, and the change it was measuring has since
been reverted (see below). Nothing in this document should be read as a measured
gain.

## The changes on this branch, and what each removes

Counted in blocking Accessibility round-trips, which is the unit that actually
governs startup cost. `W` = windows discovered at startup, `A` = apps owning
them, `H` = tiled windows sitting on non-visible workspaces, `M` = windows
absent from the on-screen window list (minimized, hidden apps, other Spaces).

| Change | Before | After |
| --- | --- | --- |
| Concurrent AX prefetch in `refresh()` | `W` registrations serialized on the main actor, 2 AX reads each | same reads, overlapped across `A` apps' AX threads |
| Skip the rect read when parking a tiling window | `H` blocking `getAxRect` calls whose result is discarded unread | 0 |
| Bound the window-level cache | up to `1 + M` full `CGWindowListCopyWindowInfo` enumerations per session | 1 |

The first is the significant one: at startup every window is new, so the whole of
`W` pays. The second also applies on every workspace switch, not only at startup.
The third bounds a case that degrades with minimized windows and hidden apps.

### Reverted from the earlier revision

Skipping the follow-up `scheduleCancellableCompleteRefreshSession` after the
startup light session. `runLightSession` cancels whatever refresh is pending when
it starts, and during startup that is routinely a real one — `restorePersistedLayout()`
awaits for a long time and every app finishing its launch in that window schedules
a refresh. The trailing schedule is what re-runs it. Dropping it left those windows
unregistered until some later unrelated event. It also had no measurable benefit to
weigh against that.

## Still to do

Re-measure on the three-display machine with the Points of Interest signposts
(`dev-docs/startup-benchmarking.md` → "Phase attribution"), which is the only
procedure that can see the refresh path at all. The readiness numbers above are
kept as a baseline record, not as a comparison.
