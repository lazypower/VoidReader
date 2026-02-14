# Tasks: Add Mermaid Diagram Support

## 1. Resource Bundling
- [ ] 1.1 Download mermaid.min.js (specific version)
- [ ] 1.2 Add to Xcode project as bundle resource
- [ ] 1.3 Create HTML template for rendering
- [ ] 1.4 Verify resources load at runtime

## 2. Mermaid Block Detection
- [ ] 2.1 Extend markdown parser to identify mermaid code blocks
- [ ] 2.2 Extract mermaid source from fenced blocks
- [ ] 2.3 Pass mermaid blocks separately from regular markdown

## 3. WebView Renderer
- [ ] 3.1 Create MermaidWebView wrapping WKWebView
- [ ] 3.2 Load HTML template with bundled mermaid.js
- [ ] 3.3 Inject mermaid source code for rendering
- [ ] 3.4 Handle render completion callback
- [ ] 3.5 Size WebView to fit rendered diagram

## 4. Integration
- [ ] 4.1 Create MermaidBlockView SwiftUI component
- [ ] 4.2 Integrate mermaid blocks into document flow
- [ ] 4.3 Maintain scroll position with mixed content

## 5. Theming
- [ ] 5.1 Detect system appearance (light/dark)
- [ ] 5.2 Pass theme to mermaid configuration
- [ ] 5.3 React to appearance changes

## 6. Error Handling
- [ ] 6.1 Display syntax errors gracefully
- [ ] 6.2 Fall back to showing raw code on render failure
- [ ] 6.3 Log errors for debugging

## 7. Testing
- [ ] 7.1 Test flowchart rendering
- [ ] 7.2 Test sequence diagram rendering
- [ ] 7.3 Test class diagram rendering
- [ ] 7.4 Test theme switching
- [ ] 7.5 Test invalid mermaid syntax handling
