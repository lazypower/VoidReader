import Foundation
import SwiftUI

/// Represents a block of rendered markdown content.
/// This allows mixing AttributedString text with special block-level elements.
public enum MarkdownBlock: Identifiable {
    case text(AttributedString)
    case table(TableData)
    case taskList([TaskItem])
    case codeBlock(CodeBlockData)

    public var id: String {
        switch self {
        case .text(let str):
            return "text-\(str.hashValue)"
        case .table(let data):
            return "table-\(data.id)"
        case .taskList(let items):
            return "tasklist-\(items.map { $0.id.uuidString }.joined())"
        case .codeBlock(let data):
            return "code-\(data.id)"
        }
    }
}

/// Data for rendering a table.
public struct TableData: Identifiable {
    public let id = UUID()
    public var headers: [TableCell]
    public var rows: [[TableCell]]
    public var alignments: [TableAlignment]

    public init(headers: [TableCell], rows: [[TableCell]], alignments: [TableAlignment]) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
    }
}

/// A single table cell with rendered content.
public struct TableCell: Identifiable {
    public let id = UUID()
    public var content: AttributedString

    public init(content: AttributedString) {
        self.content = content
    }
}

/// Table column alignment.
public enum TableAlignment {
    case left
    case center
    case right

    public var textAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    public var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

/// A task list item with checkbox state.
public struct TaskItem: Identifiable {
    public let id = UUID()
    public var isChecked: Bool
    public var content: AttributedString

    public init(isChecked: Bool, content: AttributedString) {
        self.isChecked = isChecked
        self.content = content
    }
}

/// Data for a code block with language info.
public struct CodeBlockData: Identifiable {
    public let id = UUID()
    public var code: String
    public var language: String?

    public init(code: String, language: String?) {
        self.code = code
        self.language = language
    }
}
