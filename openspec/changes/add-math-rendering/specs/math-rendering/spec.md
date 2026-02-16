# Math Rendering

This capability defines how VoidReader renders LaTeX mathematical notation using KaTeX in a lightweight WebView.

## ADDED Requirements

### Requirement: Math Expression Detection
The application SHALL detect LaTeX math expressions using dollar sign delimiters and render them as formatted equations.

#### Scenario: Inline math identification
- **WHEN** text contains `$...$` delimiters (single dollar)
- **THEN** the content between delimiters is identified as inline math
- **AND** is rendered inline with surrounding text

#### Scenario: Block math identification
- **WHEN** text contains `$$...$$` delimiters (double dollar)
- **THEN** the content between delimiters is identified as display math
- **AND** is rendered as a centered block

#### Scenario: Escaped dollar signs
- **WHEN** a dollar sign is escaped with backslash (`\$`)
- **THEN** it renders as a literal dollar sign
- **AND** does not trigger math mode

### Requirement: Bundled KaTeX Library
The application SHALL bundle KaTeX as a static resource with no runtime NPM dependency.

#### Scenario: Offline rendering
- **WHEN** the application has no internet connection
- **THEN** math expressions still render correctly
- **AND** no external resources are fetched

#### Scenario: Resource loading
- **WHEN** a math expression needs rendering
- **THEN** the bundled KaTeX loads from app resources
- **AND** renders the equation locally

### Requirement: WebView Rendering
The application SHALL use WKWebView to render math expressions, keeping WebView usage minimal and efficient.

#### Scenario: Display math rendering
- **WHEN** a display math block (`$$...$$`) is encountered
- **THEN** a WKWebView renders the equation
- **AND** the equation displays centered with appropriate vertical spacing

#### Scenario: Inline math rendering
- **WHEN** inline math (`$...$`) is encountered
- **THEN** the equation renders inline with text flow
- **AND** baseline aligns with surrounding text

#### Scenario: Mixed content document
- **WHEN** a document contains text, code, mermaid diagrams, and math
- **THEN** each content type renders with its appropriate renderer
- **AND** all content flows together in scroll order

### Requirement: Supported LaTeX Features
The application SHALL support common LaTeX math notation as implemented by KaTeX.

#### Scenario: Greek letters
- **WHEN** LaTeX Greek letter commands appear (e.g., `\alpha`, `\epsilon`)
- **THEN** they render as proper Greek symbols

#### Scenario: Fractions
- **WHEN** `\frac{num}{denom}` appears
- **THEN** it renders as a properly formatted fraction

#### Scenario: Subscripts and superscripts
- **WHEN** `_{}` or `^{}` notation appears
- **THEN** content renders as subscript or superscript respectively

#### Scenario: Mathematical functions
- **WHEN** function commands appear (e.g., `\log`, `\sin`, `\text{}`)
- **THEN** they render with appropriate formatting

### Requirement: Theme Support
The application SHALL render math expressions with appropriate styling matching system appearance.

#### Scenario: Light mode math
- **WHEN** macOS is in light mode
- **THEN** equations render with dark text on transparent background

#### Scenario: Dark mode math
- **WHEN** macOS is in dark mode
- **THEN** equations render with light text on transparent background

#### Scenario: Appearance change
- **WHEN** user toggles system appearance
- **THEN** visible math expressions update to match new theme

### Requirement: Error Handling
The application SHALL gracefully handle LaTeX syntax errors without crashing.

#### Scenario: Invalid LaTeX syntax
- **WHEN** a math expression contains syntax errors
- **THEN** an error indicator displays in place of the rendered math
- **AND** the raw LaTeX source is accessible
- **AND** the rest of the document renders normally

#### Scenario: Unsupported LaTeX commands
- **WHEN** a LaTeX command is not supported by KaTeX
- **THEN** an appropriate error or fallback displays
- **AND** the document continues to render
