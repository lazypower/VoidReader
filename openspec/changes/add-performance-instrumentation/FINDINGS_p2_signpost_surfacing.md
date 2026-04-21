# P2 — Custom signposts don't surface in Instruments: Findings

**Branch:** `feat/perf-instrumentation`
**Investigation date:** 2026-04-18
**Worktree:** `$WORKTREE/.claude/worktrees/agent-aca65f3f`
**Symptom:** `make profile FILE=...` produces a `.trace` file. Apple's built-in signposts render normally in Instruments. VoidReader's custom signposts (subsystems `place.wabash.VoidReader.*`) never appear — not in Points of Interest, not in the `os_signpost` lane, not in `xctrace export`.

---

## TL;DR

The revert commit's theory — that Apple's Points of Interest instrument enforces a "hardcoded subsystem allowlist" that forbids custom subsystems — **is incorrect folklore**. The real story is the exact opposite:

- `"PointsOfInterest"` is the **only category** whose signposts are always captured regardless of subsystem.
- Any other category (like the current per-domain strings `"rendering"`, `"lifecycle"`, etc.) falls under **Apple's dynamic-tracing rules**, which **require the subsystem to be explicitly enabled** — either in Instruments GUI Recording Options, or via a custom Instruments Package/trace template. `xctrace record` has no CLI flag for this.
- So after commit `b3fa25c` (the revert), every VoidReader signpost was dynamic-traced and the default `os_signpost` Recording Options only pre-enable `com.apple.neappprivacy`. Nothing of ours was allowlisted, so nothing was captured.

The earlier commit `a81042e` (all-POI category) should have worked. It didn't — but not because POI has an allowlist. It didn't because of **three confounders** that all landed on the same trace run, any of which is sufficient to mask POI emission.

Proper fix is small: **put the POI category back**, and remove the confounders that made the earlier attempt look like it failed.

---

## Evidence

### 1. Apple's actual rules for signpost surfacing

From Apple's `os/signpost.h` header (public docs, via Swift-by-Sundell, Donny Wals, WWDC 2018 session 405, WWDC 2019 session 414 and multiple developer.apple.com forum threads):

> **`OS_LOG_CATEGORY_POINTS_OF_INTEREST`** — "Events and intervals recorded in this category will be displayed by default in Instruments. This category is often used for events and intervals that are cheap to record."

> **`OS_LOG_CATEGORY_DYNAMIC_TRACING`** (and *any* custom category string) — "Events and intervals recorded in this category are **disabled by default**, and will only be recorded when dynamic tracing for the given subsystem is **explicitly enabled from Instruments**."

From the current Time Profiler template, extracted directly from a recorded trace in this repo (`build/traces/voidreader-20260418-105713.trace`, TOC XML):

```xml
<table category="PointsOfInterest" schema="os-signpost" ... />                                    <!-- captures POI category from any subsystem -->
<table category="PointsOfInterest" schema="os-signpost"
       dynamic-tracing-enabled-subsystems="&quot;com.apple.neappprivacy&quot;" />                  <!-- dynamic tracing allowlist — only neappprivacy is opted in by default -->
```

So:
- `"PointsOfInterest"` — captured from **any subsystem, including ours**. No allowlist.
- Anything else — only captured if the subsystem is in the `dynamic-tracing-enabled-subsystems` list. By default only `com.apple.neappprivacy` is there.

The revert commit misread the second table as "POI has a hardcoded allowlist." It actually describes the dynamic-tracing allowlist, which is what you *fall back to* when you avoid POI. So the revert made the surfacing problem worse, not better.

From the Apple Developer Forums (thread 769055 — "Not seeing signposts when profiling"), the accepted resolution: "To get a segment to show up in the PointsOfInterest in the profiler, you need to create it with the preset category of `.pointsOfInterest`."

### 2. Why the earlier `a81042e` (POI category) attempt appeared to fail

Three confounders were present at the time `a81042e` was tested. Any of them, alone, would produce an empty custom-signposts view.

#### Confounder A: the trace was recorded against a Release build of a different commit

The most recent three traces in `build/traces/` all have:
```xml
<process name="VoidReader" pid="..." path="/Users/chuck/Code/void_reader/build/derived/Build/Products/Release/VoidReader.app"/>
```

