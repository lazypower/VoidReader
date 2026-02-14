# Change: Add Split-Pane Edit Mode

## Why
While VoidReader is reader-first, users need the ability to make edits. A split-pane view with source on the left and live preview on the right provides a familiar editing experience without sacrificing the reading focus.

## What Changes
- Add toggle to switch between reader mode and edit mode
- Create split-pane layout with adjustable divider
- Implement source editor with markdown syntax highlighting
- Live preview updates as user types
- Sync scroll position between panes (optional)

## Impact
- Affected specs: edit-mode (new)
- Affected code: View layer, document binding, editor component
