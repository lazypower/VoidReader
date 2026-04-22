# Findings: <arc-name> — <scenario> on <fixture> (<YYYY-MM-DD>)

> **Required sections:** Dominant Hot Signature · Interpretation · Chosen Action.
> Raw tables without interpretation are rejected in review — the discipline
> *is* the interpretation.

## Dominant hot signature

_Top `--mode app-anywhere` or `--mode sig5` frame and its percentage of
work samples in the arc's window. Paste 1–3 lines from `parse_trace.py` output._

Example:

```
 19   95.0%  ContentView.body.getter
  7   35.0%  MarkdownReaderViewWithAnchors.computeMatchInfo(blocks:)
```

## Interpretation

_What this signature indicates about where work is happening. One or two
paragraphs. Link the signpost(s) in `PERFORMANCE.md` that the measurement
ties to. Name the design smell if one is at play (work-in-body, unbounded
invalidation, threshold cliff, removal-mindset)._

## Chosen action

_Exactly one of:_

- **Fix applied** — commit SHA: `abc1234`, brief description of change
- **Deferred** — reason + owner + condition for re-opening
- **Accepted with justification** — `PERFORMANCE.md` contract amended;
  justification:

## Baseline / delta

_Hardware target + delta vs. prior baseline. Copy the relevant row(s) from
`PERFORMANCE.md`._

| Flow | Threshold | Before | After | Δ |
|------|-----------|--------|-------|---|
|      |           |        |       |   |

## Data

_Paste the parser/sweep output. Tables and raw numbers belong here, not
in the sections above._

```
(output here)
```

## Trace artifacts

_Links to the Gitea build's `.trace` artifacts. Do not commit traces._

- Trace: <link to build artifact>
- Parsed report: <link to build artifact>
