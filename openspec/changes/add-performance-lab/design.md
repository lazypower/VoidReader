## Context

Three recent arcs (`refactor-large-code-block-rendering`, the unnamed arrow-key hang hunt, and `feat/large-doc-rendering`) followed the same loop: run xctrace, parse the XML, read the hot signature, fix the named thing, re-measure. The loop worked. The artifacts did not survive — the Python parsers lived in `/tmp`, the hang-window numbers lived in chat, and the interpretation lived in whoever happened to be debugging.

Two collaborators (the assistant and Fiona, a separate AI reviewer) independently converged on the same gap: we have tools but no discipline. The tools change (`add-performance-instrumentation`) ships signposts and capture. The discipline change (this one) ships contracts, fixtures, and the parser-as-real-artifact.

The distinction matters because the next arc probably isn't a hang. It's scroll jank, or memory growth from the caches we just added, or an invalidation cascade that looks fine in any one profile but compounds over a session. Those don't reveal themselves to "run xctrace and look for the 1s bars." They require asking the right question before measurement, and the contract layer is how we figure out the right question.

## Goals / Non-Goals

**Goals**

- Make the measure→hot-signature→fix→re-measure loop reproducible by any contributor, not just whoever's holding today's context
- Shift design review from "does this look expensive?" to "what does this do to the numbers in `PERFORMANCE.md`?"
- Catch threshold cliffs (works at 50KB, dies at 80KB) as a first-class concern, not an incidental finding
- Give SwiftUI `body` recomputes a name, so "work in body" is a testable smell, not a vibe

**Non-Goals**

- Automated perf gating in CI — that's `add-performance-instrumentation` Phase B
- Perfect fixture coverage — six shapes × a few size variants is enough to catch the common failure modes; more becomes maintenance burden
- Solving any specific perf issue — this is the lab, not the experiment
- A user-facing perf HUD — debug counters only, behind `DEBUG` flag

## Decisions

### Decision: Lab lives at repo root, not under `Tests/`

- `scripts/perf/` and `PERFORMANCE.md` are developer-loop artifacts, not test infrastructure. Putting them under `Tests/` would imply they run in CI and block merges.
- Alternative: `Tests/Perf/`. Rejected because the lab's outputs are human-interpreted markdown tables and trace files, not pass/fail assertions. The discipline is the point; automation is a downstream concern.

### Decision: Contracts are numeric, smells are qualitative

- `PERFORMANCE.md` contains numbers (ms, MB, FPS). Invalidation counters and "work in body" are called out as smells but not thresholded.
- Alternative: threshold everything. Rejected because invalidation counts vary wildly across SwiftUI versions and fixture shapes; over-thresholding would produce flaky checks and cargo-cult compliance.

### Decision: Parser script is source-controlled Python, not Swift

- `parse_trace.py` is promoted from `/tmp/parse_tp3.py` with minimal rewriting. Python because the xctrace XML export is the input, and Python's `xml.etree.ElementTree` handles it with no dependency footprint. Also because rewriting working code to satisfy language consistency is exactly the "work beyond the task" this codebase pushes back on.
- Alternative: Swift script via `swift run`. Rejected because adding a Swift package for one-off analysis inflates build time and adds no capability the Python version lacks.

### Decision: Trace output ships to Gitea build artifacts, not git

- CI workflow uploads `.trace` bundles + parsed hot-signature reports as build artifacts on every perf run. Retention starts conservative (90d) and extends as historical-query patterns demand.
- No trace files committed to the repository; `build/traces/` stays fully gitignored. Parser correctness is verified against a small XML-export test fixture under `Tests/VoidReaderCoreTests/Fixtures/traces/` — kilobytes, not megabytes.
- Alternative: self-hosted S3 (MinIO / Garage / RustFS) with per-object TTLs and a separate "goldens" bucket carrying no lifecycle rule. Deferred — genuinely more capable (differentiated retention, content-addressable URLs, pleasant historical queries) but adds a second store to operate before the lab has produced a single historical-analysis query in anger. Migration later costs one workflow file. Revisit when (a) Gitea artifact limits bite, (b) a `gitea-api | jq | download-loop` makes us curse twice in one session, or (c) cross-repo perf comparison becomes a real need.
- Alternative: commit "golden" traces under `build/traces/baselines/` with a manifest. Rejected — binary blobs in git, manual promotion discipline, and Gitea artifacts already carry the commit SHA + build metadata for free.
- Alternative: commit every trace. Rejected for the obvious reason.

### Decision: Fixture matrix caps at ~12 files

- Six shapes + at most two size-sweep variants each (12 total). Beyond that, marginal coverage drops fast and the mental load of "which fixture do I pick?" becomes real.
- Alternative: a fixture generator that synthesizes arbitrary shapes on demand. Deferred — revisit only if the matrix stops producing new findings.

### Decision: Invalidation counter is `DEBUG`-gated only

- Counters live behind `#if DEBUG` so they're inert in release. Reported via `DebugLog`, not OSSignpost, because the point is "show me this number during development," not "feed Instruments."
- Alternative: always-on via OSSignpost events. Rejected because counter increments in `body` are exactly the kind of work we want zero-cost in shipping builds.

### Decision: Orchestration and interpretation live in different languages

