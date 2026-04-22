#!/usr/bin/env python3
"""
parse_trace.py — xctrace XML hot-signature analyzer.

Consumes an xctrace time-profile XML export and reports per-window sample
breakdowns: idle vs. work, top leaf frames, call signatures at configurable
depth, and app-code frames anywhere in the stack.

Promoted from /tmp/parse_tp*.py scratch scripts. All tuning is via CLI flags;
idle and app substring lists are module-level constants, editable in-file.

Usage:
    # Single window, auto-detect main thread
    parse_trace.py trace.xml --window 5s:10s

    # Multiple windows, explicit TID, sig5 output
    parse_trace.py trace.xml \
        --window hang1=5.6s:6.1s --window hang2=19.7s:20.2s \
        --main-tid 9825346 --mode sig5 --top 10

Export an Instruments trace to XML:
    xctrace export --input foo.trace \
        --xpath '/trace-toc/run[1]/data/table[@schema="time-profile"]' \
        --output trace.xml
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Tunables — edit in-file. These are the substring denylists the scratch
# scripts used; they're small enough to maintain by hand and catching new
# idle/app patterns as they surface is preferable to an external config file.
# ---------------------------------------------------------------------------

IDLE_LEAF_SUBSTRINGS: list[str] = [
    "mach_msg2_trap",
    "mach_msg",
    "__CFRunLoopServiceMachPort",
    "__CFRunLoopRun",
    "CFRunLoopRunSpecific",
    "_DPSNextEvent",
    "nextEventMatchingEventMask",
    "nextEventMatchingMask",
    "NSApplication run",
    "NSApplicationMain",
    "RunCurrentEventLoopInMode",
    "ReceiveNextEventCommon",
    "BlockUntilNextEventMatchingListInModeWithFilter",
    "start_wqthread",
    "_pthread_wqthread",
]

APP_FRAME_SUBSTRINGS: list[str] = [
    "VoidReader",
    "BlockRenderer",
    "TextSearcher",
    "MarkdownReader",
    "BlockView",
    "ContentView",
    "buildHighlighted",
    "computeMatchInfo",
    "MarkdownContent",
    "CodeBlockView",
    "TableBlockView",
    "AttributedString",
]


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class Window:
    name: str
    start_ns: int
    end_ns: int


@dataclass
class WindowStats:
    total: int = 0
    idle: int = 0
    work: int = 0
    work_leaf: Counter = field(default_factory=Counter)
    work_sig3: Counter = field(default_factory=Counter)
    work_sig5: Counter = field(default_factory=Counter)
    app_anywhere: Counter = field(default_factory=Counter)


# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------

TIME_RE = re.compile(r"^(\d+(?:\.\d+)?)(ns|us|ms|s)?$")
UNIT_TO_NS = {"ns": 1, "us": 1_000, "ms": 1_000_000, "s": 1_000_000_000, None: 1}


def parse_time(s: str) -> int:
    m = TIME_RE.match(s.strip())
    if not m:
        raise argparse.ArgumentTypeError(f"bad time: {s!r}")
    value, unit = m.group(1), m.group(2)
    return int(float(value) * UNIT_TO_NS[unit])


def parse_window(spec: str) -> Window:
    """Accept 'START:END' or 'NAME=START:END'."""
    if "=" in spec:
        name, rest = spec.split("=", 1)
    else:
        name, rest = "window", spec
    if ":" not in rest:
        raise argparse.ArgumentTypeError(f"window needs START:END, got {spec!r}")
    start_s, end_s = rest.split(":", 1)
    return Window(name=name, start_ns=parse_time(start_s), end_ns=parse_time(end_s))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Analyze xctrace XML export for hot signatures in named windows.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("xml_path", help="Path to xctrace XML export")
    p.add_argument(
        "--window",
        action="append",
        type=parse_window,
        metavar="[NAME=]START:END",
        help="Analysis window; repeatable. Times accept ns/us/ms/s suffix (default ns).",
    )
    p.add_argument(
        "--main-tid",
        default="auto",
        help="Main thread id, or 'auto' to pick the thread with most samples.",
    )
    p.add_argument(
        "--mode",
        choices=("leaf", "sig3", "sig5", "app-anywhere"),
        default="leaf",
        help="Primary ranking: leaf frame, signature depth 3/5, or app frames anywhere.",
    )
    p.add_argument("--top", type=int, default=20, help="Result count limit per section.")
    return p


# ---------------------------------------------------------------------------
# Classification helpers
# ---------------------------------------------------------------------------

def is_idle_leaf(name: str) -> bool:
    return any(s in name for s in IDLE_LEAF_SUBSTRINGS)


def is_app_frame(name: str) -> bool:
    return any(s in name for s in APP_FRAME_SUBSTRINGS)


# ---------------------------------------------------------------------------
# XML streaming pass
# ---------------------------------------------------------------------------

def iter_samples(xml_path: str):
    """Yield (time_ns, tid, frames) tuples. Frames are deepest-first (leaf at [0])."""
    frame_name_by_id: dict[str, str] = {}
    thread_tid_by_id: dict[str, str] = {}

    current_row_time: int | None = None
    current_row_tid: str | None = None
    current_row_frames: list[str] = []
    inside_row = False
    inside_backtrace = False
    inside_thread = False
    pending_thread_id: str | None = None
    pending_thread_tid: str | None = None

    for event, elem in ET.iterparse(xml_path, events=("start", "end")):
        tag = elem.tag
        if event == "start":
            if tag == "row":
                inside_row = True
                current_row_time = None
                current_row_tid = None
                current_row_frames = []
            elif tag == "backtrace" and inside_row:
                inside_backtrace = True
            elif tag == "thread" and inside_row:
                inside_thread = True
                pending_thread_id = elem.get("id")
                pending_thread_tid = None
                ref = elem.get("ref")
                if ref and ref in thread_tid_by_id:
                    current_row_tid = thread_tid_by_id[ref]
        else:  # end
            if tag == "sample-time" and inside_row and current_row_time is None:
                if elem.text:
                    try:
                        current_row_time = int(elem.text)
                    except ValueError:
                        pass
            elif tag == "tid" and inside_thread:
                tid_val = elem.text.strip() if elem.text else None
                if tid_val:
                    pending_thread_tid = tid_val
                    if current_row_tid is None:
                        current_row_tid = tid_val
            elif tag == "thread" and inside_row:
                if pending_thread_id and pending_thread_tid:
                    thread_tid_by_id[pending_thread_id] = pending_thread_tid
                inside_thread = False
                pending_thread_id = None
                pending_thread_tid = None
            elif tag == "frame" and inside_backtrace:
                fid = elem.get("id")
                fref = elem.get("ref")
                fname = elem.get("name")
                if fid and fname:
                    frame_name_by_id[fid] = fname
                resolved = fname if fname else frame_name_by_id.get(fref)
                if resolved:
                    current_row_frames.append(resolved)
            elif tag == "backtrace":
                inside_backtrace = False
            elif tag == "row" and inside_row:
                inside_row = False
                if current_row_time is not None and current_row_tid is not None:
                    yield current_row_time, current_row_tid, current_row_frames
                elem.clear()


# ---------------------------------------------------------------------------
# Core analysis
# ---------------------------------------------------------------------------

def detect_main_tid(xml_path: str, windows: list[Window]) -> str:
    """Pick the thread with the most samples across all windows."""
    counts: Counter = Counter()
    for t, tid, _ in iter_samples(xml_path):
        if _in_any_window(t, windows):
            counts[tid] += 1
    if not counts:
        raise SystemExit("No samples found in any window; check --window bounds.")
    tid, n = counts.most_common(1)[0]
    print(f"[auto] main-tid={tid} ({n} samples across {len(windows)} window(s))",
          file=sys.stderr)
    return tid


def _in_any_window(t: int, windows: list[Window]) -> bool:
    return any(w.start_ns <= t <= w.end_ns for w in windows)


def analyze(xml_path: str, windows: list[Window], main_tid: str) -> dict[str, WindowStats]:
    stats = {w.name: WindowStats() for w in windows}
    for t, tid, frames in iter_samples(xml_path):
        if tid != main_tid:
            continue
        for w in windows:
            if w.start_ns <= t <= w.end_ns:
                s = stats[w.name]
                s.total += 1
                if frames:
                    leaf = frames[0]
                    if is_idle_leaf(leaf):
                        s.idle += 1
                    else:
                        s.work += 1
                        s.work_leaf[leaf] += 1
                        s.work_sig3[" <- ".join(frames[:3])] += 1
                        s.work_sig5[" <- ".join(frames[:5])] += 1
                    for f in frames:
                        if is_app_frame(f):
                            s.app_anywhere[f] += 1
                break
    return stats


# ---------------------------------------------------------------------------
# Report formatting
# ---------------------------------------------------------------------------

def print_counter(title: str, counter: Counter, denom: int, top: int) -> None:
    print(f"  {title}:")
    if not counter:
        print("    (none)")
        return
    for name, count in counter.most_common(top):
        pct = 100.0 * count / denom if denom else 0.0
        print(f"    {count:>5}  {pct:5.1f}%  {name}")


def report(stats: dict[str, WindowStats], mode: str, top: int) -> None:
    for name, s in stats.items():
        print(f"=== {name} ===  total={s.total}  idle={s.idle}  work={s.work}")
        if mode == "leaf":
            print_counter("Top WORK leaf frames", s.work_leaf, s.work, top)
        elif mode == "sig3":
            print_counter("Top WORK sig3", s.work_sig3, s.work, top)
        elif mode == "sig5":
            print_counter("Top WORK sig5", s.work_sig5, s.work, top)
        elif mode == "app-anywhere":
            print_counter("App frames anywhere in stack", s.app_anywhere, s.total, top)
        print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    windows = args.window or []
    if not windows:
        print("error: at least one --window required", file=sys.stderr)
        return 2

    main_tid = args.main_tid
    if main_tid == "auto":
        main_tid = detect_main_tid(args.xml_path, windows)

    stats = analyze(args.xml_path, windows, main_tid)
    report(stats, args.mode, args.top)
    return 0


if __name__ == "__main__":
    sys.exit(main())
