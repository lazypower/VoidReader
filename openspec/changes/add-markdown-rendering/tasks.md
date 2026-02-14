# Tasks: Add Native Markdown Rendering

## 1. Package Integration
- [x] 1.1 Add swift-markdown package dependency
- [x] 1.2 Configure package resolution in Xcode

## 2. Markdown Parser
- [x] 2.1 Create MarkdownParser wrapper around swift-markdown
- [x] 2.2 Parse document into Markup AST
- [x] 2.3 Handle parsing errors gracefully

## 3. AttributedString Renderer (Inline Content)
- [x] 3.1 Create MarkupToAttributedString visitor
- [x] 3.2 Implement heading styles (H1-H6)
- [x] 3.3 Implement paragraph rendering
- [x] 3.4 Implement emphasis (bold, italic, strikethrough)
- [x] 3.5 Implement inline code styling
- [x] 3.6 Implement code block rendering with monospace font
- [x] 3.7 Implement link rendering with click handling
- [ ] 3.8 Implement autolinks (bare URLs and emails)
- [x] 3.9 Implement unordered list rendering
- [x] 3.10 Implement ordered list rendering
- [x] 3.11 Implement blockquote styling
- [x] 3.12 Implement horizontal rule
- [ ] 3.13 Implement image rendering (async loading)

## 4. Block-Level Components (GFM Extensions)
- [x] 4.1 Create TableBlockView using SwiftUI Grid
- [x] 4.2 Implement column alignment (left/center/right)
- [x] 4.3 Style table headers distinctly
- [x] 4.4 Support inline formatting within cells
- [x] 4.5 Create TaskListView with checkbox controls
- [ ] 4.6 Implement checkbox toggle binding to source
- [x] 4.7 Integrate block components into document flow

## 5. Reader View
- [ ] 5.1 Create MarkdownReaderView SwiftUI component
- [ ] 5.2 Compose inline (AttributedString) and block (Tables, Tasks) views
- [ ] 5.3 Add ScrollView with appropriate padding
- [ ] 5.4 Configure readable content width
- [ ] 5.5 Support text selection

## 6. Styling
- [ ] 6.1 Define typography scale for headings
- [ ] 6.2 Configure line height and spacing
- [ ] 6.3 Support system dark/light mode
- [ ] 6.4 Use system fonts (SF Pro, SF Mono)
- [ ] 6.5 Style tables with borders/alternating rows
- [ ] 6.6 Style task checkboxes consistently

## 7. Code Block Copy Button
- [x] 7.1 Add copy button overlay to code blocks
- [x] 7.2 Show button on hover, subtle otherwise
- [x] 7.3 Copy code content to clipboard on click
- [x] 7.4 Show "Copied" feedback animation
- [x] 7.5 Preserve exact whitespace when copying

## 8. Image Zoom
- [ ] 8.1 Make images clickable
- [ ] 8.2 Create zoom overlay view
- [ ] 8.3 Dim background when zoomed
- [ ] 8.4 Display image at natural size or fit-to-window
- [ ] 8.5 Dismiss on click outside or Escape
- [ ] 8.6 Support scroll for large images

## 9. Testing
- [ ] 9.1 Unit test parser with sample markdown
- [ ] 9.2 Test each element type renders correctly
- [ ] 9.3 Test complex nested structures
- [ ] 9.4 Test GFM tables with various alignments
- [ ] 9.5 Test task list checkbox interaction
- [ ] 9.6 Test large documents for performance
- [ ] 9.7 Test code block copy works
- [ ] 9.8 Test image zoom open/close
