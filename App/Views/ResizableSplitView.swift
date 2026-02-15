import SwiftUI

/// A horizontal split view with a draggable divider and persistent position.
struct ResizableSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    @Binding var leftFraction: CGFloat
    let minLeftFraction: CGFloat
    let maxLeftFraction: CGFloat

    @State private var isDragging = false

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
                                isDragging = true
                                let newFraction = (geo.size.width * leftFraction + value.translation.width) / geo.size.width
                                leftFraction = min(max(newFraction, minLeftFraction), maxLeftFraction)
                            }
                            .onEnded { _ in
                                isDragging = false
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
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
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
