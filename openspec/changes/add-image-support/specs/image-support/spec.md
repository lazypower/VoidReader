# Image Support

This capability defines how VoidReader loads and displays images in markdown documents.

## ADDED Requirements

### Requirement: Local Image Loading
The application SHALL load and display images from local file paths relative to the document location.

#### Scenario: Relative path resolution
- **WHEN** an image references `./images/screenshot.png`
- **AND** the document is at `/Users/chuck/docs/README.md`
- **THEN** the image loads from `/Users/chuck/docs/images/screenshot.png`

#### Scenario: Parent directory reference
- **WHEN** an image references `../assets/logo.png`
- **AND** the document is at `/Users/chuck/docs/guide/intro.md`
- **THEN** the image loads from `/Users/chuck/docs/assets/logo.png`

#### Scenario: Absolute path
- **WHEN** an image references `/Users/chuck/images/photo.jpg`
- **THEN** the image loads from that absolute path directly

### Requirement: Remote Image Loading
The application SHALL load and display images from http/https URLs.

#### Scenario: HTTPS image
- **WHEN** an image references `https://example.com/logo.png`
- **THEN** the image is fetched and displayed

#### Scenario: Loading state
- **WHEN** a remote image is being fetched
- **THEN** a loading indicator displays in place of the image

### Requirement: Image Caching
The application SHALL cache remote images to improve performance and reduce network usage.

#### Scenario: Cache hit
- **WHEN** a previously loaded remote image is encountered
- **THEN** the cached version displays immediately
- **AND** no network request is made

#### Scenario: Cache location
- **WHEN** remote images are cached
- **THEN** they are stored in `~/Library/Caches/VoidReader/images/`

#### Scenario: Cache expiration
- **WHEN** a cached image is older than 24 hours
- **THEN** it is re-fetched on next load

### Requirement: Lazy Loading
The application SHALL defer image loading until images are about to become visible.

#### Scenario: Below-fold images
- **WHEN** a document contains images below the visible viewport
- **THEN** those images do not load until scrolled into view

#### Scenario: Scroll into view
- **WHEN** user scrolls and an image approaches the viewport
- **THEN** the image begins loading before becoming fully visible

### Requirement: Image Display
The application SHALL display images constrained to the viewport width while maintaining aspect ratio.

#### Scenario: Wide image
- **WHEN** an image is wider than the viewport
- **THEN** it scales down to fit viewport width
- **AND** height scales proportionally to maintain aspect ratio

#### Scenario: Narrow image
- **WHEN** an image is narrower than the viewport
- **THEN** it displays at its natural size
- **AND** is not stretched to fill width

#### Scenario: Alt text on failure
- **WHEN** an image fails to load (missing file, network error)
- **THEN** the alt text displays in place of the image
- **AND** a visual indicator shows it's a failed image

#### Scenario: Title tooltip
- **WHEN** an image has a title attribute
- **THEN** the title displays as a tooltip on hover

### Requirement: Format Support
The application SHALL support common image formats.

#### Scenario: Standard formats
- **WHEN** an image is PNG, JPG, or GIF format
- **THEN** it loads and displays correctly

#### Scenario: WebP format
- **WHEN** an image is WebP format
- **THEN** it loads and displays correctly

#### Scenario: SVG format
- **WHEN** an image is SVG format
- **THEN** it renders natively via NSImage
- **AND** scales without quality loss

### Requirement: Click-to-Expand
The application SHALL allow users to view images at full size.

#### Scenario: Expand button
- **WHEN** user hovers over an image
- **THEN** an expand button appears

#### Scenario: Expanded view
- **WHEN** user clicks the expand button
- **THEN** the image displays in a full-window overlay
- **AND** user can zoom and pan

#### Scenario: Dismiss expanded view
- **WHEN** user clicks outside the image or presses Escape
- **THEN** the expanded view closes

### Requirement: Unsaved Document Handling
The application SHALL handle images in documents that have not been saved to disk.

#### Scenario: New document with relative image
- **WHEN** a document has not been saved
- **AND** contains a relative image path
- **THEN** a placeholder displays indicating the document must be saved
- **OR** the relative path cannot be resolved
