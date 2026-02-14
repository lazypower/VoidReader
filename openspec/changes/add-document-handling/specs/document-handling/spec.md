# Document Handling

This capability defines how VoidReader opens, reads, and manages markdown files using macOS document-based app architecture.

## ADDED Requirements

### Requirement: File Document Conformance
The application SHALL implement FileDocument protocol to represent markdown documents with read/write capabilities.

#### Scenario: Reading markdown file
- **WHEN** a user opens a .md or .markdown file
- **THEN** the file content is loaded into a MarkdownDocument instance
- **AND** the document is displayed in a new window

#### Scenario: Writing markdown file
- **WHEN** a user saves changes to a document
- **THEN** the content is written back to the file system
- **AND** the document dirty state is cleared

### Requirement: Supported File Types
The application SHALL support opening files with .md and .markdown extensions via UTType registration.

#### Scenario: Opening .md file
- **WHEN** a user opens a file with .md extension
- **THEN** the application recognizes it as a markdown document

#### Scenario: Opening .markdown file
- **WHEN** a user opens a file with .markdown extension
- **THEN** the application recognizes it as a markdown document

### Requirement: File Access Methods
The application SHALL support multiple file access patterns: file picker, drag-drop, open-with, and recent documents.

#### Scenario: File picker access
- **WHEN** a user selects File > Open from the menu
- **THEN** a file picker dialog appears filtered to markdown files
- **AND** selecting a file opens it in a new window

#### Scenario: Drag-drop access
- **WHEN** a user drags a markdown file onto the app icon or window
- **THEN** the file opens in a new window

#### Scenario: Open-with access
- **WHEN** a user right-clicks a markdown file and selects "Open With" > VoidReader
- **THEN** the file opens in VoidReader

#### Scenario: Recent documents access
- **WHEN** a user selects a file from File > Open Recent
- **THEN** the previously opened file opens in a new window

### Requirement: Context-Aware Launch Mode
The application SHALL open in reader view when launched with a file, and editor view when launched without a file.

#### Scenario: Launched with file (Finder double-click)
- **WHEN** user double-clicks a .md file in Finder
- **THEN** the file opens in reader view
- **AND** the user can immediately read the content

#### Scenario: Launched with file (Open With)
- **WHEN** user opens a file via "Open With" context menu
- **THEN** the file opens in reader view

#### Scenario: Launched with file (drag-drop)
- **WHEN** user drags a file onto the app icon
- **THEN** the file opens in reader view

#### Scenario: Launched without file (app icon click)
- **WHEN** user launches the app without a file context
- **THEN** a new untitled document opens in editor view
- **AND** the cursor is ready in the source editor
- **AND** the user can immediately start writing

#### Scenario: New document from menu
- **WHEN** user selects File > New
- **THEN** a new untitled document opens in editor view

### Requirement: Single-File Model
The application SHALL operate on individual files, not a vault or workspace model.

#### Scenario: Multiple independent files
- **WHEN** a user opens multiple markdown files
- **THEN** each file opens in its own window
- **AND** files have no implicit relationship to each other

#### Scenario: No project context
- **WHEN** a user opens a markdown file
- **THEN** no sidebar, file tree, or workspace UI is shown
- **AND** the focus is entirely on the single document

### Requirement: Print and Export
The application SHALL support printing documents and exporting to PDF.

#### Scenario: Print document
- **WHEN** user selects File > Print or presses Cmd+P
- **THEN** macOS print dialog appears
- **AND** rendered markdown is sent to printer

#### Scenario: Export to PDF
- **WHEN** user selects File > Export as PDF
- **THEN** a save dialog appears
- **AND** rendered markdown is saved as PDF

#### Scenario: Print preserves formatting
- **WHEN** document is printed or exported
- **THEN** headings, code blocks, tables, and images render correctly
- **AND** mermaid diagrams are included as images

### Requirement: Scroll Position Memory
The application SHALL remember scroll position when reopening documents.

#### Scenario: Reopening document
- **WHEN** user reopens a previously viewed document
- **THEN** document scrolls to the last viewed position
- **AND** reading can resume seamlessly

#### Scenario: Position persistence
- **WHEN** app quits with documents open
- **THEN** scroll positions are persisted
- **AND** restored on next launch

### Requirement: Share Sheet Integration
The application SHALL integrate with macOS share sheet for sharing documents.

#### Scenario: Share document
- **WHEN** user clicks share button or selects File > Share
- **THEN** macOS share sheet appears
- **AND** document can be shared via available services

#### Scenario: Share as rendered
- **WHEN** sharing via share sheet
- **THEN** rendered content or PDF is shared
- **AND** not raw markdown source (unless explicitly chosen)

### Requirement: Quick Look Preview
The application SHALL provide a Quick Look extension for previewing markdown files in Finder.

#### Scenario: Quick Look in Finder
- **WHEN** user selects a .md file in Finder and presses Space
- **THEN** rendered markdown preview appears
- **AND** preview uses the app's rendering engine

#### Scenario: Quick Look styling
- **WHEN** Quick Look preview is displayed
- **THEN** styling matches the app's reader view
- **AND** respects system light/dark mode
