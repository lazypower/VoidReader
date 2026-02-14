# Navigation

This capability defines document navigation features including find, find & replace, and outline sidebar.

## ADDED Requirements

### Requirement: Find in Document
The application SHALL provide a find bar for searching text within the current document.

#### Scenario: Opening find bar
- **WHEN** user presses Cmd+F
- **THEN** a find bar appears at top of document
- **AND** the search field is focused

#### Scenario: Searching text
- **WHEN** user types in the find bar
- **THEN** all matches are highlighted in the document
- **AND** match count displays (e.g., "3 of 12")
- **AND** document scrolls to first match

#### Scenario: Navigating matches
- **WHEN** user presses Enter or Cmd+G
- **THEN** selection moves to next match
- **AND** document scrolls to show the match

#### Scenario: Previous match
- **WHEN** user presses Shift+Enter or Cmd+Shift+G
- **THEN** selection moves to previous match

#### Scenario: Wrap around
- **WHEN** user navigates past last match
- **THEN** selection wraps to first match

#### Scenario: Dismissing find bar
- **WHEN** user presses Escape
- **THEN** find bar closes
- **AND** highlights are cleared

#### Scenario: Case sensitivity
- **WHEN** user toggles case-sensitive option
- **THEN** search respects or ignores case accordingly

### Requirement: Find and Replace
The application SHALL provide find and replace functionality in edit mode.

#### Scenario: Opening find and replace
- **WHEN** user presses Cmd+H in edit mode
- **THEN** find bar appears with replace field

#### Scenario: Replace current match
- **WHEN** user clicks "Replace" or presses Cmd+Shift+1
- **THEN** the current match is replaced with replacement text
- **AND** selection moves to next match

#### Scenario: Replace all matches
- **WHEN** user clicks "Replace All"
- **THEN** all matches are replaced
- **AND** replacement count is shown

#### Scenario: Replace in reader mode
- **WHEN** user presses Cmd+H in reader mode
- **THEN** find and replace is not available
- **OR** user is prompted to switch to edit mode

### Requirement: Outline Sidebar
The application SHALL provide a toggleable sidebar showing document heading structure.

#### Scenario: Toggling outline sidebar
- **WHEN** user presses Cmd+Shift+O
- **THEN** outline sidebar toggles visibility
- **AND** sidebar animates in/out

#### Scenario: Outline content
- **WHEN** outline sidebar is visible
- **THEN** it displays all headings (H1-H6) hierarchically
- **AND** indentation reflects heading level

#### Scenario: Navigate via outline
- **WHEN** user clicks a heading in the outline
- **THEN** document scrolls to that heading
- **AND** heading is highlighted briefly

#### Scenario: Current section indicator
- **WHEN** user scrolls through document
- **THEN** outline highlights the current section
- **AND** highlighting updates as user scrolls

#### Scenario: Empty document
- **WHEN** document has no headings
- **THEN** outline shows "No headings" message

#### Scenario: Sidebar state persistence
- **WHEN** user closes and reopens a document
- **THEN** sidebar visibility state is remembered
