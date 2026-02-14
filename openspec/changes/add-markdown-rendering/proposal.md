# Change: Add Native Markdown Rendering

## Why
The core value of VoidReader is a clean reading experience. Using swift-markdown for parsing and AttributedString for rendering provides native macOS performance and text selection, avoiding the weight and limitations of WebView for standard markdown content.

## What Changes
- Integrate swift-markdown package for parsing
- Build MarkupVisitor to convert AST to AttributedString
- Render headings, paragraphs, lists, code blocks, links, images, emphasis
- Support syntax highlighting for code blocks
- Provide smooth scrolling and text selection

## Impact
- Affected specs: markdown-rendering (new)
- Affected code: Rendering pipeline, SwiftUI views
