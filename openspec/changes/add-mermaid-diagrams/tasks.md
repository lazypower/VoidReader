# Tasks: Add Mermaid Diagram Support

## 1. Resource Bundling
- [x] 1.1 Download mermaid.min.js (specific version)
- [x] 1.2 Add to Xcode project as bundle resource
- [x] 1.3 Create HTML template for rendering
- [x] 1.4 Verify resources load at runtime

## 2. Mermaid Block Detection
- [x] 2.1 Extend markdown parser to identify mermaid code blocks
- [x] 2.2 Extract mermaid source from fenced blocks
- [x] 2.3 Pass mermaid blocks separately from regular markdown

## 3. WebView Renderer
- [x] 3.1 Create MermaidWebView wrapping WKWebView
- [x] 3.2 Load HTML template with bundled mermaid.js
- [x] 3.3 Inject mermaid source code for rendering
- [x] 3.4 Handle render completion callback
- [x] 3.5 Size WebView to fit rendered diagram

## 4. Integration
- [x] 4.1 Create MermaidBlockView SwiftUI component
- [x] 4.2 Integrate mermaid blocks into document flow
- [x] 4.3 Maintain scroll position with mixed content

## 5. Theming
- [x] 5.1 Detect system appearance (light/dark)
- [x] 5.2 Pass theme to mermaid configuration
- [x] 5.3 React to appearance changes

## 6. Error Handling
- [x] 6.1 Display syntax errors gracefully
- [x] 6.2 Fall back to showing raw code on render failure
- [x] 6.3 Log errors for debugging

## 7. Testing
- [ ] 7.1 Test flowchart rendering
- [ ] 7.2 Test sequence diagram rendering
- [ ] 7.3 Test class diagram rendering
- [ ] 7.4 Test theme switching
- [ ] 7.5 Test invalid mermaid syntax handling
