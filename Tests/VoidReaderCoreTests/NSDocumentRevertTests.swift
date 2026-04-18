#if canImport(AppKit)
import Testing
import Foundation
import AppKit
@testable import VoidReaderCore

/// Tests the `NSDocument.revert(toContentsOf:ofType:)` contract we rely on to reload
/// a document from disk without marking it dirty.
///
/// This is the other half of the "reload from disk" fix: the FileWatcher wakes us up,
/// but the actual reload must go through NSDocument's revert path so SwiftUI's
/// DocumentGroup does not think the user edited the document.
@Suite("NSDocument Revert Contract")
@MainActor
struct NSDocumentRevertTests {

    /// Minimal NSDocument subclass that mirrors the shape of SwiftUI's internal
    /// document wrapper for a plain-text FileDocument. We are exercising the
    /// AppKit contract, not SwiftUI's bridge.
    final class PlainTextDocument: NSDocument {
        var text: String = ""

        override func read(from data: Data, ofType typeName: String) throws {
            text = String(data: data, encoding: .utf8) ?? ""
        }

        override func data(ofType typeName: String) throws -> Data {
            text.data(using: .utf8) ?? Data()
        }
    }

    private static func makeTempFile(contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader-revert-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("doc.md")
        try contents.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Revert clears the dirty flag and updates content from disk")
    func revertClearsDirtyFlagAndUpdatesContent() throws {
        let url = try Self.makeTempFile(contents: "original")
        defer { Self.cleanup(url) }

        let doc = PlainTextDocument()
        doc.fileURL = url
        doc.fileType = "public.plain-text"
        try doc.read(from: try Data(contentsOf: url), ofType: "public.plain-text")
        #expect(doc.text == "original")
        #expect(doc.isDocumentEdited == false)

        // Simulate a user edit in the buffer.
        doc.text = "user edit"
        doc.updateChangeCount(.changeDone)
        #expect(doc.isDocumentEdited == true, "Sanity: a user edit should mark the document dirty")

        // External change on disk.
        try "external write".write(to: url, atomically: false, encoding: .utf8)

        // This is the exact call site we use in reloadFromDisk().
        try doc.revert(toContentsOf: url, ofType: "public.plain-text")

        #expect(doc.isDocumentEdited == false, "Revert must clear the dirty flag")
        #expect(doc.text == "external write", "Revert must replace buffer content with on-disk content")
    }

    @Test("Revert on an unedited document is a no-op for the dirty flag")
    func revertOnCleanDocumentStaysClean() throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        let doc = PlainTextDocument()
        doc.fileURL = url
        doc.fileType = "public.plain-text"
        try doc.read(from: try Data(contentsOf: url), ofType: "public.plain-text")
        #expect(doc.isDocumentEdited == false)

        try "v2".write(to: url, atomically: false, encoding: .utf8)
        try doc.revert(toContentsOf: url, ofType: "public.plain-text")

        #expect(doc.isDocumentEdited == false)
        #expect(doc.text == "v2")
    }

    @Test("Revert preserves fileURL and fileType")
    func revertPreservesMetadata() throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        let doc = PlainTextDocument()
        doc.fileURL = url
        doc.fileType = "public.plain-text"
        try doc.read(from: try Data(contentsOf: url), ofType: "public.plain-text")

        try "v2".write(to: url, atomically: false, encoding: .utf8)
        try doc.revert(toContentsOf: url, ofType: "public.plain-text")

        #expect(doc.fileURL == url)
        #expect(doc.fileType == "public.plain-text")
    }
}
#endif
