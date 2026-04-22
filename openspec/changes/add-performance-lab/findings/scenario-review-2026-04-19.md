# Scenario Review: 2026-04-19 (initial)

> First scheduled review. Sets the clock: next review is due three arcs
> from now OR 2026-07-19, whichever comes first.

## Context

This is the lab's opening scenario review, committed alongside
`add-performance-lab`. It documents which scenarios exist and why,
rather than reviewing against real-world inputs — there are none yet.
The purpose is to record the starting premise so future reviews can
judge drift.

## Inputs reviewed

- Past arcs: `refactor-large-code-block-rendering`, the arrow-key hang
  hunt (`manual-3.trace`), `feat/large-doc-rendering`.
- User-reported perf issues: none filed yet.
- Dogfooded document captures: the 81KB manifest Chuck uses for RC
  validation; a handful of repo READMEs and changelogs.
- Real-world paste-from-web pathologies: captured in the
  `real-world-messy.md` fixture (zero-width space, smart quotes, BOM,
  non-breaking space, mixed line endings).
- GitHub issue threads tagged `performance`: none yet.

## Scenarios and rationale

| Scenario          | Why it exists                                                                                  | Primary fixture                          |
|-------------------|------------------------------------------------------------------------------------------------|------------------------------------------|
| open-large        | Cold-open flow for manifest-class docs — most-frequent user-visible perf moment.               | `wide-line-pathology-100KB.md`           |
| search-navigate   | Validated by the manual-3 arc; 40→2 hang cut came from instrumenting this flow.                | `wide-line-pathology-100KB.md` or table  |
| scroll-to-bottom  | Scroll jank is the next likely smell; many-small-blocks surfaces invalidation fan-out.         | `many-small-blocks-100KB.md`             |
| edit-toggle       | Covers the syntax-highlighting transition; measures reader↔editor swap cost on midsize code.   | `midsize_250k_code.md`                   |

## Fixtures and rationale

Six canonical shapes + size-sweep variants for the two shapes most used
in cliff hunts. Total: 12 fixtures. See
`scripts/perf/generate_fixtures.py` for the generator.

- Kept: all six shapes — none dominated the matrix yet, and the matrix
  cap is ~12. If a shape becomes the "boring" one that never surfaces
  findings across three arcs, retire it then.
- Retired: none.
- Added: all six in this commit (none previously existed as named
  shapes; prior fixtures were `torture_*` files with ad-hoc shapes).

## Decisions

- **Keep the four scenarios for the first three arcs.** Lab claims they
  cover the most-common failure modes; data from the first three arcs
  will tell us.
- **Watch for a missing fifth scenario** — if a real-world perf report
  lands that doesn't fit one of the four, the next review must name it.
- **Watch `real-world-messy.md`** — it's the only fixture that isn't
  purely synthetic, and it's the most likely to be out-of-date first.
  Update opportunistically when a new pathology surfaces in user data.

## Next review trigger

- Date: **2026-07-19** (one calendar quarter).
- OR three arcs from now, whichever comes first.
- PR bodies for subsequent arcs must reference this review until a
  newer one exists.
