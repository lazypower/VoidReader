# Large-Document Rendering — Spike Findings

**Spike date:** 2026-04-18
**Trigger:** Profiling `feat/perf-instrumentation` against `torture_100k_code.md` (3MB, one 100k-line code block) revealed an 11.23s severe hang on the main thread plus heavy JavaScriptCore heap activity.
**Outcome:** One bug fixed (CodeBlockView main-thread highlight), one structural bug exposed (markdown-naïve chunking), instrumentation work parked.
**Branch state:**
- `fix/code-highlight-main-thread` — contains the surgical fix; could ship to main on its own.
- `feat/large-doc-rendering` — this branch; integration target for the broader rendering arc. Includes the fix as starting point.
- `feat/perf-instrumentation` — parked with `wip:` commit; resume after rendering work stabilises so we can validate via fresh trace.

---

## What we now know about the system

The torture doc (`TestDocuments/torture_100k_code.md`) is a single 100,000-line Swift code block (~3MB). It is designed to exercise the rendering path. Profiling it surfaced four overlapping bugs, layered like an onion. Removing the outer layer reveals the next.

The order matters. Each bug was hidden by the one outside it:

```
B1 (Highlightr on main)
 └─ masked B2 (SwiftUI Text can't render multi-MB strings)
     └─ masked B3 (chunker cuts inside markdown structure)
         └─ masked B4 (height-cache estimates compound when blocks mis-parse)
```

We've peeled off B1 and B2 in `fix/code-highlight-main-thread`. B3 and B4 are visible now and are the targets of `feat/large-doc-rendering`.

---

## Bug ledger

### B1 — Highlightr ran synchronously on the main thread

**Status: FIXED** (`fix/code-highlight-main-thread`, `App/Views/CodeBlockView.swift`)

`Highlightr` wraps `highlight.js` running inside a JavaScriptCore `JSContext`. The previous code called `highlightr.highlight(...)` from `.onAppear` on the main thread, with no size cap. For our 1.5MB code block this meant:

- Swift `String` → `JSValue` bridge (copy)
- `highlight.js` builds a giant token tree on a JSCore VM heap (the Heap Helper Threads we saw in the trace)
- HTML output assembled → parsed back to `NSAttributedString` (another copy)
- `NSAttributedString` → `AttributedString` (another copy)

Result: ~5s/MB main-thread freeze, ~150 MB transient allocation. The trace showed three Heap Helper Threads, the libpas scavenger, and the JSC Heap Collector Thread all spiking simultaneously around the same wall-clock window as the Severe Hang on the main thread.

**Why we can't just `Task.detached`:** `JSContext` has thread affinity. A single shared `Highlightr` instance must always be called from the same thread. The fix uses a dedicated `DispatchQueue` (label `place.wabash.VoidReader.highlight`, qos `.userInitiated`) — every call funnels through that one thread.

**Stale-result guard:** if the user toggles dark mode while a highlight is in flight, the dispatched closure's result must not overwrite a newer pending one. We bump a monotonic `requestSeq` `@State` on dispatch and compare on apply; older results are dropped.

**Tradeoff accepted:** brief plain-text-to-highlighted flash on first appear. Could be softened later with a fade or short delay; not worth fixing now.

---

### B2 — SwiftUI `Text` + `ScrollView` cannot lay out multi-MB strings on the main thread

**Status: FIXED** for code blocks (`fix/code-highlight-main-thread`)

This was the structural bug hiding under B1. We confirmed it with a cheap experiment: bypassed Highlightr entirely and reproduced the beachball halfway through the document. Then truncated the displayed text to 5KB and the beachball vanished. So the size-of-string-in-`Text` is the problem, independent of highlighting.

`SwiftUI.Text` measures intrinsic content size synchronously when laid out. Inside `ScrollView(.horizontal)`, this includes measuring the widest line. Inside `LazyVStack`, the measure happens lazily — when scroll brings the giant block onscreen, layout fires synchronously on main. Multi-MB strings cannot complete in a frame.

**Fix:** above `maxHighlightableChars = 50_000`, swap the inner content from `Text` inside `ScrollView` to a new `CodeTextView: NSViewRepresentable` wrapping `NSScrollView` + `NSTextView`. TextKit handles arbitrary sizes well — its `layoutManager.ensureLayout(for:)` on the same data is dramatically faster than SwiftUI's intrinsic-size path.

**Above the threshold we lose syntax color.** Matching highlight at this scale would need a streaming/chunked highlighter (highlight a block as ranges scroll into view, applying attributes incrementally) — significant new code, deferred.

