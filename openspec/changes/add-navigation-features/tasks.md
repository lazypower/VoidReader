# Tasks: Add Navigation Features

## 1. Find Bar
- [ ] 1.1 Create FindBar view component
- [ ] 1.2 Implement Cmd+F to show/focus find bar
- [ ] 1.3 Implement Escape to dismiss find bar
- [ ] 1.4 Search document content as user types
- [ ] 1.5 Highlight all matches in document
- [ ] 1.6 Show match count (e.g., "3 of 12")
- [ ] 1.7 Implement Enter/Shift+Enter for next/previous match
- [ ] 1.8 Implement Cmd+G / Cmd+Shift+G for next/previous
- [ ] 1.9 Scroll to and highlight current match
- [ ] 1.10 Support case-sensitive toggle
- [ ] 1.11 Support regex toggle (optional)

## 2. Find & Replace (Edit Mode)
- [ ] 2.1 Extend FindBar with replace field
- [ ] 2.2 Implement Cmd+H to show find & replace
- [ ] 2.3 Replace current match button
- [ ] 2.4 Replace all matches button
- [ ] 2.5 Show replacement preview
- [ ] 2.6 Only enable in edit mode

## 3. Outline/TOC Sidebar
- [ ] 3.1 Extract headings from markdown AST
- [ ] 3.2 Build hierarchical outline model (H1 > H2 > H3...)
- [ ] 3.3 Create OutlineSidebar view component
- [ ] 3.4 Display heading hierarchy with indentation
- [ ] 3.5 Click heading to scroll to location
- [ ] 3.6 Highlight current section based on scroll position
- [ ] 3.7 Implement Cmd+Shift+O to toggle sidebar
- [ ] 3.8 Remember sidebar state per window
- [ ] 3.9 Animate sidebar show/hide

## 4. Keyboard Navigation
- [ ] 4.1 Arrow keys navigate outline when focused
- [ ] 4.2 Enter jumps to selected heading
- [ ] 4.3 Tab moves focus between find bar fields

## 5. Testing
- [ ] 5.1 Test find with various queries
- [ ] 5.2 Test find wraps around document
- [ ] 5.3 Test replace single and all
- [ ] 5.4 Test outline extracts all heading levels
- [ ] 5.5 Test outline click scrolls accurately
- [ ] 5.6 Test current section highlighting updates on scroll
