# VoidReader Development Guide

> For devops pros cosplaying as macOS developers. No judgment, only vibes.

## Prerequisites

### Required
```bash
# Xcode (sorry, it's the law)
# Install from App Store, then:
xcode-select --install

# XcodeGen - generates .xcodeproj from YAML (no manual project management)
brew install xcodegen

# SwiftLint - catches style issues (optional but nice)
brew install swiftlint

# SwiftFormat - auto-formats code (optional)
brew install swiftformat
```

### Verify Setup
```bash
# Should show Xcode path
xcode-select -p

# Should show version
xcodegen --version

# Should show Swift 5.9+
swift --version
```

## Project Structure

```
void_reader/
├── project.yml                 # XcodeGen config (THE source of truth for project)
├── Package.swift               # Swift Package for core logic
├── DEVELOPMENT.md              # You are here
├── CLAUDE.md                   # Instructions for Claude sessions
│
├── Sources/
│   └── VoidReaderCore/         # Core logic (Swift Package)
│       ├── Document/           # Document model, file handling
│       ├── Parser/             # Markdown parsing
│       ├── Renderer/           # AttributedString rendering
│       ├── Mermaid/            # Mermaid diagram support
│       ├── Linter/             # Markdown linter/formatter
│       └── Theme/              # Theming, syntax highlighting
│
├── App/                        # macOS App (thin shell)
│   ├── VoidReaderApp.swift     # @main entry point
│   ├── Views/                  # SwiftUI views
│   ├── Resources/              # Assets, mermaid.min.js
│   └── Info.plist
│
├── QuickLook/                  # Quick Look extension
│   └── PreviewExtension/
│
├── Tests/
│   └── VoidReaderCoreTests/
│
├── VoidReader.xcodeproj/       # GENERATED - don't edit manually
│
└── openspec/                   # Specifications (you know this part)
```

## Daily Workflow

### The Vibe Coding Loop

```
┌─────────────────────────────────────────────────────┐
│  1. Tell Claude what you want                       │
│  2. Claude writes the code                          │
│  3. Regenerate project: make project                │
│  4. Build: make build (or Cmd+B in Xcode)           │
│  5. Run: make run (or Cmd+R in Xcode)               │
│  6. Look at it, vibe check                          │
│  7. Tell Claude what to change                      │
│  8. Repeat                                          │
└─────────────────────────────────────────────────────┘
```

### Common Commands

```bash
# Regenerate Xcode project after any project.yml or file structure changes
make project
# or: xcodegen generate

# Build (without opening Xcode)
make build
# or: xcodebuild -scheme VoidReader -configuration Debug build

# Run tests
make test
# or: swift test (for package tests)

# Clean build artifacts
make clean

# Format code
make format

# Lint code
make lint

# Open in Xcode (when you must)
make xcode
# or: open VoidReader.xcodeproj
```

## When You Must Open Xcode

### One-Time Setup (do this once)
1. `make project` to generate .xcodeproj
2. `open VoidReader.xcodeproj`
3. Select the VoidReader target
4. Signing & Capabilities tab → Select your Team
5. That's it. Close Xcode if you want.

### Running the App
Option A (Xcode):
- `make xcode` → Cmd+R

Option B (CLI + Xcode):
- `make build` → `make run`

### Debugging UI Issues
Sometimes you need Xcode's view debugger:
- Cmd+R to run
- Debug → View Debugging → Capture View Hierarchy

### When Things Go Wrong
```bash
# Nuclear option - clean everything
make clean
make project
make build
```

## Architecture Notes

### Why Swift Package + App Shell?

```
┌─────────────────────────────────────────────────────┐
│  VoidReaderCore (Swift Package)                     │
│  ├── All the logic                                  │
│  ├── Testable without Xcode                         │
│  ├── Claude can work on this directly               │
│  └── swift build / swift test works                 │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  VoidReader App (Xcode Project)                     │
│  ├── Thin shell - just wires things together        │
│  ├── SwiftUI views that use Core                    │
│  ├── App lifecycle, menus, windows                  │
│  └── Code signing, entitlements                     │
└─────────────────────────────────────────────────────┘
```

### Why XcodeGen?

Without XcodeGen:
- Add a file → manually add to Xcode project
- Rename a file → Xcode freaks out
- Git conflicts in .xcodeproj → pain
- Claude adds files → you have to add them in Xcode

With XcodeGen:
- Add a file → it just works
- Rename a file → it just works
- Git conflicts → rare, easy to resolve
- Claude adds files → `make project` and done

## File Responsibilities

| File | What It Does | Who Edits It |
|------|--------------|--------------|
| `project.yml` | Xcode project config | Claude (you review) |
| `Package.swift` | SPM dependencies | Claude |
| `Sources/**/*.swift` | All the code | Claude |
| `App/**/*.swift` | SwiftUI views | Claude |
| `*.xcodeproj` | Generated project | Nobody (regenerate) |
| `Info.plist` | App metadata | Claude (rarely) |

## Troubleshooting

### "No such module 'VoidReaderCore'"
```bash
make clean && make project
# Then build again
```

### Signing Issues
1. Open Xcode
2. Target → Signing & Capabilities
3. Select your team
4. If "Automatically manage signing" is off, turn it on

### Xcode Won't Build
```bash
# Close Xcode first, then:
rm -rf ~/Library/Developer/Xcode/DerivedData/VoidReader-*
make project
make build
```

### "xcodegen: command not found"
```bash
brew install xcodegen
```

### Swift Version Mismatch
```bash
# Check what you have
swift --version

# Should be 5.9+. If not:
xcode-select -s /Applications/Xcode.app
```

## Tips for Vibe Coding with Claude

1. **Be specific about what's wrong**: "The heading is too small" > "it looks bad"

2. **Screenshot if possible**: Visual bugs are easier with screenshots

3. **Trust but verify**: Run the build after changes to catch issues early

4. **Iterate small**: Better to do 5 small changes than 1 big refactor

5. **Ask for explanations**: If I write something you don't understand, ask! You're learning macOS dev.

## Resources (When You Need Them)

- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Swift-Markdown](https://github.com/apple/swift-markdown)
- [XcodeGen Docs](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
- [Catppuccin Palette](https://github.com/catppuccin/catppuccin)
- [Mermaid.js](https://mermaid.js.org/)

---

*Remember: Xcode is just a means to an end. The goal is the app, not wrestling with tooling.*