**Risks to monitor in the wild:**
- **Height bridge.** `CodeTextView` reports `layoutManager.usedRect(for:).height` back to the parent via `@Binding<CGFloat>`. If layout is incomplete when the read happens, height will be wrong → row clips or leaves gap. We force `ensureLayout` before reading and update async to avoid SwiftUI mid-render warnings, but TextKit can still update height after attached. May need to observe `NSTextStorageDelegate` if jitter shows up.
- **Scroll hijack.** `NSTextView` inside `LazyVStack` inside the document `ScrollView` — three nested scrolling surfaces. Initial spike testing didn't show issues but worth verifying with trackpad scroll over the giant block.
- **Color scheme refresh.** `NSColor.textColor` is dynamic so should adjust automatically. Verify dark/light toggle still updates the rendered text.

---

### B3 — `findFirstChunkEnd` cuts inside markdown structure (THE BIG ONE)

**Status: NOT FIXED** — this is the next deep fix on `feat/large-doc-rendering`.

**Location:** `App/Views/ContentView.swift:571-590`.

```swift
private func findFirstChunkEnd(in text: String) -> Int {
    let targetSize = 20_000  // ~20KB
    let maxLines = 500

    var lineCount = 0
    var charCount = 0

    for char in text {
        charCount += 1
        if char == "\n" {
            lineCount += 1
            if charCount >= targetSize || lineCount >= maxLines {
                return charCount
            }
        }
    }

    return text.count
}
```

The function comment says "Always ends at a line boundary to avoid breaking markdown elements." This is wrong — line boundaries are not markdown boundaries. A code fence, blockquote, list, or table can span hundreds of lines. Cutting at any `\n` inside one of those is a bug.

**The cascade for `torture_100k_code.md`:**

1. Code block opens at line 5: `` ```swift ``. Function visits each char until ~500 lines.
2. Cut returns at the 500-line mark — *inside* the code block, no closing fence yet.
3. **First chunk** (lines 0-500): markdown parser sees `` ```swift `` opening, no close — most parsers tolerate this and treat it as a code block running to EOF of the chunk. Result: a complete-looking ~500-line code block. This is small enough (well under 50KB) to take the SwiftUI Text + Highlightr path. **It renders highlighted.**
4. **Second chunk** (lines 501-100006): no opening fence in scope. Parser sees ~99,500 lines of what looks like Swift code as plain text — probably as a single long paragraph or many short ones. Eventually hits the actual closing `` ``` `` at line 100006 — and *now* the parser interprets that as an *opening* fence with no close, producing yet more confusion.

**What the user sees:** two visually distinct blocks where there should be one. Top is the 500-line "complete" code block (highlighted because <50KB, takes the SwiftUI path). Bottom is the orphaned-paragraph rendering of what should have been the rest of the code (no highlight because no language attribution survived; weird styling because it's parsed as paragraphs).

**Why we never noticed before:** B1 and B2 ensured we never got past the beachball to scroll far enough to see B3's render output. The "perf" bug masked a "correctness" bug.

**Fix shape (sketch — needs design):**

The chunker needs to be markdown-structure-aware. Options ranked by complexity:

1. **Cheap heuristic:** before cutting at the line-boundary candidate, scan backwards for any unclosed structural marker (` ``` `, `>`, `- `, `* `, `1. `, `|`). If found, push the cut back to before that marker started. Risk: any markdown grammar we forget about lurks as a future bug.

2. **Use the markdown parser to find boundaries:** parse the text once at the AST level just to find safe block boundaries (top-level block transitions), then cut at the first AST-block boundary past the target size. More expensive (full parse) but always correct. May be acceptable since the parse is fast (the log showed 3.73ms for 3MB).

3. **Don't pre-chunk at all:** rely on `LazyVStack` virtualization for rendering. Render to blocks once, in background, as a single pass. Simpler model, but loses the "first 20KB visible immediately" UX win for huge docs (would show blank during initial parse).

Option 2 is probably the right shape: parse once, find the first safe boundary past 20KB, render the prefix sync, render the rest async. Preserves current UX, fixes the bug.

**Out-of-scope but worth flagging:** the same chunking code path runs on every `document.text` change (typing, edit). For the edit case, structural splitting matters even more — typing inside a fence shouldn't reflow the entire document.

---

### B4 — `BlockHeightCache` estimates compound when blocks mis-parse

**Status: PROBABLY-RESOLVED-BY-B3, verify after B3 lands**

**Location:** `Sources/VoidReaderCore/Renderer/BlockHeightCache.swift` — per-block-type height estimates used by `MarkdownReaderView`'s chunked rendering for `LazyVStack` virtualization.

**Symptom:** scrolling to ~75% of `torture_100k_code.md` lands in a blank screen — content is somewhere, scrollbar is somewhere else. The cumulative virtual height has drifted from real content height.

