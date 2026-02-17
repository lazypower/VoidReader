# Change: Add Image Support

## Why
VoidReader currently shows placeholder text for images instead of rendering them. READMEs and documentation are increasingly image-heavy (screenshots, diagrams, badges, logos). A markdown reader that can't display images is incomplete.

## What Changes
- Load and display local images (relative paths resolved from document location)
- Load and display remote images (http/https URLs)
- Cache remote images for performance
- Lazy load images as they scroll into view
- Constrain images to viewport width
- Support common formats: PNG, JPG, GIF, WebP, SVG (native rendering)
- Show alt text gracefully on load failure
- Optional click-to-expand for viewing full-size images

## Design Decisions
- **Lazy loading**: Better UX for large documents with many images
- **Remote caching**: Reduces network calls, keeps app responsive
- **Viewport-width max**: Images scale to fit, configurable parameter
- **SVG native**: Use NSImage for SVG (covers 99% of markdown use cases)
- **No WebView**: Images render natively, no heavyweight web components

## Impact
- Affected specs: image-support (new)
- Affected code: ImageBlockView, image loading utilities, cache layer
- Pattern: Native rendering with AsyncImage-style loading states
