# Capability: Performance Instrumentation

Named signpost instrumentation for Instruments profiling, plus an optional CI regression-gating pipeline built on top of it.

## ADDED Requirements

### Requirement: OSSignposter Infrastructure

The app SHALL provide an `OSSignposter`-based instrumentation utility in VoidReaderCore with per-subsystem categorization.

#### Scenario: Signposts organized by subsystem category
- **Given** the signpost utility is in use
- **When** a developer records a trace with Instruments
- **Then** signposts appear under categories `rendering`, `lifecycle`, `scroll`, `mermaid`, and `image`
- **And** each category uses a stable, documented subsystem identifier so Instruments filters are reproducible

#### Scenario: Zero overhead when Instruments is not attached
- **Given** the app is running without Instruments recording
- **When** an instrumented code path executes
- **Then** no measurable overhead is introduced relative to the uninstrumented baseline

#### Scenario: Instrumented code remains testable
- **Given** signposts wrap functions covered by `MarkdownPerformanceTests`
- **When** the existing test suite runs
- **Then** all bounded-time assertions still pass

---

### Requirement: Lifecycle Signposts

The app SHALL emit signpost intervals for document lifecycle boundaries.

#### Scenario: Document open
- **Given** a user opens a markdown file
- **When** the open flow executes
- **Then** an `openDocument` interval is emitted spanning from invocation to first successful render

#### Scenario: Document close
- **Given** a user closes an open document
- **When** the close flow executes
- **Then** a `closeDocument` interval is emitted spanning the teardown

#### Scenario: Reload from disk
- **Given** the user invokes Reload from Disk (Cmd-R) or the external-change reload flow
- **When** `reloadFromDisk()` executes
- **Then** a `reloadFromDisk` interval is emitted

---

### Requirement: Rendering Signposts

The app SHALL emit signpost intervals for the markdown rendering pipeline.

#### Scenario: Markdown parse
- **Given** a document is being rendered
- **When** `BlockRenderer.render()` executes
- **Then** a `parseMarkdown` interval is emitted with input size (bytes) and produced-node count as metadata

#### Scenario: Render batch
- **Given** a document is being rendered progressively
- **When** a batch of blocks is produced
- **Then** a `renderBatch` interval is emitted per batch with the batch size (block count) as metadata

#### Scenario: First paint event
- **Given** a document is opening
- **When** the first batch containing meaningful content (not placeholder/skeleton) becomes visible on screen
- **Then** a `firstPaint` event is emitted
- **And** "meaningful content" is defined as the first batch of rendered blocks attributable to the document body — precise enough that the event fires at a consistent boundary across runs

#### Scenario: Syntax highlight pass
- **Given** the user is in edit mode
- **When** a syntax highlighting pass executes
- **Then** a `syntaxHighlightPass` interval is emitted covering the pass

---

### Requirement: Subsystem Signposts

The app SHALL emit signposts for the mermaid, image, and scroll subsystems.

#### Scenario: Mermaid render
- **Given** a document contains mermaid blocks
- **When** `MermaidImageRenderer.renderAll` executes
- **Then** a `mermaidRender` interval is emitted covering the batch render

#### Scenario: Image load
- **Given** a document references images
- **When** `ImageLoader.loadImage` executes
- **Then** an `imageLoad` interval is emitted per image

#### Scenario: Scroll tick
- **Given** the user is scrolling
- **When** the scroll position observer fires
- **Then** a `scrollTick` event is emitted (event form, not interval, to avoid pairing overhead in a hot loop)

---

### Requirement: Profiling Developer Workflow

The project SHALL document a profiling workflow that any developer can execute without prior Instruments experience.

#### Scenario: Profile target
- **Given** a developer wants to profile the app
- **When** they run `make profile` (or the documented equivalent)
- **Then** Instruments launches with a sensible template against the debug build

#### Scenario: Scroll-jank runbook
- **Given** `DEVELOPMENT.md` contains a "Profiling scroll jank" runbook
- **When** a developer follows the runbook against a torture fixture
- **Then** the runbook's stated output appears (named intervals, hitch markers, etc.) without further guidance

#### Scenario: Cold-open runbook
- **Given** `DEVELOPMENT.md` contains a "Profiling cold open" runbook
- **When** a developer follows it to profile opening a large doc
- **Then** Time Profiler shows the `openDocument` and `firstPaint` signposts bracketing the work

#### Scenario: Memory-growth runbook
- **Given** `DEVELOPMENT.md` contains a "Profiling memory growth" runbook
- **When** a developer follows it to profile repeated open/close cycles
- **Then** Allocations reveals whether memory is retained across cycles and which signpost intervals correlate with growth

---

### Requirement: CI Regression Gating (Phase B — Conditional)

The project SHALL provide automated performance-regression detection on CI, ramping through three stages (record-only → soft warning → hard gate), CONDITIONAL on `xctrace` being viable under the Gitea runner's `launchctl-asuser` session.

#### Scenario: Baseline trace on main
- **Given** a commit lands on main
- **When** the perf workflow runs
- **Then** a trace is recorded against a fixed scenario and key interval durations are stored as part of the rolling baseline distribution

#### Scenario: Baseline is a distribution, not a point
- **Given** a PR is compared to the main baseline
- **When** the comparison runs
- **Then** the baseline represents a distribution (at least N=5 recent main runs) with stddev computed per metric
- **And** thresholds are expressed relative to observed variance (e.g., multiples of stddev), not a fixed percent

#### Scenario: Stage 1 — record only
- **Given** Phase B is in its initial stage
- **When** a PR perf workflow runs
- **Then** it records a trace, extracts metrics, produces a human-readable report, and always passes
- **And** the report is posted to the PR so maintainers can build intuition about noise before any gating takes effect

#### Scenario: Stage 2 — soft warning
- **Given** at least four weeks of Stage 1 data have been collected and variance per metric is documented
- **When** a PR metric exceeds the warning threshold
- **Then** the workflow surfaces a warning (non-blocking) on the PR
- **And** the workflow still passes regardless of warnings

#### Scenario: Stage 3 — hard gate
- **Given** Stage 2 warnings have proven to correlate with real regressions (not noise) over a documented observation period
- **When** a PR metric exceeds the gating threshold
- **Then** the workflow fails and blocks merge
- **And** the threshold is documented with a rationale that references the observed noise floor

#### Scenario: Synthetic regression detection
- **Given** a PR intentionally adds a `Thread.sleep` to an instrumented function
- **When** the perf workflow runs in Stage 3
- **Then** the corresponding interval metric regresses and the gate fails

#### Scenario: Trace artifacts available
- **Given** a perf workflow run has completed (in any stage)
- **When** a developer investigates a regression or inspects a run
- **Then** both the baseline and PR `.trace` files are available as downloadable CI artifacts

#### Scenario: Phase B no-go path
- **Given** the xctrace research spike determines CI integration is not viable
- **When** the Phase B tasks are concluded
- **Then** the reason is documented in `design.md` and this requirement is removed from the spec before archival, leaving Phase A as the shipped scope
