import Testing
@testable import VoidReaderCore

@Suite("Markdown Text Utils Tests")
struct MarkdownTextUtilsTests {

    // MARK: - Basic toggling by ordinal

    @Test("Toggles unchecked task to checked")
    func toggleUncheckedToChecked() {
        let input = """
        - [ ] First task
        - [ ] Second task
        """
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 0, expectedChecked: false, to: true)
        #expect(result.contains("- [x] First task"))
        #expect(result.contains("- [ ] Second task"))
    }

    @Test("Toggles checked task to unchecked")
    func toggleCheckedToUnchecked() {
        let input = """
        - [x] First task
        - [x] Second task
        """
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 1, expectedChecked: true, to: false)
        #expect(result.contains("- [x] First task"))
        #expect(result.contains("- [ ] Second task"))
    }

    @Test("Handles uppercase X")
    func handlesUppercaseX() {
        let input = "- [X] Task with uppercase"
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 0, expectedChecked: true, to: false)
        #expect(result.contains("- [ ] Task with uppercase"))
    }

    // MARK: - The three §2.3 bugs

    @Test("Star and plus markers toggle the correct item (marker-agnostic)")
    func markerAgnosticToggle() {
        let input = """
        * [ ] Star task
        + [ ] Plus task
        """
        let starChecked = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 0, expectedChecked: false, to: true)
        #expect(starChecked.contains("* [x] Star task"))
        #expect(starChecked.contains("+ [ ] Plus task"))

        let plusChecked = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 1, expectedChecked: false, to: true)
        #expect(plusChecked.contains("* [ ] Star task"))
        #expect(plusChecked.contains("+ [x] Plus task"))
    }

    @Test("Second task list toggles its own item, not the first list's")
    func multipleTaskListsUseGlobalOrdinal() {
        let input = """
        - [ ] List one item A
        - [ ] List one item B

        Some prose in between.

        - [ ] List two item A
        - [ ] List two item B
        """
        // Ordinal 2 is the first item of the SECOND list.
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 2, expectedChecked: false, to: true)
        #expect(result.contains("- [x] List two item A"))
        // Nothing in the first list changed.
        #expect(result.contains("- [ ] List one item A"))
        #expect(result.contains("- [ ] List one item B"))
    }

    @Test("Fenced task-looking lines are not counted or toggled")
    func fenceBlindnessFixed() {
        let input = """
        - [ ] Real task before

        ```markdown
        - [ ] This is documentation, not a task
        - [ ] Neither is this
        ```

        - [ ] Real task after
        """
        // Only two real tasks exist; ordinal 1 is "Real task after".
        #expect(MarkdownTextUtils.taskCount(in: input) == 2)

        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 1, expectedChecked: false, to: true)
        #expect(result.contains("- [x] Real task after"))
        // The fenced sample lines are untouched.
        #expect(result.contains("- [ ] This is documentation, not a task"))
        #expect(result.contains("- [ ] Neither is this"))
    }

    // MARK: - Drift guard

    @Test("Refuses to toggle when the expected state no longer matches")
    func staleExpectedStateRefused() {
        let input = "- [x] Already checked"
        // Caller thinks it is unchecked — stale. Toggle must be refused.
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 0, expectedChecked: false, to: true)
        #expect(result == input)
    }

    @Test("Returns original text if ordinal out of bounds")
    func outOfBoundsReturnsOriginal() {
        let input = "- [ ] Only one task"
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 5, expectedChecked: false, to: true)
        #expect(result == input)
    }

    @Test("Preserves surrounding content")
    func preservesNonTaskContent() {
        let input = """
        # Heading

        Some paragraph.

        - [ ] A task

        More text.
        """
        let result = MarkdownTextUtils.toggleTask(in: input, taskOrdinal: 0, expectedChecked: false, to: true)
        #expect(result.contains("# Heading"))
        #expect(result.contains("Some paragraph."))
        #expect(result.contains("- [x] A task"))
        #expect(result.contains("More text."))
    }

    // MARK: - Counting

    @Test("Counts checkbox items, ignoring regular siblings")
    func countsTasksCorrectly() {
        let input = """
        - [ ] Task 1
        - [x] Task 2
        - Regular list item
        - [ ] Task 3
        """
        #expect(MarkdownTextUtils.taskCount(in: input) == 3)
    }

    @Test("Counts zero tasks in non-task content")
    func countsZeroTasks() {
        let input = """
        # Just a heading

        - Regular list
        - Another item
        """
        #expect(MarkdownTextUtils.taskCount(in: input) == 0)
    }

    @Test("Task slots record source lines in document order")
    func taskSlotsRecordSourceLines() {
        let input = """
        Intro paragraph.

        - [ ] First
        - [x] Second
        """
        let slots = MarkdownTextUtils.taskSlots(in: input)
        #expect(slots.count == 2)
        #expect(slots[0].line == 3)
        #expect(slots[0].isChecked == false)
        #expect(slots[1].line == 4)
        #expect(slots[1].isChecked == true)
    }
}
