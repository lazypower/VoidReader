#!/usr/bin/env python3
"""
parse_signposts.py — xctrace signpost-intervals analyzer.

Consumes one or more xctrace `os-signpost-interval` XML exports and emits a
markdown p50/p95 duration table per signpost name. Single-file mode reports
one column; labeled-sweep mode reports one pair of columns per label (e.g.
10KB / 100KB / 1MB) so callers like `sweep.sh` can render threshold-cliff
tables without inlining Python.

## XML Schema (xctrace os-signpost-interval)

xctrace exports interval rows as positional columns matching a `<schema>`
block at the top of the export. The standard layout is:

    col 0: start-time  (engineering-type: start-time)
    col 1: duration    (engineering-type: duration)
    col 2: layout-qualifier
    col 3: name        (engineering-type: string)
    col 4: category
    col 5: subsystem
    col 6: identifier  (os-signpost-identifier)
    ...

Each row has one child per column in that order. String-type values are
interned: a column cell either carries `id="N" fmt="..."` with literal
text, or `ref="N"` pointing to a prior-defined value. Duration text is
a raw nanosecond integer (fmt is human-readable like "74.33 µs", ignore).

    <row>
      <start-time id="1" fmt="00:00.860">860944958</start-time>
      <duration id="2" fmt="74.33 µs">74333</duration>
      <layout-id id="3" fmt="0">0</layout-id>
      <string id="4" fmt="Register Property Providers">Register Property Providers</string>
      <category id="5" fmt="default">default</category>
      <subsystem id="6" fmt="com.apple.FileURL">com.apple.FileURL</subsystem>
      ...
    </row>

Subsystems are heavily Apple-internal (com.apple.FileURL, com.apple.CoreGraphics,
etc.). We filter to `place.wabash.VoidReader.*` so the table shows only our
own instrumented intervals. Override via `--subsystem-prefix` if you need
to surface system signposts for a specific hunt.

## Empty-export policy

Exports without interval rows (scenario emitted no signposts, template didn't
record them, or trace only captured Apple-internal signposts we filter out)
produce an empty-but-labeled table rather than a hard failure — same policy
as `run_scenario.sh`'s best-effort export.

## Capture template note

`run_scenario.sh` passes `--instrument os_signpost` on top of
`--template "Time Profiler"`. Time Profiler alone does NOT capture signposts;
the `--instrument os_signpost` flag is load-bearing. See
openspec/changes/add-performance-instrumentation/FINDINGS_p2_signpost_surfacing.md
for the full diagnosis of how this was originally missed.

Export one from an Instruments trace:
    xctrace export --input foo.trace \
        --xpath '/trace-toc/run[1]/data/table[@schema="os-signpost-interval"]' \
        --output signposts.xml

Usage:
    # Single-trace table
    parse_signposts.py signposts.xml

    # Include Apple-system signposts too
    parse_signposts.py signposts.xml --subsystem-prefix ""

    # Sweep table — repeat --labeled per size
    parse_signposts.py \
        --labeled 10KB:build/traces/search-navigate-10KB.signposts.xml \
        --labeled 100KB:build/traces/search-navigate-100KB.signposts.xml \
        --labeled 1MB:build/traces/search-navigate-1MB.signposts.xml

    # Sweep with delta-vs-baseline column
    parse_signposts.py --labeled ... --baseline prior/sweep.json
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path


# ---------------------------------------------------------------------------
# XML extraction
# ---------------------------------------------------------------------------

# Default subsystem prefix filter — suppresses Apple-internal signposts
# (com.apple.FileURL, com.apple.CoreGraphics, etc.). Override via
# `--subsystem-prefix ""` to surface all subsystems, or a custom value to
# hunt in a specific one.
DEFAULT_SUBSYSTEM_PREFIX = "place.wabash.VoidReader"


def _read_schema_columns(root: ET.Element) -> list[str]:
    """Return column mnemonics in order (e.g., ['start', 'duration', ..., 'name', 'category', 'subsystem']).

    Falls back to the documented standard layout if the schema block is
    missing or malformed — newer xctrace versions have kept this stable,
    but the fallback means a partial/truncated export still parses.
    """
    schema = root.find(".//schema[@name='os-signpost-interval']")
    if schema is not None:
        cols = []
        for col in schema.findall("col"):
            mn = col.find("mnemonic")
            cols.append(mn.text if mn is not None and mn.text else "")
        if cols:
            return cols
    # Documented standard layout — covers all columns parse_signposts cares
    # about (duration@1, name@3, subsystem@5).
    return [
        "start", "duration", "layout-qualifier", "name",
        "category", "subsystem", "identifier",
        "process", "end-process", "start-thread", "end-thread",
        "start-message", "end-message",
        "start-backtrace", "end-backtrace",
        "start-emit-location", "end-emit-location",
        "signature",
    ]


def _build_intern_map(root: ET.Element) -> tuple[dict[str, str], dict[str, str]]:
    """Walk the tree and collect id→fmt (display strings) and id→text (raw values).

    xctrace interns repeated values — a cell carries either id+value or a
    bare `ref="N"`. We need both maps because:
    - string-type columns (name, subsystem, category) want the fmt/display
    - duration column wants the raw text (nanosecond integer)
    """
    id_fmt: dict[str, str] = {}
    id_text: dict[str, str] = {}
    for elem in root.iter():
        eid = elem.get("id")
        if eid is None:
            continue
        fmt = elem.get("fmt")
        if fmt:
            id_fmt[eid] = fmt
        if elem.text:
            stripped = elem.text.strip()
            if stripped:
                id_text[eid] = stripped
    return id_fmt, id_text


def _resolve_display(elem: ET.Element, id_fmt: dict[str, str], id_text: dict[str, str]) -> str | None:
    """Prefer `fmt`, fall back to text; resolve refs through both maps."""
    if elem is None:
        return None
    ref = elem.get("ref")
    if ref is not None:
        return id_fmt.get(ref) or id_text.get(ref)
    fmt = elem.get("fmt")
    if fmt:
        return fmt
    if elem.text:
        stripped = elem.text.strip()
        return stripped or None
    return None


def _resolve_int(elem: ET.Element, id_text: dict[str, str]) -> int | None:
    """Integer from text content, resolving refs. Ignores `fmt` (it's human display)."""
    if elem is None:
        return None
    ref = elem.get("ref")
    if ref is not None:
        raw = id_text.get(ref)
    else:
        raw = elem.text.strip() if elem.text else None
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def extract_intervals(
    xml_path: str,
    subsystem_prefix: str = DEFAULT_SUBSYSTEM_PREFIX,
) -> dict[str, list[int]]:
    """Return {signpost_name: [duration_ns, ...]} for an intervals export.

    Filters to rows whose subsystem starts with `subsystem_prefix` (default:
    `place.wabash.VoidReader`). Pass `""` to include all subsystems.

    Tolerates:
    - missing file (returns {})
    - empty / root-only exports (returns {})
    - rows with missing cells or malformed values (skipped per-row)
    - schema block absent (falls back to documented standard column layout)
    """
    path = Path(xml_path)
    if not path.exists() or path.stat().st_size == 0:
        return {}

    try:
        tree = ET.parse(xml_path)
    except ET.ParseError as e:
        print(f"# parse error {xml_path}: {e}", file=sys.stderr)
        return {}

    root = tree.getroot()
    cols = _read_schema_columns(root)

    # Locate the three columns we care about. If any is missing from the
    # schema (unexpected xctrace version), bail with empty rather than mis-index.
    try:
        duration_idx = cols.index("duration")
        name_idx = cols.index("name")
        subsystem_idx = cols.index("subsystem")
    except ValueError:
        print(f"# unexpected schema in {xml_path}: cols={cols}", file=sys.stderr)
        return {}

    id_fmt, id_text = _build_intern_map(root)
    by_name: dict[str, list[int]] = defaultdict(list)

    # Rows live under <node>/<row>; iterate all rows regardless of node depth.
    for row in root.iter("row"):
        cells = list(row)
        if len(cells) <= max(duration_idx, name_idx, subsystem_idx):
            continue

        subsystem = _resolve_display(cells[subsystem_idx], id_fmt, id_text)
        if subsystem_prefix and (not subsystem or not subsystem.startswith(subsystem_prefix)):
            continue

        name = _resolve_display(cells[name_idx], id_fmt, id_text)
        duration = _resolve_int(cells[duration_idx], id_text)
        if not name or duration is None:
            continue

        by_name[name].append(duration)

    return dict(by_name)


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

def percentile(vals: list[int], q: float) -> int | None:
    """Nearest-rank percentile. Returns None for empty input."""
    if not vals:
        return None
    ordered = sorted(vals)
    k = int(round((q / 100.0) * (len(ordered) - 1)))
    return ordered[k]


def fmt_ns(ns: int | None) -> str:
    if ns is None:
        return "—"
    if ns < 1_000_000:
        return f"{ns/1_000:.1f}μs"
    if ns < 1_000_000_000:
        return f"{ns/1_000_000:.1f}ms"
    return f"{ns/1_000_000_000:.2f}s"


def fmt_delta(current: int | None, baseline: int | None) -> str:
    """Format a p50/p95 delta cell: '+12.3%' or '−4.1%' or '—'."""
    if current is None or baseline is None or baseline == 0:
        return "—"
    pct = 100.0 * (current - baseline) / baseline
    sign = "+" if pct >= 0 else "−"
    return f"{sign}{abs(pct):.1f}%"


# ---------------------------------------------------------------------------
# Output modes
# ---------------------------------------------------------------------------

def render_single(path: str, subsystem_prefix: str = DEFAULT_SUBSYSTEM_PREFIX) -> str:
    by_name = extract_intervals(path, subsystem_prefix=subsystem_prefix)
    lines = [
        "| Signpost | count | p50 | p95 |",
        "|---|---|---|---|",
    ]
    if not by_name:
        lines.append("| _(no signpost intervals in export)_ | — | — | — |")
        return "\n".join(lines)
    for name in sorted(by_name):
        vals = by_name[name]
        lines.append(
            f"| `{name}` | {len(vals)} | "
            f"{fmt_ns(percentile(vals, 50))} | {fmt_ns(percentile(vals, 95))} |"
        )
    return "\n".join(lines)


def render_sweep(labeled: list[tuple[str, str]],
                 baseline_data: dict[str, dict[str, int]] | None,
                 subsystem_prefix: str = DEFAULT_SUBSYSTEM_PREFIX) -> tuple[str, dict]:
    """Render a sweep table. Returns (markdown, machine_readable_snapshot)."""
    # label -> {name: [durations]}
    per_label: dict[str, dict[str, list[int]]] = {
        label: extract_intervals(path, subsystem_prefix=subsystem_prefix)
        for label, path in labeled
    }
    labels = [lbl for lbl, _ in labeled]

    # Union of signpost names across all labels
    all_names = sorted({
        n for data in per_label.values() for n in data
    })

    # Build snapshot for --baseline consumers: {name: {label: p50_ns}}
    snapshot: dict[str, dict[str, int]] = {}
    for name in all_names:
        snapshot[name] = {}
        for lbl in labels:
            p50 = percentile(per_label[lbl].get(name, []), 50)
            if p50 is not None:
                snapshot[name][lbl] = p50

    # Header
    header_cells = ["Signpost"]
    for lbl in labels:
        header_cells.append(f"{lbl} p50 / p95")
        if baseline_data is not None:
            header_cells.append(f"{lbl} Δp50")

    lines = [
        "| " + " | ".join(header_cells) + " |",
        "|" + "|".join(["---"] * len(header_cells)) + "|",
    ]

    if not all_names:
        empty_row = ["_(no signpost intervals in exports)_"]
        for _ in labels:
            empty_row.append("—")
            if baseline_data is not None:
                empty_row.append("—")
        lines.append("| " + " | ".join(empty_row) + " |")
        return "\n".join(lines), snapshot

    for name in all_names:
        row = [f"`{name}`"]
        for lbl in labels:
            vals = per_label[lbl].get(name, [])
            p50 = percentile(vals, 50)
            p95 = percentile(vals, 95)
            row.append(f"{fmt_ns(p50)} / {fmt_ns(p95)}")
            if baseline_data is not None:
                prior = baseline_data.get(name, {}).get(lbl)
                row.append(fmt_delta(p50, prior))
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines), snapshot


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_labeled(spec: str) -> tuple[str, str]:
    if ":" not in spec:
        raise argparse.ArgumentTypeError(
            f"--labeled expects LABEL:PATH, got {spec!r}"
        )
    label, path = spec.split(":", 1)
    if not label or not path:
        raise argparse.ArgumentTypeError(f"--labeled has empty label or path: {spec!r}")
    return label, path