All three were **Release builds**, despite `make profile: build` depending on the Debug target. That's because `xcodebuild -showBuildSettings` picked up a previously written-down `build/derived/` SYMROOT (populated by `make dmg` / `make install`) instead of the standard DerivedData path. The `grep -m 1 BUILT_PRODUCTS_DIR` in the Makefile is fragile against this.

Further — the very first trace (`voidreader-20260418-105343.trace`) shows **zero environment variables** in the TOC. Whatever built that binary, it wasn't launched with `VOID_READER_DEBUG=1` or `VOID_READER_OPEN`. The Makefile at `a81042e` didn't even set env vars yet — that change landed in `f5724d1`. So the "signposts not in trace" observation that prompted the revert was made against a binary that may not have been the committed `a81042e` build at all.

#### Confounder B: the first trace's `make profile` did **not** add the `os_signpost` instrument

The `--instrument os_signpost` flag was added to the Makefile in commit `f5724d1` at **11:17**. All three traces captured before that point (10:53, 10:57, 11:10) ran under a Makefile that did *not* pass that flag, so only signposts from the baseline Time Profiler template's built-in POI table would appear.

That built-in POI table *does* capture our POI-category signposts — but only from processes that actually emit them. If the Release binary wasn't emitting them (see A), the table is empty.

#### Confounder C: the diagnostic probe that would have proved emission never fired

The diagnostic line at `ContentView.swift:186` —

```swift
DebugLog.info(.lifecycle, "Signposts.lifecycle.isEnabled=\(Signposts.lifecycle.isEnabled) rendering.isEnabled=\(Signposts.rendering.isEnabled)")
```

— was committed at `f5724d1` at 11:17. The last profile run (trace `111017`, i.e. at 11:10) was **before that commit**. The debug log for that trace (`voidreader-20260418-111017.debug.log`) has only 3 startup lines; `ContentView.onAppear` never ran at all. No document was opened because `VOID_READER_OPEN` env-var support also landed in `f5724d1` — the binary being profiled only recognized `--open` argv, and the Makefile at that time was passing via env-var. Silent no-op.

So there is **no trace in the repo** where all of:
- The probe code was compiled into the binary being profiled,
- The `os_signpost` instrument was explicitly recorded,
- The document actually opened,

held simultaneously. P2 was diagnosed against incomplete data, which is how the POI-is-a-trap folklore got committed as a fix.

### 3. Confirming the signposts are actually emitted at runtime

`swift test --filter SignpostsTests` passes 7/7, including the zero-overhead budget checks. Those tests exercise `beginInterval` / `endInterval` / `emitEvent` for every category, so we can be confident the Swift code path is valid and the `OSSignposter` instances are well-formed. The `.isEnabled` field on `OSSignposter` returns true iff Instruments is currently capturing the corresponding log handle — it's the cheapest runtime check we can do to confirm emission is live. That's what the diagnostic probe is for, and it's currently committed but has never produced output in any trace run, for the reasons in Confounder C.

---

## Root cause (single sentence)

Custom category strings (`"rendering"`, `"lifecycle"`, `"scroll"`, `"mermaid"`, `"image"`) put every signpost into Apple's dynamic-tracing path, which is disabled by default per subsystem; the `os_signpost` instrument's only subsystem allowlist under `xctrace record`'s default configuration is `com.apple.neappprivacy`; xctrace has no CLI option to add subsystems to that allowlist; therefore every custom signpost is dropped. The earlier attempt to use `"PointsOfInterest"` (which *would* have surfaced them) was judged a failure based on traces of the wrong binary configuration under an incomplete Makefile.

---

## Proposed fix

### Fix A (primary, 5 lines of code): route signposts back to the POI category

This is the revert of the revert. Every signposter uses `category: .pointsOfInterest`:

```swift
public static let rendering = OSSignposter(subsystem: renderingSubsystem,
                                            category: .pointsOfInterest)
public static let lifecycle = OSSignposter(subsystem: lifecycleSubsystem,
                                            category: .pointsOfInterest)
public static let scroll    = OSSignposter(subsystem: scrollSubsystem,
                                            category: .pointsOfInterest)
public static let mermaid   = OSSignposter(subsystem: mermaidSubsystem,
                                            category: .pointsOfInterest)
public static let image     = OSSignposter(subsystem: imageSubsystem,
                                            category: .pointsOfInterest)
```

