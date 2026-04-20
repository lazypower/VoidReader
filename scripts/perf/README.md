# Performance Lab Tooling

Developer-loop tools for the measure → hot-signature → fix → re-measure arc.
The entry point for contributors is [`PERFORMANCE.md`](../../PERFORMANCE.md) at
the repo root; the [`DEVELOPMENT.md`](../../DEVELOPMENT.md) "Profiling" section
narrates the workflow.

## Files

| File                    | Role                                                    |
|-------------------------|---------------------------------------------------------|
| `parse_trace.py`        | xctrace XML → hot-signature report (interpretation).    |
| `test_parse_trace.py`   | Unit coverage against the committed XML fixture.        |
| `run_scenario.sh`       | Named scenario capture: xctrace record + parse handoff. |
| `sweep.sh`              | Size-sweep harness for threshold-cliff findings.        |
| `findings_template.md`  | Required structure for arc findings docs.               |

## Orchestration vs interpretation — hard boundary

The lab tools are split across two languages intentionally:

- **`run_scenario.sh` / `sweep.sh`** own orchestration: invoking `xctrace`,
  resolving fixtures, managing output paths, handing off to the parser,
  wiring CI artifact uploads. They contain **zero interpretation logic**.
- **`parse_trace.py`** owns all interpretation: idle-frame filtering, main-TID
  selection, hot-signature ranking, window scoping, report formatting. It
  never invokes `xctrace`.

Rule-of-thumb for PR review: if a shell script starts parsing trace content,
reject the PR and move the logic into Python. If Python starts invoking
`xctrace`, reject and move it back to shell.

The motivation is durability. Shell awk/sed pipelines become unmaintainable
the moment the xctrace XML format shifts; Python with `xml.etree.ElementTree`
handles format drift with clear errors. Keeping the languages apart makes the
boundary enforceable by code review, not convention.

## Running a scenario

```bash
# Default fixture for the scenario
scripts/perf/run_scenario.sh search-navigate

# Custom fixture, 60-second recording window
scripts/perf/run_scenario.sh open-large --fixture path/to/doc.md --duration 60
```

Outputs land in `build/traces/<scenario>-<timestamp>.trace` + `.xml`.
`build/traces/` is fully gitignored — raw traces never land in the repo.
Retention happens via Gitea build artifacts uploaded by `.gitea/workflows/
test-perf-lab.yml` (default 90 days, extensible).

## Parsing a trace

```bash
# Single window, auto-detect main thread
scripts/perf/parse_trace.py build/traces/foo.xml --window 5s:10s

# Multiple named windows, sig5 output, top 10
scripts/perf/parse_trace.py build/traces/foo.xml \
    --window hang1=5.5s:6.1s --window hang2=19.7s:20.2s \
    --mode sig5 --top 10

# App frames anywhere in the stack (find SwiftUI body work)
scripts/perf/parse_trace.py build/traces/foo.xml \
    --window 0s:30s --mode app-anywhere
```

Tunables (idle-frame denylist, app-frame filter) are module-level constants
at the top of `parse_trace.py`. Edit in-file and commit — they're small
enough to maintain by hand, and catching new idle/app patterns as they
surface is preferable to an external config file.

## Unit coverage

```bash
python3 -m unittest scripts.perf.test_parse_trace -v
```

Tests run against `Tests/VoidReaderCoreTests/Fixtures/traces/
search_navigate_fixture.xml` — a synthetic kilobyte-scale XML that
exercises main-TID auto-detection, idle classification, and each output
mode. Deterministic; no xctrace dependency.

## JSON output (deferred)

`parse_trace.py --json` output mode is deferred until a real consumer
(CI dashboard, historical-analysis tool) exists. The moment we find
ourselves grepping the CLI output in another script, that's the signal
to add it.
