# Tasks: Add Markdown Linter and Formatter

## 1. Linter Engine
- [x] 1.1 Create MarkdownLinter class that walks AST
- [x] 1.2 Define LintRule protocol with check() method
- [x] 1.3 Define LintWarning struct (line, column, message, severity)
- [x] 1.4 Implement rule: consistent list markers (MD004)
- [x] 1.5 Implement rule: consistent emphasis markers (MD049)
- [x] 1.6 Implement rule: no trailing whitespace (MD009)
- [x] 1.7 Implement rule: blank lines around headings (MD022)
- [x] 1.8 Implement rule: blank lines around code blocks (MD031)
- [x] 1.9 Implement rule: no multiple blank lines (MD012)
- [x] 1.10 Implement rule: heading increment (MD001)
- [x] 1.11 Implement rule: no trailing punctuation in headings (MD026)

## 2. Formatter Engine
- [x] 2.1 Create MarkdownFormatter with text manipulation
- [x] 2.2 Normalize list markers to configured style
- [x] 2.3 Normalize emphasis markers to configured style
- [x] 2.4 Remove trailing whitespace
- [x] 2.5 Ensure blank lines around headings
- [x] 2.6 Ensure blank lines around code blocks
- [x] 2.7 Collapse multiple blank lines to one
- [x] 2.8 Align table columns
- [x] 2.9 Remove trailing punctuation from headings
- [x] 2.10 Ensure file ends with single newline

## 3. Editor Integration
- [x] 3.1 Run linter on text changes (debounced 500ms)
- [ ] 3.2 Display warnings in editor gutter (deferred - NSRulerView layout issues)
- [ ] 3.3 Show warning details on hover (needs gutter)
- [x] 3.4 Add warning count badge in status bar

## 4. Save Integration
- [x] 4.1 Hook into document save pipeline (Cmd+S)
- [x] 4.2 Run formatter before writing to disk (when enabled)
- [x] 4.3 Update editor text with formatted result
- [x] 4.4 Suppress file watcher during format-save

## 5. Configuration
- [x] 5.1 Add Formatting section to Settings
- [x] 5.2 Toggle: enable/disable format on save
- [x] 5.3 Toggle: enable/disable individual lint rules
- [x] 5.4 Choice: preferred list marker (- * +)
- [x] 5.5 Choice: preferred emphasis marker (* _)
- [x] 5.6 Store preferences in UserDefaults (@AppStorage)

## 6. Bug Fixes (during implementation)
- [x] 6.1 Fix false "document modified" on highlight (check text equality)
- [x] 6.2 Debounce expensive operations (headings, blocks) for performance
- [x] 6.3 Consolidate onChange handlers to prevent Swift type-check timeout
- [x] 6.4 Fix font size slider only updating code blocks

---

## Summary

All 8 lint rules implemented with auto-fix for 7 of them (MD001 heading increment cannot be auto-fixed - ambiguous intent).

### Files Created
- `Sources/VoidReaderCore/Linter/FormatterOptions.swift`
- `Sources/VoidReaderCore/Linter/MarkdownFormatter.swift`
- `Sources/VoidReaderCore/Linter/LintWarning.swift`
- `Sources/VoidReaderCore/Linter/LintRule.swift`
- `Sources/VoidReaderCore/Linter/MarkdownLinter.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD001HeadingIncrement.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD004ConsistentListMarkers.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD009TrailingWhitespace.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD012MultipleBlankLines.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD022BlankLinesAroundHeadings.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD026TrailingPunctuation.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD031BlankLinesAroundCodeBlocks.swift`
- `Sources/VoidReaderCore/Linter/Rules/MD049ConsistentEmphasis.swift`

### Future Work
- Gutter warnings need custom NSView container (NSRulerView conflicts with NSTextView.scrollableTextView layout)
