# Tasks: Add Theming Support

## 1. Core Theme Types (VoidReaderCore)
- [ ] 1.1 Create ThemePalette struct with color properties (base, text, surface, accents)
- [ ] 1.2 Create AppTheme struct requiring BOTH lightPalette AND darkPalette
- [ ] 1.3 Create ThemeRegistry singleton with themes array
- [ ] 1.4 Implement "System" theme using NSColor semantic colors for both variants
- [ ] 1.5 Implement CatppuccinLatte palette (light variant)
- [ ] 1.6 Implement CatppuccinMocha palette (dark variant)
- [ ] 1.7 Add AppTheme.catppuccin with Latte (light) and Mocha (dark)
- [ ] 1.8 Add helper: palette(for: ColorScheme) -> ThemePalette
- [ ] 1.9 Add helper: mermaidThemeVariables(for: ColorScheme) -> [String: String]

## 2. Theme Picker UI
- [ ] 2.1 Add @AppStorage("selectedThemeID") defaulting to "system"
- [ ] 2.2 Create ThemePreviewSwatch view (color circles showing theme accents)
- [ ] 2.3 Add "Appearance" section to SettingsView with theme Picker
- [ ] 2.4 Add appearance override picker (System / Always Light / Always Dark)
- [ ] 2.5 Verify "System" theme is default on first launch
- [ ] 2.6 Verify theme and override selections persist across sessions

## 3. Editor Syntax Highlighting
- [ ] 3.1 Create MarkdownSyntaxStorage (NSTextStorage subclass)
- [ ] 3.2 Define regex patterns for markdown syntax elements
- [ ] 3.3 Map syntax tokens to current theme's palette colors
- [ ] 3.4 Create SyntaxHighlightingEditor (NSViewRepresentable wrapping NSTextView)
- [ ] 3.5 Wire up text binding and delegate for changes
- [ ] 3.6 Replace TextEditor with SyntaxHighlightingEditor in ContentView
- [ ] 3.7 Verify "System" theme uses NSColor.textColor etc. for syntax
- [ ] 3.8 Verify Catppuccin theme uses palette colors for syntax
- [ ] 3.9 Verify syntax colors update when theme or colorScheme changes

## 4. Mermaid Theme Integration
- [ ] 4.1 Update mermaid-template.html to use themeVariables config
- [ ] 4.2 Add {{MERMAID_THEME_VARIABLES}} placeholder to template
- [ ] 4.3 Update MermaidWebView to get current theme from registry
- [ ] 4.4 For "System" theme: use mermaid's "default"/"dark" built-in themes
- [ ] 4.5 For Catppuccin: generate themeVariables JSON from palette
- [ ] 4.6 Verify diagrams render correctly with both themes
- [ ] 4.7 Verify diagrams re-render on theme or appearance change

## 5. Reader View Theme Integration
- [ ] 5.1 Update BlockRenderer to accept theme palette
- [ ] 5.2 For "System" theme: continue using NSColor semantic colors
- [ ] 5.3 For Catppuccin: apply palette colors to headings, links, code, etc.
- [ ] 5.4 Verify reader view respects selected theme coherently

## 6. Testing & Verification
- [ ] 6.1 Test "System" theme is default and uses native macOS colors
- [ ] 6.2 Test Catppuccin theme applies Latte (light) / Mocha (dark) correctly
- [ ] 6.3 Test theme picker shows available themes with swatches
- [ ] 6.4 Test appearance override works (Always Light / Always Dark)
- [ ] 6.5 Test theme applies coherently: reader, editor, mermaid all match
- [ ] 6.6 Test light/dark switching updates all themed elements
- [ ] 6.7 Build and run end-to-end verification

---

## Completed (Font Configuration)
- [x] Add reader font family picker (native macOS font panel)
- [x] Add reader font size slider (10-32pt range)
- [x] Add code font family picker (monospace)
- [x] Implement Cmd++/Cmd+- for quick size adjust
- [x] Implement Cmd+0 to reset default size
- [x] Persist font preferences in UserDefaults
- [x] Settings view with native font picker integration

## Skipped (Out of Scope for v1)
- [~] UI chrome theming - macOS semantic colors handle natively
- [~] Line height/spacing adjustment - not prioritized

## Future Work (Lower Priority)
- [ ] Theme creation guide / documentation
- [ ] User theme discovery from disk (~/Library/Application Support/VoidReader/Themes/)
- [ ] Theme validation (ensure light + dark variants present)
