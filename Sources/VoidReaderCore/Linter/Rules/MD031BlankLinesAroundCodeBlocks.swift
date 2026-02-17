import Foundation
import Markdown

/// MD031: Fenced code blocks should be surrounded by blank lines.
public struct MD031BlankLinesAroundCodeBlocks: LintRule {
    public let id = "MD031"
    public let description = "Code blocks should have blank lines around them"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []
        let lines = source.components(separatedBy: "\n")

        var walker = CodeBlockWalker()
        walker.visit(document)

        for codeBlock in walker.codeBlocks {
            guard let range = codeBlock.range else { continue }

            let startLine = range.lowerBound.line
            let endLine = range.upperBound.line

            // Check line before code block (if not first line)
            if startLine > 1 {
                let prevLine = lines[startLine - 2]
                if !prevLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    warnings.append(LintWarning(
                        line: startLine,
                        column: 1,
                        message: "Code block should have a blank line before it",
                        ruleID: id
                    ))
                }
            }

            // Check line after code block (if not last line)
            if endLine < lines.count {
                let nextLine = lines[endLine]
                if !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    warnings.append(LintWarning(
                        line: endLine,
                        column: 1,
                        message: "Code block should have a blank line after it",
                        ruleID: id
                    ))
                }
            }
        }

        return warnings
    }
}

private struct CodeBlockWalker: MarkupWalker {
    var codeBlocks: [CodeBlock] = []

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        codeBlocks.append(codeBlock)
    }
}
