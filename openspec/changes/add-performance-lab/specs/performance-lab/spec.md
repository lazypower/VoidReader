## ADDED Requirements

### Requirement: Performance Contract Document

The project SHALL maintain a `PERFORMANCE.md` file at the repository root that specifies numeric performance thresholds for each named user flow.

The document MUST define, for each user flow:
- A named fixture from the fixture matrix
- A capture method (which signpost, which scenario script)
- A primary metric (wall-clock ms, MB, or FPS)
- A pass/fail threshold
- A dated "actual" measurement

#### Scenario: Contract covers doc-open flow
- **WHEN** a contributor reads `PERFORMANCE.md`
- **THEN** they find a "Document Open" section with fixture, metric, threshold, and current measurement for the 81KB manifest-class document

#### Scenario: Contract covers search-navigate flow
- **WHEN** a contributor reads `PERFORMANCE.md`
- **THEN** they find a "Search Navigate" section specifying the per-step budget and the capture method

#### Scenario: Contract references live signposts
- **WHEN** a metric in `PERFORMANCE.md` is tied to a specific signpost
- **THEN** that signpost exists in the codebase OR a task exists against `add-performance-instrumentation` to add it

### Requirement: Fixture Matrix

The test fixtures directory SHALL include a matrix covering the six canonical document shapes, with size-sweep variants for at least two shapes.

The matrix MUST include fixtures for:
- Wide-line pathology (single lines exceeding 1000 characters)
- Many small blocks (thousands of short paragraphs)
- Deep nesting (ten or more levels of nested lists or quotes)
- Heavy inline styling (pervasive bold/italic/code/links)
- Mixed media (images, mermaid diagrams, math, tables together)
- Real-world messy (paste-from-web artifacts)

Each fixture MUST carry a header comment describing its shape, size, and reason-for-existence.

#### Scenario: Shape coverage is discoverable
- **WHEN** a contributor lists `Tests/VoidReaderCoreTests/Fixtures/`
- **THEN** each of the six shapes is represented by at least one file

#### Scenario: Size-sweep variants enable cliff hunting
- **WHEN** a contributor runs a threshold sweep on a shape
- **THEN** 10KB, 100KB, and 1MB variants of that shape are available

#### Scenario: Fixture purpose is self-documenting
- **WHEN** a contributor opens any matrix fixture
- **THEN** a header comment identifies the shape, approximate size, and what failure mode the fixture is designed to expose

### Requirement: Trace Parser Script

The repository SHALL provide `scripts/perf/parse_trace.py` that consumes xctrace XML export and emits hang-window analysis without requiring source edits between runs.

The parser MUST support command-line configuration for:
- Analysis window (start and end times in nanoseconds)
- Main thread ID (with auto-detection when unspecified)
- Output mode (leaf frame, signature depth 3, signature depth 5, app-anywhere)
- Result count limit

The parser MUST apply a configurable idle-frame denylist to separate idle samples from work samples.

#### Scenario: Parser runs without editing source
- **WHEN** a contributor invokes `scripts/perf/parse_trace.py --window 5s:10s <trace.xml>`
- **THEN** the parser produces a hang-window report without requiring any edits to the script

#### Scenario: Main TID auto-detection works
- **WHEN** the parser is invoked without `--main-tid`
- **THEN** it selects the thread with the most samples in the window and reports the choice

#### Scenario: Parser reproduces known finding
- **WHEN** `parse_trace.py` is run against the checked-in `manual-3.trace` baseline
- **THEN** it identifies the two known hangs (initial `findFirstChunkEnd` and single `computeMatchInfo` rebuild) with no source edits

### Requirement: Scenario Runner

The repository SHALL provide `scripts/perf/run_scenario.sh` that drives xctrace capture and trace parsing for a named scenario with a single command.

The runner MUST support named scenarios for `open-large`, `search-navigate`, `scroll-to-bottom`, and `edit-toggle`.

The runner MUST emit both a raw `.trace` bundle and a parsed report.

#### Scenario: Single-command capture and parse
- **WHEN** a contributor runs `scripts/perf/run_scenario.sh search-navigate`
- **THEN** a `.trace` file is written to `build/traces/` and a parsed report is printed to stdout

#### Scenario: Scenario name is validated
- **WHEN** a contributor passes an unknown scenario name
- **THEN** the runner exits with an error listing valid scenario names

### Requirement: Threshold Sweep Harness

The repository SHALL provide `scripts/perf/sweep.sh` that runs a scenario against size-sweep fixtures and emits a committable markdown table.

The harness MUST iterate fixture sizes (10KB, 100KB, 1MB), extract per-signpost p50 and p95 durations, and format results as a markdown table with sizes as columns and signposts as rows.

#### Scenario: Sweep produces committable output
- **WHEN** a contributor runs `scripts/perf/sweep.sh search-navigate wide-line-pathology`
- **THEN** a markdown table is printed to stdout and saved to `openspec/changes/<arc>/findings/sweep-<scenario>-<date>.md` when invoked with a `--save` flag

#### Scenario: Cliff behavior is visible
- **WHEN** a threshold sweep crosses a cliff (e.g., 100KB passes, 1MB fails a budget)
- **THEN** the resulting table makes the cliff obvious without further analysis

### Requirement: Golden-Trace Baselines

The repository SHALL maintain a `build/traces/baselines/` directory containing curated reference traces with an accompanying manifest.

Baseline traces MUST be opt-in check-ins; all other traces under `build/traces/` MUST be gitignored.

The manifest MUST identify, for each baseline: the scenario, the fixture, the date captured, the commit SHA, and the hardware.

#### Scenario: Baselines survive rebuilds
- **WHEN** a contributor runs `make clean`
- **THEN** `build/traces/baselines/` and its contents are not deleted

#### Scenario: Manifest is complete
- **WHEN** a contributor reads `build/traces/baselines/MANIFEST.md`
- **THEN** every `.trace` in the directory is documented with scenario, fixture, date, commit, and hardware

### Requirement: Invalidation Counter Harness

The app SHALL provide a `DEBUG`-gated counter harness that surfaces per-view SwiftUI `body` recompute counts for key views.

The harness MUST instrument at minimum `BlockView`, `ContentView`, and `MarkdownReaderView`.

The counters MUST be inert (zero runtime cost) in release builds.

#### Scenario: Counters produce per-flow reports in debug
- **WHEN** the app is built in `DEBUG` and a contributor performs a search-navigate step
- **THEN** `DebugLog` reports the number of `BlockView` body recomputes caused by that step

#### Scenario: Counters do not ship in release
- **WHEN** the app is built in release configuration
- **THEN** the counter code is excluded and no `body` instrumentation runs

### Requirement: Untapped-Instruments Runbooks

`DEVELOPMENT.md` SHALL contain runbook entries for Allocations, Leaks, and Core Animation FPS profiling, each executable without further guidance.

Each runbook MUST specify: the Instruments template, the fixture, the user actions to perform, and the signal to look for.

#### Scenario: Allocations runbook covers new caches
- **WHEN** a contributor opens the Allocations runbook
- **THEN** it guides them through measuring memory growth from `MatchInfo.blockHighlighted` and `matchTexts` on a large document

#### Scenario: Leaks runbook covers actor boundaries
- **WHEN** a contributor opens the Leaks runbook
- **THEN** it targets `ImageLoader` and `MermaidImageRenderer` as known candidates for actor retain cycles

#### Scenario: CA FPS runbook targets scroll jank
- **WHEN** a contributor opens the Core Animation FPS runbook
- **THEN** it uses the `many-small-blocks` fixture and describes what a scroll hitch looks like on the FPS track
