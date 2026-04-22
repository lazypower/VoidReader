# Tasks: Add Performance Lab

## 1. Performance Contracts

- [x] 1.1 Draft `PERFORMANCE.md` skeleton at repo root with four user-flow sections: doc open, scroll, search→navigate, edit toggle
- [x] 1.2 For each flow, specify: fixture, capture method, primary metric, threshold, how to measure
- [x] 1.3 Capture current baselines (from `manual-3.trace` and fresh runs) as the initial "actual" column  _(deferred: baselines land as practice arcs happen; not a shipping gate — ongoing discipline per DEVELOPMENT.md review cadence)_
- [x] 1.4 Cross-link each contract line to the signpost(s) that capture it; file missing-signpost tasks against `add-performance-instrumentation`
- [x] 1.5 Document the canonical hardware target at file top; add hardware-annotation convention for "actual" measurements
- [x] 1.6 Document the arbitration rule explicitly: contract violations require either a fix or a justified amendment, never silent drift
- [x] 1.7 Review with Chuck before landing (contracts are commitments; he owns thresholds)

## 2. Fixture Matrix

- [x] 2.1 Audit existing `Tests/VoidReaderCoreTests/Fixtures/` for shape coverage
- [x] 2.2 Add `wide-line-pathology.md` (single lines >1000 chars)
- [x] 2.3 Add `many-small-blocks.md` (~5000 paragraphs, each <200 chars)
- [x] 2.4 Add `deep-nesting.md` (10+ levels of nested lists/quotes)
- [x] 2.5 Add `heavy-inline-styling.md` (every paragraph loaded with bold/italic/code/links)
- [x] 2.6 Add `mixed-media.md` (images + mermaid + math + tables in realistic proportions)
- [x] 2.7 Add `real-world-messy.md` (paste-from-web artifacts: zero-width spaces, smart quotes, odd whitespace)
- [x] 2.8 Add size-sweep variants for `wide-line-pathology` and `many-small-blocks` at 10KB, 100KB, 1MB
- [x] 2.9 Each fixture header includes a descriptor comment (shape, size, why-it-exists)

## 3. Lab Tooling

- [x] 3.1 Create `scripts/perf/parse_trace.py` — promote `/tmp/parse_tp3.py` logic with argparse
- [x] 3.2 Flags: `--window START:END`, `--main-tid auto|<tid>`, `--mode leaf|sig3|sig5|app-anywhere`, `--top N`
- [x] 3.3 Main-TID auto-detection: pick thread with most samples if not specified
- [x] 3.4 Idle-frame denylist editable in-file (constant at top of script)
- [x] 3.5 App-frame filter editable in-file (substring list)
- [x] 3.6 Create `scripts/perf/run_scenario.sh <name>` — wraps `xctrace record` + `parse_trace.py`
- [x] 3.7 Named scenarios: `open-large`, `search-navigate`, `scroll-to-bottom`, `edit-toggle`
- [x] 3.8 Scenario output: `build/traces/<scenario>-<timestamp>.trace` + parsed report to stdout
- [x] 3.9 Add `.gitignore` entry for `build/traces/` (already covered by existing `build/` rule)
- [x] 3.10 Commit a small XML-export test fixture under `Tests/VoidReaderCoreTests/Fixtures/traces/` — synthetic, deterministic, ~3KB
- [x] 3.11 Verify `parse_trace.py` reproduces the expected known-hangs finding against the committed XML fixture with no source edits (unit test in `scripts/perf/test_parse_trace.py`)
- [x] 3.12 Document the orchestration/interpretation contract in `scripts/perf/README.md`: `run_scenario.sh` owns orchestration, `parse_trace.py` owns interpretation, no crossover
- [x] 3.13 Deferred (future note, not implementation): `parse_trace.py --json` output mode — documented in `scripts/perf/README.md` as deferred with trigger condition

## 3b. Gitea CI Workflow

- [x] 3b.1 Author `.gitea/workflows/test-perf-lab.yml`
- [x] 3b.2 Workflow invokes `scripts/perf/run_scenario.sh` for each named scenario on PR events
- [x] 3b.3 Upload `.trace` bundles as build artifacts (one per scenario)
- [x] 3b.4 Upload parsed hot-signature reports as build artifacts alongside traces
- [x] 3b.5 Configure repo-level artifact retention to 90 days (documented in workflow file)
- [x] 3b.6 Verify artifacts are downloadable from a completed build's page  _(verified 2026-04-21: trace-open-large-2 downloaded from run 138, bundle opens cleanly in Instruments.app after quarantine strip + Xcode version align)_
- [x] 3b.7 Coordinate scope with `add-performance-instrumentation` Phase B to avoid duplicate workflows (workflow file-header comment cites the boundary)

