import XCTest
@testable import VoidReaderCore

final class ImageLoaderTests: XCTestCase {

    // MARK: - Path Resolution Tests

    func testAbsoluteHTTPURL() {
        let source = "https://example.com/image.png"
        let resolved = resolveImageURL(source: source, documentURL: nil)
        XCTAssertEqual(resolved?.absoluteString, "https://example.com/image.png")
    }

    func testAbsoluteHTTPSURL() {
        let source = "https://example.com/image.png"
        let resolved = resolveImageURL(source: source, documentURL: nil)
        XCTAssertEqual(resolved?.absoluteString, "https://example.com/image.png")
    }

    func testAbsoluteFileURL() {
        let source = "file:///Users/test/image.png"
        let resolved = resolveImageURL(source: source, documentURL: nil)
        XCTAssertEqual(resolved?.absoluteString, "file:///Users/test/image.png")
    }

    func testAbsoluteFilePath() {
        let source = "/Users/test/image.png"
        let resolved = resolveImageURL(source: source, documentURL: nil)
        XCTAssertEqual(resolved?.path, "/Users/test/image.png")
    }

    func testRelativePathWithDocument() {
        let source = "images/photo.png"
        let docURL = URL(fileURLWithPath: "/Users/test/docs/README.md")
        let resolved = resolveImageURL(source: source, documentURL: docURL)
        XCTAssertEqual(resolved?.path, "/Users/test/docs/images/photo.png")
    }

    func testRelativePathWithParentDir() {
        let source = "../assets/photo.png"
        let docURL = URL(fileURLWithPath: "/Users/test/docs/README.md")
        let resolved = resolveImageURL(source: source, documentURL: docURL)
        XCTAssertEqual(resolved?.path, "/Users/test/assets/photo.png")
    }

    func testRelativePathWithCurrentDir() {
        let source = "./photo.png"
        let docURL = URL(fileURLWithPath: "/Users/test/docs/README.md")
        let resolved = resolveImageURL(source: source, documentURL: docURL)
        XCTAssertEqual(resolved?.path, "/Users/test/docs/photo.png")
    }

    func testRelativePathWithoutDocument() {
        let source = "images/photo.png"
        let resolved = resolveImageURL(source: source, documentURL: nil)
        XCTAssertNil(resolved, "Relative path without document context should return nil")
    }

    func testSiblingFile() {
        let source = "sibling.png"
        let docURL = URL(fileURLWithPath: "/Users/test/docs/README.md")
        let resolved = resolveImageURL(source: source, documentURL: docURL)
        XCTAssertEqual(resolved?.path, "/Users/test/docs/sibling.png")
    }

    func testDeepNestedRelativePath() {
        let source = "../../other/assets/deep/image.png"
        let docURL = URL(fileURLWithPath: "/Users/test/project/docs/guide/README.md")
        let resolved = resolveImageURL(source: source, documentURL: docURL)
        XCTAssertEqual(resolved?.path, "/Users/test/project/other/assets/deep/image.png")
    }

    // MARK: - Helper (mirrors ImageLoader logic)

    private func resolveImageURL(source: String, documentURL: URL?) -> URL? {
        // Try as absolute URL first (http://, https://, file://)
        if let url = URL(string: source), url.scheme != nil {
            return url
        }

        // Try as absolute file path
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        // Resolve relative to document
        guard let docURL = documentURL else {
            return nil
        }

        let documentDirectory = docURL.deletingLastPathComponent()
        let resolved = documentDirectory.appendingPathComponent(source).standardized
        return resolved
    }
}

// MARK: - Cache Tests

final class ImageCacheTests: XCTestCase {

    func testCacheKeyGeneration() {
        // Cache keys should be filesystem-safe.
        let key = ImageCache.diskFileName(for: "https://example.com/path/to/image.png?query=1&other=2")
        XCTAssertFalse(key.contains("/"), "Cache key should not contain slashes")
        XCTAssertFalse(key.contains("?"), "Cache key should not contain query chars")
        XCTAssertTrue(key.hasSuffix(".png"), "Cache key should have .png extension")
    }

    func testCacheKeyDeterministic() {
        XCTAssertEqual(
            ImageCache.diskFileName(for: "https://example.com/image.png"),
            ImageCache.diskFileName(for: "https://example.com/image.png")
        )
    }

    func testCacheKeyUnique() {
        XCTAssertNotEqual(
            ImageCache.diskFileName(for: "https://example.com/image1.png"),
            ImageCache.diskFileName(for: "https://example.com/image2.png")
        )
    }

    func testCacheKeyNoCollisionForLongURLsDifferingAtEnd() {
        // The old base64(url).prefix(64) truncation collided when URLs shared a
        // long prefix and differed only near the end (common for CDN paths).
        let base = String(repeating: "a", count: 200)
        let k1 = ImageCache.diskFileName(for: "https://cdn.example.com/\(base)/one.png")
        let k2 = ImageCache.diskFileName(for: "https://cdn.example.com/\(base)/two.png")
        XCTAssertNotEqual(k1, k2, "Long URLs differing only at the end must not collide")
    }
}
