#!/usr/bin/env python3
"""Generate the performance-lab fixture matrix.

Writes files under Tests/VoidReaderCoreTests/Fixtures/ covering six canonical
document shapes, with 10KB / 100KB / 1MB size-sweep variants for the two
shapes most used in threshold-cliff hunting.

Each fixture carries a header comment naming shape, approximate size, and
the failure mode it's designed to expose.

Deterministic: the same inputs produce byte-identical fixtures across runs.
Safe to re-run — regenerates fixtures in place.
"""
from __future__ import annotations

import os
from pathlib import Path

FIXTURE_DIR = Path(__file__).resolve().parent.parent.parent / "Tests" / "VoidReaderCoreTests" / "Fixtures"

# Target sizes for size-sweep variants
SIZE_TARGETS = {
    "10KB":   10 * 1024,
    "100KB":  100 * 1024,
    "1MB":    1024 * 1024,
}


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"  {path.relative_to(FIXTURE_DIR.parent.parent)}  ({len(content):,} bytes)")


def header(shape: str, approx_size: str, why: str) -> str:
    return (
        f"<!--\n"
        f"  Shape: {shape}\n"
        f"  Approx size: {approx_size}\n"
        f"  Why: {why}\n"
        f"-->\n\n"
    )


# ---------------------------------------------------------------------------
# Shape 1: wide-line-pathology
# ---------------------------------------------------------------------------

