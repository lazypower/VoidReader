# Trace Fixtures

Small xctrace XML exports consumed by `scripts/perf/parse_trace.py` unit coverage.
Committed fixtures are kilobyte-scale so parser correctness is verifiable offline
without shipping megabytes of binary-derived trace data through git.

## `search_navigate_fixture.xml`

Synthetic fixture mirroring the shape of a real `xctrace export` for the
search-navigate arc (`manual-3.trace`). Two hang windows on main thread:

| Window | Range          | Dominant signature                                 |
|--------|----------------|----------------------------------------------------|
| hang1  | 5.5s..6.1s     | `AG::Graph::propagate_dirty` + `MarkdownChunker.findFirstChunkEnd` |
| hang2  | 19.7s..20.2s   | `computeMatchInfo` / `updateMatchInfoIfNeeded`     |

Expected behavior under `parse_trace.py`:

- `--main-tid auto` picks TID `9825346` (main) over TID `9825400` (background).
- The `mach_msg2_trap` sample at `5.9s` is classified as idle, not work.
- `--mode app-anywhere` floats `ContentView.body.getter` to the top
  (present in every work backtrace).

Synthetic rather than sliced from a real trace because xctrace symbols drift
across Xcode versions; deterministic expected output is more valuable for
regression testing than perfect fidelity to a frozen arc.
