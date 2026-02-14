# Markdown Rendering

This capability defines how VoidReader parses and renders markdown content using native macOS technologies. Full GitHub Flavored Markdown (GFM) is supported.

## ADDED Requirements

### Requirement: GFM Compliance
The application SHALL support the full GitHub Flavored Markdown specification, including tables, task lists, strikethrough, and autolinks.

#### Scenario: GFM document rendering
- **WHEN** a document contains GFM-specific syntax
- **THEN** all GFM extensions render correctly
- **AND** the document displays as it would on GitHub

### Requirement: Native Text Rendering
The application SHALL render markdown text using swift-markdown for parsing and AttributedString for display, providing native macOS text handling.

#### Scenario: Rendering standard markdown
- **WHEN** a markdown document is opened
- **THEN** the content is parsed by swift-markdown
- **AND** rendered as AttributedString in a SwiftUI Text view
- **AND** text selection and copy work natively

#### Scenario: Performance on large documents
- **WHEN** a markdown document exceeds 10,000 lines
- **THEN** the document renders within 2 seconds
- **AND** scrolling remains smooth (60fps)

### Requirement: Heading Rendering
The application SHALL render headings (H1-H6) with visually distinct typography following a consistent scale.

#### Scenario: H1 heading display
- **WHEN** a line begins with `# `
- **THEN** it renders as a large, bold heading
- **AND** has increased spacing above and below

#### Scenario: Heading hierarchy
- **WHEN** a document contains H1 through H6 headings
- **THEN** each level is visually smaller than the previous
- **AND** the hierarchy is clearly distinguishable

### Requirement: Text Formatting
The application SHALL render emphasis (bold, italic, strikethrough), inline code, and links with appropriate styling.

#### Scenario: Bold text
- **WHEN** text is wrapped in `**` or `__`
- **THEN** it renders with bold weight

#### Scenario: Italic text
- **WHEN** text is wrapped in `*` or `_`
- **THEN** it renders with italic style

#### Scenario: Inline code
- **WHEN** text is wrapped in backticks
- **THEN** it renders in monospace font with subtle background

#### Scenario: Links
- **WHEN** a markdown link `[text](url)` is present
- **THEN** the text renders as a clickable link
- **AND** clicking opens the URL in the default browser

### Requirement: List Rendering
The application SHALL render ordered and unordered lists with proper indentation and markers.

#### Scenario: Unordered list
- **WHEN** lines begin with `- `, `* `, or `+ `
- **THEN** they render as a bulleted list
- **AND** nested items are indented

#### Scenario: Ordered list
- **WHEN** lines begin with `1. `, `2. `, etc.
- **THEN** they render as a numbered list
- **AND** numbers are right-aligned

### Requirement: Code Block Rendering
The application SHALL render fenced code blocks with monospace font and optional syntax highlighting.

#### Scenario: Basic code block
- **WHEN** text is wrapped in triple backticks
- **THEN** it renders in a monospace font
- **AND** has a distinct background color
- **AND** preserves whitespace exactly

#### Scenario: Code block with language hint
- **WHEN** a code block specifies a language (e.g., ```swift)
- **THEN** syntax highlighting is applied for that language

### Requirement: Blockquote Rendering
The application SHALL render blockquotes with visual distinction from regular text.

#### Scenario: Blockquote display
- **WHEN** lines begin with `> `
- **THEN** they render with left border or indentation
- **AND** text may be styled differently (e.g., italic or muted)

### Requirement: Image Rendering
The application SHALL render images inline with async loading and appropriate sizing.

#### Scenario: Local image
- **WHEN** a markdown image references a relative path
- **THEN** the image loads relative to the document location
- **AND** displays inline in the content

#### Scenario: Remote image
- **WHEN** a markdown image references an HTTP(S) URL
- **THEN** the image loads asynchronously
- **AND** a placeholder shows while loading

### Requirement: Reader-First Default
The application SHALL default to rendered view, not source view, when opening documents.

#### Scenario: Opening a document
- **WHEN** a user opens a markdown file
- **THEN** the rendered markdown view is displayed
- **AND** the raw source is not visible by default

### Requirement: Table Rendering
The application SHALL render GFM tables using native SwiftUI layout components.

#### Scenario: Basic table
- **WHEN** a document contains a GFM table with pipes and dashes
- **THEN** the table renders with aligned columns and rows
- **AND** header row is visually distinct

#### Scenario: Table alignment
- **WHEN** a table specifies column alignment (`:---`, `:---:`, `---:`)
- **THEN** cell content aligns left, center, or right accordingly

#### Scenario: Table with inline formatting
- **WHEN** table cells contain bold, italic, code, or links
- **THEN** inline formatting renders within cells

### Requirement: Task List Rendering
The application SHALL render GFM task lists with interactive checkboxes.

#### Scenario: Task list display
- **WHEN** a list contains `- [ ]` or `- [x]` items
- **THEN** items render with checkbox controls
- **AND** checked items show as checked

#### Scenario: Task list interaction (edit mode)
- **WHEN** user clicks a task checkbox in edit mode
- **THEN** the source toggles between `[ ]` and `[x]`
- **AND** the document is marked as modified

#### Scenario: Task list interaction (reader mode)
- **WHEN** user clicks a task checkbox in reader mode
- **THEN** no change occurs (read-only)
- **OR** optionally prompts to enter edit mode

### Requirement: Autolink Rendering
The application SHALL automatically convert URLs and email addresses to clickable links.

#### Scenario: URL autolink
- **WHEN** a bare URL appears in text (e.g., https://example.com)
- **THEN** it renders as a clickable link
- **AND** clicking opens the URL in default browser

#### Scenario: Email autolink
- **WHEN** a bare email appears in text (e.g., user@example.com)
- **THEN** it renders as a clickable mailto link

### Requirement: Copy Code Block Button
The application SHALL display a copy button on code blocks for one-click copying.

#### Scenario: Copy button visibility
- **WHEN** a code block is rendered
- **THEN** a copy button appears in the corner of the block
- **AND** the button is subtle but visible on hover

#### Scenario: Copying code
- **WHEN** user clicks the copy button
- **THEN** code block content is copied to clipboard
- **AND** button shows brief "Copied" confirmation

#### Scenario: Copy preserves formatting
- **WHEN** code is copied
- **THEN** indentation and whitespace are preserved exactly

### Requirement: Image Zoom
The application SHALL allow users to zoom/enlarge images by clicking them.

#### Scenario: Click to zoom
- **WHEN** user clicks an inline image
- **THEN** image expands to a larger view
- **AND** background dims to focus on image

#### Scenario: Dismiss zoomed image
- **WHEN** user clicks outside zoomed image or presses Escape
- **THEN** zoom view closes
- **AND** focus returns to document

#### Scenario: Zoom sizing
- **WHEN** image is zoomed
- **THEN** it displays at natural size or fits within window
- **AND** user can scroll if image exceeds viewport

### Requirement: Dark Mode Support
The application SHALL adapt rendering to system appearance (light/dark mode).

#### Scenario: System dark mode
- **WHEN** macOS is in dark mode
- **THEN** text renders in light colors on dark background
- **AND** code blocks and other elements adapt appropriately