def load_baseline(path: str) -> dict[str, dict[str, int]]:
    """Load a JSON snapshot previously written via --emit-snapshot."""
    data = json.loads(Path(path).read_text())
    if not isinstance(data, dict):
        raise SystemExit(f"baseline {path} is not a JSON object")
    return data


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Render markdown p50/p95 tables from xctrace signpost-intervals XML.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument(
        "xml_path",
        nargs="?",
        help="Single signposts XML (mutually exclusive with --labeled).",
    )
    p.add_argument(
        "--labeled",
        action="append",
        metavar="LABEL:PATH",
        type=parse_labeled,
        help="Sweep entry (repeat per size). Renders one column group per label.",
    )
    p.add_argument(
        "--baseline",
        metavar="PATH",
        help="JSON snapshot from a prior --emit-snapshot; adds per-label Δp50 columns.",
    )
    p.add_argument(
        "--emit-snapshot",
        metavar="PATH",
        help="Write {name: {label: p50_ns}} JSON alongside the table (sweep mode).",
    )
    p.add_argument(
        "--subsystem-prefix",
        default=DEFAULT_SUBSYSTEM_PREFIX,
        metavar="PREFIX",
        help=(
            "Filter to rows whose subsystem starts with PREFIX "
            f"(default: {DEFAULT_SUBSYSTEM_PREFIX!r}). Pass '' to include all "
            "subsystems including Apple-internal signposts."
        ),
    )
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.xml_path and args.labeled:
        print("error: pass either a positional XML path or --labeled, not both",
              file=sys.stderr)
        return 2

    if args.xml_path:
        if args.baseline or args.emit_snapshot:
            print("error: --baseline / --emit-snapshot only meaningful with --labeled",
                  file=sys.stderr)
            return 2
        print(render_single(args.xml_path, subsystem_prefix=args.subsystem_prefix))
        return 0

    if not args.labeled:
        print("error: need positional XML or at least one --labeled", file=sys.stderr)
        return 2

    baseline_data = load_baseline(args.baseline) if args.baseline else None
    table, snapshot = render_sweep(args.labeled, baseline_data,
                                   subsystem_prefix=args.subsystem_prefix)
    print(table)

    if args.emit_snapshot:
        Path(args.emit_snapshot).write_text(json.dumps(snapshot, indent=2, sort_keys=True))
        print(f"[parse_signposts] snapshot -> {args.emit_snapshot}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
