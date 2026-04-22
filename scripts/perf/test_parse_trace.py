#!/usr/bin/env python3
"""Unit coverage for parse_trace.py against the committed XML fixture.

Run:
    python3 -m unittest scripts/perf/test_parse_trace.py
"""

from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
FIXTURE = REPO_ROOT / "Tests" / "VoidReaderCoreTests" / "Fixtures" / "traces" / "search_navigate_fixture.xml"

sys.path.insert(0, str(SCRIPT_DIR))
import parse_trace  # noqa: E402


class ParseTraceTests(unittest.TestCase):
    def test_main_tid_autodetect_picks_busiest_thread(self):
        tid = parse_trace.detect_main_tid(
            str(FIXTURE),
            [parse_trace.Window("all", 0, 30_000_000_000)],
        )
        self.assertEqual(tid, "9825346")

    def test_hang1_classifies_idle_sample_separately(self):
        stats = parse_trace.analyze(
            str(FIXTURE),
            [parse_trace.Window("hang1", 5_500_000_000, 6_100_000_000)],
            main_tid="9825346",
        )
        s = stats["hang1"]
        self.assertEqual(s.total, 10)
        self.assertEqual(s.idle, 1)  # mach_msg2_trap at 5.9s
        self.assertEqual(s.work, 9)

    def test_hang1_dominant_leaf_is_ag_graph_propagate_dirty(self):
        stats = parse_trace.analyze(
            str(FIXTURE),
            [parse_trace.Window("hang1", 5_500_000_000, 6_100_000_000)],
            main_tid="9825346",
        )
        top_leaf, count = stats["hang1"].work_leaf.most_common(1)[0]
        self.assertIn("propagate_dirty", top_leaf)
        self.assertEqual(count, 6)

    def test_hang2_dominant_leaf_is_compute_match_info(self):
        stats = parse_trace.analyze(
            str(FIXTURE),
            [parse_trace.Window("hang2", 19_700_000_000, 20_200_000_000)],
            main_tid="9825346",
        )
        top_leaf, _ = stats["hang2"].work_leaf.most_common(1)[0]
        self.assertIn("computeMatchInfo", top_leaf)

    def test_background_thread_not_attributed_to_main(self):
        stats = parse_trace.analyze(
            str(FIXTURE),
            [parse_trace.Window("all", 0, 30_000_000_000)],
            main_tid="9825346",
        )
        for leaf, _ in stats["all"].work_leaf.items():
            self.assertNotIn("background_work_loop", leaf)

    def test_app_anywhere_surfaces_contentview_body(self):
        stats = parse_trace.analyze(
            str(FIXTURE),
            [parse_trace.Window("all", 0, 30_000_000_000)],
            main_tid="9825346",
        )
        top_app, _ = stats["all"].app_anywhere.most_common(1)[0]
        self.assertIn("ContentView.body.getter", top_app)

    def test_cli_main_reproduces_finding(self):
        """End-to-end: parser runs against fixture with no source edits."""
        out = io.StringIO()
        err = io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = parse_trace.main([
                str(FIXTURE),
                "--window", "hang1=5.5s:6.1s",
                "--window", "hang2=19.7s:20.2s",
                "--mode", "leaf",
                "--top", "3",
            ])
        self.assertEqual(rc, 0)
        stdout = out.getvalue()
        self.assertIn("hang1", stdout)
        self.assertIn("hang2", stdout)
        self.assertIn("propagate_dirty", stdout)
        self.assertIn("computeMatchInfo", stdout)
        self.assertIn("main-tid=9825346", err.getvalue())

    def test_time_parsing_handles_unit_suffixes(self):
        self.assertEqual(parse_trace.parse_time("500ms"), 500_000_000)
        self.assertEqual(parse_trace.parse_time("2.5s"), 2_500_000_000)
        self.assertEqual(parse_trace.parse_time("100us"), 100_000)
        self.assertEqual(parse_trace.parse_time("1000000000"), 1_000_000_000)

    def test_window_parsing_accepts_named_and_anonymous(self):
        w1 = parse_trace.parse_window("hang=1s:2s")
        self.assertEqual((w1.name, w1.start_ns, w1.end_ns), ("hang", 1_000_000_000, 2_000_000_000))
        w2 = parse_trace.parse_window("1s:2s")
        self.assertEqual(w2.name, "window")


if __name__ == "__main__":
    unittest.main()
