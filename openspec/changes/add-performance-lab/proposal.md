# Proposal: Add Performance Lab

## Why

The `feat/large-doc-rendering` arc cut 40 consecutive ~1s arrow-key hangs down to 2 by measuring, reading the hot signature, fixing, and re-measuring. That loop worked — but it lived entirely in `/tmp/parse_tp*.py` scratch scripts and chat context.

`add-performance-instrumentation` is the tools layer. This proposal adds the discipline layer: written contracts, a fixture matrix, parsers promoted to `scripts/perf/`, and a design vocabulary for the questions we haven't asked yet (scroll, cold open, cache memory, invalidation fan-out).

## What Changes

**Phase 1 — Performance Contracts**

- Author `PERFORMANCE.md` at repo root with numeric thresholds for each named user flow (doc open → first paint, scroll, search → navigate, toggle edit mode)
- Thresholds are budgets, not aspirations; each has a fixture, a capture method, and a pass/fail criterion
- Contracts SHALL reference signposts from `add-performance-instrumentation` where those exist; missing signposts become task items on that change

**Phase 2 — Fixture Matrix**

- Extend `Tests/VoidReaderCoreTests/Fixtures/` with a named matrix covering: wide-line pathology, many-small-blocks, deep nesting, heavy inline styling, mixed media (images + mermaid + math), real-world-messy (paste-from-web artifacts)
- Each fixture carries a size + shape descriptor in its header comment so a human reviewer can reason about coverage at a glance
- Size-sweep variants (10KB, 100KB, 1MB of the same shape) enable threshold-cliff hunting

**Phase 3 — Lab Tooling**

- Promote `/tmp/parse_tp*.py` to `scripts/perf/parse_trace.py` with:
  - Idle-frame denylist (kept in-file, editable)
  - Hang-window scoping (`--window START:END`)
  - Main-TID auto-detection (currently hard-coded per run)
  - App-frame filter (currently substring list)
  - Output modes: `leaf`, `sig3`, `sig5`, `app-anywhere`
- Add `scripts/perf/run_scenario.sh` that drives xctrace record + parse for a named scenario (`open-large`, `search-navigate`, `scroll-to-bottom`, `edit-toggle`)
- Add a Gitea CI workflow that invokes the scenario runner and uploads `.trace` bundles + parsed reports as build artifacts (retention-based historical access, no trace files in git)
- Commit a small XML-exported test fixture under `Tests/VoidReaderCoreTests/Fixtures/traces/` so parser correctness is verifiable offline

**Phase 4 — Untapped Instruments**

- Runbook additions covering Allocations (memory audit — new caches from 0928a10 have not been sized), Leaks (actor retain cycles in `ImageLoader`/`MermaidImageRenderer`), Core Animation FPS (scroll diagnosis)
- Signpost additions around high-churn boundaries identified during this arc: `computeMatchInfo`, `buildHighlighted`, `updateRenderedBlocks`, `highlightedString` — feed directly into `add-performance-instrumentation` Phase A
- Invalidation instrumentation: a lightweight counter harness that surfaces SwiftUI `body` recomputes per user action, so "work in body" regressions get caught by measurement, not review

**Phase 5 — Threshold Sweep Harness**

- `scripts/perf/sweep.sh <scenario> <size-sweep>` runs the scenario against 10KB/100KB/1MB fixtures and emits a table of p50/p95 durations per named signpost
- Output is markdown, committable — each arc produces a dated table under `openspec/changes/<arc>/findings/`
- Makes threshold-cliff behavior a first-class observable (the kind of thing that produces "works fine under 50KB, falls apart at 80KB" findings without ambiguity)

**Out of scope**

