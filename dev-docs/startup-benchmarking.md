# Startup benchmarking

This tool compares the process-lifetime startup cost of a debug AeroSpace
executable. Each iteration performs two cold launches: an Xcode `App Launch`
trace reports launch-to-exit duration, then `/usr/bin/time -l` reports direct
process elapsed/user/system CPU time and maximum resident set size.

The two launches are matched samples rather than one combined measurement.
Their values are comparable only when the same executable type, config,
connected displays, normal running applications, and sample count are used.

## Preparation

1. Keep the usual three-display arrangement connected.
2. Use the same AeroSpace config and normal application workload for both
   revisions.
3. Confirm the supplied executable returns after startup. The debug
   `./.debug/AeroSpaceApp` executable does so in this development setup.
4. Choose a fresh, ignored output directory. The runner never quits or kills
   another AeroSpace process and refuses to overwrite `results.csv`.

## Run

```bash
./build-debug.sh -Xswiftc -warnings-as-errors
./script/benchmark-startup.sh \
  --executable ./.debug/AeroSpaceApp \
  --output-dir .benchmarks/<revision> \
  --runs 7
```

Each output directory contains `results.csv`, one trace bundle per run, each
trace's exported table of contents, and direct-process timing output. Do not
commit these artifacts: they may contain machine-specific trace data.

Report the median of each numeric CSV column, individual numeric samples, the
machine model, macOS/Swift versions, display topology, and the exact benchmark
command. Treat results as local measurements, not universal performance claims.