def wide_line(target_bytes: int, line_chars: int = 1200) -> str:
    """Paragraphs made of extremely long single lines (>1000 chars)."""
    lorem = (
        "Quickly measured the render pipeline across successive reloads of the "
        "canonical manifest while chasing an attribute-graph cliff that only "
        "manifests when a single unbroken line exceeds the wrap threshold. "
    )
    # Build one long line approximately `line_chars` chars
    line = (lorem * ((line_chars // len(lorem)) + 1))[:line_chars]
    h = header(
        "wide-line-pathology",
        f"~{target_bytes//1024}KB" if target_bytes >= 1024 else f"{target_bytes}B",
        "single lines over 1000 chars exercise wrap/layout cost and highlight "
        "AttributedString paragraph-break assumptions. Tuned to surface "
        "CoreText line-fragment work.",
    )
    body = []
    size = len(h)
    i = 0
    while size < target_bytes:
        para = f"{line}\n\n"
        body.append(para)
        size += len(para)
        i += 1
    return h + "".join(body)


# ---------------------------------------------------------------------------
# Shape 2: many-small-blocks
# ---------------------------------------------------------------------------

def many_small_blocks(target_bytes: int) -> str:
    """Thousands of short paragraphs under 200 chars each."""
    h = header(
        "many-small-blocks",
        f"~{target_bytes//1024}KB" if target_bytes >= 1024 else f"{target_bytes}B",
        "many small top-level blocks surface invalidation fan-out and "
        "BlockView body-recompute churn. Good for Core Animation FPS hunts "
        "and scroll-jank diagnosis.",
    )
    templates = [
        "A short paragraph describing the current rendering batch boundary and the observed reflow behavior.",
        "Another short note that exists purely to inflate the block count past the per-frame budget.",
        "Yet another terse entry mirroring the shape of a changelog bullet without any inline styling.",
        "The fourth variant keeps text brief while preserving ASCII punctuation and a trailing period.",
    ]
    body = []
    size = len(h)
    i = 0
    while size < target_bytes:
        line = templates[i % len(templates)] + f" (#{i})\n\n"
        body.append(line)
        size += len(line)
        i += 1
    return h + "".join(body)


# ---------------------------------------------------------------------------
# Shape 3: deep-nesting
# ---------------------------------------------------------------------------

def deep_nesting(max_depth: int = 12) -> str:
    h = header(
        "deep-nesting",
        "~2KB",
        "ten-plus levels of nested lists and quotes exercise recursive block "
        "walkers and nested-style attribute merging. Tuned to surface stack "
        "depth and style-inheritance cost.",
    )
    body = []
    for depth in range(max_depth):
        indent = "  " * depth
        body.append(f"{indent}- Level {depth+1}: nested list entry referencing the depth counter.\n")
    body.append("\n")
    # Nested blockquote chain
    for depth in range(max_depth):
        prefix = "> " * (depth + 1)
        body.append(f"{prefix}Blockquote depth {depth+1}: nested citation fragment.\n")
    body.append("\n")
    # Nested list-in-quote combo
    for depth in range(max_depth // 2):
        indent = "  " * depth
        body.append(f"{indent}- Outer item {depth+1}\n")
        body.append(f"{indent}  > Quoted subtext at depth {depth+1}.\n")
        body.append(f"{indent}  - Nested bullet under quote at depth {depth+1}.\n")
    return h + "".join(body)


# ---------------------------------------------------------------------------
# Shape 4: heavy-inline-styling
# ---------------------------------------------------------------------------

def heavy_inline_styling() -> str:
    h = header(
        "heavy-inline-styling",
        "~8KB",
        "every paragraph loaded with bold/italic/code/link runs exercises "
        "inline-attribute merging and link-detection. Tuned to surface "
        "AttributedString construction cost and regex amplification.",
    )
    paras = []
    for i in range(80):
        p = (
            f"Paragraph **{i+1}** interleaves *italic* with `inline code`, "
            f"links to [example](https://example.com/{i}), **bold _nested_ italic**, "
            f"and ~~strikethrough~~ fragments. A second sentence doubles the "
            f"density with `a() + b()` and [another reference](#anchor-{i}) "
            f"so the block never has a simple unstyled run.\n\n"
        )
        paras.append(p)
    return h + "".join(paras)


# ---------------------------------------------------------------------------
# Shape 5: mixed-media
# ---------------------------------------------------------------------------

def mixed_media() -> str:
    h = header(
        "mixed-media",
        "~3KB",
        "images, mermaid diagrams, math, and tables together in realistic "
        "proportions exercise cross-renderer coordination. Tuned to surface "
        "WKWebView setup cost and cross-kind cache contention.",
    )
    parts = [
        "# Mixed Media Fixture\n\n",
        "Realistic document combining markdown, mermaid, math, and tables.\n\n",
        "## Section A — Image\n\n",
        "![Placeholder](https://example.com/image.png)\n\n",
        "Inline context paragraph about the image above.\n\n",
        "## Section B — Mermaid\n\n",
        "```mermaid\n",
        "graph TD\n",
        "    A[Start] --> B{Decision}\n",
        "    B -->|yes| C[Path 1]\n",
        "    B -->|no| D[Path 2]\n",
        "    C --> E[End]\n",
        "    D --> E\n",
        "```\n\n",
        "## Section C — Math\n\n",
        "Inline math: $E = mc^2$ embedded in a sentence.\n\n",
        "Block math:\n\n",
        "$$\n",
        "\\int_0^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}\n",
        "$$\n\n",
        "## Section D — Table\n\n",
        "| Column A | Column B | Column C |\n",
        "|----------|----------|----------|\n",
        "| value 1  | value 2  | value 3  |\n",
        "| value 4  | value 5  | value 6  |\n",
        "| value 7  | value 8  | value 9  |\n\n",
        "## Section E — Code\n\n",
        "```swift\n",
        "struct Example {\n",
        "    let name: String\n",
        "    func greet() -> String { \"Hello, \\(name)\" }\n",
        "}\n",
        "```\n\n",
        "## Section F — Another Image\n\n",
        "![Second](https://example.com/second.png)\n\n",
        "Closing paragraph to exercise the post-media continuation renderer.\n",
    ]
    return h + "".join(parts)


# ---------------------------------------------------------------------------
# Shape 6: real-world-messy
# ---------------------------------------------------------------------------

def real_world_messy() -> str:
    h = header(
        "real-world-messy",
        "~4KB",
        "paste-from-web artifacts: zero-width spaces, smart quotes, non-breaking "
        "spaces, odd whitespace, mixed line endings. Tuned to surface normalizer "
        "and whitespace-heuristic regressions.",
    )
    # Deliberate inclusion of:
    # - zero-width space (U+200B)
    # - zero-width no-break space / BOM (U+FEFF)
    # - non-breaking space (U+00A0)
    # - smart quotes (“ ” ‘ ’)
    # - em/en dashes (— –)
    # - ellipsis (…)
    # - mixed CRLF / LF
    content = (
        "# Real\u2010World Messy\n"  # hyphen minus variant U+2010
        "\n"
        "A paragraph pasted from\u200bthe web with\u200ba zero-width space\n"
        "and a non\u00a0breaking space mid-sentence.\r\n"
        "Mixed line endings live above; \u201csmart quotes\u201d bracket this\n"
        "sentence, along with \u2018single\u2019 variants and an em\u2014dash.\n"
        "\n"
        "\ufeffA second paragraph begins with a BOM artifact.\n"
        "Trailing whitespace lurks here:    \n"
        "and an ellipsis\u2026 closes the thought with an en dash \u2013 sometimes.\n"
        "\n"
        "- Bullet with\u00a0nbsp\n"
        "- Bullet with\u200bzwsp\n"
        "- Bullet with mixed  double  spaces\n"
        "\n"
        "```\n"
        "Code block with\ttabs\tembedded\tand a line ending in space    \n"
        "Second line, same block, no trailing whitespace.\n"
        "```\n"
        "\n"
        "| Col A | Col B |\n"
        "| --- | --- |\n"
        "| \u201cquoted\u201d | plain |\n"
        "| \u2013 dash | \u2014 dash |\n"
    )
    return h + content


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def main() -> int:
    print(f"writing fixtures to {FIXTURE_DIR}")

    # Base-shape files (single size)
    write(FIXTURE_DIR / "wide-line-pathology.md", wide_line(20 * 1024))
    write(FIXTURE_DIR / "many-small-blocks.md", many_small_blocks(200 * 1024))
    write(FIXTURE_DIR / "deep-nesting.md", deep_nesting())
    write(FIXTURE_DIR / "heavy-inline-styling.md", heavy_inline_styling())
    write(FIXTURE_DIR / "mixed-media.md", mixed_media())
    write(FIXTURE_DIR / "real-world-messy.md", real_world_messy())

    # Size-sweep variants for the two shapes most used in cliff hunts
    for label, size in SIZE_TARGETS.items():
        write(FIXTURE_DIR / f"wide-line-pathology-{label}.md", wide_line(size))
        write(FIXTURE_DIR / f"many-small-blocks-{label}.md", many_small_blocks(size))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
