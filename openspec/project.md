# Project Context

## Purpose
VoidReader is a macOS markdown viewer application focused on a clean reading experience with support for Mermaid diagrams.

## Tech Stack
- Swift 5.9+
- SwiftUI
- macOS 14+ (Sonoma)
- swift-markdown (Apple's official parser)
- AttributedString for native text rendering
- WKWebView for Mermaid diagram rendering
- Bundled mermaid.min.js (no Node/NPM runtime dependency)

## Project Conventions

### Code Style
- Swift naming conventions (camelCase properties, PascalCase types)
- SwiftUI idiomatic patterns (ViewModifiers, environment values)
- Prefer composition over inheritance

### Architecture Patterns
- Document-based app architecture (DocumentGroup, FileDocument)
- MVVM where appropriate for complex views
- Separation of parsing (Markdown) from rendering (SwiftUI views)
- WebView isolation for Mermaid blocks only

### Testing Strategy
- Unit tests for markdown parsing logic
- UI tests for critical reading/editing flows
- Snapshot tests for rendered output consistency

### Git Workflow
- Feature branches off main
- Conventional commits preferred

## Domain Context
- "Reader-first" means rendered markdown is the default view, not source
- "Edit mode" is an optional toggle, not the primary experience
- Mermaid blocks are fenced code blocks with `mermaid` language identifier
- No vault/workspace model - operates on individual files

## Important Constraints
- No runtime Node.js or NPM dependencies
- Must work offline (bundled mermaid.min.js)
- macOS only for initial release
- Native rendering for text, WebView only for diagrams

## External Dependencies
- swift-markdown: https://github.com/apple/swift-markdown
- mermaid.js: bundled as static asset
