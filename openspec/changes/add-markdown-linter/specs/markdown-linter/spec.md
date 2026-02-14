# Markdown Linter

This capability defines VoidReader's built-in markdown linting and formatting, running natively without external tools.

## ADDED Requirements

### Requirement: Native Linting Engine
The application SHALL provide a native markdown linter built on swift-markdown that checks for style issues without external dependencies.

#### Scenario: Linting a document
- **WHEN** a document is edited in the editor pane
- **THEN** the linter analyzes the markdown AST
- **AND** returns a list of warnings with line numbers and messages

#### Scenario: No external dependencies
- **WHEN** linting runs
- **THEN** no external processes are spawned
- **AND** no network requests are made
- **AND** linting works offline

### Requirement: Lint Rules
The application SHALL implement common markdown lint rules covering consistency and formatting issues.

#### Scenario: Consistent list markers (MD004)
- **WHEN** a document mixes `-`, `*`, and `+` for unordered lists
- **THEN** a warning is raised for inconsistent markers

#### Scenario: Consistent emphasis markers (MD049/MD050)
- **WHEN** a document mixes `*` and `_` for emphasis
- **THEN** a warning is raised for inconsistent markers

#### Scenario: No trailing whitespace (MD009)
- **WHEN** a line ends with spaces or tabs
- **THEN** a warning is raised for trailing whitespace

#### Scenario: Blank lines around headings (MD022)
- **WHEN** a heading lacks blank lines above or below
- **THEN** a warning is raised for missing spacing

#### Scenario: Blank lines around code blocks (MD031)
- **WHEN** a fenced code block lacks blank lines above or below
- **THEN** a warning is raised for missing spacing

#### Scenario: No multiple consecutive blank lines (MD012)
- **WHEN** more than one consecutive blank line appears
- **THEN** a warning is raised for excessive blank lines

#### Scenario: Heading level increment (MD001)
- **WHEN** heading levels skip (e.g., H1 to H3)
- **THEN** a warning is raised for non-sequential headings

### Requirement: Native Formatter
The application SHALL provide a markdown formatter that normalizes style by re-serializing the AST with consistent conventions.

#### Scenario: Formatting a document
- **WHEN** format is triggered
- **THEN** the document is re-serialized from AST
- **AND** all configured style rules are applied

#### Scenario: List marker normalization
- **WHEN** formatting runs with list marker preference set to `-`
- **THEN** all unordered list markers become `-`

#### Scenario: Emphasis marker normalization
- **WHEN** formatting runs with emphasis preference set to `*`
- **THEN** all emphasis uses `*` instead of `_`

#### Scenario: Whitespace normalization
- **WHEN** formatting runs
- **THEN** trailing whitespace is removed
- **AND** multiple blank lines collapse to one
- **AND** file ends with single newline

#### Scenario: Table alignment
- **WHEN** formatting a document with tables
- **THEN** table columns are aligned with consistent padding

### Requirement: Format on Save
The application SHALL run the formatter automatically when a document is saved or autosaved.

#### Scenario: Manual save triggers format
- **WHEN** user presses Cmd+S
- **THEN** formatter runs before writing to disk
- **AND** the formatted content is saved

#### Scenario: Autosave triggers format
- **WHEN** autosave fires (after idle period or focus loss)
- **THEN** formatter runs before writing to disk
- **AND** the formatted content is saved

#### Scenario: Editor reflects formatted content
- **WHEN** formatting runs on save
- **THEN** the editor updates to show formatted text
- **AND** cursor position is preserved as closely as possible

### Requirement: Lint Warning Display
The application SHALL display lint warnings in the editor with visual indicators.

#### Scenario: Gutter indicators
- **WHEN** a line has lint warnings
- **THEN** a warning icon appears in the editor gutter
- **AND** icon color indicates severity (yellow for warning, red for error)

#### Scenario: Warning details on hover
- **WHEN** user hovers over a gutter warning icon
- **THEN** a tooltip shows the warning message and rule ID

#### Scenario: Inline underlines (optional)
- **WHEN** inline warnings are enabled
- **THEN** problematic text is underlined with warning color

### Requirement: Configurable Rules
The application SHALL allow users to configure which lint rules are enabled and formatter preferences.

#### Scenario: Disabling a rule
- **WHEN** user disables a specific lint rule in preferences
- **THEN** that rule no longer produces warnings

#### Scenario: Format on save toggle
- **WHEN** user disables "Format on Save" in preferences
- **THEN** saving does not trigger the formatter
- **AND** linting still runs for warnings

#### Scenario: Marker preferences
- **WHEN** user sets list marker preference to `*`
- **THEN** formatter uses `*` for all unordered lists

### Requirement: Idempotent Formatting
The application SHALL ensure formatting is idempotent - running format twice produces identical output.

#### Scenario: Stable formatting
- **WHEN** a formatted document is formatted again
- **THEN** no changes occur
- **AND** the document is not marked as modified
