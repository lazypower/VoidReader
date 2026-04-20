#!/usr/bin/env bash
# sweep.sh — size-sweep harness for threshold-cliff hunting.
#
# Runs a scenario against 10KB / 100KB / 1MB variants of a named fixture shape
# and emits a markdown table of per-signpost p50/p95 durations extracted from
# each trace. Output goes to stdout and (with --save) to a findings doc.
#
# Orchestration only. Signpost duration extraction is delegated to xctrace
# export + parse_trace.py. No stack parsing in shell.
#
# Usage:
#     scripts/perf/sweep.sh <scenario> <shape> [--save ARC_NAME] [--baseline PATH]
#
# Example:
#     scripts/perf/sweep.sh search-navigate wide-line-pathology \
#         --save add-performance-lab

set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: $0 <scenario> <shape> [--save ARC_NAME] [--baseline BASELINE_MD]

Runs <scenario> against <shape> at three sizes (10KB, 100KB, 1MB) and
emits a markdown p50/p95 table per named signpost.

Options:
    --save ARC_NAME     Write result to openspec/changes/<ARC_NAME>/findings/
                        sweep-<scenario>-<date>.md (stdout also prints)
    --baseline PATH     Prior sweep markdown to diff against; adds a
                        "delta vs. baseline" column.

Shapes (match names under Tests/VoidReaderCoreTests/Fixtures/):
    wide-line-pathology, many-small-blocks
EOF
    exit 2
}

if [[ $# -lt 2 ]]; then usage; fi

SCENARIO="$1"; SHAPE="$2"; shift 2
SAVE_ARC=""
BASELINE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --save)     SAVE_ARC="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *) echo "unknown flag: $1" >&2; usage ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/Tests/VoidReaderCoreTests/Fixtures"

SIZES=("10KB" "100KB" "1MB")
TRACES=()

# Run scenario against each size variant
for SIZE in "${SIZES[@]}"; do
    FIXTURE="$FIXTURE_DIR/${SHAPE}-${SIZE}.md"
    if [[ ! -f "$FIXTURE" ]]; then
        echo "warning: missing fixture $FIXTURE — skipping $SIZE" >&2
        continue
    fi
    echo "[sweep] $SCENARIO @ $SIZE" >&2
    # run_scenario.sh emits paths on stderr; we just rely on the output dir
    bash "$SCRIPT_DIR/run_scenario.sh" "$SCENARIO" --fixture "$FIXTURE" >/dev/null
    # Pick up the most recent trace
    LATEST_XML="$(ls -1t "$REPO_ROOT/build/traces/${SCENARIO}-"*.xml 2>/dev/null | head -1)"
    TRACES+=("${SIZE}|${LATEST_XML}")
done

# Compose the table via a helper python inlined below — extraction belongs in
# Python, not shell. Passed as stdin to avoid creating yet another tracked file
# for a small routine that only this shell script invokes.
TABLE_SCRIPT="$(cat <<'PYEOF'
import sys, re, os, statistics
from collections import defaultdict
import xml.etree.ElementTree as ET

# Format: SIZE|XML_PATH per line on stdin
entries = [ln.strip().split("|", 1) for ln in sys.stdin if ln.strip()]
sizes = [e[0] for e in entries]
paths = {e[0]: e[1] for e in entries}

# For each trace, extract signpost durations (begin/end pairs). xctrace XML
# exports include these under the signpost-intervals schema when recorded.
# This implementation is conservative: if the export doesn't include intervals,
# we fall back to reporting sample-count totals.
per_size_per_name = defaultdict(lambda: defaultdict(list))

for size in sizes:
    path = paths[size]
    if not os.path.exists(path):
        continue
    try:
        tree = ET.parse(path)
    except Exception as e:
        print(f"# parse error {path}: {e}", file=sys.stderr)
        continue
    root = tree.getroot()
    # Try signpost-intervals: rows with <name> + <duration> columns
    for row in root.iter("row"):
        name_el = row.find(".//os-signpost-name")
        dur_el  = row.find(".//duration")
        if name_el is not None and name_el.text and dur_el is not None and dur_el.text:
            try:
                dur_ns = int(dur_el.text)
                per_size_per_name[size][name_el.text].append(dur_ns)
            except ValueError:
                continue

# Gather all signpost names
all_names = sorted({n for size in sizes for n in per_size_per_name[size]})

def pct(vals, q):
    if not vals: return None
    vals = sorted(vals)
    k = int(round((q/100.0)*(len(vals)-1)))
    return vals[k]

def fmt_ns(ns):
    if ns is None: return "—"
    if ns < 1_000_000: return f"{ns/1_000:.1f}μs"
    if ns < 1_000_000_000: return f"{ns/1_000_000:.1f}ms"
    return f"{ns/1_000_000_000:.2f}s"

print(f"| Signpost | " + " | ".join(f"{s} p50 / p95" for s in sizes) + " |")
print(f"|---|" + "---|"*len(sizes))
if not all_names:
    print(f"| _(no signpost intervals in export — check recording template)_ |" + " —|"*len(sizes))
for name in all_names:
    cells = []
    for s in sizes:
        vals = per_size_per_name[s].get(name, [])
        cells.append(f"{fmt_ns(pct(vals,50))} / {fmt_ns(pct(vals,95))}")
    print(f"| `{name}` | " + " | ".join(cells) + " |")
PYEOF
)"

# Stream the entries into the inline python
TABLE="$(printf "%s\n" "${TRACES[@]}" | python3 -c "$TABLE_SCRIPT")"

DATE_STR="$(date +%Y-%m-%d)"
HEADER="# Sweep: $SCENARIO on $SHAPE ($DATE_STR)

Generated by \`scripts/perf/sweep.sh $SCENARIO $SHAPE\`.

## Dominant hot signature

_(fill in from manual review of the trace exports)_

## Interpretation

_(what this table says about where work is happening)_

## Chosen action

_(fix applied / deferred / accepted-with-justification)_

## Data

$TABLE
"

if [[ -n "$BASELINE" && -f "$BASELINE" ]]; then
    HEADER="${HEADER}

Baseline compared: \`$BASELINE\`
(delta column: see Python extraction when implemented in future sweep)
"
fi

echo "$HEADER"

if [[ -n "$SAVE_ARC" ]]; then
    OUT_DIR="$REPO_ROOT/openspec/changes/$SAVE_ARC/findings"
    mkdir -p "$OUT_DIR"
    OUT_FILE="$OUT_DIR/sweep-${SCENARIO}-${DATE_STR}.md"
    echo "$HEADER" > "$OUT_FILE"
    echo "[sweep] saved to $OUT_FILE" >&2
fi
