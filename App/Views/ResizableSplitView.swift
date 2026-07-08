import SwiftUI

/// A horizontal split view with a draggable divider and persistent position.
struct ResizableSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    @Binding var leftFraction: CGFloat
    let minLeftFraction: CGFloat
    let maxLeftFraction: CGFloat

    /// Fixed coordinate space the divider drag is measured in.
    private static var coordinateSpace: String { "ResizableSplitView" }

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
                        // Track the cursor's ABSOLUTE x in the fixed container
                        // coordinate space, not translation in the divider's own
                        // (moving) space. As the divider moves with leftFraction,
                        // a local/translation gesture re-references itself every
                        // tick — that feedback is what made the divider shudder and
                        // snap to the clamp edges. Absolute position doesn't feed back.
                        DragGesture(coordinateSpace: .named(Self.coordinateSpace))
                            .onChanged { value in
                                let fraction = value.location.x / geo.size.width
                                leftFraction = min(max(fraction, minLeftFraction), maxLeftFraction)
                            }
                    )

                right
                    .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: Self.coordinateSpace)
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
