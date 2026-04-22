"""Unit tests for parse_signposts.py.

Covers:
- Empty / root-only / missing exports (tolerated)
- Real xctrace os-signpost-interval schema: positional columns, interned refs,
  subsystem filtering
- Render modes: single, sweep, sweep+baseline
- Snapshot emit for future `--baseline` consumption

Synthetic XML mirrors the real xctrace schema captured from
`build/traces/open-large-*.signposts.xml` — positional columns, id/ref
interning, both VoidReader and Apple-internal rows so we exercise the
subsystem filter.
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.perf import parse_signposts as ps


# Schema block placed at the top of every synthetic export. Matches the
# column order that `parse_signposts._read_schema_columns` expects.
SCHEMA_BLOCK = """
<schema name="os-signpost-interval">
  <col><mnemonic>start</mnemonic></col>
  <col><mnemonic>duration</mnemonic></col>
  <col><mnemonic>layout-qualifier</mnemonic></col>
  <col><mnemonic>name</mnemonic></col>
  <col><mnemonic>category</mnemonic></col>
  <col><mnemonic>subsystem</mnemonic></col>
  <col><mnemonic>identifier</mnemonic></col>
</schema>
""".strip()


def _make_row(start: int, duration: int, layout_id: int,
              name: str, name_id: int | None, name_ref: int | None,
              category: str, category_id: int | None, category_ref: int | None,
              subsystem: str, subsystem_id: int | None, subsystem_ref: int | None,
              identifier_id: int, identifier_val: int) -> str:
    """Build one <row> matching xctrace's schema (seven positional cells)."""
    def cell(tag: str, value: str, fid: int | None, ref: int | None, text_only: bool = False) -> str:
        if ref is not None:
            return f'<{tag} ref="{ref}"/>'
        attrs = f' id="{fid}"' if fid is not None else ""
        if not text_only:
            attrs += f' fmt="{value}"'
        return f"<{tag}{attrs}>{value}</{tag}>"

    return "".join([
        "<row>",
        cell("start-time", str(start), None, None, text_only=False),
        cell("duration", str(duration), None, None, text_only=True),
        cell("layout-id", str(layout_id), None, None),
        cell("string", name, name_id, name_ref),
        cell("category", category, category_id, category_ref),
        cell("subsystem", subsystem, subsystem_id, subsystem_ref),
        f'<os-signpost-identifier id="{identifier_id}" fmt="ID_{identifier_val}">{identifier_val}</os-signpost-identifier>',
        "</row>",
    ])


def _write(tmpdir: Path, name: str, body: str) -> str:
    p = tmpdir / name
    p.write_text(
        f'<?xml version="1.0"?>\n<trace-query-result>\n<node>{SCHEMA_BLOCK}{body}</node>\n</trace-query-result>\n'
    )
    return str(p)


class ExtractIntervalsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="parse_signposts_test_"))

    def test_empty_file_returns_empty_dict(self):
        p = self.tmp / "empty.xml"
        p.write_text("")
        self.assertEqual(ps.extract_intervals(str(p)), {})

    def test_root_only_xml_returns_empty_dict(self):
        p = self.tmp / "rootonly.xml"
        p.write_text('<?xml version="1.0"?>\n<trace-query-result>\n</trace-query-result>\n')
        self.assertEqual(ps.extract_intervals(str(p)), {})

    def test_missing_file_returns_empty_dict(self):
        self.assertEqual(ps.extract_intervals("/nonexistent/path.xml"), {})

    def test_voidreader_signposts_surface_durations(self):
        body = "".join([
            _make_row(100, 5_000_000, 0, "parseMarkdown", 1, None,
                      "PointsOfInterest", 2, None,
                      "place.wabash.VoidReader.rendering", 3, None,
                      10, 1111),
            _make_row(200, 15_000_000, 0, "parseMarkdown", None, 1,
                      "PointsOfInterest", None, 2,
                      "place.wabash.VoidReader.rendering", None, 3,
                      11, 1112),
            _make_row(300, 2_500_000, 0, "renderBatch", 4, None,
                      "PointsOfInterest", None, 2,
                      "place.wabash.VoidReader.rendering", None, 3,
                      12, 1113),
        ])
        xml = _write(self.tmp, "vr.xml", body)
        out = ps.extract_intervals(xml)
        self.assertEqual(sorted(out.keys()), ["parseMarkdown", "renderBatch"])
        self.assertEqual(sorted(out["parseMarkdown"]), [5_000_000, 15_000_000])
        self.assertEqual(out["renderBatch"], [2_500_000])

    def test_subsystem_filter_excludes_apple_internal(self):
        body = "".join([
            _make_row(100, 5_000_000, 0, "parseMarkdown", 1, None,
                      "PointsOfInterest", 2, None,
                      "place.wabash.VoidReader.rendering", 3, None, 10, 1),
            _make_row(200, 80_000, 0, "Commit", 4, None,
                      "default", 5, None,
                      "com.apple.CoreAnimation", 6, None, 11, 2),
        ])
        xml = _write(self.tmp, "mixed.xml", body)

        default_filter = ps.extract_intervals(xml)
        self.assertEqual(list(default_filter.keys()), ["parseMarkdown"])

        no_filter = ps.extract_intervals(xml, subsystem_prefix="")
        self.assertEqual(sorted(no_filter.keys()), ["Commit", "parseMarkdown"])

        apple_only = ps.extract_intervals(xml, subsystem_prefix="com.apple")
        self.assertEqual(list(apple_only.keys()), ["Commit"])

    def test_interned_refs_resolve_across_rows(self):
        """A name introduced with id=N must resolve when a later row uses ref=N."""
        body = "".join([
            _make_row(1, 100, 0, "sharedName", 42, None,
                      "cat", 7, None,
                      "place.wabash.VoidReader.lifecycle", 8, None, 20, 1),
            _make_row(2, 200, 0, "sharedName", None, 42,
                      "cat", None, 7,
                      "place.wabash.VoidReader.lifecycle", None, 8, 21, 2),
        ])
        xml = _write(self.tmp, "refs.xml", body)
        out = ps.extract_intervals(xml)
        self.assertEqual(sorted(out["sharedName"]), [100, 200])

    def test_row_with_missing_cells_is_skipped_without_raising(self):
        body = "<row><start-time>1</start-time></row>"  # way too few columns
        xml = _write(self.tmp, "short.xml", body)
        self.assertEqual(ps.extract_intervals(xml), {})


class RenderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="parse_signposts_render_"))
        # Single populated trace
        body = "".join([
            _make_row(100, 5_000_000, 0, "openDocument", 1, None,
                      "PointsOfInterest", 2, None,
                      "place.wabash.VoidReader.lifecycle", 3, None, 10, 1),
            _make_row(200, 7_000_000, 0, "openDocument", None, 1,
                      "PointsOfInterest", None, 2,
                      "place.wabash.VoidReader.lifecycle", None, 3, 11, 2),
        ])
        self.populated = _write(self.tmp, "pop.xml", body)
        # Empty trace
        self.empty = self.tmp / "empty.xml"
        self.empty.write_text('<?xml version="1.0"?>\n<trace-query-result></trace-query-result>\n')

    def test_single_populated_renders_table(self):
        out = ps.render_single(self.populated)
        self.assertIn("| `openDocument` |", out)
        self.assertIn("5.0ms", out)
        self.assertIn("7.0ms", out)

    def test_single_empty_renders_placeholder_row(self):
        out = ps.render_single(str(self.empty))
        self.assertIn("no signpost intervals", out)

    def test_sweep_produces_per_label_columns(self):
        table, snapshot = ps.render_sweep(
            [("10KB", self.populated), ("100KB", str(self.empty))],
            baseline_data=None,
        )
        self.assertIn("10KB p50 / p95", table)
        self.assertIn("100KB p50 / p95", table)
        # openDocument's p50 lands in snapshot under the populated label only
        self.assertIn("openDocument", snapshot)
        self.assertEqual(snapshot["openDocument"], {"10KB": 5_000_000})

    def test_sweep_with_baseline_emits_delta_columns(self):
        baseline = {"openDocument": {"10KB": 5_000_000}}  # identical to current
        table, _ = ps.render_sweep(
            [("10KB", self.populated)],
            baseline_data=baseline,
        )
        self.assertIn("10KB Δp50", table)
        self.assertIn("+0.0%", table)  # zero delta on the populated row

    def test_baseline_delta_formats_regression_as_positive_percent(self):
        baseline = {"openDocument": {"10KB": 1_000_000}}  # prior was faster
        table, _ = ps.render_sweep(
            [("10KB", self.populated)],
            baseline_data=baseline,
        )
        # Current p50 is 5ms, baseline was 1ms — 400% regression.
        self.assertIn("+400.0%", table)


class FormattingTests(unittest.TestCase):
    def test_fmt_ns_picks_units_by_magnitude(self):
        self.assertEqual(ps.fmt_ns(500), "0.5μs")
        self.assertEqual(ps.fmt_ns(500_000), "500.0μs")
        self.assertEqual(ps.fmt_ns(5_000_000), "5.0ms")
        self.assertEqual(ps.fmt_ns(2_500_000_000), "2.50s")
        self.assertEqual(ps.fmt_ns(None), "—")

    def test_percentile_nearest_rank_handles_small_samples(self):
        # Formula: vals[round((q/100)*(N-1))]. Python 3 uses banker's rounding
        # on .5, so round(1.5)=2 — p50 of 4 values lands at index 2.
        # Documented here because the choice matters for interpreting tables.
        self.assertEqual(ps.percentile([10, 20, 30, 40], 50), 30)
        self.assertEqual(ps.percentile([10, 20, 30, 40], 95), 40)
        self.assertEqual(ps.percentile([10, 20, 30, 40, 50], 50), 30)
        self.assertEqual(ps.percentile([100], 95), 100)
        self.assertIsNone(ps.percentile([], 50))

    def test_fmt_delta_signs_and_zero_baseline(self):
        self.assertEqual(ps.fmt_delta(110, 100), "+10.0%")
        self.assertEqual(ps.fmt_delta(90, 100), "−10.0%")
        self.assertEqual(ps.fmt_delta(None, 100), "—")
        self.assertEqual(ps.fmt_delta(100, 0), "—")


if __name__ == "__main__":
    unittest.main()
