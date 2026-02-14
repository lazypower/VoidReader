import Testing
@testable import VoidReaderCore

@Suite("Markdown Text Utils Tests")
struct MarkdownTextUtilsTests {

    @Test("Toggles unchecked task to checked")
    func toggleUncheckedToChecked() {
        let input = """
        - [ ] First task
        - [ ] Second task
        """
        let result = MarkdownTextUtils.toggleTask(in: input, at: 0, to: true)
        #expect(result.contains("- [x] First task"))
        #expect(result.contains("- [ ] Second task"))
    }

    @Test("Toggles checked task to unchecked")
    func toggleCheckedToUnchecked() {
        let input = """
        - [x] First task
        - [x] Second task
        """
        let result = MarkdownTextUtils.toggleTask(in: input, at: 1, to: false)
        #expect(result.contains("- [x] First task"))
        #expect(result.contains("- [ ] Second task"))
    }

    @Test("Toggles task with indentation")
    func toggleIndentedTask() {
        let input = """
        - [x] Parent
          - [ ] Child task
        """
        let result = MarkdownTextUtils.toggleTask(in: input, at: 1, to: true)
        #expect(result.contains("  - [x] Child task"))
    }

    @Test("Handles uppercase X")
    func handlesUppercaseX() {
        let input = "- [X] Task with uppercase"
        let result = MarkdownTextUtils.toggleTask(in: input, at: 0, to: false)
        #expect(result.contains("- [ ] Task with uppercase"))
    }

    @Test("Preserves non-task content")
    func preservesNonTaskContent() {
        let input = """
        # Heading

        Some paragraph.

        - [ ] A task

        More text.
        """
        let result = MarkdownTextUtils.toggleTask(in: input, at: 0, to: true)
        #expect(result.contains("# Heading"))
        #expect(result.contains("Some paragraph."))
        #expect(result.contains("- [x] A task"))
        #expect(result.contains("More text."))
    }

    @Test("Returns original text if index out of bounds")
    func outOfBoundsReturnsOriginal() {
        let input = "- [ ] Only one task"
        let result = MarkdownTextUtils.toggleTask(in: input, at: 5, to: true)
        #expect(result == input)
    }

    @Test("Counts tasks correctly")
    func countsTasksCorrectly() {
        let input = """
        - [ ] Task 1
        - [x] Task 2
        - Regular list item
        - [ ] Task 3
        """
        let count = MarkdownTextUtils.taskCount(in: input)
        #expect(count == 3)
    }

    @Test("Counts zero tasks in non-task content")
    func countsZeroTasks() {
        let input = """
        # Just a heading

        - Regular list
        - Another item
        """
        let count = MarkdownTextUtils.taskCount(in: input)
        #expect(count == 0)
    }
}
