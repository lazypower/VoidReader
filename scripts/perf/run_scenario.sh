#!/usr/bin/env bash
# run_scenario.sh — orchestrates xctrace capture for a named perf scenario.
#
# Owns orchestration: xctrace invocation, fixture selection, output paths,
# handoff to parse_trace.py. Owns ZERO interpretation logic — if you're
# tempted to parse trace content here, stop and move it into parse_trace.py.
#
# Usage:
#     scripts/perf/run_scenario.sh <scenario> [--fixture PATH] [--duration SECONDS]
#
# Scenarios:
#     open-large        - document open flow on a large manifest
#     search-navigate   - open, then cycle through search matches
#     scroll-to-bottom  - open, scroll from top to bottom
#     edit-toggle       - open, toggle edit mode on/off repeatedly
#
# Output:
#     build/traces/<scenario>-<timestamp>.trace       (raw Instruments bundle)
#     build/traces/<scenario>-<timestamp>.xml         (xctrace XML export)
#     stdout: parsed hot-signature report

set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: $0 <scenario> [--fixture PATH] [--duration SECONDS]

Scenarios:
    open-large, search-navigate, scroll-to-bottom, edit-toggle

Options:
    --fixture PATH     Override default fixture for the scenario
    --duration SEC     xctrace recording duration (default 30)
EOF
    exit 2
}

if [[ $# -lt 1 ]]; then usage; fi

SCENARIO="$1"; shift
FIXTURE=""
DURATION=30

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixture)  FIXTURE="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *) echo "unknown flag: $1" >&2; usage ;;
    esac
done

# Resolve repo root (scripts/perf/ -> repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Scenario -> default fixture + parse arguments
DEFAULT_FIXTURE=""
PARSE_MODE="leaf"
PARSE_WINDOW="0s:${DURATION}s"

# Fixture mapping per openspec/changes/add-performance-lab/findings/
# scenario-review-2026-04-19.md. Canonical lab fixtures use the -100KB
# size-sweep variants where the cliff hunts have surfaced signal.
case "$SCENARIO" in
    open-large)
        DEFAULT_FIXTURE="$REPO_ROOT/Tests/VoidReaderCoreTests/Fixtures/wide-line-pathology-100KB.md"
        PARSE_MODE="app-anywhere"
        ;;
    search-navigate)
        DEFAULT_FIXTURE="$REPO_ROOT/Tests/VoidReaderCoreTests/Fixtures/wide-line-pathology-100KB.md"
        PARSE_MODE="sig5"
        ;;
    scroll-to-bottom)
        DEFAULT_FIXTURE="$REPO_ROOT/Tests/VoidReaderCoreTests/Fixtures/many-small-blocks-100KB.md"
        PARSE_MODE="leaf"
        ;;
    edit-toggle)
        DEFAULT_FIXTURE="$REPO_ROOT/Tests/VoidReaderCoreTests/Fixtures/midsize_250k_code.md"
        PARSE_MODE="app-anywhere"
        ;;
    *)
        echo "error: unknown scenario '$SCENARIO'" >&2
        echo "valid: open-large, search-navigate, scroll-to-bottom, edit-toggle" >&2
        exit 2
        ;;
esac

# Output paths — mkdir early so callers that pipe our output (e.g. CI `tee`)
# have a landing directory even if we exit before recording.
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$REPO_ROOT/build/traces"
mkdir -p "$OUTPUT_DIR"
TRACE_PATH="$OUTPUT_DIR/${SCENARIO}-${TIMESTAMP}.trace"
XML_PATH="$OUTPUT_DIR/${SCENARIO}-${TIMESTAMP}.xml"

FIXTURE="${FIXTURE:-$DEFAULT_FIXTURE}"
if [[ ! -f "$FIXTURE" ]]; then
    echo "error: fixture not found: $FIXTURE" >&2
    exit 1
fi

# Preconditions
if ! command -v xctrace >/dev/null 2>&1; then
    echo "error: xctrace not found (Xcode command line tools required)" >&2
    exit 1
fi

# Resolve the .app bundle via xcodebuild rather than assuming a path. `make
# build` doesn't pass -derivedDataPath, so products land in
# ~/Library/Developer/Xcode/DerivedData/<project>-<hash>/Build/Products/Debug/
# which varies per machine and per checkout.
APP_BUNDLE="$(
    xcodebuild -scheme VoidReader -configuration Debug -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = /{print $2; exit}'
)/VoidReader.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: VoidReader.app not found at $APP_BUNDLE" >&2
    echo "       run 'make build' first" >&2
    exit 1
fi

echo "[run_scenario] scenario=$SCENARIO" >&2
echo "[run_scenario] fixture=$FIXTURE" >&2
echo "[run_scenario] duration=${DURATION}s" >&2
echo "[run_scenario] output=$TRACE_PATH" >&2

# Kill any stale instances so xctrace attaches to a fresh process
killall VoidReader 2>/dev/null || true
sleep 1

# Record the trace. Launches the app with the fixture, profiles for DURATION
# seconds, then stops. The launched process exits when Instruments detaches.
#
# xctrace can exit non-zero while still producing a valid .trace bundle — e.g.
# the Time Profiler samples land correctly but an unrelated data stream (like
# os_log, which requires TCC access to /var/db/diagnostics) is flagged corrupt.
# CPU stack samples are what `parse_trace.py` consumes, so we tolerate xctrace's
# exit code and gate solely on whether the .trace bundle materialized.
set +e
xctrace record \
    --template "Time Profiler" \
    --output "$TRACE_PATH" \
    --time-limit "${DURATION}s" \
    --target-stdout - \
    --launch -- "$APP_BUNDLE/Contents/MacOS/VoidReader" "$FIXTURE"
xctrace_exit=$?
set -e

if [[ ! -d "$TRACE_PATH" ]]; then
    echo "error: xctrace did not produce $TRACE_PATH (exit=$xctrace_exit)" >&2
    exit 1
fi
if (( xctrace_exit != 0 )); then
    echo "[run_scenario] note: xctrace exited $xctrace_exit but trace bundle was produced — continuing" >&2
fi

# Export XML for the parser
echo "[run_scenario] exporting XML" >&2
xctrace export \
    --input "$TRACE_PATH" \
    --xpath '/trace-toc/run[1]/data/table[@schema="time-profile"]' \
    --output "$XML_PATH"

# Parse and print the hot-signature report. All interpretation lives in Python.
echo "[run_scenario] parsing hot signatures" >&2
python3 "$SCRIPT_DIR/parse_trace.py" "$XML_PATH" \
    --window "$PARSE_WINDOW" \
    --mode "$PARSE_MODE" \
    --top 15

echo "[run_scenario] done" >&2
echo "  trace: $TRACE_PATH" >&2
echo "  xml:   $XML_PATH" >&2
