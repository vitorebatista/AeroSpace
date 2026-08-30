# Startup Performance Design

## Goal

Reduce CPU work and elapsed time during a quit-and-relaunch of AeroSpace on a
three-display macOS desktop, without changing window placement correctness or
the behavior of `after-startup-command`.

## Scope

The investigation is limited to the app's launch sequence and the work it
causes immediately afterwards. It includes a focused review of the launch,
configuration, and local UNIX-socket paths for issues exposed by the change.
It does not change the command protocol, configuration format, or unrelated
window-management behavior.

AeroSpace already uses Swift 6.3. The investigation will nevertheless assess
Swift-specific improvements that can be demonstrated in the benchmark, notably
unnecessary main-actor serialization, task creation, collection allocation, and
copying in the launch path. A Swift toolchain upgrade or language-version
migration is not assumed to improve runtime performance; it is in scope only
when it retains macOS 13 compatibility, builds cleanly under the project's
strict-concurrency and memory-safety settings, and shows a reproducible gain.

## Observed Launch Flow

`initAppBundle()` loads configuration, starts the server and global observers,
discovers windows through a non-cancellable heavy refresh, restores the saved
layout, and then runs a light startup session. A light session always schedules
a cancellable heavy refresh after its body completes. At startup this creates a
second, immediate full Accessibility scan after the first one has already
enumerated live windows. The second scan can contend with normal applications
while macOS is still settling three displays.

## Chosen Design

1. Add stable Points-of-Interest signposts for the important startup stages:
   configuration load, initial window discovery, persisted-layout restoration,
   and startup finalization.
2. Add a checked-in benchmark guide and script that runs repeated cold
   relaunches, collects `xctrace` signpost timing plus process CPU and peak RSS,
   and writes a timestamped, machine-readable result outside the repository.
3. Change the startup finalization path so it does not automatically request
   the redundant full refresh. The finalization still performs its existing
   layout and `after-startup-command`; subsequent AX and workspace
   notifications continue to request refreshes normally.
4. Extract the scheduling decision into a small, unit-tested helper so the
   special startup behavior is explicit and cannot silently regress.
5. Run the benchmark before and after the change on the requested three-display
   environment and publish the raw commands, sample count, machine/display
   configuration, median, and individual samples in the PR description.

## Alternatives Rejected

**Increase AX parallelism.** Per-app AX work is already dispatched through
dedicated run loops. More concurrency would raise CPU contention and risks
violating Accessibility API assumptions before measurements show it is needed.

**Defer saved-layout restoration.** This may reduce perceived startup time but
would visibly move windows after the app appears, which is a worse relaunch
experience.

## Correctness and Safety Constraints

- Use Swift 6.3 strict concurrency and preserve main-actor ownership of app
  state.
- Prefer a simpler Swift concurrency or collection implementation only when
  profiling demonstrates less launch CPU, elapsed time, or peak RSS; do not
  trade correctness for parallelism.
- Do not change the pinned Swift toolchain unless compatibility and the same
  before/after benchmark demonstrate a material benefit.
- Do not hand-edit generated files or introduce runtime dependencies.
- Do not make the startup socket accept commands before the first discovery
  phase has completed.
- The instrumentation must not log window titles, configuration contents,
  socket payloads, or other user data.
- Benchmark artifacts are untracked and contain only aggregate process metrics.
- Preserve automatic refreshes caused by Accessibility, workspace, display, and
  `after-startup-command` side effects; removing the unconditional startup
  refresh must be the only behavior change.

## Testing and Verification

Unit tests will prove the scheduling decision for `.startup` and a non-startup
event. The normal project debug build with warnings treated as errors and the
full Swift test suite must pass. Manual benchmark comparison requires at least
seven cold relaunch samples per revision, with the same user configuration,
three connected displays, and the same active applications. If median launch
time or peak RSS regresses, the change will not be proposed as an optimization.

## Deliverables

- Small, individually committed implementation and test changes.
- A benchmark tool and usage documentation.
- A committed before/after benchmark report once the measurements are captured.
- A draft GitHub PR from `codex/startup-performance-benchmark` into `main`.
