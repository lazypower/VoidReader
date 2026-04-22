# Findings: add-performance-lab — search-navigate on manual-3 (backfill, 2026-04-19)

> **Backfill example.** This doc is a reference implementation of the
> findings template against a real arc (`feat/large-doc-rendering`'s
> search-navigate hang hunt). Written after the fact from the
> `manual-3.trace` + `parse_tp3.py` outputs — not a fresh measurement.
> Exists to give future arcs a worked example to copy from.

## Dominant hot signature

From `scripts/perf/parse_trace.py /tmp/tp3.xml --window hang1=5.5s:6.1s --mode sig5`:

```
    6    1.5%  AG::Graph::propagate_dirty(AG::AttributeID)
              <- StoredLocationBase.beginUpdate()
              <- StoredLocationBase.BeginUpdate.apply()
              <- GraphHost.flushTransactions()
              <- GraphHost.runTransaction(_:do:id:)
    4    1.0%  String.distance(from:to:)
              <- MarkdownChunker.findFirstChunkEnd(in:targetSize:)
              <- ContentView.updateRenderedBlocks(from:)
              <- ContentView.body.getter
```

From `--mode app-anywhere` across the full 5s–20s arc:

```
 9552  97.0%  VoidReaderApp.$main()
  612   6.2%  ContentView.body.getter
  167   1.7%  MarkdownReaderViewWithAnchors.computeMatchInfo(blocks:)
  167   1.7%  MarkdownReaderViewWithAnchors.updateMatchInfoIfNeeded(blocks:)
```

## Interpretation

Two stories under one symptom:

1. **SwiftUI invalidation cascade (`AG::Graph::propagate_dirty`).**
   `ContentView.body` was running often enough that the attribute graph
   spent a meaningful fraction of CPU re-dirtying downstream attributes.
   Smell: **unbounded invalidation**. Fix was state scoping in
   `MarkdownReaderViewWithAnchors` — decoupling match-info from the
   binding that triggered a whole-subtree rebuild.

2. **Chunker walking too much string per navigation (`String.distance`).**
   `MarkdownChunker.findFirstChunkEnd` ran `String.distance` per call and
   was invoked on every `ContentView.updateRenderedBlocks`. Smell:
   **work in body** — measurable work living inside a reactive path that
   re-ran per arrow-key press. Fix was AST-aware chunk boundaries
   (commit `a4438ef`) so boundaries precompute once.

Combined impact: 40 consecutive ~1s hangs → 2 remaining hangs (one
~600ms, one ~500ms). The remaining hangs are Swift metadata-cache churn
in `_swift_getGenericMetadata` — not our code — and tolerated.

## Chosen action

**Fix applied.** Commits:

- `a336e5f` — off-main highlight + NSTextView for large blocks
- `a4438ef` — AST-aware chunk boundaries
- `9e5127d` — layout/highlight threshold split, attribute diet
- `71b59f4` — large-doc fixtures

All on branch `feat/large-doc-rendering` (see PR #3).

## Baseline / delta

Strawman numbers (pre-lab; no committed baseline file yet — this backfill
establishes one).

| Flow            | Threshold           | Before  | After   | Δ        |
|-----------------|---------------------|---------|---------|----------|
| Search navigate | ≤ 300 ms p95        | ~1000 ms | ~500 ms | −500 ms  |
| Hangs > 1s/arc  | = 0                 | 40      | 0\*     | −40      |

\* Two residual hangs remain (~500–600ms) attributed to Swift runtime
metadata cache, not app code. They register as hitches, not hangs, on
the contract.

## Data

See `/tmp/tp3.xml` (not committed — ephemeral trace artifact) and the
`scripts/perf/parse_trace.py` outputs quoted above. Committed deterministic
fixture at `Tests/VoidReaderCoreTests/Fixtures/traces/
search_navigate_fixture.xml` preserves the shape for parser regression
tests.

## Trace artifacts

- Trace: `/tmp/manual-3.trace` (not retained; pre-dates CI artifact upload)
- Parsed report: regenerated ad-hoc via
  `python3 scripts/perf/parse_trace.py /tmp/tp3.xml --mode sig5`

Future arcs of this kind will have their `.trace` + parsed report
uploaded as Gitea build artifacts via
`.gitea/workflows/test-perf-lab.yml` (90-day retention).
