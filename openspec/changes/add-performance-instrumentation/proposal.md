# Proposal: Add Performance Instrumentation

## Why

VoidReader has shipped meaningful performance wins (134x load time improvement on large docs, LazyVStack virtualization, debounced scroll tracking) but the approach has been reactive — diagnose a symptom, fix it, move on. There is no systematic way to see where time goes during a cold doc open or a mid-scroll hitch, compare performance characteristics across commits, or catch regressions before they ship. The app already has partial perf infrastructure (`FrameDropMonitor`, `DebugLog`, `MarkdownPerformanceTests`) but none of it feeds Instruments, which is where visual performance diagnosis actually happens.

## What Changes

**Phase A — Signposts + Runbooks (must land before 1.1.0 tag)**

- Wire `OSSignposter` into VoidReaderCore and the App shell with per-subsystem `OSLog` categories (rendering, lifecycle, scroll, mermaid, image)
- Emit named intervals at key points: `openDocument`, `closeDocument`, `reloadFromDisk`, `parseMarkdown`, `renderBatch`, `firstPaint`, `syntaxHighlightPass`, `mermaidRender`, `imageLoad`
- Emit `scrollTick` as an event (not interval) to avoid pairing overhead in the scroll hot loop
- Enforce zero-overhead contract: `MarkdownPerformanceTests` bounded-time assertions must pass unchanged
- Add `make profile` convenience target
- Add DEVELOPMENT.md runbooks: "Profiling scroll jank", "Profiling cold open", "Profiling memory growth"

**Phase B — CI Regression Detection (conditional on xctrace viability under `launchctl-asuser`)**

Ramped rollout to avoid the UI-test failure mode of gating on an unmeasured noise floor:

- Prototype `xctrace record --launch` under the Gitea runner's GUI session; go/no-go on the rest of Phase B based on spike
- Add `Scripts/profile-scenario.sh` that drives a reproducible workload (open torture doc → scroll → close)
- Write metric-extraction script that consumes `.trace` export and produces JSON (interval p50/p95, hitch count, allocations)
- **Stage 1:** `.gitea/workflows/test-perf.yml` runs record-only — posts reports to PRs, always passes. Collects distribution of per-metric values across ~4 weeks of real PR traffic.
- **Stage 2:** Once variance is characterized, surface soft warnings (non-blocking) when metrics exceed threshold. Validate that warnings correlate with real regressions.
- **Stage 3:** Flip to hard gating with thresholds expressed relative to observed variance (multiples of stddev), not fixed percentages.
- Upload both `.trace` files as CI artifacts at every stage

**Out of scope**

- Production analytics, remote telemetry, or user-facing perf UI
- Optimizing any perf-sensitive code path — this change instruments, it does not optimize
- Replacing `FrameDropMonitor`, `DebugLog`, or `MarkdownPerformanceTests`
- lazypower/VoidReader#1 items 1/2/3 (print scale, bullet whitespace, remembered printer) — tracked separately
- iOS/iPadOS profiling

## Impact

- **Affected specs:** new capability `performance-instrumentation`
- **Affected code:**
  - `Sources/VoidReaderCore/Utilities/Signposts.swift` (new)
  - Instrumentation call sites in `BlockRenderer`, `MarkdownRenderer`, `MermaidImageRenderer`, `ImageLoader`, scroll observer
  - `App/VoidReaderApp.swift` and `App/Views/ContentView.swift` for lifecycle boundaries
  - `Makefile` for `make profile`
  - `DEVELOPMENT.md` runbook section
  - `.gitea/workflows/test-perf.yml` (Phase B)
  - `Scripts/profile-scenario.sh` (Phase B)
- **Release gate:** 1.1.0 tag blocked until Phase A ships and app has been profiled + tuned based on findings
- **Related changes:** `add-debug-telemetry` (complementary, not replaced); `optimize-large-document-performance` (this proposal provides the measurement infrastructure that makes future optimization data-driven)

## Success Criteria

1. Launching the app via Xcode → Profile → Animation Hitches (or Time Profiler) shows named intervals for `openDocument`, `firstPaint`, `parseMarkdown`, `renderBatch`, `syntaxHighlightPass`, `scrollTick`, etc.
2. Signposts add no measurable overhead when Instruments is not attached (verified via unchanged `MarkdownPerformanceTests` bounded-time assertions).
3. DEVELOPMENT.md contains three profiling runbooks, each executable by a developer without further help.
4. A PR that intentionally regresses performance (e.g., `Thread.sleep` in `parseMarkdown`) is flagged by the CI gate (Phase B Stage 3 only; earlier stages surface a report/warning but do not block).
5. Baseline and PR traces are retrievable as CI artifacts for manual inspection at every Phase B stage.
6. Version 1.1.0 tag ships only after Phase A lands and the app has been profiled + tuned.

## Risks

- **`xctrace` under `launchctl-asuser` may not work.** Mitigation: treat Phase B as research-heavy; fall back to local-only profiling if CI integration proves intractable. Phase A is still valuable standalone.
- **Signpost overhead in hot loops.** Mitigation: `OSSignposter` is designed to no-op when not recording; hot-path signposts (`scrollTick`) use `emitEvent` not `beginInterval`.
- **Trace metrics noisy on shared runner.** Mitigation: start with wide regression thresholds; narrow as noise floor is measured.
