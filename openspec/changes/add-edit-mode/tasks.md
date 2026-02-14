# Tasks: Add Split-Pane Edit Mode

## 1. Mode Toggle
- [x] 1.1 Add view mode state (reader/edit) to document view
- [x] 1.2 Create toolbar button for mode toggle
- [x] 1.3 Add keyboard shortcut for toggle (Cmd+E)
- [x] 1.4 Animate transition between modes

## 2. Split Pane Layout
- [x] 2.1 Create HSplitView with source and preview panes
- [x] 2.2 Add draggable divider
- [ ] 2.3 Remember divider position per window
- [x] 2.4 Set sensible default split (50/50)

## 3. Source Editor
- [x] 3.1 Create TextEditor for markdown source
- [x] 3.2 Use monospace font for source
- [ ] 3.3 Add line numbers (optional)
- [ ] 3.4 Implement basic syntax highlighting
- [x] 3.5 Bind to document text for saving

## 4. Live Preview
- [x] 4.1 Reuse MarkdownReaderView for preview pane
- [x] 4.2 Update preview on source changes
- [x] 4.3 Debounce updates for performance
- [x] 4.4 Handle rapid typing gracefully

## 5. Scroll Sync (Optional)
- [ ] 5.1 Track scroll position in source editor
- [ ] 5.2 Map source lines to preview positions
- [ ] 5.3 Sync preview scroll to approximate position
- [ ] 5.4 Add preference to enable/disable sync

## 6. Polish
- [x] 6.1 Focus source editor when entering edit mode
- [ ] 6.2 Restore scroll position when exiting edit mode
- [x] 6.3 Show unsaved indicator in title bar (handled by macOS DocumentGroup)

## 7. Status Bar
- [x] 7.1 Create StatusBar view component
- [x] 7.2 Calculate word count from document
- [x] 7.3 Calculate character count
- [x] 7.4 Calculate reading time (~200 wpm)
- [x] 7.5 Update stats on document change (debounced)
- [ ] 7.6 Show selection stats when text selected
- [ ] 7.7 Add status bar toggle to preferences
- [x] 7.8 Persist preference (@AppStorage)

## 8. Distraction-Free Mode
- [x] 8.1 Implement Cmd+Shift+F toggle
- [x] 8.2 Enter fullscreen on activation
- [x] 8.3 Hide toolbar, status bar, sidebar
- [x] 8.4 Center content with readable margins
- [x] 8.5 Show controls on mouse hover at top
- [x] 8.6 Exit on Escape or repeat shortcut

## 9. GFM Cheat Sheet
- [x] 9.1 Create cheat sheet content view with GFM syntax examples
- [x] 9.2 Implement key event monitoring for Option+Shift+/
- [x] 9.3 Create popover overlay anchored to window center
- [x] 9.4 Show overlay on key-down, dismiss on key-up
- [x] 9.5 Make examples selectable/copyable

## 10. Testing
- [x] 10.1 Test mode toggle preserves content
- [ ] 10.2 Test divider drag and persistence
- [x] 10.3 Test live preview updates
- [x] 10.4 Test save from edit mode
- [x] 10.5 Test cheat sheet appears/dismisses correctly
- [x] 10.6 Test cheat sheet works in both modes
- [x] 10.7 Test status bar updates correctly
- [ ] 10.8 Test status bar toggle in preferences
- [ ] 10.9 Test distraction-free mode enter/exit
- [ ] 10.10 Test hover controls in distraction-free