- Optimizing any specific code path. This change institutionalizes the hunt; individual hunts live in their own proposals.
- Replacing `FrameDropMonitor`, `DebugLog`, `MarkdownPerformanceTests`, or the CI gate work in `add-performance-instrumentation` Phase B
- Production telemetry, analytics, or user-visible perf UI
- CI-based pass/fail gating — the lab's CI integration is artifact-upload-only for historical access; automated regression gates remain `add-performance-instrumentation` Phase B's responsibility
- Self-hosted object storage (MinIO / Garage / RustFS) with differentiated retention — considered, deferred until Gitea artifact limits or query pain justify the additional infrastructure
- iOS / iPadOS

## Impact

- **Affected specs:** new capability `performance-lab`
- **Affected code:**
  - `PERFORMANCE.md` (new)
  - `scripts/perf/` (new directory: `parse_trace.py`, `run_scenario.sh`, `sweep.sh`)
  - `.gitea/workflows/test-perf-lab.yml` (new — may fold into `add-performance-instrumentation` Phase B workflow if shipped first)
  - `Tests/VoidReaderCoreTests/Fixtures/` (expanded with shape matrix)
  - `Tests/VoidReaderCoreTests/Fixtures/traces/` (new — small XML exports for parser unit coverage)
  - `.gitignore` (add `build/traces/` if not already covered)
  - Signpost additions in `App/Views/MarkdownReaderView.swift` (`computeMatchInfo`, `buildHighlighted`, `updateRenderedBlocks`) — coordinated with `add-performance-instrumentation`
  - `DEVELOPMENT.md` runbook section extended
- **Related changes:**
  - `add-performance-instrumentation` — upstream dependency for signposts. Lab consumes what instrumentation produces; does not replace it.
  - `optimize-large-document-performance` — consumer. Future phases of that change should run through this lab before shipping.
  - `refactor-large-code-block-rendering` — recent arc that validated the loop; its findings inform the initial contract thresholds.

## Success Criteria

1. `PERFORMANCE.md` exists with at least one numeric threshold for each of the four named user flows, plus a capture method per flow.
2. Fixture matrix covers all six shapes, with size-sweep variants for at least two shapes.
3. `scripts/perf/parse_trace.py` reproduces the `parse_tp3.py` analysis against the committed XML test fixture with no scratch-file edits — all tuning is via CLI flags.
4. `scripts/perf/run_scenario.sh search-navigate` produces a trace and a parsed report in under 30 seconds of developer time (one command).
5. Gitea CI workflow uploads `.trace` bundles and parsed reports as build artifacts on every perf-run invocation, retrievable from the build page.
6. Allocations + Leaks + CA FPS each have a runbook entry that a new contributor can execute without further help.
7. Invalidation counter harness exposes per-flow body-recompute counts when a `DEBUG` flag is set; the counts are non-zero only when expected.
8. A threshold sweep for `search-navigate` across 10KB/100KB/1MB produces a markdown table, and that table is committed as the baseline under `openspec/changes/add-performance-lab/findings/`.

## Risks

- **Duplication with `add-performance-instrumentation`.** Mitigation: this change owns discipline (contracts, fixtures, practices); that change owns tools (signposts, capture). Signpost additions needed by the lab are raised as tasks on that change, not duplicated here.
- **Parser script rot.** Mitigation: `parse_trace.py` is exercised every arc; if it falls out of sync with xctrace XML, it breaks loudly in the next hunt. Treat as a real artifact, review changes in PR.
- **Fixture matrix grows unbounded.** Mitigation: cap at ~12 fixtures total; retire redundant ones when new shapes are added.
- **"Work in body" and invalidation counts are useful but imprecise.** Mitigation: counts are a smell-detector, not a contract. Contracts remain numeric (ms, MB, FPS); counts feed code review and local hunts.
- **Gitea artifact retention cap eventually bites.** Mitigation: start with 90d retention; escalate retention configuration before migrating to S3. Migration cost is one workflow file + optional backfill.
- **Historical-analysis queries awkward against Gitea API.** Mitigation: accepted trade-off for starting small. Track pain — the second time a query against Gitea API produces a curse, re-open the S3 question with concrete justification.
