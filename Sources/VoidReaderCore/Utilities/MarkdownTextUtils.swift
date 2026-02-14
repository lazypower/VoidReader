import Foundation

/// Utilities for manipulating markdown source text.
public enum MarkdownTextUtils {

    /// Pattern matching task list items: `- [ ]` or `- [x]` (case insensitive for x)
    private static let taskPattern = #/^(\s*-\s*)\[([ xX])\]/#

    /// Toggles the checkbox state of the task at the given index.
    /// - Parameters:
    ///   - text: The markdown source text
    ///   - index: The zero-based index of the task to toggle
    ///   - newState: The new checked state
    /// - Returns: The modified text, or the original if the task wasn't found
    public static func toggleTask(in text: String, at index: Int, to newState: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        var taskCount = 0

        for i in 0..<lines.count {
            let line = lines[i]

            // Check if this line is a task item
            if let match = line.firstMatch(of: taskPattern) {
                if taskCount == index {
                    // This is the task we want to toggle
                    let prefix = String(match.output.1)
                    let newCheckbox = newState ? "[x]" : "[ ]"
                    let rest = String(line[match.range.upperBound...])
                    lines[i] = prefix + newCheckbox + rest
                    break
                }
                taskCount += 1
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Counts the number of task list items in the text.
    public static func taskCount(in text: String) -> Int {
        text.components(separatedBy: "\n")
            .filter { $0.firstMatch(of: taskPattern) != nil }
            .count
    }
}
