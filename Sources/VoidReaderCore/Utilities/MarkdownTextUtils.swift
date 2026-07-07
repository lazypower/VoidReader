import Foundation
import Markdown

/// Utilities for manipulating markdown source text.
public enum MarkdownTextUtils {

    /// One task-list slot as the reader renders it: the 1-based source line of
    /// the list item and whether it currently carries a checkbox.
    ///
    /// Slots come from the parsed AST, which makes them fence-aware (a `- [ ]`
    /// line inside a code fence is code, never a list item) and marker-agnostic
    /// (`-`, `*`, and `+` all count). Enumeration mirrors BlockRenderer's rule:
    /// an unordered list where *any* item has a checkbox is a task list, and
    /// *every* one of its direct items becomes a slot.
    struct TaskSlot: Equatable {
        let line: Int
        let isChecked: Bool
        let hasCheckbox: Bool
    }

    /// Enumerates every task slot in `text`, in document order.
    static func taskSlots(in text: String) -> [TaskSlot] {
        var slots: [TaskSlot] = []
        collectTaskSlots(from: MarkdownParser.parse(text), into: &slots)
        return slots
    }

    /// Toggles the checkbox of the task slot at `ordinal` — its position among
    /// all task slots in document order, which is exactly the order the reader
    /// renders them. This replaces the old marker-counting toggle, which used a
    /// block-local index against a document-wide, `-`-only, fence-blind count
    /// and so toggled the wrong line whenever a document had more than one task
    /// list, used `*`/`+` markers, or contained a fenced `- [ ]` line.
    ///
    /// `expectedChecked` is the slot's state as the caller last saw it. If the
    /// freshly parsed slot disagrees — a sign the ordinal has drifted — the edit
    /// is refused rather than risk flipping the wrong line.
    /// - Returns: the modified text, or the original when the slot cannot be
    ///   confidently identified.
    public static func toggleTask(
        in text: String,
        taskOrdinal ordinal: Int,
        expectedChecked: Bool,
        to newState: Bool
    ) -> String {
        let slots = taskSlots(in: text)
        guard ordinal >= 0, ordinal < slots.count else { return text }

        let slot = slots[ordinal]
        guard slot.hasCheckbox, slot.isChecked == expectedChecked else { return text }

        var lines = text.components(separatedBy: "\n")
        let lineIndex = slot.line - 1
        guard lineIndex >= 0, lineIndex < lines.count else { return text }

        lines[lineIndex] = setCheckbox(on: lines[lineIndex], to: newState)
        return lines.joined(separator: "\n")
    }

    /// Number of checkbox task items in the text (fence-aware, marker-agnostic).
    public static func taskCount(in text: String) -> Int {
        taskSlots(in: text).filter { $0.hasCheckbox }.count
    }

    // MARK: - Private

    private static func collectTaskSlots(from markup: Markup, into slots: inout [TaskSlot]) {
        for child in markup.children {
            if let list = child as? UnorderedList,
               list.listItems.contains(where: { $0.checkbox != nil }) {
                // Task list — each direct item is a slot. Nested content is not
                // rendered as further task slots, matching BlockRenderer, so we
                // do not recurse into these items.
                for item in list.listItems {
                    guard let line = item.range?.lowerBound.line else { continue }
                    slots.append(TaskSlot(
                        line: line,
                        isChecked: item.checkbox == .checked,
                        hasCheckbox: item.checkbox != nil
                    ))
                }
            } else {
                collectTaskSlots(from: child, into: &slots)
            }
        }
    }

    /// Flips the checkbox token on a single task line, preserving the marker
    /// (`-`, `*`, `+`, or an ordered `1.`/`1)`), indentation, and any trailing CR.
    private static func setCheckbox(on line: String, to checked: Bool) -> String {
        guard let range = line.range(of: #"\[[ xX]\]"#, options: .regularExpression) else {
            return line
        }
        // Confirm the bracket token is the leading checkbox — only a list marker
        // and whitespace precede it — not a bracket in the item's content.
        let prefix = line[line.startIndex..<range.lowerBound]
        guard prefix.range(of: #"^\s*(?:[-*+]|\d+[.)])\s+$"#, options: .regularExpression) != nil else {
            return line
        }
        return line.replacingCharacters(in: range, with: checked ? "[x]" : "[ ]")
    }
}
