# Startup Performance Benchmark — 2026-08-30

## Scope

This manual local comparison used the exact parent of the performance change
(d69af2b2) and the optimized debug build. Both used the same MacBook Pro,
macOS 26.5.1, Swift 6.3.3, AeroSpace configuration, and one native plus two
external displays. Each sample launched the debug app, polled the local
list-monitors command every 100 ms until it responded, sampled that PID's CPU
and RSS, then stopped only that debug PID.

Socket readiness happens before the removed follow-up refresh, so this
measurement does not claim to quantify later layout-settle latency. It measures
early availability and startup resource use.

## Results

| Metric | Baseline median | Optimized median | Change |
| --- | ---: | ---: | ---: |
| Ready poll | 3 (≤0.3s) | 3 (≤0.3s) | no measurable change |
| CPU sample | 29.1% | 28.9% | -0.7% |
| RSS sample | 84,496 KiB | 84,448 KiB | -0.1% |

### Baseline samples

| Run | Ready poll | CPU | RSS KiB |
| --- | ---: | ---: | ---: |
| 1 | 5 | 42.2% | 84,496 |
| 2 | 3 | 27.9% | 84,272 |
| 3 | 3 | 24.6% | 84,592 |
| 4 | 3 | 31.5% | 84,528 |
| 5 | 3 | 29.1% | 87,968 |
| 6 | 3 | 28.9% | 84,400 |
| 7 | 3 | 29.7% | 84,320 |

### Optimized samples

| Run | Ready poll | CPU | RSS KiB |
| --- | ---: | ---: | ---: |
| 1 | 3 | 31.6% | 84,448 |
| 2 | 3 | 25.9% | 85,488 |
| 3 | 3 | 28.9% | 84,528 |
| 4 | 2 | 30.6% | 84,304 |
| 5 | 3 | 27.3% | 84,368 |
| 6 | 3 | 28.9% | 87,264 |
| 7 | 3 | 26.8% | 84,432 |

## Additional diagnostic

An Activity Monitor trace of the baseline recorded a 22.7% CPU interval and
28.33 MiB physical footprint during startup. The trace is excluded from Git.
Its fixed 15-second time limit terminates the target, so it is diagnostic only,
not part of the comparison above.

## Conclusion

The early-ready metrics are effectively unchanged, as expected. The code change
removes the subsequent, redundant complete Accessibility refresh and therefore
reduces work after readiness without adding concurrency or changing placement
behavior. No Swift toolchain upgrade was attempted: the project is already on
Swift 6.3.3 and the measured change did not justify a compatibility-risking
migration.
