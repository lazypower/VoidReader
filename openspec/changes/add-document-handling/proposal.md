# Change: Add Document-Based App Architecture

## Why
VoidReader needs a solid foundation for file handling that follows macOS conventions. Users expect to open files via drag-drop, double-click, file picker, and recent documents - all patterns that macOS DocumentGroup provides out of the box.

## What Changes
- Implement FileDocument conformance for markdown files
- Set up DocumentGroup as the app's entry point
- Support .md and .markdown file extensions
- Enable drag-drop onto app icon and windows
- Register as handler for markdown UTTypes

## Impact
- Affected specs: document-handling (new)
- Affected code: App entry point, document model