**Suspected mechanism:** when B3 produces wildly mis-categorized blocks (a 99,500-line "paragraph" that's actually code), the height-cache estimate for `.paragraph` (probably ~50pt or whatever) is off by orders of magnitude vs. actual rendered height. Multiplied across 100k+ phantom paragraphs, the virtual scroll math breaks down.

**Action:** after B3 fix, retest `torture_100k_code.md`. If blank-area issue persists, B4 is its own bug. If it doesn't, write a regression test (synthetic doc with known block sizes, assert virtual scroll math matches actual).

---

## Parked from `feat/perf-instrumentation`

Not relevant to landing the rendering fixes, but blocks the validation step.

### P1 — Two app instances spawn under `make profile`

Last `wip:` commit on `feat/perf-instrumentation`. We tried two fixes:

- Routed file path from `--open argv` to `VOID_READER_OPEN` env var (so AppKit/LaunchServices can't sniff it from argv and trigger `application:openFiles:` second-process spawn).
- Added cleanup in `handleOpenArgument` to close any docs without a `fileURL` (auto-spawned blanks).

**Neither fully worked.** Two windows still appeared, both opened the requested file, only one was attached to xctrace. The second instance starts ~7s after the first finishes rendering — that timing rules out a simultaneous spawn at launch and points at something *triggered by* the first instance's render or by the trace harness itself.

Hypotheses to investigate:
- xctrace's `--launch` behavior when given a path to the binary inside a `.app` bundle — does it launch via LaunchServices despite the explicit path?
- DocumentGroup state restoration replaying a previous open?
- Bundle ID registration causing LaunchServices to fan-out the open event?

Doesn't break recording (we get a trace), just creates noise and fragments attribution.

### P2 — Custom signposts (`place.wabash.VoidReader.*`) don't appear in os_signpost lane

Same branch. Even after switching off `"PointsOfInterest"` category (which has Apple's hardcoded subsystem allowlist), our subsystems don't show in any of:
- Points of Interest lane (rejected by allowlist — known)
- os_signpost subsystem breakdown (lists only `com.apple.*` subsystems despite `--instrument os_signpost`)

The diagnostic line at `App/Views/ContentView.swift:186` (parked on instrumentation branch) was supposed to log `Signposts.lifecycle.isEnabled` to confirm the signposters were live. **It never fired in the debug log** — but lines immediately above and below it did. Most likely cause: the binary used at trace time was stale (the `make profile: build` chain was probably skipping the rebuild despite the source change).

After resuming, first action: `make clean && make build && make profile FILE=...` and look for the diagnostic line in the debug log.

---

## Recommended sequence when resuming

1. **Smoke-test B1+B2 fix on a normal doc.** Pick something realistic (one of the existing fixture docs, or a real README from a popular repo) and confirm: small code blocks highlight cleanly, no flicker that bothers, no regression in copy/select behavior, dark/light toggle works on the NSTextView path.
2. **Tackle B3.** Probably option 2 from the sketch — parse-once-to-find-safe-boundary. Add a unit test for the chunker that feeds a synthetic doc with a code block crossing the boundary and asserts the cut lands outside the fence.
3. **Re-test the torture doc.** B3 fix should produce a single CodeBlockView with the full ~3MB content, routed to the NSTextView path (above 50KB threshold). Verify B4 resolves automatically. If not, address B4 separately.
4. **Profile again.** Resume `feat/perf-instrumentation`, fix P2 (so signposts surface), record a trace of the fixed code path. The deliverable for the instrumentation change becomes: the trace before and after, side-by-side, demonstrating the perf candidate identified and fixed.
5. **Decide branch strategy.** Either:
   - Merge `fix/code-highlight-main-thread` to main first (ship the surgical fix), then continue B3/B4 on `feat/large-doc-rendering` and merge later.
   - Or ship the whole arc together from `feat/large-doc-rendering`.

---

## Pre-fix trace baseline (for comparison after B3 lands)

Captured against `torture_100k_code.md` on 2026-04-18 from `voidreader-20260418-105713.trace`.

```
Startup memory:                  12.3 MB
After document open:             98.6 MB    (+86 MB)
After render complete:          245.3 MB    (+147 MB)
Document size:                  3,033,799 chars (~3 MB)
Memory amplification:           ~80×
Severe Hang on main thread:     11.23 s
Microhang:                      477 ms
Hang:                           729 ms
JSC Heap Helper Threads active: 3 (simultaneous spike)
```

Expected after fixes:
- Memory amplification drops sharply (no Highlightr roundtrip on the giant block — NSTextView holds attributed string once)
- Severe Hang gone
- JSC heap activity should be near-zero for code-only docs (no Mermaid, no math)
- Anything still showing is the next perf candidate

---

## Files touched this spike

**On `fix/code-highlight-main-thread` and `feat/large-doc-rendering`:**
- `App/Views/CodeBlockView.swift` — full restructure: off-main highlight, NSTextView wrapper, threshold gating

**Parked on `feat/perf-instrumentation`:**
- `App/Views/ContentView.swift` — diagnostic `Signposts.*.isEnabled` log line at 186 (remove after P2 resolves)
- `App/VoidReaderApp.swift` — `VOID_READER_OPEN` env var support alongside `--open` argv
- `Makefile` — `profile` target with xctrace headless recording, env-var path
