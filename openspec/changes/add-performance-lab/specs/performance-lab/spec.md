## ADDED Requirements

### Requirement: Performance Contract Document

The project SHALL maintain a `PERFORMANCE.md` file at the repository root that specifies numeric performance thresholds for each named user flow.

The document MUST define, for each user flow:
- A named fixture from the fixture matrix
- A capture method (which signpost, which scenario script)
- A primary metric (wall-clock ms, MB, or FPS)
- A pass/fail threshold (absolute)
- A dated "actual" measurement, annotated with hardware when it differs from the canonical target

Thresholds are absolute numbers relative to a canonical hardware target footnoted at the file top.

When a change violates a contract, the arc MUST either restore compliance or amend the contract with explicit justification; silent drift is prohibited.

#### Scenario: Contract covers doc-open flow
- **WHEN** a contributor reads `PERFORMANCE.md`
- **THEN** they find a "Document Open" section with fixture, metric, threshold, and current measurement for the 81KB manifest-class document

#### Scenario: Contract covers search-navigate flow
- **WHEN** a contributor reads `PERFORMANCE.md`
- **THEN** they find a "Search Navigate" section specifying the per-step budget and the capture method

#### Scenario: Contract references live signposts
- **WHEN** a metric in `PERFORMANCE.md` is tied to a specific signpost
- **THEN** that signpost exists in the codebase OR a task exists against `add-performance-instrumentation` to add it

#### Scenario: Measurements carry hardware annotations
- **WHEN** an "actual" measurement is recorded on hardware different from the canonical target
- **THEN** the entry includes a machine/OS annotation so future readers can interpret variance

#### Scenario: Contract violation forces explicit choice
- **WHEN** an arc's measurement exceeds a threshold
- **THEN** the PR either fixes the regression or amends the contract with a written justification in the arc's findings doc; a reviewer rejects silent acceptance

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
- **WHEN** `parse_trace.py` is run against a small canonical XML export committed as a test fixture under `Tests/VoidReaderCoreTests/Fixtures/traces/`
- **THEN** it identifies the expected known hangs (derived from the `manual-3.trace` search-navigation arc) with no source edits

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

#### Scenario: Sweep output includes deltas vs. baseline
- **WHEN** a sweep runs against a prior baseline from the same scenario
- **THEN** the markdown table includes a `Δ vs. baseline` column alongside absolute p50/p95, so reviewers see regression or improvement independent of hardware variance

#### Scenario: Cliff behavior is visible
- **WHEN** a threshold sweep crosses a cliff (e.g., 100KB passes, 1MB fails a budget)
- **THEN** the resulting table makes the cliff obvious without further analysis

### Requirement: CI Artifact Retention

The Gitea CI workflow SHALL upload generated trace bundles and parsed hot-signature reports as build artifacts for each perf-run invocation.

Artifact retention MUST be configured at the repo level to support historical analysis across recent build history; the initial retention period is a deliberate conservative choice and may be extended as query patterns demand.

Raw `.trace` bundles MUST NOT be committed to the repository; `build/traces/` MUST remain fully gitignored.

#### Scenario: Traces are retrievable from build history
- **WHEN** a contributor opens a past Gitea build for a perf-run invocation
- **THEN** the `.trace` bundles and parsed reports appear as downloadable build artifacts

#### Scenario: Parsed reports accompany traces
- **WHEN** the CI workflow completes a perf scenario
- **THEN** both the raw `.trace` and the human-readable parsed report are uploaded as artifacts of the same build

#### Scenario: Traces are not committed
- **WHEN** a contributor runs a local perf scenario producing `build/traces/<scenario>-<timestamp>.trace`
- **THEN** `git status` does not show the trace file as untracked-but-stageable, because `build/traces/` is gitignored

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

### Requirement: Findings Document Structure

Every findings document under `openspec/changes/<arc>/findings/` SHALL name the dominant hot signature, state its interpretation, and declare the chosen action. Raw tables without interpretation are insufficient.

Required structure (at minimum):
- **Dominant hot signature** — the top app-anywhere or sig5 frame and its percentage
- **Interpretation** — what the signature indicates about where work is happening
- **Chosen action** — one of: fix applied (link commit), deferred (reason + owner), accepted-with-justification (contract amendment reference)

#### Scenario: Findings without interpretation are rejected
- **WHEN** a PR adds a findings doc containing only a sweep table
- **THEN** the reviewer rejects it for missing hot signature / interpretation / action

#### Scenario: Findings template exists
- **WHEN** a contributor starts a new findings doc
- **THEN** a template at `scripts/perf/findings_template.md` provides the required structure with inline guidance

### Requirement: Scenario Relevance Review

The project SHALL audit lab scenarios against real-world inputs on a recurring cadence to prevent drift between synthetic fixtures and actual user workloads.

Review cadence: every three arcs, or once per calendar quarter, whichever comes first.

Review inputs: user-reported perf issues, dogfooded document captures, real-world paste-from-web pathologies, GitHub issue threads tagged performance.

Review output: a dated note under `openspec/changes/add-performance-lab/findings/scenario-review-<date>.md` listing fixtures added, scenarios added, fixtures retired, and unchanged-but-still-relevant decisions.

#### Scenario: Missed review blocks the next merge
- **WHEN** the last scenario review date is older than one quarter AND three arcs have shipped since
- **THEN** the next arc's PR is blocked pending a scenario review

#### Scenario: Review note is committable
- **WHEN** a scheduled review completes
- **THEN** a `scenario-review-<date>.md` note is committed with adds / removes / kept decisions and the inputs reviewed