- `run_scenario.sh` owns orchestration: xctrace invocation, fixture selection, output paths, invoking the parser, CI upload handoff. No interpretation logic ever.
- `parse_trace.py` owns all interpretation: idle-frame filtering, hot-signature ranking, window scoping, report formatting. No xctrace invocation.
- Rule-of-thumb for PR review: if a shell script starts parsing trace content, reject the PR and move the logic into Python. If Python starts invoking xctrace, reject and move it back to shell.
- Alternative: fold everything into shell. Rejected because shell parsing is where diagnostic tools go to die — awk-and-sed pipelines become unmaintainable the moment xctrace's output format shifts.
- Alternative: fold everything into Python including xctrace invocation via subprocess. Plausible, but shell wraps xctrace more naturally and the boundary is easier to enforce with two languages than with one file by convention.

### Decision: Contracts absolute, measurements hardware-annotated, findings track deltas

- `PERFORMANCE.md` thresholds are absolute numbers (ms, MB, FPS). One canonical hardware target per threshold ("measured on M-series Apple Silicon, macOS 14+") footnoted at the file top.
- Each "actual" measurement in `PERFORMANCE.md` MUST include a hardware annotation when the measuring machine differs from the canonical target.
- Threshold-sweep findings MUST include a `Δ vs. baseline` column alongside absolute p50/p95 — because absolute numbers mislead across machines, but deltas tell the truth about whether *this change* regressed anything.
- Alternative: per-hardware threshold tables (M1 column, M3 column, etc.). Rejected — multiplies maintenance by N hardware targets for marginal clarity gain at our scale.
- Alternative: deltas only, no absolutes. Rejected because absolute budgets are the arbitration anchor; deltas are a supplementary truth-telling mechanism.

### Decision: Contract arbitration is explicit, never silent

- When an arc's measurement violates a `PERFORMANCE.md` threshold, reviewers MUST see one of: (a) code change that restores the budget, (b) a contract amendment with a written justification in the arc's findings doc. Silent acceptance is a review blocker.
- The goal is to make drift visible. Numbers that silently creep upward are the single most common way performance systems lose legitimacy.
- Amendment justifications become searchable history — useful when a future contributor asks "why is the budget this loose?"

### Decision: Findings docs include interpretation, not just data

- Every findings doc under `openspec/changes/<arc>/findings/` MUST name: (a) the dominant hot signature, (b) the interpretation (what the signature is telling us), (c) the chosen action (fix applied, deferred with reason, or accepted with justification).
- A raw table is insufficient. The discipline is in the interpretation — tables without interpretation are "lab becomes ceremony" in action.
- Reviewers reject findings docs that skip any of the three required elements.

## Risks / Trade-offs

- **Risk: `PERFORMANCE.md` goes stale.** Once contracts are written and nobody updates them, they become lies. Mitigation: each perf arc touches `PERFORMANCE.md` to update the "actual" column; reviewers reject arcs that don't.
- **Risk: Parser diverges from xctrace output.** xctrace XML format could change across Xcode versions. Mitigation: `parse_trace.py` fails loudly on unrecognized structure; the failure is cheap to diagnose during a hunt.
- **Risk: Fixtures drift from production shapes.** Synthetic fixtures don't match what users actually open. Mitigation: `real-world-messy.md` is derived from actual paste-from-web captures; update opportunistically when we see a new pathology in the wild.
- **Trade-off: Discipline is overhead until it isn't.** The first arc after this ships will be slower (contracts to write, fixtures to pick, tables to produce). The second should be faster than the pre-lab loop. If the second arc isn't faster, the lab is wrong and we tear it down.

## Migration Plan

1. Merge lab scaffolding (scripts, fixtures, `PERFORMANCE.md` skeleton) without deleting any `/tmp` artifacts
2. Run a practice arc (scroll-to-bottom on `many-small-blocks`) end-to-end using only lab tooling
3. If the practice arc produces a committable findings doc, archive any residual `/tmp` parsers
4. Update `add-performance-instrumentation` tasks to add the signposts the lab needs
5. Announce the lab in `DEVELOPMENT.md` and root `README.md`

Rollback: if the lab doesn't produce a usable practice-arc finding, delete `scripts/perf/` and revert `PERFORMANCE.md` to a stub. The fixture matrix stays regardless — tests benefit even if the lab doesn't.

## Open Questions

- Does the lab's threshold sweep ever get promoted to pass/fail CI gating? `add-performance-instrumentation` Phase B handles one answer for scenario regressions; the sweep harness might have a different CI shape (e.g., "did any cliff move?"). Defer until we've run three or four arcs through the lab and know what a useful sweep-based gate looks like.
- What's the right cadence for scenario-relevance review — quarterly calendar-based, or every-three-arcs workload-based? Proposal chose "whichever comes first" but we'll learn which trigger fires first in practice.
- Does `parse_trace.py` need a `--json` output mode for machine consumption? Deferred until a real consumer exists (CI dashboards, historical-analysis tooling). The moment we find ourselves grepping our own CLI output, that's the signal to add JSON.

## Questions Closed by Review

- ~~Hardware-specific vs fixed thresholds?~~ → Absolute thresholds, hardware-annotated measurements, delta-tracked findings. See Decisions.
- ~~Who owns the invalidation counter harness?~~ → Whoever breaks it, fixes it. PRs modifying instrumented views verify counters pre-merge. See Decisions.
