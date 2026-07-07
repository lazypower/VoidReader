import SwiftUI
import VoidReaderCore

/// Renders a task list with interactive checkboxes.
struct TaskListView: View {
    let items: [TaskItem]
    var onToggle: ((UUID, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                        .foregroundColor(item.isChecked ? .accentColor : .secondary)
                        .font(.system(size: 16))
                        .onTapGesture {
                            // Identify the tapped item by its stable id, not its
                            // block-local index — ContentView maps the id to the
                            // correct document task slot.
                            onToggle?(item.id, !item.isChecked)
                        }

                    Text(item.content)
                        .strikethrough(item.isChecked)
                        .foregroundColor(item.isChecked ? .secondary : .primary)
                }
            }
        }
    }
}

#Preview {
    TaskListView(items: [
        TaskItem(isChecked: true, content: AttributedString("Completed task")),
        TaskItem(isChecked: false, content: AttributedString("Pending task")),
        TaskItem(isChecked: false, content: AttributedString("Another pending task"))
    ])
    .padding()
}