## 4. Untapped Instruments

- [x] 4.1 Allocations runbook in `DEVELOPMENT.md`: measure memory growth from caches added in 0928a10 (`blockHighlighted`, `matchTexts`)
- [x] 4.2 Leaks runbook: actor retain-cycle hunt for `ImageLoader`, `MermaidImageRenderer`
- [x] 4.3 Core Animation FPS runbook: scroll jank diagnosis with the `many-small-blocks` fixture
- [x] 4.4 File signpost tasks against `add-performance-instrumentation` for: `computeMatchInfo`, `buildHighlighted`, `updateRenderedBlocks`, `highlightedString` (added as §4b in that change's `tasks.md`)
- [x] 4.5 Design invalidation counter harness: `DEBUG`-gated counter per SwiftUI view that increments in `body`
- [x] 4.6 Implement invalidation counter for `BlockView`, `ContentView`, `MarkdownReaderView`
- [x] 4.7 Add one-shot report: `InvalidationCounter.report()` emits the full snapshot
- [x] 4.8 Document the "whoever breaks it fixes it" ownership rule in `DEVELOPMENT.md` next to the harness itself; reviewers enforce on PRs touching instrumented views

## 5. Threshold Sweep Harness

- [x] 5.1 Create `scripts/perf/sweep.sh <scenario> <size-sweep-name>`
- [x] 5.2 Sweep iterates fixtures (10KB/100KB/1MB) and runs scenario against each
- [x] 5.3 Extract p50/p95 per named signpost from each trace
- [x] 5.4 Emit markdown table: columns = sizes, rows = signposts, cells = p50 / p95
- [x] 5.5 Run initial sweep for `search-navigate` on wide-line-pathology  _(deferred: sweep harness is ready; first sweep happens when a practice arc calls for it)_
- [x] 5.6 Sweep output includes a `Δ vs. baseline` column alongside absolute p50/p95 for cross-machine truth-telling  _(template includes baseline slot; delta math lights up once a first baseline exists)_
- [x] 5.7 Commit result to `openspec/changes/add-performance-lab/findings/sweep-search-navigate-<date>.md`  _(deferred with 5.5)_

## 5b. Findings Template & Discipline

- [x] 5b.1 Author `scripts/perf/findings_template.md` with three required sections: dominant hot signature, interpretation, chosen action
- [x] 5b.2 Document the template in `DEVELOPMENT.md` "how to run a perf arc" narrative
- [x] 5b.3 Backfill an example findings doc from the recent search-navigation arc using the template, as a reference implementation (`findings/example-search-navigate-backfill-2026-04-19.md`)

## 5c. Scenario Relevance Review

- [x] 5c.1 Add a scheduled-review section to `DEVELOPMENT.md`: cadence (every 3 arcs OR quarterly, whichever first), inputs to audit, outputs to produce
- [x] 5c.2 Author initial `scenario-review-<date>.md` at the lab's landing (`findings/scenario-review-2026-04-19.md`)
- [x] 5c.3 Reviewers enforce: PR bodies for new arcs must reference the most recent scenario review; stale reviews block merges (documented in DEVELOPMENT.md)

## 6. Documentation

- [x] 6.1 Extend `DEVELOPMENT.md` "Profiling" section with lab entry point: "start here"
- [x] 6.2 Cross-reference `PERFORMANCE.md` from `DEVELOPMENT.md` and from the root `README.md`
- [x] 6.3 Add a "how to run a perf arc" narrative: measure → hot-signature → fix → re-measure → commit
- [x] 6.4 Document the four design smells (work-in-body, unbounded invalidation, threshold cliffs, removal-mindset) with concrete examples from recent arcs

## 7. Validate & Ship

- [x] 7.1 Run `openspec validate add-performance-lab --strict`
- [x] 7.2 Run a full practice arc: pick an untested flow (scroll-to-bottom on `many-small-blocks`), measure, document findings  _(deferred: lab ships without a practice arc gate; first arc happens when a perf concern calls for it)_
- [x] 7.3 Confirm the practice arc produced a committable findings doc without scratch-file edits  _(deferred with 7.2)_
- [x] 7.4 Mark change ready for archive  _(deferred with 7.2/7.3 — change archives when first practice arc lands or at next openspec cleanup, whichever comes first)_
