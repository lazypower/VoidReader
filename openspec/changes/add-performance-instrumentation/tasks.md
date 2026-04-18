# Tasks: Performance Instrumentation

## Phase A — Signposts + Runbooks

### 1. Core Signpost Infrastructure

- [x] 1.1 Create `Sources/VoidReaderCore/Utilities/Signposts.swift` with:
  - [x] 1.1.1 `SignpostCategory` enum (rendering, lifecycle, scroll, mermaid, image)
  - [x] 1.1.2 Per-category `OSSignposter` instances with stable subsystem/category identifiers
  - [x] 1.1.3 Convenience `interval(_:category:_:)` method taking a name and closure
  - [x] 1.1.4 Convenience `event(_:category:)` method for point-in-time emission
  - [x] 1.1.5 Public API exported from VoidReaderCore

- [x] 1.2 Verify zero-overhead contract
  - [x] 1.2.1 Run existing `MarkdownPerformanceTests` — all bounded-time assertions still pass
  - [x] 1.2.2 Add a micro-benchmark test that calls an instrumented function 1000× with no Instruments attached; assert total time within tolerance of uninstrumented baseline (using `MarkdownParser.parse` as the unit of work per design.md guidance — using a trivial workload made the ratio meaningless because per-call overhead, ~1µs, dwarfs a single MAD instruction)

### 2. Phase A Instrumentation

- [x] 2.1 Lifecycle signposts
  - [x] 2.1.1 Wrap document open path with `openDocument` interval; attach metadata (file size, extension) — wired into ContentView's `.onAppear` (the natural document-open boundary for SwiftUI's `DocumentGroup`); metadata uses `OSLogMessage` interpolation via `Signposts.signposter(for:)` so it stays lazy when not recording
  - [x] 2.1.2 Wrap document close path with `closeDocument` interval — wired into `.onDisappear`
  - [x] 2.1.3 Wrap `reloadFromDisk()` with `reloadFromDisk` interval — placed after the `guard let url = fileURL` so 0-duration no-op cases don't pollute the trace

- [ ] 2.2 Rendering signposts
  - [ ] 2.2.1 Wrap `BlockRenderer.render()` with `parseMarkdown` interval; attach metadata (input bytes, produced-node count)
  - [ ] 2.2.2 Wrap `MarkdownRenderer` output generation with `renderBatch` interval; attach metadata (batch index, block count)
  - [ ] 2.2.3 Emit `firstPaint` event when the first batch of document-body blocks becomes visible — exclude placeholder/skeleton states per design.md definition
  - [ ] 2.2.4 Wrap syntax highlight pass with `syntaxHighlightPass` interval

- [ ] 2.3 Subsystem signposts
  - [ ] 2.3.1 Wrap `MermaidImageRenderer.renderAll` with `mermaidRender` interval; attach metadata (diagram count)
  - [ ] 2.3.2 Wrap `ImageLoader.loadImage` with `imageLoad` interval; attach metadata (URL scheme, bytes loaded)
  - [ ] 2.3.3 Emit `scrollTick` event from scroll position observer (event form, no interval pairing)

### 3. Developer Workflow

- [ ] 3.1 Add `make profile` target that launches Xcode's Profile action against the debug scheme (or `open -a Instruments` with a sensible template)
- [ ] 3.2 Extend `DEVELOPMENT.md` with a new "Profiling" section containing three runbooks:
  - [ ] 3.2.1 "Profiling scroll jank" — open torture_100k_code.md, use Animation Hitches template, interpret output
  - [ ] 3.2.2 "Profiling cold open" — launch with a large doc via `--open` argument, use Time Profiler, locate slow intervals
  - [ ] 3.2.3 "Profiling memory growth" — open + close N docs, use Allocations template, verify no retained growth
- [ ] 3.3 Verify each runbook is executable by running through the steps and confirming the described output appears

### 4. Phase A Validation

