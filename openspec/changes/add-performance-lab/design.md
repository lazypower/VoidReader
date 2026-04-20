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

- Should `PERFORMANCE.md` thresholds be hardware-specific (M1 vs M3) or fixed? Leaning fixed with a "measured on <machine>" footnote; revisit if variance makes the numbers meaningless.
- Who owns the invalidation counter harness long-term? It's debug-only, but debug code that nobody maintains becomes debug code that nobody trusts.
- Does the lab ever get promoted to CI? `add-performance-instrumentation` Phase B handles one answer; the lab's threshold sweep might have a different CI shape. Defer until we've run three or four arcs through the lab.
