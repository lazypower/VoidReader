# Tasks: Add Image Support

## 1. Image URL Resolution
- [x] 1.1 Resolve relative paths from document directory
- [x] 1.2 Handle absolute file:// URLs
- [x] 1.3 Handle http/https remote URLs
- [x] 1.4 Normalize path handling (../, ./, spaces, encoded characters)

## 2. Image Loading
- [x] 2.1 Create ImageLoader utility with async loading
- [x] 2.2 Support PNG, JPG, GIF formats via NSImage
- [x] 2.3 Support WebP format
- [x] 2.4 Support SVG format (native NSImage rendering)
- [x] 2.5 Implement lazy loading (load when scrolled into view)

## 3. Remote Image Caching
- [x] 3.1 Create ImageCache with disk-backed storage
- [x] 3.2 Cache remote images after first fetch
- [x] 3.3 Implement cache expiration policy (24h default)
- [x] 3.4 Handle cache size limits (disk) - 100MB max, FIFO eviction
- [x] 3.5 Cache location: ~/Library/Caches/VoidReader/images/

## 4. Image Display
- [x] 4.1 Rewrite ImageBlockView for actual image rendering
- [x] 4.2 Show loading state while fetching
- [x] 4.3 Constrain max width to viewport
- [x] 4.4 Maintain aspect ratio on resize
- [x] 4.5 Display alt text on load failure
- [x] 4.6 Support optional title as tooltip

## 5. Click-to-Expand
- [x] 5.1 Add expand button on hover (like Mermaid)
- [x] 5.2 Create ImageExpandedOverlay for full-size view
- [x] 5.3 Support zoom/pan in expanded view
- [x] 5.4 Dismiss on click outside or Escape

## 6. Integration
- [x] 6.1 Pass document URL to renderer for path resolution
- [x] 6.2 Update ContentView to provide document context
- [x] 6.3 Handle documents without saved location (new/unsaved)

## 7. Quick Look Support
- [x] 7.1 Update QuickLookBlockView for basic image display
- [x] 7.2 Handle local images in Quick Look context
- [x] 7.3 Graceful fallback for remote images in Quick Look

## 8. Testing
- [x] 8.1 Test local image loading - unit tests for path resolution + VIBE_CHECK.md
- [x] 8.2 Test remote image loading - VIBE_CHECK.md uses picsum.photos
- [x] 8.3 Test cache behavior - unit tests for cache key generation
- [x] 8.4 Test failure states - visual verification (alt text displays on failure)
- [x] 8.5 Test format support - VIBE_CHECK.md exercises PNG; other formats verified manually
