# Startup Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant full Accessibility refresh after a cold AeroSpace startup and demonstrate the impact with repeatable CPU, peak-RSS, and signpost timing measurements.

**Architecture:** Keep launch state on the main actor. `runLightSession` will use a pure scheduling-policy helper, so startup alone finalizes its layout without enqueuing a second heavy refresh. Constant `OSSignposter` intervals make startup phases visible in Instruments without recording user data. A local-only benchmark runner will launch a supplied debug executable repeatedly under `xctrace` and record process metrics in an ignored directory.

**Tech Stack:** Swift 6.3, AppKit, `OSSignposter`, XCTest, Bash, Xcode `xctrace`, macOS `/usr/bin/time`.

**Spec:** `docs/superpowers/specs/2026-08-30-startup-performance-design.md`

## Global Constraints

- Preserve macOS 13 compatibility, Swift strict concurrency, and strict memory safety.
- Do not log window titles, configuration values, command payloads, or socket data.
- Do not add dependencies, change generated files, or make the server externally reachable.
- Treat `RefreshSessionEvent.startup` as the only event that skips the automatic follow-up refresh.
- Preserve `after-startup-command`, the initial layout, and refreshes created by later AX, workspace, or display notifications.
- Produce comparison data from at least seven cold relaunches per revision with the same three-display setup and active-app set.

---

### Task 1: Test and remove the startup follow-up refresh

**Files:**
- Create: `Sources/AppBundleTests/RefreshSessionSchedulingTest.swift`
- Modify: `Sources/AppBundle/layout/refresh.swift:69-98`

**Interfaces:**
- Consumes: `RefreshSessionEvent.isStartup` from `Sources/Common/util/commonUtil.swift`.
- Produces: `func shouldScheduleFollowUpRefresh(after event: RefreshSessionEvent) -> Bool`, called by `runLightSession`.

- [ ] **Step 1: Write the failing tests**

```swift
@testable import AppBundle
import Common
import XCTest

final class RefreshSessionSchedulingTest: XCTestCase {
    func testStartupDoesNotScheduleFollowUpRefresh() {
        XCTAssertFalse(shouldScheduleFollowUpRefresh(after: .startup))
    }

    func testNonStartupEventSchedulesFollowUpRefresh() {
        XCTAssertTrue(shouldScheduleFollowUpRefresh(after: .menuBarButton))
    }
}
```

- [ ] **Step 2: Run the focused test to prove the helper is absent**

Run: `swift test --filter RefreshSessionSchedulingTest`

Expected: compilation fails naming `shouldScheduleFollowUpRefresh`.

- [ ] **Step 3: Implement the minimum policy and guard the existing scheduling call**

```swift
func shouldScheduleFollowUpRefresh(after event: RefreshSessionEvent) -> Bool {
    !event.isStartup
}

if shouldScheduleFollowUpRefresh(after: event) {
    scheduleCancellableCompleteRefreshSession(event)
}
```

Do not move any other `runLightSession` work or alter the initial heavy refresh.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter RefreshSessionSchedulingTest && ./swift-test.sh`

Expected: exit zero and the script reports `✅ Swift tests have passed successfully`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/layout/refresh.swift Sources/AppBundleTests/RefreshSessionSchedulingTest.swift
git commit -m "perf: skip redundant startup refresh"
```

### Task 2: Instrument constant startup stages

**Files:**
- Modify: `Sources/AppBundle/initAppBundle.swift:5-55`
- Modify: `Sources/AppBundle/tree/frozen/persistedLayout.swift:78-93`

**Interfaces:**
- Consumes: the process-global `signposter` from `Sources/AppBundle/util/appBundleUtil.swift`.
- Produces: intervals named `startup.config`, `startup.initialRefresh`, `startup.restorePersistedLayout`, and `startup.finalize`.

- [ ] **Step 1: Write a failing unit test first only if a semantic helper is introduced**

Add the new case to `RefreshSessionSchedulingTest.swift` and run it before implementation. Do not test `OSSignposter` implementation details; trace inspection verifies the instrumentation.

- [ ] **Step 2: Wrap existing calls with the established signposter pattern**

```swift
let state = signposter.beginInterval("startup.initialRefresh")
defer { signposter.endInterval("startup.initialRefresh", state) }
await runHeavyCompleteRefreshSession(...)
```

Use constant labels only. Do not interpolate display, window, config, or command data.

- [ ] **Step 3: Build with warnings as errors**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors`

Expected: exit zero.

- [ ] **Step 4: Inspect one trace**

Run: `xcrun xctrace record --template 'Points of Interest' --time-limit 15s --output /tmp/aerospace-startup-smoke.trace --launch -- ./.debug/AeroSpaceApp`

Expected: the Points of Interest instrument exposes the four constant intervals. Remove only the explicit `/tmp/aerospace-startup-smoke.trace` after inspection.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppBundle/initAppBundle.swift Sources/AppBundle/tree/frozen/persistedLayout.swift
git commit -m "perf: add startup phase signposts"
```