(Note: Apple's Swift API exposes `OSLog.Category.pointsOfInterest` — passing that constant is cleaner than the magic `"PointsOfInterest"` string used in `a81042e`. Both resolve to the same underlying thing; the constant is less error-prone.)

Per-domain grouping moves to the **subsystem** identifier, which we already have distinct per domain (`place.wabash.VoidReader.rendering`, etc.). The Instruments detail panes filter by subsystem, so we keep the "find just the rendering signposts" workflow intact.

### Fix B (secondary, optional): tighten the Makefile

Three small improvements to remove the Confounders that hid Fix A last time:

1. **Force-refresh the derived path**. Always resolve APP_PATH via a freshly-built Debug build rather than trusting `-showBuildSettings`:
   ```makefile
   APP_PATH="$$(xcodebuild -scheme VoidReader -configuration Debug -derivedDataPath build/profile-dd build 2>&1 | tail -1; echo build/profile-dd/Build/Products/Debug/VoidReader.app)"
   ```
   Or simpler: add an explicit `-derivedDataPath` to the `build` and `-showBuildSettings` calls so they're guaranteed to be the same tree.

2. **Fail fast if the resolved path is a Release build**. One grep after APP_PATH is computed:
   ```makefile
   case "$$APP_PATH" in *Release*) echo "ERROR: resolved Release build; clean build/derived and retry"; exit 1 ;; esac
   ```

3. **Keep `--instrument os_signpost`** (current). Harmless with POI-category signposts (POI already surfaces without it), useful if anyone later tests a dynamic-tracing subsystem.

Both Makefile changes are small quality-of-life, not load-bearing for P2 itself; Fix A alone should cause signposts to appear.

### Fix C (optional hardening): preserve the diagnostic until a real trace validates

Keep the `DebugLog.info(.lifecycle, "Signposts.lifecycle.isEnabled=...")` line at `ContentView.swift:186` until a post-fix trace demonstrates `isEnabled=true` during recording. Remove it only after we have a recorded proof of life.

---

## What I did not do

Per the task brief I was conservative about applied changes. The only code modification I made is **Fix A in this worktree only** (see diff below). I did not modify the Makefile and did not commit, push, rebase, merge, or touch any other branch.

### Applied diff

Swapped `category:` strings to `.pointsOfInterest` in `Sources/VoidReaderCore/Utilities/Signposts.swift`. Also updated the doc comment to state the actual Apple behavior, so the folklore doesn't get re-introduced on the next debugging cycle. Left the test `subsystemIdentifiersAreStable` untouched — it still guards the subsystem strings, which are the real contract.

Unit tests still pass (`swift test --filter SignpostsTests`, 7/7).

---

## Validation procedure for Chuck

With Fix A applied (already done in this worktree) **and Fix B applied** (you'll want to do this before validating — see below for why), run:

```bash
# From repo root, on feat/perf-instrumentation
rm -rf build/derived build/profile-dd                           # purge stale Release derived data
make clean
make build                                                      # Debug build into DerivedData
# sanity-check we're about to profile a Debug binary
xcodebuild -scheme VoidReader -configuration Debug -showBuildSettings \
  | grep -m1 BUILT_PRODUCTS_DIR
# path should end in .../Products/Debug, not .../Products/Release

make profile FILE=TestDocuments/torture_100k_code.md
```

Then, in a separate shell during/after the trace:

```bash
# Verify the probe fired — confirms Signposts.lifecycle.isEnabled was true during recording
grep 'Signposts.lifecycle.isEnabled' build/traces/voidreader-*.debug.log | tail -1
# Expect: "Signposts.lifecycle.isEnabled=true rendering.isEnabled=true"
```

```bash
# Verify signposts were captured in the trace
xcrun xctrace export --input build/traces/voidreader-<stamp>.trace \
  --xpath '/trace-toc/run/data/table[@schema="os-signpost"]' \
  | grep -c 'place.wabash'
# Expect: non-zero (dozens to hundreds; scrollTick alone emits per scroll update)
```

If both checks pass, P2 is resolved. If the probe fires (`isEnabled=true`) but the xctrace grep returns 0, the POI category theory needs further investigation — likely OS-version-specific, in which case the fallback is to ship a bundled Instruments Package (`.instrdst`) with pre-declared subsystems and invoke via `--package`. That's a meaningful chunk of XML/schema work (est. half a day) and I'd not start on it until Fix A is empirically shown insufficient.

**Why I did not run the validation myself:** this requires Instruments + xctrace + user interaction (Instruments GUI may prompt for first-run permissions, and a Release binary in `build/derived/` is still present from your earlier spike). The P1 dual-spawn issue is also not in scope for me but remains and may still cause the trace to have two processes fighting for the same debug log file. Resolving P1 is orthogonal to this fix but would make the validation cleaner.

---

## Why this won't re-regress

Two guards:

1. The existing `SignpostsTests.subsystemIdentifiersAreStable` still enforces the subsystem strings. A future rename of our subsystem prefix would fail the test.
2. The updated doc comment in `Signposts.swift` now states both (a) the correct Apple behavior around POI and dynamic-tracing, and (b) a one-line reason why this was re-learned. If someone re-encounters a weird trace and is tempted to "revert to per-domain categories again," the docstring tells them what actually went wrong last time.

It is worth adding a third guard in Phase B: a test that runs inside a live `xctrace record` session and asserts the output trace contains at least one `place.wabash.VoidReader.*` signpost row. That's a CI-integration piece, not a unit test, and belongs with the Phase B rollout ramp described in `openspec/changes/add-performance-instrumentation/design.md`. Noting it here rather than adding scope to this fix.

---

## File map (absolute paths)

- **Findings report (this file):** `/Users/chuck/Code/void_reader/.claude/worktrees/agent-aca65f3f/FINDINGS_p2_signpost_surfacing.md`
- **Fixed source:** `/Users/chuck/Code/void_reader/.claude/worktrees/agent-aca65f3f/Sources/VoidReaderCore/Utilities/Signposts.swift`
- **Upstream FINDINGS with parked P2 note:** `/Users/chuck/Code/void_reader/FINDINGS_large_doc_rendering.md` (§"Parked from feat/perf-instrumentation" → P2)
- **Makefile (Fix B target):** `/Users/chuck/Code/void_reader/.claude/worktrees/agent-aca65f3f/Makefile` (profile target, not modified)
- **Probe site (Fix C):** `/Users/chuck/Code/void_reader/.claude/worktrees/agent-aca65f3f/App/Views/ContentView.swift:186`
- **Existing traces for reference:** `/Users/chuck/Code/void_reader/build/traces/` (three traces, all Release builds, incomplete for diagnosis)
- **Signpost emission call sites:**
  - `Sources/VoidReaderCore/Renderer/BlockRenderer.swift:14,16`
  - `Sources/VoidReaderCore/Utilities/ImageLoader.swift:31`
  - `App/Views/MermaidImageRenderer.swift:24`
  - `App/Views/SyntaxHighlightingEditor.swift:86`
  - `App/Views/ScrollPercentageObserver.swift:76`
  - `App/Views/ContentView.swift:174, 202, 533, 633, 900`

---

## References

- [OSSignposter — Apple Developer Documentation](https://developer.apple.com/documentation/os/ossignposter)
- [Not seeing signposts when profiling — Apple Developer Forums (thread 769055)](https://developer.apple.com/forums/thread/769055)
- [Emitting Signposts to Instruments on macOS using C++](https://www.jviotti.com/2022/02/21/emitting-signposts-to-instruments-on-macos-using-cpp.html) — describes the "add subsystem to Recording Options" workflow
- [Measuring performance with os_signpost — Donny Wals](https://www.donnywals.com/measuring-performance-with-os_signpost/)
- [Getting started with signposts — Swift by Sundell / WWDC 2018](https://www.swiftbysundell.com/wwdc2018/getting-started-with-signposts/)
- [WWDC 2018 Session 405 — Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/)
- [WWDC 2019 Session 414 — Developing a Great Profiling Experience](https://developer.apple.com/videos/play/wwdc2019/414/)
- [xctrace(1) man page](https://keith.github.io/xcode-man-pages/xctrace.1.html)
