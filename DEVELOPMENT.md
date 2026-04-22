# VoidReader Development Guide

> For devops pros cosplaying as macOS developers. No judgment, only vibes.

## Prerequisites

### Required
```bash
# Xcode (sorry, it's the law)
# Install from App Store, then:
xcode-select --install

# XcodeGen - generates .xcodeproj from YAML (no manual project management)
brew install xcodegen

# SwiftLint - catches style issues (optional but nice)
brew install swiftlint

# SwiftFormat - auto-formats code (optional)
brew install swiftformat
```

### Verify Setup
```bash
# Should show Xcode path
xcode-select -p

# Should show version
xcodegen --version

# Should show Swift 5.9+
swift --version
```

## Project Structure

```
void_reader/
├── project.yml                 # XcodeGen config (THE source of truth for project)
├── Package.swift               # Swift Package for core logic
├── DEVELOPMENT.md              # You are here
├── CLAUDE.md                   # Instructions for Claude sessions
│
├── Sources/
│   └── VoidReaderCore/         # Core logic (Swift Package)
│       ├── Document/           # Document model, file handling
│       ├── Parser/             # Markdown parsing
│       ├── Renderer/           # AttributedString rendering
│       ├── Mermaid/            # Mermaid diagram support
│       ├── Linter/             # Markdown linter/formatter
│       └── Theme/              # Theming, syntax highlighting
│
├── App/                        # macOS App (thin shell)
│   ├── VoidReaderApp.swift     # @main entry point
│   ├── Views/                  # SwiftUI views
│   ├── Resources/              # Assets, mermaid.min.js
│   └── Info.plist
│
├── QuickLook/                  # Quick Look extension
│   └── PreviewExtension/
│
├── Tests/
│   └── VoidReaderCoreTests/
│
├── VoidReader.xcodeproj/       # GENERATED - don't edit manually
│
└── openspec/                   # Specifications (you know this part)
```

## Daily Workflow

### The Vibe Coding Loop

```
┌─────────────────────────────────────────────────────┐
│  1. Tell Claude what you want                       │
│  2. Claude writes the code                          │
│  3. Regenerate project: make project                │
│  4. Build: make build (or Cmd+B in Xcode)           │
│  5. Run: make run (or Cmd+R in Xcode)               │
│  6. Look at it, vibe check                          │
│  7. Tell Claude what to change                      │
│  8. Repeat                                          │
└─────────────────────────────────────────────────────┘
```

### Common Commands

```bash
# Regenerate Xcode project after any project.yml or file structure changes
make project
# or: xcodegen generate

# Build (without opening Xcode)
make build
# or: xcodebuild -scheme VoidReader -configuration Debug build

# Run tests
make test
# or: swift test (for package tests)

# Clean build artifacts
make clean

# Format code
make format

# Lint code
make lint

# Open in Xcode (when you must)
make xcode
# or: open VoidReader.xcodeproj
```

## When You Must Open Xcode

### One-Time Setup (do this once)
1. `make project` to generate .xcodeproj
2. `open VoidReader.xcodeproj`
3. Select the VoidReader target
4. Signing & Capabilities tab → Select your Team
5. That's it. Close Xcode if you want.

### Running the App
Option A (Xcode):
- `make xcode` → Cmd+R

Option B (CLI + Xcode):
- `make build` → `make run`

### Debugging UI Issues
Sometimes you need Xcode's view debugger:
- Cmd+R to run
- Debug → View Debugging → Capture View Hierarchy

### When Things Go Wrong
```bash
# Nuclear option - clean everything
make clean
make project
make build
```

## Architecture Notes

### Why Swift Package + App Shell?

```
┌─────────────────────────────────────────────────────┐
│  VoidReaderCore (Swift Package)                     │
│  ├── All the logic                                  │
│  ├── Testable without Xcode                         │
│  ├── Claude can work on this directly               │
│  └── swift build / swift test works                 │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  VoidReader App (Xcode Project)                     │
│  ├── Thin shell - just wires things together        │
│  ├── SwiftUI views that use Core                    │
│  ├── App lifecycle, menus, windows                  │
│  └── Code signing, entitlements                     │
└─────────────────────────────────────────────────────┘
```

### Why XcodeGen?

Without XcodeGen:
- Add a file → manually add to Xcode project
- Rename a file → Xcode freaks out
- Git conflicts in .xcodeproj → pain
- Claude adds files → you have to add them in Xcode

With XcodeGen:
- Add a file → it just works
- Rename a file → it just works
- Git conflicts → rare, easy to resolve
- Claude adds files → `make project` and done

## File Responsibilities

| File | What It Does | Who Edits It |
|------|--------------|--------------|
| `project.yml` | Xcode project config | Claude (you review) |
| `Package.swift` | SPM dependencies | Claude |
| `Sources/**/*.swift` | All the code | Claude |
| `App/**/*.swift` | SwiftUI views | Claude |
| `*.xcodeproj` | Generated project | Nobody (regenerate) |
| `Info.plist` | App metadata | Claude (rarely) |

