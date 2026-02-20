# Markdown Rendering - Performance Delta

## MODIFIED Requirements

### Requirement: Native Text Rendering
The application SHALL render markdown text using swift-markdown for parsing and AttributedString for display, providing native macOS text handling with virtual scrolling for large documents.

#### Scenario: Rendering standard markdown
- **WHEN** a markdown document is opened
- **THEN** the content is parsed by swift-markdown
- **AND** rendered as AttributedString in SwiftUI views
- **AND** text selection and copy work natively

#### Scenario: Performance on large documents
- **WHEN** a markdown document exceeds 50,000 lines
- **THEN** scrolling remains smooth (60fps)
- **AND** initial render completes within 500ms
- **AND** memory usage stays under 100MB for view layer

#### Scenario: Virtual scrolling behavior
- **WHEN** user scrolls through a large document
- **THEN** only visible blocks plus buffer are rendered
- **AND** blocks are created on-demand as they scroll into view
- **AND** scroll position is tracked via single geometry observer

#### Scenario: Block height estimation
- **WHEN** a block scrolls into view for the first time
- **THEN** its height is estimated based on block type
- **AND** actual height is measured and cached after render
- **AND** cached heights are used for subsequent renders

## ADDED Requirements

### Requirement: Outline Sync with Virtual Scrolling
The application SHALL maintain outline sidebar synchronization when using virtual scrolling.

#### Scenario: Outline highlights during scroll
- **WHEN** user scrolls through document with outline visible
- **THEN** current section is determined via scroll offset calculation
- **AND** outline sidebar highlights the current heading
- **AND** updates are debounced to avoid excessive recalculation

#### Scenario: Outline click navigation
- **WHEN** user clicks a heading in the outline
- **THEN** document scrolls to that heading
- **AND** heading block is rendered if not already visible
- **AND** scroll position is accurate despite lazy loading

### Requirement: Search with Virtual Scrolling
The application SHALL support search functionality with virtual scrolling.

#### Scenario: Search match navigation
- **WHEN** user searches in a large document
- **THEN** match locations are pre-computed across all blocks
- **AND** navigating to a match scrolls the block into view
- **AND** match highlighting is applied when block renders

#### Scenario: Search highlighting efficiency
- **WHEN** search is active
- **THEN** highlighting is applied only to visible blocks
- **AND** off-screen blocks receive highlighting when scrolled into view

### Requirement: Efficient Syntax Highlighting
The application SHALL provide efficient syntax highlighting in the editor.

#### Scenario: Line offset caching
- **WHEN** syntax highlighting is applied
- **THEN** line-to-character offset mapping is built once
- **AND** subsequent offset lookups are O(1)
- **AND** highlighting completes without blocking UI

#### Scenario: Visible region highlighting
- **WHEN** user edits text in a large document
- **THEN** highlighting is applied to visible region plus buffer
- **AND** off-screen text is highlighted when scrolled into view
- **AND** editor remains responsive during continuous typing

#### Scenario: Highlighting debounce
- **WHEN** user types continuously
- **THEN** highlighting updates are debounced by 200ms
- **AND** typing does not trigger per-keystroke highlighting
