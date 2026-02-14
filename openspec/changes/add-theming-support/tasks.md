# Tasks: Add Theming Support

## 1. Editor Syntax Token System
- [ ] 1.1 Define SyntaxTheme protocol with token properties
- [ ] 1.2 Implement CatppuccinMocha syntax theme (dark)
- [ ] 1.3 Implement CatppuccinLatte syntax theme (light)
- [ ] 1.4 Create SyntaxThemeManager that switches based on colorScheme

## 2. System Appearance Detection
- [ ] 2.1 Monitor colorScheme environment value
- [ ] 2.2 Map .light → Latte, .dark → Mocha
- [ ] 2.3 Propagate theme via environment

## 3. Reader View (Native macOS Colors)
- [ ] 3.1 Use NSColor.textColor for body text
- [ ] 3.2 Use NSColor.labelColor with weight for headings
- [ ] 3.3 Use NSColor.linkColor for links
- [ ] 3.4 Use NSColor.textBackgroundColor for code blocks
- [ ] 3.5 Use NSColor.separatorColor for borders
- [ ] 3.6 Verify automatic light/dark adaptation

## 4. Editor Syntax Highlighting
- [ ] 4.1 Define syntax token categories for markdown
- [ ] 4.2 Map Catppuccin palette to syntax tokens:
  - [ ] Headings → Mauve
  - [ ] Emphasis markers → Subtext
  - [ ] Links → Blue
  - [ ] Code/backticks → Green
  - [ ] List markers → Teal
  - [ ] Blockquote markers → Lavender
- [ ] 4.3 Implement syntax highlighter using AttributedString
- [ ] 4.4 Apply highlighting in real-time during editing

## 5. Mermaid Theme Integration
- [ ] 5.1 Create theme CSS variables for mermaid
- [ ] 5.2 Pass current theme to mermaid init config
- [ ] 5.3 Re-render diagrams on theme change

## 6. UI Chrome Theming
- [ ] 6.1 Apply surface colors to toolbar/dividers
- [ ] 6.2 Apply accent colors to buttons/controls
- [ ] 6.3 Style scrollbars appropriately

## 7. Font Configuration
- [ ] 7.1 Add reader font family picker (system fonts)
- [ ] 7.2 Add reader font size slider (12-24pt range)
- [ ] 7.3 Add editor font family picker (filter to monospace)
- [ ] 7.4 Add editor font size slider (10-20pt range)
- [ ] 7.5 Add line height/spacing adjustment (1.0-2.0x)
- [ ] 7.6 Add code block font picker (monospace)
- [ ] 7.7 Implement Cmd++/Cmd+- for quick size adjust
- [ ] 7.8 Implement Cmd+0 to reset default size
- [ ] 7.9 Persist font preferences in UserDefaults

## 8. Appearance Preferences
- [ ] 8.1 Add appearance setting (System/Light/Dark)
- [ ] 8.2 Override colorScheme when not "System"
- [ ] 8.3 Persist preference

## 9. Testing
- [ ] 9.1 Test system light → Latte applied
- [ ] 9.2 Test system dark → Mocha applied
- [ ] 9.3 Test live switching between modes
- [ ] 9.4 Test all syntax highlighting colors
- [ ] 9.5 Test mermaid theme matches app theme
- [ ] 9.6 Test font changes apply immediately
- [ ] 9.7 Test Cmd++/-/0 shortcuts work
- [ ] 9.8 Test font preferences persist across restart
