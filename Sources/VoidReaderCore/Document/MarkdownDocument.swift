import SwiftUI
import UniformTypeIdentifiers

/// Represents a markdown document that can be opened, edited, and saved.
public struct MarkdownDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        [.plainText, UTType(filenameExtension: "md") ?? .plainText]
    }

    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