- [ ] 4.1 Record a trace against a torture doc; confirm all Phase A signposts appear under "Points of Interest" with correct categories
- [ ] 4.2 Use the trace to identify at least one real perf improvement candidate; document it as a follow-up (but do not implement — out of scope)
- [ ] 4.3 Confirm `MarkdownPerformanceTests` suite passes unchanged
- [ ] 4.4 Release gate check: Phase A complete and app profiled-and-tuned → 1.1.0 can tag

## Phase B — CI Regression Gating

### 5. xctrace Research Spike

- [ ] 5.1 On the Gitea runner, prototype `xctrace record --template 'Time Profiler' --launch -- /path/to/VoidReader.app --open path/to/torture.md` under the existing `launchctl-asuser` GUI session
- [ ] 5.2 Document findings in `design.md` (append a "Phase B Findings" section): does it work, what are the gotchas, what's the trace file size
- [ ] 5.3 Decide go/no-go on Phase B based on spike results. If no-go, close Phase B tasks and note in proposal.

### 6. Trace Scenario Scripting

- [ ] 6.1 Create `Scripts/profile-scenario.sh` that runs a reproducible workload: launch app → wait for firstPaint signpost → scroll to bottom → close
- [ ] 6.2 Make the scenario script parameterizable by fixture document path
- [ ] 6.3 Run the scenario 5× locally; confirm signpost intervals appear with consistent magnitudes

### 7. Metric Extraction

- [ ] 7.1 Determine export format (`xctrace export --xpath` XML vs `-toc` table-of-contents)
- [ ] 7.2 Write a metric extraction script (Swift or Python) that consumes a trace file and produces a JSON report of key interval durations
- [ ] 7.3 Report schema: openDocument.p50/p95, parseMarkdown.p50/p95, renderBatch.p50/p95, hitchCount, allocationsHighWatermark
- [ ] 7.4 Run extraction against 5 main-branch traces; compute noise floor (stddev per metric)

### 8. CI Workflow Integration — Stage 1 (record only)

- [ ] 8.1 Add `.gitea/workflows/test-perf.yml` in record-only mode:
  - [ ] 8.1.1 Runs on PR
  - [ ] 8.1.2 Checks out main, runs scenario N=5 times, stores per-run metrics
  - [ ] 8.1.3 Checks out PR, runs scenario, extracts metrics
  - [ ] 8.1.4 Posts a human-readable report to the PR (median, stddev, per-metric deltas) — workflow ALWAYS passes in this stage
  - [ ] 8.1.5 Uploads both `.trace` files as artifacts
- [ ] 8.2 Let Stage 1 run on real PR traffic for at least ~4 weeks; collect enough data to compute a stable per-metric stddev

### 9. CI Workflow — Stage 2 (soft warnings)

- [ ] 9.1 Once §8.2 observation period completes, document the noise floor per metric in `design.md`
- [ ] 9.2 Update workflow to surface warnings (non-blocking) when a metric exceeds threshold (initial: 2× stddev)
- [ ] 9.3 Track whether Stage 2 warnings correlate with real regressions vs noise across a second observation period; iterate on scenario or thresholds if signal is poor

### 10. CI Workflow — Stage 3 (hard gate)

- [ ] 10.1 Only advance to hard gating once Stage 2 warnings are trusted (documented observation period with low false-positive rate)
- [ ] 10.2 Flip workflow to fail-on-regression mode; include rationale for the chosen threshold (cite noise floor) in the commit
- [ ] 10.3 Dry-run against a synthetic regression PR (add `Thread.sleep` to `parseMarkdown`); confirm gate fires

### 11. Phase B Documentation

- [ ] 11.1 Update DEVELOPMENT.md "Profiling" section with CI section: what runs at each stage, how to read the artifact, what "baseline distribution" means
- [ ] 11.2 Document threshold tuning policy: who can change thresholds, when, and why — each change must cite observed variance data

## Phase C — Archive

- [ ] 12.1 Once Phase A ships and signposts are being used in practice, validate the spec's requirements are all met
- [ ] 12.2 When Phase B reaches Stage 3 (or is declared no-go with design.md note), archive this change via `openspec:archive`
