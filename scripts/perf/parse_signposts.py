#!/usr/bin/env python3
"""
parse_signposts.py — xctrace signpost-intervals analyzer.

Consumes one or more xctrace `os-signpost-interval` XML exports and emits a
markdown p50/p95 duration table per signpost name. Single-file mode reports
one column; labeled-sweep mode reports one pair of columns per label (e.g.
10KB / 100KB / 1MB) so callers like `sweep.sh` can render threshold-cliff
tables without inlining Python.

Interval rows look like:

    <row>
      <sample-time fmt="...">1234567</sample-time>
      <duration fmt="...">8901234</duration>
      <os-signpost-name ...>buildHighlighted</os-signpost-name>
      ...
    </row>

Exports without interval rows (scenario emitted no signposts, or the
template didn't record them) produce an empty-but-labeled table rather
than a hard failure — same policy as `run_scenario.sh`'s best-effort
export.

Export one from an Instruments trace:
    xctrace export --input foo.trace \
        --xpath '/trace-toc/run[1]/data/table[@schema="os-signpost-interval"]' \
        --output signposts.xml

Usage:
    # Single-trace table
    parse_signposts.py signposts.xml

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

def extract_intervals(xml_path: str) -> dict[str, list[int]]:
    """Return {signpost_name: [duration_ns, ...]} for an intervals export.

    Tolerates:
    - missing file (returns {})
    - empty file (returns {})
    - rows without name or duration (skipped)
    - malformed duration values (skipped)
    """
    path = Path(xml_path)
    if not path.exists() or path.stat().st_size == 0:
        return {}

    # Streamed parse keeps memory flat for long traces.
    by_name: dict[str, list[int]] = defaultdict(list)
    name_by_id: dict[str, str] = {}

    try:
        for event, elem in ET.iterparse(xml_path, events=("end",)):
            if elem.tag != "row":
                continue

            # os-signpost-name may be inline (has text) or a ref to a prior
            # inline definition. xctrace interns repeated string values.
            name_el = elem.find(".//os-signpost-name")
            name: str | None = None
            if name_el is not None:
                nid = name_el.get("id")
                nref = name_el.get("ref")
                if name_el.text:
                    name = name_el.text.strip() or None
                    if nid and name:
                        name_by_id[nid] = name
                elif nref:
                    name = name_by_id.get(nref)

            dur_el = elem.find(".//duration")
            if name and dur_el is not None and dur_el.text:
                try:
                    by_name[name].append(int(dur_el.text))
                except ValueError:
                    pass

            elem.clear()
    except ET.ParseError as e:
        # Empty-ish exports (only a root tag) read cleanly; real parse errors
        # print to stderr so callers see them in the xctrace log.
        print(f"# parse error {xml_path}: {e}", file=sys.stderr)
        return {}

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

def render_single(path: str) -> str:
    by_name = extract_intervals(path)
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
                 baseline_data: dict[str, dict[str, int]] | None) -> tuple[str, dict]:
    """Render a sweep table. Returns (markdown, machine_readable_snapshot)."""
    # label -> {name: [durations]}
    per_label: dict[str, dict[str, list[int]]] = {
        label: extract_intervals(path) for label, path in labeled
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
        print(render_single(args.xml_path))
        return 0

    if not args.labeled:
        print("error: need positional XML or at least one --labeled", file=sys.stderr)
        return 2

    baseline_data = load_baseline(args.baseline) if args.baseline else None
    table, snapshot = render_sweep(args.labeled, baseline_data)
    print(table)

    if args.emit_snapshot:
        Path(args.emit_snapshot).write_text(json.dumps(snapshot, indent=2, sort_keys=True))
        print(f"[parse_signposts] snapshot -> {args.emit_snapshot}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
