# Tasks: Add Split-Pane Edit Mode

## 1. Mode Toggle
- [ ] 1.1 Add view mode state (reader/edit) to document view
- [ ] 1.2 Create toolbar button for mode toggle
- [ ] 1.3 Add keyboard shortcut for toggle (Cmd+E)
- [ ] 1.4 Animate transition between modes

## 2. Split Pane Layout
- [ ] 2.1 Create HSplitView with source and preview panes
- [ ] 2.2 Add draggable divider
- [ ] 2.3 Remember divider position per window
- [ ] 2.4 Set sensible default split (50/50)

## 3. Source Editor
- [ ] 3.1 Create TextEditor for markdown source
- [ ] 3.2 Use monospace font for source
- [ ] 3.3 Add line numbers (optional)
- [ ] 3.4 Implement basic syntax highlighting
- [ ] 3.5 Bind to document text for saving

## 4. Live Preview
- [ ] 4.1 Reuse MarkdownReaderView for preview pane
- [ ] 4.2 Update preview on source changes
- [ ] 4.3 Debounce updates for performance
- [ ] 4.4 Handle rapid typing gracefully

## 5. Scroll Sync (Optional)
- [ ] 5.1 Track scroll position in source editor
- [ ] 5.2 Map source lines to preview positions
- [ ] 5.3 Sync preview scroll to approximate position
- [ ] 5.4 Add preference to enable/disable sync

## 6. Polish
- [ ] 6.1 Focus source editor when entering edit mode
- [ ] 6.2 Restore scroll position when exiting edit mode
- [ ] 6.3 Show unsaved indicator in title bar

## 7. Status Bar
- [ ] 7.1 Create StatusBar view component
- [ ] 7.2 Calculate word count from document
- [ ] 7.3 Calculate character count
- [ ] 7.4 Calculate reading time (~200 wpm)
- [ ] 7.5 Update stats on document change (debounced)
- [ ] 7.6 Show selection stats when text selected
- [ ] 7.7 Add status bar toggle to preferences
- [ ] 7.8 Persist preference

## 8. Distraction-Free Mode
- [ ] 8.1 Implement Cmd+Shift+F toggle
- [ ] 8.2 Enter fullscreen on activation
- [ ] 8.3 Hide toolbar, status bar, sidebar
- [ ] 8.4 Center content with readable margins
- [ ] 8.5 Show controls on mouse hover at top
- [ ] 8.6 Exit on Escape or repeat shortcut

## 9. GFM Cheat Sheet
- [ ] 9.1 Create cheat sheet content view with GFM syntax examples
- [ ] 9.2 Implement key event monitoring for Option+Shift+/
- [ ] 9.3 Create popover overlay anchored to window center
- [ ] 9.4 Show overlay on key-down, dismiss on key-up
- [ ] 9.5 Make examples selectable/copyable

## 10. Testing
- [ ] 10.1 Test mode toggle preserves content
- [ ] 10.2 Test divider drag and persistence
- [ ] 10.3 Test live preview updates
- [ ] 10.4 Test save from edit mode
- [ ] 10.5 Test cheat sheet appears/dismisses correctly
- [ ] 10.6 Test cheat sheet works in both modes
- [ ] 10.7 Test status bar updates correctly
- [ ] 10.8 Test status bar toggle in preferences
- [ ] 10.9 Test distraction-free mode enter/exit
- [ ] 10.10 Test hover controls in distraction-free
