# Edit Mode

This capability defines the split-pane editing experience in VoidReader.

## ADDED Requirements

### Requirement: Mode Toggle
The application SHALL provide a toggle between reader mode (default) and edit mode.

#### Scenario: Entering edit mode
- **WHEN** user clicks the edit button or presses Cmd+E
- **THEN** the view transitions to split-pane edit mode
- **AND** the source editor receives focus

#### Scenario: Exiting edit mode
- **WHEN** user clicks the reader button or presses Cmd+E again
- **THEN** the view transitions back to reader mode
- **AND** scroll position is preserved approximately

#### Scenario: Default mode
- **WHEN** a document is opened
- **THEN** it displays in reader mode
- **AND** edit mode is not shown by default

### Requirement: Split Pane Layout
The application SHALL display source and preview side-by-side in edit mode with an adjustable divider.

#### Scenario: Split pane display
- **WHEN** edit mode is active
- **THEN** source editor appears on the left
- **AND** live preview appears on the right
- **AND** a draggable divider separates them

#### Scenario: Divider adjustment
- **WHEN** user drags the divider
- **THEN** pane proportions adjust accordingly
- **AND** position is remembered for the session

#### Scenario: Minimum pane size
- **WHEN** user drags divider to extreme position
- **THEN** minimum width is enforced for both panes
- **AND** neither pane can be collapsed to zero

### Requirement: Source Editor
The application SHALL provide a text editor for markdown source with appropriate styling.

#### Scenario: Source display
- **WHEN** edit mode is active
- **THEN** raw markdown source is displayed
- **AND** monospace font is used
- **AND** text is editable

#### Scenario: Syntax highlighting
- **WHEN** markdown source is displayed
- **THEN** headings, emphasis, links, and code are visually distinguished
- **AND** highlighting updates as user types

#### Scenario: Document binding
- **WHEN** user edits source text
- **THEN** changes are reflected in the document model
- **AND** the document is marked as having unsaved changes

### Requirement: Live Preview
The application SHALL update the preview pane as the user edits source.

#### Scenario: Live update
- **WHEN** user types in the source editor
- **THEN** preview updates to reflect changes
- **AND** updates occur within 300ms of typing pause

#### Scenario: Parse error resilience
- **WHEN** user is mid-edit with incomplete markdown
- **THEN** preview shows best-effort rendering
- **AND** does not show error states for transient invalid syntax

#### Scenario: Mermaid preview
- **WHEN** user edits a mermaid block
- **THEN** diagram re-renders in preview
- **AND** updates are debounced to avoid excessive re-rendering

### Requirement: Editing Workflow
The application SHALL support standard editing workflows including save, undo, and redo.

#### Scenario: Saving changes
- **WHEN** user presses Cmd+S in edit mode
- **THEN** document is saved to disk
- **AND** unsaved indicator clears

#### Scenario: Undo/redo
- **WHEN** user presses Cmd+Z or Cmd+Shift+Z
- **THEN** changes are undone or redone
- **AND** both source and preview reflect the change

### Requirement: Status Bar
The application SHALL provide a toggleable status bar displaying document statistics.

#### Scenario: Status bar content
- **WHEN** status bar is visible
- **THEN** it displays word count, character count, and reading time
- **AND** updates as document changes

#### Scenario: Status bar toggle
- **WHEN** user disables status bar in preferences
- **THEN** status bar is hidden
- **AND** document view expands to fill space

#### Scenario: Reading time estimate
- **WHEN** document has content
- **THEN** status bar shows estimated reading time
- **AND** estimate assumes ~200 words per minute

#### Scenario: Selection statistics
- **WHEN** user selects text in editor
- **THEN** status bar shows selection word/character count
- **AND** reverts to document totals when deselected

### Requirement: Distraction-Free Mode
The application SHALL provide a distraction-free mode that hides all UI chrome.

#### Scenario: Entering distraction-free mode
- **WHEN** user presses Cmd+Shift+F or selects View > Distraction Free
- **THEN** window enters fullscreen
- **AND** toolbar, status bar, and sidebar hide
- **AND** only document content is visible

#### Scenario: Content centering
- **WHEN** distraction-free mode is active
- **THEN** content is centered with comfortable margins
- **AND** line width remains readable (not edge-to-edge)

#### Scenario: Exiting distraction-free mode
- **WHEN** user presses Escape or Cmd+Shift+F
- **THEN** window returns to normal mode
- **AND** all UI chrome reappears

#### Scenario: Controls on hover
- **WHEN** user moves mouse to top of screen in distraction-free mode
- **THEN** minimal controls appear temporarily
- **AND** controls hide after mouse moves away

### Requirement: GFM Syntax Cheat Sheet
The application SHALL provide a hold-to-reveal overlay showing GFM syntax reference.

#### Scenario: Showing cheat sheet
- **WHEN** user holds Option+Shift+/ (⌥⇧/)
- **THEN** a popover overlay appears with GFM syntax reference
- **AND** the overlay remains visible while keys are held

#### Scenario: Hiding cheat sheet
- **WHEN** user releases the key combination
- **THEN** the overlay dismisses immediately
- **AND** focus returns to previous location

#### Scenario: Cheat sheet content
- **WHEN** the cheat sheet is displayed
- **THEN** it shows syntax for: headings, emphasis, links, images, code, lists, task lists, tables, blockquotes, and horizontal rules
- **AND** examples are copyable

#### Scenario: Cheat sheet in reader mode
- **WHEN** user holds the key combo in reader mode
- **THEN** the cheat sheet still appears
- **AND** it serves as a reference for understanding the document
