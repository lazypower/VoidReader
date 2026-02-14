# Change: Add Mermaid Diagram Support

## Why
Mermaid diagrams are widely used in technical documentation for flowcharts, sequence diagrams, and architecture diagrams. Supporting them makes VoidReader useful for viewing technical markdown without requiring external tools.

## What Changes
- Bundle mermaid.min.js as a static resource (no NPM runtime)
- Create WKWebView component for rendering mermaid blocks
- Detect mermaid fenced code blocks during parsing
- Render diagrams inline within the document flow
- Support diagram theming (light/dark mode)

## Impact
- Affected specs: mermaid-diagrams (new)
- Affected code: Resource bundle, WebView component, markdown parser integration
