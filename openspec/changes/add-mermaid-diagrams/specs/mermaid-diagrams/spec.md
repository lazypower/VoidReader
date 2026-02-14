# Mermaid Diagrams

This capability defines how VoidReader renders Mermaid diagrams using a bundled JavaScript library in WKWebView.

## ADDED Requirements

### Requirement: Mermaid Block Detection
The application SHALL detect fenced code blocks with `mermaid` language identifier and render them as diagrams.

#### Scenario: Mermaid block identification
- **WHEN** a code block begins with ` ```mermaid `
- **THEN** the block is identified as a mermaid diagram
- **AND** is rendered using the mermaid renderer instead of as code

#### Scenario: Non-mermaid code blocks
- **WHEN** a code block has any other language identifier
- **THEN** it renders as a normal code block
- **AND** is not processed by the mermaid renderer

### Requirement: Bundled Mermaid Library
The application SHALL bundle mermaid.min.js as a static resource with no runtime Node.js or NPM dependency.

#### Scenario: Offline rendering
- **WHEN** the application has no internet connection
- **THEN** mermaid diagrams still render correctly
- **AND** no external resources are fetched

#### Scenario: Resource loading
- **WHEN** a mermaid block needs rendering
- **THEN** the bundled mermaid.min.js loads from app resources
- **AND** renders the diagram locally

### Requirement: WebView Rendering
The application SHALL use WKWebView to render mermaid diagrams, keeping WebView usage isolated to diagram blocks only.

#### Scenario: Diagram rendering
- **WHEN** a mermaid block is displayed
- **THEN** a WKWebView renders the diagram
- **AND** the WebView sizes to fit the rendered content

#### Scenario: Mixed content document
- **WHEN** a document contains both text and mermaid diagrams
- **THEN** text renders natively with AttributedString
- **AND** only mermaid blocks use WebView
- **AND** all content flows together in scroll order

### Requirement: Supported Diagram Types
The application SHALL support common mermaid diagram types including flowchart, sequence, class, state, and gantt.

#### Scenario: Flowchart rendering
- **WHEN** a mermaid block contains flowchart syntax
- **THEN** nodes and edges render as a flowchart diagram

#### Scenario: Sequence diagram rendering
- **WHEN** a mermaid block contains sequenceDiagram syntax
- **THEN** participants and messages render as a sequence diagram

#### Scenario: Class diagram rendering
- **WHEN** a mermaid block contains classDiagram syntax
- **THEN** classes and relationships render as a class diagram

### Requirement: Theme Support
The application SHALL render mermaid diagrams with appropriate theme matching system appearance.

#### Scenario: Light mode diagram
- **WHEN** macOS is in light mode
- **THEN** diagrams render with light background and dark lines/text

#### Scenario: Dark mode diagram
- **WHEN** macOS is in dark mode
- **THEN** diagrams render with dark background and light lines/text

#### Scenario: Appearance change
- **WHEN** user toggles system appearance
- **THEN** visible diagrams re-render with updated theme

### Requirement: Error Handling
The application SHALL gracefully handle mermaid syntax errors without crashing.

#### Scenario: Invalid mermaid syntax
- **WHEN** a mermaid block contains syntax errors
- **THEN** an error message displays in place of the diagram
- **AND** the raw mermaid source is accessible
- **AND** the rest of the document renders normally

#### Scenario: Render timeout
- **WHEN** mermaid rendering takes longer than 5 seconds
- **THEN** the render is cancelled
- **AND** a timeout error is displayed
