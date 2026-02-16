# Change: Add LaTeX Math Rendering

## Why
Technical documentation and AI/ML specs increasingly use mathematical notation. The habitat architecture specs use LaTeX for formulas like cluster validation metrics, distance functions, and dynamic epsilon calculations. Without math rendering, these appear as raw LaTeX markup, making specs harder to read.

## What Changes
- Bundle KaTeX.min.js and KaTeX.min.css as static resources (no NPM runtime)
- Create lightweight WKWebView component for rendering math blocks
- Detect inline math (`$...$`) and block math (`$$...$$`) during parsing
- Render equations inline within the document flow
- Support theme-appropriate styling (light/dark mode)

## Example Use Cases
```
Inline: The threshold $\epsilon = 0.08$ controls sensitivity.

Block:
$$CSI = \frac{\delta}{\sigma} \cdot \log(n + 1)$$
```

## Impact
- Affected specs: math-rendering (new)
- Affected code: Resource bundle, MathView component, markdown parser integration
- Pattern: Same architecture as Mermaid - bundled JS, WKWebView, isolated rendering
