# Design: Performance Instrumentation

## Why a Design Doc

This change spans two systems (in-process instrumentation and CI infrastructure) and introduces a new pattern (signposts alongside existing DebugLog/FrameDropMonitor). Worth stating the boundaries and trade-offs before implementation.

## Architecture

### Signpost vs DebugLog vs FrameDropMonitor

Three overlapping pieces of perf infrastructure exist or are proposed. They are not redundant — each serves a different audience and use case.

| Layer | Audience | Output | When to use |
|---|---|---|---|
| `DebugLog` (existing) | Developer in Console.app | Structured log lines with timings | Debugging a specific issue, grep-friendly output |
| `FrameDropMonitor` (existing) | Developer in the app window | On-screen frame-drop counter | Quick visual feedback during dev |
| `OSSignposter` (new) | Developer in Instruments | Named intervals on a timeline | Visualizing call relationships, hitch attribution, memory timing |

Signposts are specifically for Instruments consumption. They replace nothing. A future refactor may unify these behind a common "event" type, but not as part of this change.

### Signpost Categories

One `OSLog` per subsystem, each with a stable identifier so Instruments filters work:

| Category | Subsystem identifier | Intervals emitted |
|---|---|---|
| `rendering` | `place.wabash.VoidReader.rendering` | `parseMarkdown`, `renderBatch`, `firstPaint`, `syntaxHighlightPass` |
| `lifecycle` | `place.wabash.VoidReader.lifecycle` | `openDocument`, `closeDocument`, `reloadFromDisk` |
| `scroll` | `place.wabash.VoidReader.scroll` | `scrollTick` (as event, not interval) |
| `mermaid` | `place.wabash.VoidReader.mermaid` | `mermaidRender` |
| `image` | `place.wabash.VoidReader.image` | `imageLoad` |

Identifiers mirror the convention used by `DebugLog` (`com.voidreader.debug.*`). Using distinct bundle-prefix (`place.wabash.VoidReader.*`) for signposts so Instruments "Points of Interest" filter can isolate them cleanly without pulling in existing DebugLog noise.

### Interval vs Event Signposts

- **Interval** (`beginInterval` + `endInterval`): for operations with a meaningful duration — `openDocument`, `parseMarkdown`, `renderBatch`.
- **Event** (`emitEvent`): for discrete points in time or hot-loop signals where pairing overhead would matter — `scrollTick` fires on every scroll update and becomes a density marker in the timeline.

### Interval Metadata Convention

Every interval SHOULD carry metadata that lets a future-you reading a trace answer "what was the input shape?" without cross-referencing the code. Minimum metadata per interval:

| Interval | Metadata |
|---|---|
| `openDocument` | file size (bytes), file extension |
| `parseMarkdown` | input size (bytes), produced-node count |
| `renderBatch` | batch index, block count in batch |
| `mermaidRender` | diagram count |
| `imageLoad` | URL scheme (file/https), bytes loaded |

Metadata attaches via `OSSignposter`'s message formatter. Keep values scalar and stringifiable — no allocations in the hot path beyond what the signposter already does.

### firstPaint Definition

"firstPaint" is easy to define imprecisely and that kills comparability across runs. Canonical definition: **the first batch of rendered blocks attributable to the document body becomes visible on screen**. Specifically excluded: placeholder views, skeleton loading states, chrome/toolbar first-render. The event fires exactly once per document-open lifecycle; a subsequent reload emits a fresh `firstPaint` paired with a new `reloadFromDisk` interval.

### Zero-Overhead Contract

`OSSignposter` is designed to be essentially free when Instruments is not recording. Verification strategy:

1. `MarkdownPerformanceTests` currently runs without signposts. After Phase A adds signposts, the same tests must pass with the same bounded-time assertions. If any test slows measurably, the signpost placement is wrong.
2. Add one explicit test in Phase A that calls `parseMarkdown` 1000× and asserts total time is within a tolerance of a baseline — catches accidental `beginInterval`/`endInterval` imbalance or string interpolation in signpost names.

## Phase Sequencing

Strict phase ordering (A before B) is not technically required but strongly preferred:

- Phase B's primary value is regression detection on *named intervals*. Without Phase A, the metrics are raw samples that are hard to attribute and noisy.
- Phase B carries CI risk (per the UI-test saga). Landing Phase A first gives us value even if Phase B proves intractable.
- Phase A is cleanly scoped to a single PR; Phase B likely spans multiple PRs of iteration.

## Phase B Rollout Ramp (Important)

The naive path — "ship a 10% regression gate on day one" — is how we recreate the UI-test spiral with perf data instead. Same failure mode: build gating on top of an unmeasured noise floor, then spend weeks chasing flakes that are actually variance. Explicit three-stage ramp:

1. **Stage 1 — Record only.** Workflow runs on every PR, extracts metrics, posts a human-readable report to the PR, and always passes. Goal: accumulate a real distribution of per-metric values under actual CI conditions. Collect for a documented observation period (minimum ~4 weeks of regular PR traffic, or enough data to compute a stable stddev per metric).
2. **Stage 2 — Soft warning.** Once variance is characterized, start surfacing warnings when metrics exceed threshold (e.g., 2× stddev). Still non-blocking. Goal: validate that warnings correlate with real regressions before trusting them as gates. If Stage 2 warnings are mostly noise, tighten the scenario or widen the thresholds before advancing.
3. **Stage 3 — Hard gate.** Only once Stage 2 signal is trustworthy does the workflow start blocking PRs. Thresholds are expressed relative to observed variance, not fixed percentages, and every threshold commit includes a one-line rationale citing the noise floor.

Baselines are distributions, not single numbers. Compare a PR against the rolling median + stddev of the last N main runs (N ≥ 5). A single trace is too noisy to be authoritative for anything.

## Open Questions (to be resolved during Phase B)

1. **Does `xctrace record --launch` work under our existing `launchctl-asuser` session?** Prototype on day 1.
2. **Can we reliably detect hitches without a real display?** The runner is headless for UI tests but the CI runs a GUI session via launchctl. Animation Hitches may or may not be meaningful there.
3. **Export format.** `xctrace export` supports XML and `-toc`. Pick whichever yields the flattest parsing for the metrics we care about.
4. **Baseline storage.** Options: (a) commit baseline JSON to the repo, (b) store as Gitea artifact keyed by main SHA, (c) compute baseline from last N main commits at PR time. (c) is most adaptive but most complex.
5. **How many samples per metric?** A single trace is too noisy. 3–5 runs with median is the usual pattern.

These are resolved in Phase B task items, not now.

## Trade-offs Accepted

- **Three overlapping perf systems.** Unifying them is future work. Today, each has a distinct purpose.
- **Signpost placement is a judgement call.** We risk too few (gaps in coverage) or too many (noise). Placement is guided by existing `DebugLog.measure()` call sites as a prior decision.
- **Phase B may never ship.** That's acceptable. Phase A is useful on its own; Phase B is the ambitious extension.

## Non-Goals Restated

This proposal does NOT:
- Change any existing perf code path
- Add new features to the app
- Replace `DebugLog`, `FrameDropMonitor`, or `MarkdownPerformanceTests`
- Profile or optimize — it only makes profiling and optimization measurable
