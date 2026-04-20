# Tasks: Add Performance Lab

## 1. Performance Contracts

- [ ] 1.1 Draft `PERFORMANCE.md` skeleton at repo root with four user-flow sections: doc open, scroll, search→navigate, edit toggle
- [ ] 1.2 For each flow, specify: fixture, capture method, primary metric, threshold, how to measure
- [ ] 1.3 Capture current baselines (from `manual-3.trace` and fresh runs) as the initial "actual" column
- [ ] 1.4 Cross-link each contract line to the signpost(s) that capture it; file missing-signpost tasks against `add-performance-instrumentation`
- [ ] 1.5 Review with Chuck before landing (contracts are commitments; he owns thresholds)

## 2. Fixture Matrix

- [ ] 2.1 Audit existing `Tests/VoidReaderCoreTests/Fixtures/` for shape coverage
- [ ] 2.2 Add `wide-line-pathology.md` (single lines >1000 chars)
- [ ] 2.3 Add `many-small-blocks.md` (~5000 paragraphs, each <200 chars)
- [ ] 2.4 Add `deep-nesting.md` (10+ levels of nested lists/quotes)
- [ ] 2.5 Add `heavy-inline-styling.md` (every paragraph loaded with bold/italic/code/links)
- [ ] 2.6 Add `mixed-media.md` (images + mermaid + math + tables in realistic proportions)
- [ ] 2.7 Add `real-world-messy.md` (paste-from-web artifacts: zero-width spaces, smart quotes, odd whitespace)
- [ ] 2.8 Add size-sweep variants for `wide-line-pathology` and `many-small-blocks` at 10KB, 100KB, 1MB
- [ ] 2.9 Each fixture header includes a descriptor comment (shape, size, why-it-exists)

## 3. Lab Tooling

- [ ] 3.1 Create `scripts/perf/parse_trace.py` — promote `/tmp/parse_tp3.py` logic with argparse
- [ ] 3.2 Flags: `--window START:END`, `--main-tid auto|<tid>`, `--mode leaf|sig3|sig5|app-anywhere`, `--top N`
- [ ] 3.3 Main-TID auto-detection: pick thread with most samples if not specified
- [ ] 3.4 Idle-frame denylist editable in-file (constant at top of script)
- [ ] 3.5 App-frame filter editable in-file (substring list)
- [ ] 3.6 Create `scripts/perf/run_scenario.sh <name>` — wraps `xctrace record` + `parse_trace.py`
- [ ] 3.7 Named scenarios: `open-large`, `search-navigate`, `scroll-to-bottom`, `edit-toggle`
- [ ] 3.8 Scenario output: `build/traces/<scenario>-<timestamp>.trace` + parsed report to stdout
- [ ] 3.9 Add `.gitignore` entry for `build/traces/` (entire directory, no opt-in check-ins)
- [ ] 3.10 Commit a small XML-export test fixture under `Tests/VoidReaderCoreTests/Fixtures/traces/` derived from the `manual-3.trace` search-navigate arc — kilobytes, not megabytes
- [ ] 3.11 Verify `parse_trace.py` reproduces the expected known-hangs finding against the committed XML fixture with no source edits

## 3b. Gitea CI Workflow

- [ ] 3b.1 Author `.gitea/workflows/test-perf-lab.yml` (or add job to existing `test-perf.yml` from `add-performance-instrumentation` if shipped first)
- [ ] 3b.2 Workflow invokes `scripts/perf/run_scenario.sh` for each named scenario on PR events
- [ ] 3b.3 Upload `.trace` bundles as build artifacts (one per scenario)
- [ ] 3b.4 Upload parsed hot-signature reports as build artifacts alongside traces
- [ ] 3b.5 Configure repo-level artifact retention to 90 days (document in workflow file)
- [ ] 3b.6 Verify artifacts are downloadable from a completed build's page
- [ ] 3b.7 Coordinate scope with `add-performance-instrumentation` Phase B to avoid duplicate workflows

## 4. Untapped Instruments

- [ ] 4.1 Allocations runbook in `DEVELOPMENT.md`: measure memory growth from caches added in 0928a10 (`blockHighlighted`, `matchTexts`)
- [ ] 4.2 Leaks runbook: actor retain-cycle hunt for `ImageLoader`, `MermaidImageRenderer`
- [ ] 4.3 Core Animation FPS runbook: scroll jank diagnosis with the `many-small-blocks` fixture
- [ ] 4.4 File signpost tasks against `add-performance-instrumentation` for: `computeMatchInfo`, `buildHighlighted`, `updateRenderedBlocks`, `highlightedString`
- [ ] 4.5 Design invalidation counter harness: `DEBUG`-gated counter per SwiftUI view that increments in `body`
- [ ] 4.6 Implement invalidation counter for `BlockView`, `ContentView`, `MarkdownReaderView`
- [ ] 4.7 Add one-shot report: "search→navigate tick increments BlockView body N times" — sanity check

## 5. Threshold Sweep Harness

- [ ] 5.1 Create `scripts/perf/sweep.sh <scenario> <size-sweep-name>`
- [ ] 5.2 Sweep iterates fixtures (10KB/100KB/1MB) and runs scenario against each
- [ ] 5.3 Extract p50/p95 per named signpost from each trace
- [ ] 5.4 Emit markdown table: columns = sizes, rows = signposts, cells = p50 / p95
- [ ] 5.5 Run initial sweep for `search-navigate` on wide-line-pathology
- [ ] 5.6 Commit result to `openspec/changes/add-performance-lab/findings/sweep-search-navigate-<date>.md`

## 6. Documentation

- [ ] 6.1 Extend `DEVELOPMENT.md` "Profiling" section with lab entry point: "start here"
- [ ] 6.2 Cross-reference `PERFORMANCE.md` from `DEVELOPMENT.md` and from the root `README.md`
- [ ] 6.3 Add a "how to run a perf arc" narrative: measure → hot-signature → fix → re-measure → commit
- [ ] 6.4 Document the four design smells (work-in-body, unbounded invalidation, threshold cliffs, removal-mindset) with concrete examples from recent arcs

## 7. Validate & Ship

- [ ] 7.1 Run `openspec validate add-performance-lab --strict`
- [ ] 7.2 Run a full practice arc: pick an untested flow (scroll-to-bottom on `many-small-blocks`), measure, document findings
- [ ] 7.3 Confirm the practice arc produced a committable findings doc without scratch-file edits
- [ ] 7.4 Mark change ready for archive
