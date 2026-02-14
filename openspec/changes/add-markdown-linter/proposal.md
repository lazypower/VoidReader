# Change: Add Markdown Linter and Formatter

## Why
Consistent markdown formatting improves readability and reduces noise in diffs. A built-in linter/formatter running on save keeps documents clean without requiring external tools or manual effort.

## What Changes
- Implement native markdown linter using swift-markdown AST
- Implement formatter that normalizes markdown style
- Run lint checks on document changes (debounced)
- Run formatter on save/autosave events
- Display lint warnings in editor gutter or inline
- Make rules configurable via preferences

## Impact
- Affected specs: markdown-linter (new)
- Affected code: Editor view, document save pipeline, preferences
