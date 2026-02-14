# Tasks: Add Markdown Linter and Formatter

## 1. Linter Engine
- [ ] 1.1 Create MarkdownLinter class that walks AST
- [ ] 1.2 Define LintRule protocol with check() method
- [ ] 1.3 Define LintWarning struct (line, column, message, severity)
- [ ] 1.4 Implement rule: consistent list markers (MD004)
- [ ] 1.5 Implement rule: consistent emphasis markers (MD049/MD050)
- [ ] 1.6 Implement rule: no trailing whitespace (MD009)
- [ ] 1.7 Implement rule: blank lines around headings (MD022)
- [ ] 1.8 Implement rule: blank lines around code blocks (MD031)
- [ ] 1.9 Implement rule: no multiple blank lines (MD012)
- [ ] 1.10 Implement rule: heading increment (no skipping levels) (MD001)
- [ ] 1.11 Implement rule: no trailing punctuation in headings (MD026)

## 2. Formatter Engine
- [ ] 2.1 Create MarkdownFormatter that re-serializes AST
- [ ] 2.2 Normalize list markers to configured style (- or *)
- [ ] 2.3 Normalize emphasis markers to configured style (* or _)
- [ ] 2.4 Remove trailing whitespace
- [ ] 2.5 Ensure blank lines around block elements
- [ ] 2.6 Collapse multiple blank lines to one
- [ ] 2.7 Align table columns
- [ ] 2.8 Ensure file ends with single newline

## 3. Editor Integration
- [ ] 3.1 Run linter on text changes (debounced 500ms)
- [ ] 3.2 Display warnings in editor gutter (yellow/red dots)
- [ ] 3.3 Show warning details on hover
- [ ] 3.4 Underline problematic text inline (optional)
- [ ] 3.5 Add "Problems" summary in status area

## 4. Save Integration
- [ ] 4.1 Hook into document save pipeline
- [ ] 4.2 Run formatter before writing to disk
- [ ] 4.3 Update editor text with formatted result
- [ ] 4.4 Preserve cursor position after format
- [ ] 4.5 Handle autosave events same as manual save

## 5. Configuration
- [ ] 5.1 Add lint/format settings to preferences
- [ ] 5.2 Toggle: enable/disable format on save
- [ ] 5.3 Toggle: enable/disable individual lint rules
- [ ] 5.4 Choice: preferred list marker (- or *)
- [ ] 5.5 Choice: preferred emphasis marker (* or _)
- [ ] 5.6 Store preferences in UserDefaults

## 6. Testing
- [ ] 6.1 Unit test each lint rule with positive/negative cases
- [ ] 6.2 Unit test formatter output matches expected
- [ ] 6.3 Test round-trip: format → parse → format is stable
- [ ] 6.4 Test cursor preservation after format
- [ ] 6.5 Test autosave triggers formatting
