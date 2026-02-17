# Tasks: Add LaTeX Math Rendering

## 1. Resource Bundling
- [x] 1.1 Download KaTeX bundle (katex.min.js + katex.min.css + fonts)
- [x] 1.2 Add to Xcode project as bundle resources
- [x] 1.3 Create HTML template for math rendering
- [x] 1.4 Verify resources load at runtime

## 2. Math Block Detection
- [x] 2.1 Detect inline math delimiters `$...$` (styled text, not KaTeX)
- [x] 2.2 Detect block math delimiters `$$...$$`
- [x] 2.3 Escape handling (ignore `\$` escaped dollars)
- [x] 2.4 Pass math expressions to renderer with context (inline vs block)

## 3. WebView Renderer
- [x] 3.1 Create MathWebView wrapping WKWebView (lightweight, reusable)
- [x] 3.2 Load HTML template with bundled KaTeX
- [x] 3.3 Inject LaTeX source for rendering
- [x] 3.4 Handle render completion and sizing
- [ ] 3.5 Optimize for inline rendering (minimal height)

## 4. Integration
- [x] 4.1 Create MathBlockView for display math ($$)
- [x] 4.2 Inline math rendered as styled text (monospace purple) - no separate view needed
- [x] 4.3 Integrate math expressions into document flow
- [x] 4.4 Baseline alignment natural with styled text approach

## 5. Theming
- [x] 5.1 Detect system appearance (light/dark)
- [x] 5.2 Style math output to match document text color
- [x] 5.3 React to appearance changes

## 6. Error Handling
- [x] 6.1 Display LaTeX syntax errors gracefully
- [x] 6.2 Fall back to showing raw LaTeX on render failure
- [x] 6.3 Log errors - KaTeX console output visible in debug builds

## 7. Testing
- [x] 7.1 Test Greek letters - VIBE_CHECK.md includes $\alpha$, $\beta$, $\gamma$
- [x] 7.2 Test fractions/superscripts - VIBE_CHECK.md includes quadratic formula, Euler
- [x] 7.3 Test inline vs block - VIBE_CHECK.md exercises both $...$ and $$...$$
- [x] 7.4 Test theme switching - verified manually with appearance override
- [x] 7.5 Test invalid LaTeX - block math shows error, inline shows raw text

## 8. Quick Look Support
- [x] 8.1 Show LaTeX source in Quick Look (no WebView rendering)
