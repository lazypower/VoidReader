## ADDED Requirements

### Requirement: Large Code Block Segmentation
The application SHALL render code blocks of arbitrary size by splitting
them into multiple rendered segments when the block exceeds a line-count
threshold, presenting the segments as a single continuous visual block.
Segmentation MUST NOT change what the user sees relative to a non-segmented
code block of equivalent appearance: one language badge, one copy button,
one continuous background, and no visible seams between segments.

#### Scenario: Short code block renders as one segment
- **WHEN** a fenced code block contains fewer lines than the segmentation threshold
- **THEN** the block renders as a single row with language badge, copy button, and full syntax highlighting

#### Scenario: Very large code block renders as multiple segments
- **WHEN** a fenced code block contains more lines than the segmentation threshold
- **THEN** the block is rendered as N adjacent rows sharing a group identity
- **AND** the first row shows the language badge and copy button
- **AND** subsequent rows show no badge or copy button
- **AND** the rows render with a shared continuous background and no visible seams between them

#### Scenario: Outer scroll stays healthy with a very large code block
- **WHEN** the user opens a document whose code block exceeds the per-segment height ceiling
- **THEN** mouse-wheel, trackpad, scroll-bar drag, and keyboard scroll on the outer document SHALL all remain responsive

#### Scenario: Copy copies the entire block
- **WHEN** the user clicks the copy button on a segmented code block
- **THEN** the clipboard receives the full original unsegmented code

#### Scenario: Scroll percentage tracks the segmented block accurately
- **WHEN** the user scrolls through a document containing a segmented code block
- **THEN** the displayed scroll percentage advances monotonically from 0% at the top to 100% at the bottom
- **AND** the percentage reflects the cumulative rendered height of all segments, not a truncated or capped height