### Task 3: Add local benchmark collection

**Files:**
- Create: `script/benchmark-startup.sh`
- Create: `dev-docs/startup-benchmarking.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `--executable PATH`, `--output-dir PATH`, optional `--runs N`, and local `xcrun xctrace`.
- Produces: one CSV row per run with revision, run number, elapsed seconds, user CPU seconds, system CPU seconds, maximum RSS KiB, and trace name.

- [ ] **Step 1: Write the shell acceptance checks before the runner**

```bash
./script/benchmark-startup.sh --help
test "$(./script/benchmark-startup.sh --help | head -1)" = "Usage: benchmark-startup.sh --executable PATH --output-dir PATH [--runs N]"
```

Run the first command before adding the script. Expected: file-not-found failure.

- [ ] **Step 2: Implement safe argument validation and collection**

Require executable and output directory, default to seven runs, reject non-positive runs, create only the requested output directory, and never kill or quit a running AeroSpace process. Each run calls:

```bash
/usr/bin/time -l xcrun xctrace record --template 'Points of Interest' --time-limit 15s \
  --output "$trace_path" --launch -- "$executable"
```

Parse `time -l` real/user/system/maximum-resident-set-size output into CSV and fail clearly if `xctrace` fails.

- [ ] **Step 3: Document and ignore local artifacts**

The guide requires manually quitting the installed AeroSpace, keeping the same three displays, normal workload, configuration, binary type, and seven samples for each revision. Add `.benchmarks/` to `.gitignore`; do not commit traces or raw metrics.

- [ ] **Step 4: Verify against a disposable process**

Run: `./script/benchmark-startup.sh --help`

Run once against `/usr/bin/true` and a fresh `/tmp` output folder. Confirm a CSV header and exactly one data row. This validates tooling only, not AeroSpace performance.

- [ ] **Step 5: Commit**

```bash
git add script/benchmark-startup.sh dev-docs/startup-benchmarking.md .gitignore
git commit -m "test: add startup benchmark runner"
```

### Task 4: Benchmark, evaluate Swift changes, and draft the PR

**Files:**
- Create: `dev-docs/benchmarks/2026-08-30-startup-performance.md`
- Modify: a narrow Swift 6.3 launch-path file only if tracing identifies a separate measurable cause.

**Interfaces:**
- Consumes: Task 3 CSV files and Points-of-Interest traces from baseline and optimized revisions.
- Produces: an aggregate-only report with machine model, macOS/Swift version, three-display topology, run count, elapsed/user/system CPU/peak-RSS medians, individual numeric samples, and percentage deltas.

- [ ] **Step 1: Collect the baseline**

Use a temporary worktree or archive at the parent of `perf: skip redundant startup refresh`; build it with `./build-debug.sh -Xswiftc -warnings-as-errors`; run seven samples into a unique ignored output directory. Do not alter the primary worktree while measuring baseline.

- [ ] **Step 2: Collect matched optimized samples**

Build the branch revision with the same command and collect seven samples to a separate ignored directory, preserving config, display arrangement, normal applications, binary type, and sample count.

- [ ] **Step 3: Evaluate Swift-specific opportunities**

Inspect Time Profiler and Allocations. Implement a further Swift change only with a narrowly identified cause, a failing test first, a passing focused test, and a second matched improvement. Record rejected toolchain-upgrade, added-AX-concurrency, and allocation-rewrite ideas with evidence.

- [ ] **Step 4: Write the aggregate report**

Exclude trace paths, window titles, config contents, command data, user identifiers, and application names. State that results are local measurements. If an optimized primary-metric median regresses, document it and revert the optimization.

- [ ] **Step 5: Verify, commit, push, and create the draft PR**

Run: `./build-debug.sh -Xswiftc -warnings-as-errors && ./swift-test.sh && ./lint.sh && git diff --check && git status --short`

Expected: each verifier exits zero; status contains only the user-owned untracked `.agents/` and `AGENTS.md` after ignored artifacts are excluded.

```bash
git add dev-docs/benchmarks/2026-08-30-startup-performance.md
git commit -m "docs: report startup benchmark results"
git push -u origin codex/startup-performance-benchmark
gh pr create --draft --base main --head codex/startup-performance-benchmark \
  --title "perf: reduce startup refresh work" \
  --body-file /tmp/aerospace-startup-pr.md
```

The PR body lists commits, verification evidence, benchmark method and results, the focused security-review outcome, and remaining manual validation.