## Troubleshooting

### "No such module 'VoidReaderCore'"
```bash
make clean && make project
# Then build again
```

### Signing Issues
1. Open Xcode
2. Target → Signing & Capabilities
3. Select your team
4. If "Automatically manage signing" is off, turn it on

### Xcode Won't Build
```bash
# Close Xcode first, then:
rm -rf ~/Library/Developer/Xcode/DerivedData/VoidReader-*
make project
make build
```

### "xcodegen: command not found"
```bash
brew install xcodegen
```

### Swift Version Mismatch
```bash
# Check what you have
swift --version

# Should be 5.9+. If not:
xcode-select -s /Applications/Xcode.app
```

## Tips for Vibe Coding with Claude

1. **Be specific about what's wrong**: "The heading is too small" > "it looks bad"

2. **Screenshot if possible**: Visual bugs are easier with screenshots

3. **Trust but verify**: Run the build after changes to catch issues early

4. **Iterate small**: Better to do 5 small changes than 1 big refactor

5. **Ask for explanations**: If I write something you don't understand, ask! You're learning macOS dev.

## Resources (When You Need Them)

- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Swift-Markdown](https://github.com/apple/swift-markdown)
- [XcodeGen Docs](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
- [Catppuccin Palette](https://github.com/catppuccin/catppuccin)
- [Mermaid.js](https://mermaid.js.org/)

---

## Profiling — start here

VoidReader has a dedicated **performance lab** that institutionalizes the
measure → hot-signature → fix → re-measure loop. If you're chasing a perf
regression, start with:

1. **[`PERFORMANCE.md`](PERFORMANCE.md)** — numeric thresholds per user flow.
   Absolute budgets. Arc findings update the Actual column.
2. **[`scripts/perf/README.md`](scripts/perf/README.md)** — lab tooling
   reference: parser, scenario runner, sweep harness.
3. The runbooks below — three Instruments templates not yet covered by the
   scenario scripts.

### How to run a perf arc

The full loop, once per finding:

```text
measure → hot-signature → interpret → fix → re-measure → commit
```

1. **Identify the flow** you suspect. Look it up in `PERFORMANCE.md`. If
   there's no contract yet, write one (strawman is fine; it's what
   arbitration starts from).
2. **Capture a trace.** Named scenarios cover the four blessed flows:
   ```bash
   scripts/perf/run_scenario.sh search-navigate --duration 30
   ```
   Output lands in `build/traces/<scenario>-<timestamp>.trace` + `.xml`.
   The trace directory is gitignored.
3. **Find the hot signature.** The runner pipes the export through
   `parse_trace.py` automatically, but you'll often want a second pass:
   ```bash
   python3 scripts/perf/parse_trace.py build/traces/foo.xml \
       --window hang=5s:10s --mode app-anywhere --top 15
   ```
   `sig5` is best for SwiftUI-internal work (AG::Graph, metadata lookups).
   `app-anywhere` is best for "where is my code actually running."
4. **Interpret.** Name what the signature says. Is it the four-smell
   taxonomy below?
5. **Fix or defer or accept.** Exactly one. Silent acceptance is a review
   blocker per `PERFORMANCE.md`'s arbitration rule.
6. **Re-measure.** Same scenario, confirm the hot signature receded.
   Update the Actual column in `PERFORMANCE.md` with the new number.
7. **Commit.** Write the findings doc using
   `scripts/perf/findings_template.md` under
   `openspec/changes/<arc-name>/findings/`. Three required sections:
   *Dominant hot signature*, *Interpretation*, *Chosen action*. Reviewers
   reject docs missing any of the three.

### Four design smells to name when you see them

1. **Work in body.** A SwiftUI `body` property doing allocation, parsing,
   regex work, or I/O. Each invalidation replays the work. Invalidation
   counter harness (see below) surfaces this as a churn number.
2. **Unbounded invalidation.** State at a level that triggers body
   recomputes for subtrees that never needed the change. Fix by scoping
   state or splitting the view.
3. **Threshold cliff.** Works fine at 50KB, dies at 80KB. A linear cost
   collides with a superlinear dependency. Hunt with
   `scripts/perf/sweep.sh`.
4. **Removal-mindset.** "We must be doing extra work somewhere" without a
   measurement. Reject. The lab exists so the answer to "where is the
   time going" is a signature, not a hypothesis.

### Invalidation counter harness

`InvalidationCounter` (DEBUG-gated, `App/Debug/InvalidationCounter.swift`)
tallies SwiftUI `body` recomputes for:

- `BlockView` — per-block invalidation fan-out
- `ContentView` — top-level document view
- `MarkdownReaderView` — between the two

The counter is active only in debug builds. Inspect via `DebugLog` console
output (throttled to one line per view per second), or via a scenario
script that calls `InvalidationCounter.report()` at the tail of a
measurement window.

**Ownership rule — whoever breaks it, fixes it.** A PR that modifies
`BlockView`, `ContentView`, or `MarkdownReaderView` body or their state
shape MUST verify the counters still report sensible numbers post-change.
Reviewers enforce on PRs touching instrumented views; no separate
maintainer. If the numbers are worse, the PR either explains why the
increase is load-bearing or reduces them before merge.

### Runbook: Allocations — memory growth from caches

**Template:** Allocations. **Fixture:**
`Tests/VoidReaderCoreTests/Fixtures/wide-line-pathology-1MB.md`.

1. Build Debug. Open Instruments with the Allocations template.
2. Attach to VoidReader. Take a Generation snapshot.
3. Open the 1MB fixture. Wait for firstPaint.
4. Type a search term (cmd-F) and cycle through 20 matches.
5. Take another snapshot. Repeat 5× (search-clear-search cycle).
6. Look at `MatchInfo.blockHighlighted` and `matchTexts`-adjacent
   allocations. The caches added in commit `0928a10` are currently
   unbounded; persistent growth over 5 cycles is a regression.
7. Also inspect `CodeBlockView`'s `blockHighlighted` cache on the 100K
   code fixture for the same unbounded pattern.

What to look for: growth that does not return to baseline after closing
the document. If it does return → cache is bounded by doc lifetime, fine.
If it doesn't → cache leaks or retains the closed document.

### Runbook: Leaks — actor retain cycles

**Template:** Leaks. **Targets:** `ImageLoader`, `MermaidImageRenderer`.

1. Build Debug. Open Instruments with the Leaks template.
2. Attach to VoidReader.
3. Open `Tests/VoidReaderCoreTests/Fixtures/mixed-media.md` (has both
   images and mermaid diagrams).
4. Close the document. Wait 5 seconds for deinits.
5. Open, close, repeat 10×.
6. Look for `ImageLoader` or `MermaidImageRenderer` instances that
   accumulate. Actor-based types can form retain cycles when a closure
   captures `self` across the isolation boundary — each retained actor
   instance means a past document stayed alive.

What to look for: **accumulation across cycles**, not steady state.
Cached-by-design items stay steady; leaks grow.

### Runbook: Core Animation FPS — scroll jank

**Template:** Core Animation (or Animation Hitches under Instruments 15+).
**Fixture:** `Tests/VoidReaderCoreTests/Fixtures/many-small-blocks.md` or
the 100KB sweep variant.

1. Build Debug. Open Instruments with the Core Animation template.
2. Launch VoidReader with the fixture via
   `scripts/perf/run_scenario.sh scroll-to-bottom`.
3. The scenario drives a sustained scroll from top to bottom.
4. Inspect the FPS track. Sustained 55–60 FPS is contract-met. Dips below
   45 FPS for more than 100ms are hitches worth chasing.
5. Overlay the `scrollTick` signpost lane — gaps indicate scroll
   starvation; clusters indicate runaway ticks.

What a scroll hitch looks like: a sharp trough in the FPS track
coinciding with a `BlockView` body-recompute burst in the signpost lane.
That's the "work in body" smell manifesting on the scroll path.

### Scenario relevance review — scheduled cadence

Synthetic fixtures drift from real-world inputs over time. To prevent
lab-becomes-irrelevant, scenarios are audited on a recurring cadence:

- **Cadence:** every **three arcs**, OR once per **calendar quarter**,
  whichever comes first. Missed reviews block the next arc's merge.
- **Inputs to audit:** user-reported perf issues, dogfooded document
  captures, real-world paste-from-web pathologies, GitHub issue threads
  tagged `performance`, any surprise findings from the last three arcs.
- **Outputs to produce:** a dated note under
  `openspec/changes/add-performance-lab/findings/
  scenario-review-<YYYY-MM-DD>.md` listing fixtures added, scenarios
  added, fixtures retired, and unchanged-but-still-relevant decisions.
  The note sets the clock for the next review.

PR bodies for new arcs must reference the most recent scenario review.
Stale reviews block merges — reviewers enforce.

### Findings template

All arc findings docs live under
`openspec/changes/<arc>/findings/` and follow
[`scripts/perf/findings_template.md`](scripts/perf/findings_template.md).
Three required sections: *Dominant hot signature*, *Interpretation*,
*Chosen action* (exactly one of fix / defer / accept-with-justification).

Raw tables without interpretation are insufficient. The discipline
*is* the interpretation — if you cannot name what the numbers mean,
the arc isn't done.

---

*Remember: Xcode is just a means to an end. The goal is the app, not wrestling with tooling.*
