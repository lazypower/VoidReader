import SwiftUI

/// A horizontal split view with a draggable divider and persistent position.
struct ResizableSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    @Binding var leftFraction: CGFloat
    let minLeftFraction: CGFloat
    let maxLeftFraction: CGFloat

    /// The divider fraction captured at the start of a drag. `DragGesture`
    /// reports translation cumulatively from the drag's start, so we must add it
    /// to the *start* fraction — adding it to the already-updated `leftFraction`
    /// each tick double-counts and makes the divider accelerate away.
    @State private var dragStartFraction: CGFloat?

    init(
        leftFraction: Binding<CGFloat>,
        minLeftFraction: CGFloat = 0.2,
        maxLeftFraction: CGFloat = 0.8,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self._leftFraction = leftFraction
        self.minLeftFraction = minLeftFraction
        self.maxLeftFraction = maxLeftFraction
        self.left = left()
        self.right = right()
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                left
                    .frame(width: geo.size.width * leftFraction)

                // Draggable divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .overlay(
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .cursor(.resizeLeftRight)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let start = dragStartFraction ?? leftFraction
                                if dragStartFraction == nil { dragStartFraction = start }
                                let newFraction = (geo.size.width * start + value.translation.width) / geo.size.width
                                leftFraction = min(max(newFraction, minLeftFraction), maxLeftFraction)
                            }
                            .onEnded { _ in
                                dragStartFraction = nil
                            }
                    )

                right
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Cursor Modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursor(cursor: cursor))
    }
}

/// Pushes a cursor while hovered and always balances the pop — including when
/// the view disappears mid-hover, which the bare `onHover` push/pop leaked,
/// leaving the resize cursor stuck.
private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, !pushed {
                    cursor.push()
                    pushed = true
                } else if !hovering, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

#Preview {
    @Previewable @State var fraction: CGFloat = 0.5

    ResizableSplitView(leftFraction: $fraction) {
        Color.blue.opacity(0.3)
            .overlay(Text("Left"))
    } right: {
        Color.green.opacity(0.3)
            .overlay(Text("Right"))
    }
    .frame(width: 600, height: 400)
}
