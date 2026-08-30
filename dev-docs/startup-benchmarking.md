# Startup benchmarking

This tool compares the process-lifetime startup cost of a debug AeroSpace
executable. Each iteration performs one cold launch under Xcode `App Launch`
and reports launch-to-exit duration.

The durations are comparable only when the same executable type, config,
connected displays, normal running applications, and sample count are used.

## Preparation

1. Keep the usual three-display arrangement connected.
2. Use the same AeroSpace config and normal application workload for both
   revisions.
3. Confirm the supplied executable returns under App Launch tracing. If it
   remains alive, use the manual procedure below instead.
4. Choose a fresh, ignored output directory. The runner never quits or kills
   another AeroSpace process and refuses to overwrite `results.csv`.

## Run

```bash
./build-debug.sh -Xswiftc -warnings-as-errors
./script/benchmark-startup.sh \
  --executable ./.debug/AeroSpaceApp \
  --output-dir .benchmarks/<revision> \
  --revision <revision> \
  --runs 7
```

Each output directory contains `results.csv`, one trace bundle per run, and
each trace's exported table of contents. Do not commit these artifacts: they
may contain machine-specific trace data.

Report the median of each numeric CSV column, individual numeric samples, the
machine model, macOS/Swift versions, display topology, and the exact benchmark
command. Treat results as local measurements, not universal performance claims.

## CPU and memory diagnosis

Use Instruments' `Activity Monitor` template as a separate diagnostic capture:

```bash
xcrun xctrace record --template 'Activity Monitor' --time-limit 15s \
  --output /tmp/aerospace-activity.trace --launch -- ./.debug/AeroSpaceApp
```

Export the `activity-monitor-process-live` table to inspect CPU percentage and
physical footprint. This trace terminates the target at its time limit, so do
not use it as a launch-duration benchmark or leave it running against a
production instance.

## Manual local readiness measurement

For a running debug executable, launch it in the background, poll
`./.debug/aerospace-edge list-monitors` every 100 ms until it succeeds, take
`ps -p <pid> -o %cpu=,rss=` immediately, and then stop only that launched
debug PID. Repeat seven times for each revision. This measures server readiness
and an early startup CPU/RSS sample; it does not measure the later layout-settle
work that happens after the socket accepts commands.
