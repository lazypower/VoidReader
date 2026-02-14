<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# VoidReader Project Context

## What This Is
VoidReader is a macOS SwiftUI markdown viewer app. Reader-first design with edit mode, Mermaid diagram support, and native rendering.

## Tech Stack
- Swift 5.9+, SwiftUI, macOS 14+
- swift-markdown for parsing
- AttributedString for native text rendering
- WKWebView for Mermaid diagrams only (bundled mermaid.min.js)
- XcodeGen for project management

## Project Structure
```
Sources/VoidReaderCore/    # Swift Package - all core logic
App/                       # Thin Xcode app shell - SwiftUI views
project.yml                # XcodeGen config (source of truth)
Makefile                   # Build commands
```

## Development Workflow
- User describes what they want
- Claude writes code
- `make project` to regenerate Xcode project
- `make build` or `make run` to build/run
- Iterate

## Key Commands
```bash
make project   # Regenerate .xcodeproj from project.yml
make build     # Build app
make run       # Build and run
make test      # Run tests
make clean     # Clean build artifacts
```

## Process Agreements

### Workflow
- **OpenSpec drives tracking** - tasks.md is source of truth, update as you go
- **One section at a time** - easier to reason about deltas
- **Feature branches** - branch per capability, merge to main when complete
- **Commits** - Conventional commits, commit at logical feature boundaries

### Versioning (Semver)
- `0.1.x` - incremental features
- `0.x.0` - capability milestones
- `1.0.0` - all specs complete + lived-in polish

### Testing Strategy
- **Core logic** (parser, linter, themes): TDD / tests alongside
- **SwiftUI views**: Light testing, rely on vibe checks
- **Integration**: Test after it works

### Vibe Checks
- Use judgment - pause when something visual changes significantly
- User will course-correct if too frequent or too sparse

## When Writing Code
1. Core logic goes in `Sources/VoidReaderCore/`
2. SwiftUI views go in `App/Views/`
3. After adding new files, user runs `make project`
4. Follow specs in `openspec/changes/` for requirements

## Specs Overview
See `openspec list` for current capabilities:
- document-handling: File open/save, print, Quick Look
- markdown-rendering: GFM, tables, task lists, code copy, image zoom
- mermaid-diagrams: WKWebView rendering with bundled JS
- edit-mode: Split pane, status bar, distraction-free, GFM cheat sheet
- theming: Native macOS colors (reader), Catppuccin syntax (editor)
- navigation: Find, replace, outline sidebar
- markdown-linter: Format on save, configurable rules

## User Context
The user is a devops professional, not a macOS developer. Explain Swift/SwiftUI concepts when relevant. Minimize Xcode exposure - prefer CLI workflows.