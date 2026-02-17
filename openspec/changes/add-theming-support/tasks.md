# Tasks: Add Theming Support

## 1. Core Theme Types (VoidReaderCore)
- [x] 1.1 Create ThemePalette struct with color properties (base, text, surface, accents)
- [x] 1.2 Create AppTheme struct requiring BOTH lightPalette AND darkPalette
- [x] 1.3 Create ThemeRegistry singleton with themes array
- [x] 1.4 Implement "System" theme using NSColor semantic colors for both variants
- [x] 1.5 Implement CatppuccinLatte palette (light variant)
- [x] 1.6 Implement CatppuccinMocha palette (dark variant)
- [x] 1.7 Add AppTheme.catppuccin with Latte (light) and Mocha (dark)
- [x] 1.8 Add helper: palette(for: ColorScheme) -> ThemePalette
- [x] 1.9 Add helper: mermaidThemeVariables(for: ColorScheme) -> [String: String]

## 2. Theme Picker UI
- [x] 2.1 Add @AppStorage("selectedThemeID") defaulting to "system"
- [x] 2.2 Create ThemePreviewSwatch view (color circles showing theme accents)
- [x] 2.3 Add "Appearance" section to SettingsView with theme Picker
- [ ] 2.4 Add appearance override picker (System / Always Light / Always Dark)
- [x] 2.5 Verify "System" theme is default on first launch
- [x] 2.6 Verify theme and override selections persist across sessions

## 3. Editor Syntax Highlighting
- [x] 3.1 Create MarkdownSyntaxHighlighter using swift-markdown AST walker
- [x] 3.2 Map syntax tokens to current theme's palette colors
- [x] 3.3 Create SyntaxHighlightingEditor (NSViewRepresentable wrapping NSTextView)
- [x] 3.4 Wire up text binding and delegate for changes
- [x] 3.5 Replace TextEditor with SyntaxHighlightingEditor in ContentView
- [x] 3.6 Verify "System" theme uses NSColor.textColor etc. for syntax
- [x] 3.7 Verify Catppuccin theme uses palette colors for syntax
- [x] 3.8 Verify syntax colors update when theme or colorScheme changes

## 4. Mermaid Theme Integration
- [x] 4.1 Update mermaid-template.html to use themeVariables config
- [x] 4.2 Add {{MERMAID_THEME_VARIABLES}} placeholder to template
- [x] 4.3 Update MermaidWebView to get current theme from registry
- [x] 4.4 For "System" theme: use mermaid's "default"/"dark" built-in themes
- [x] 4.5 For Catppuccin: generate themeVariables JSON from palette
- [x] 4.6 Verify diagrams render correctly with both themes
- [x] 4.7 Verify diagrams re-render on theme or appearance change

## 5. Reader View Theme Integration
- [ ] 5.1 Update BlockRenderer to accept theme palette
- [x] 5.2 For "System" theme: continue using NSColor semantic colors
- [ ] 5.3 For Catppuccin: apply palette colors to headings, links, code, etc.
- [x] 5.4 Verify reader view respects selected theme coherently

## 6. Runtime Theme Loading
- [x] 6.1 Create ThemeLoader to read JSON theme files from disk
- [x] 6.2 Define JSON schema for theme files (id, name, light/dark palettes)
- [x] 6.3 Load themes from ~/Library/Application Support/VoidReader/Themes/
- [x] 6.4 Write example theme file on first launch
- [x] 6.5 Add "Open Themes Folder" button in Settings
- [x] 6.6 Reload user themes when themes directory changes

## 7. Testing & Verification
- [ ] 7.1 Test "System" theme is default and uses native macOS colors
- [ ] 7.2 Test Catppuccin theme applies Latte (light) / Mocha (dark) correctly
- [ ] 7.3 Test theme picker shows available themes with swatches
- [ ] 7.4 Test appearance override works (Always Light / Always Dark)
- [ ] 7.5 Test theme applies coherently: reader, editor, mermaid all match
- [ ] 7.6 Test light/dark switching updates all themed elements
- [ ] 7.7 Build and run end-to-end verification

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
- [ ] Theme validation (ensure light + dark variants present)
