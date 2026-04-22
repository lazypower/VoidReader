# Performance Contracts

This document specifies numeric performance thresholds for named VoidReader
user flows. Contracts are **commitments**, not aspirations — every change that
violates a contract must either (a) restore compliance or (b) amend the
contract with explicit justification. Silent drift is prohibited.

## Canonical hardware target

All thresholds below are absolute numbers measured on:

> **Apple Silicon (M-series), macOS 14+**, debug build, default Xcode
> toolchain, no other heavy apps running.

Measurements taken on other hardware MUST be annotated with the machine/OS
in the Actual column. Absolute numbers mislead across machines — for
arc-scoped comparisons, prefer the `Δ vs. baseline` column produced by
`scripts/perf/sweep.sh`.

**Status key:** 🟢 meets contract · 🟡 within 20% of threshold · 🔴 violates
contract · ⚪ not yet measured.

**Strawman notice:** the thresholds in this initial commit are strawman
numbers derived from the `manual-3.trace` search-navigate arc and recent
large-document findings. Intended to be tightened or loosened once the first
full practice arc runs through the lab. Chuck owns the final numbers.

---

## Flow 1: Document Open

**Fixture:** `Tests/VoidReaderCoreTests/Fixtures/wide-line-pathology-100KB.md`
(81KB manifest-class document preferred if a canonical one is chosen later).

**Capture method:** `scripts/perf/run_scenario.sh open-large`. Extract
`openDocument` + `firstPaint` signpost durations.

**Primary metric:** Wall-clock ms from `openDocument` begin to `firstPaint`
event on the main thread.

| Dimension          | Threshold | Actual (strawman) | Notes |
|--------------------|-----------|-------------------|-------|
| p50 first paint    | ≤ 1500 ms | ⚪                 | Budget based on observed ~1.1s hang windows; target is "no hang." |
| p95 first paint    | ≤ 2500 ms | ⚪                 | |
| Peak RSS growth    | ≤ 150 MB  | ⚪                 | Caches added in 0928a10 (`blockHighlighted`, `matchTexts`) unbounded — see Allocations runbook. |

**Signposts (existing):** `openDocument`, `firstPaint`, `parseMarkdown`,
`renderBatch`.

---

## Flow 2: Scroll

**Fixture:** `Tests/VoidReaderCoreTests/Fixtures/many-small-blocks-100KB.md`.

**Capture method:** `scripts/perf/run_scenario.sh scroll-to-bottom`. Use
Core Animation FPS instrument + `scrollTick` signpost event counts.

**Primary metric:** Sustained FPS during continuous scroll + frames-dropped
rate.

| Dimension                   | Threshold | Actual (strawman) | Notes |
|-----------------------------|-----------|-------------------|-------|
| Sustained FPS (p50)         | ≥ 55      | ⚪                 | Display refresh is 60 Hz; 55 leaves headroom for minor hitches. |
| Frames dropped / second     | ≤ 5       | ⚪                 | `FrameDropMonitor` threshold in existing torture-tests. |
| `scrollTick` event interval | ≤ 20 ms   | ⚪                 | Proxy for "work-in-body" on scroll path. |

**Signposts (existing):** `scrollTick`.

---

## Flow 3: Search → Navigate

**Fixture:** `Tests/VoidReaderCoreTests/Fixtures/wide-line-pathology-100KB.md`
or `torture_50k_table.md`.

**Capture method:** `scripts/perf/run_scenario.sh search-navigate`. Measure
time from arrow-key press (advance to next match) to scroll-settled.

**Primary metric:** Wall-clock ms per navigation step.

| Dimension            | Threshold | Actual (strawman) | Notes |
|----------------------|-----------|-------------------|-------|
| Per-step p50         | ≤ 100 ms  | ⚪                 | manual-3.trace arc cut 40 × 1s hangs to 2 — target is "no perceivable delay." |
| Per-step p95         | ≤ 300 ms  | ⚪                 | |
| Hangs > 1s per arc   | ≤ 0       | ⚪                 | Absolute — any 1s+ hang on the search-navigate path is a regression. |

**Signposts (missing — filed against `add-performance-instrumentation`):**
`computeMatchInfo`, `buildHighlighted`, `updateRenderedBlocks`,
`highlightedString`.

---

## Flow 4: Edit Toggle

**Fixture:** `Tests/VoidReaderCoreTests/Fixtures/midsize_250k_code.md`.

**Capture method:** `scripts/perf/run_scenario.sh edit-toggle`. Measure time
from toggle click to editor-ready / reader-ready.

**Primary metric:** Wall-clock ms per toggle.

| Dimension         | Threshold | Actual (strawman) | Notes |
|-------------------|-----------|-------------------|-------|
| Reader → editor   | ≤ 200 ms  | ⚪                 | Syntax highlighting pass + layout re-settle. |
| Editor → reader   | ≤ 150 ms  | ⚪                 | Reader side already rendered; mostly tear-down. |

**Signposts (existing):** `syntaxHighlightPass`.

---

## Arbitration

When an arc's measurement violates a threshold above, the PR MUST contain
one of:

1. **Code change that restores the budget** — linked from the arc's
   findings doc as the Chosen Action.
2. **Contract amendment with written justification** — edit the threshold
   above, increment the table, and record *why* in the arc's findings doc.
   Amendment justifications become searchable history; future contributors
   asking "why is the budget this loose?" should find the answer here.

Reviewers reject silent acceptance — a measurement that exceeds threshold
without one of the above blocks the merge.

## Updating actual columns

Each perf arc MUST update the Actual column(s) it touched, with:

- Numeric measurement
- Date (YYYY-MM-DD)
- Arc reference (PR number or commit SHA)
- Hardware annotation if measured off-target

Stale actuals are worse than missing ones — review rejects arcs that
skip the update.

## Related docs

- [`scripts/perf/README.md`](scripts/perf/README.md) — lab tooling
- [`DEVELOPMENT.md`](DEVELOPMENT.md) — profiling workflow narrative
- [`scripts/perf/findings_template.md`](scripts/perf/findings_template.md) — arc findings structure
- [`openspec/changes/add-performance-instrumentation/`](openspec/changes/add-performance-instrumentation/) — signpost tools
- [`openspec/changes/add-performance-lab/`](openspec/changes/add-performance-lab/) — this lab's design doc
