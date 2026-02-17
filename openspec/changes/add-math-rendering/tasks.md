# Tasks: Add LaTeX Math Rendering

## 1. Resource Bundling
- [x] 1.1 Download KaTeX bundle (katex.min.js + katex.min.css + fonts)
- [x] 1.2 Add to Xcode project as bundle resources
- [x] 1.3 Create HTML template for math rendering
- [x] 1.4 Verify resources load at runtime

## 2. Math Block Detection
- [ ] 2.1 Detect inline math delimiters `$...$`
- [x] 2.2 Detect block math delimiters `$$...$$`
- [ ] 2.3 Escape handling (ignore `\$` escaped dollars)
- [x] 2.4 Pass math expressions to renderer with context (inline vs block)

## 3. WebView Renderer
- [x] 3.1 Create MathWebView wrapping WKWebView (lightweight, reusable)
- [x] 3.2 Load HTML template with bundled KaTeX
- [x] 3.3 Inject LaTeX source for rendering
- [x] 3.4 Handle render completion and sizing
- [ ] 3.5 Optimize for inline rendering (minimal height)

## 4. Integration
- [x] 4.1 Create MathBlockView for display math ($$)
- [ ] 4.2 Create InlineMathView for inline math ($)
- [x] 4.3 Integrate math expressions into document flow
- [ ] 4.4 Ensure proper baseline alignment for inline math

## 5. Theming
- [x] 5.1 Detect system appearance (light/dark)
- [x] 5.2 Style math output to match document text color
- [x] 5.3 React to appearance changes

## 6. Error Handling
- [x] 6.1 Display LaTeX syntax errors gracefully
- [x] 6.2 Fall back to showing raw LaTeX on render failure
- [ ] 6.3 Log errors for debugging

## 7. Testing
- [ ] 7.1 Test Greek letters and symbols
- [ ] 7.2 Test fractions and subscripts/superscripts
- [ ] 7.3 Test inline vs block rendering
- [ ] 7.4 Test theme switching
- [ ] 7.5 Test invalid LaTeX handling

## 8. Quick Look Support
- [x] 8.1 Show LaTeX source in Quick Look (no WebView rendering)
