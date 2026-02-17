import SwiftUI
import VoidReaderCore

/// Data passed when expanding an image.
struct ExpandedImageData: Equatable {
    let image: NSImage
    let altText: String

    static func == (lhs: ExpandedImageData, rhs: ExpandedImageData) -> Bool {
        lhs.image === rhs.image && lhs.altText == rhs.altText
    }
}

/// Environment key for image expansion handler.
private struct ImageExpansionKey: EnvironmentKey {
    static let defaultValue: ((ExpandedImageData) -> Void)? = nil
}

extension EnvironmentValues {
    var onImageExpand: ((ExpandedImageData) -> Void)? {
        get { self[ImageExpansionKey.self] }
        set { self[ImageExpansionKey.self] = newValue }
    }
}

/// Renders an image with async loading, caching, and zoom capability.
struct ImageBlockView: View {
    let data: ImageData
    let documentURL: URL?
    var maxWidth: CGFloat? = nil  // nil = use viewport width

    @Environment(\.onImageExpand) private var onExpand
    @State private var loadedImage: NSImage?
    @State private var isLoading = true
    @State private var isHovering = false

    var body: some View {
        Group {
            if let image = loadedImage {
                imageContent(image)
            } else if isLoading {
                loadingView
            } else {
                errorView
            }
        }
        .task(id: data.source) {
            await loadImage()
        }
    }

    @ViewBuilder
    private func imageContent(_ image: NSImage) -> some View {
        let imageSize = image.size

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let constrainedWidth = maxWidth ?? geo.size.width
                let scale = min(1.0, constrainedWidth / imageSize.width)
                let displayWidth = imageSize.width * scale
                let displayHeight = imageSize.height * scale

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayWidth, height: displayHeight)
                    .cornerRadius(6)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            onExpand?(ExpandedImageData(image: image, altText: data.altText))
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.black.opacity(0.6))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .opacity(isHovering ? 1 : 0)
                    }
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                    .onTapGesture(count: 2) {
                        onExpand?(ExpandedImageData(image: image, altText: data.altText))
                    }
                    .help(data.title ?? "Double-click to expand")
                    .onHover { hovering in
                        isHovering = hovering
                    }
            }
            .frame(height: calculateDisplayHeight(for: image))

            // Caption (alt text)
            if !data.altText.isEmpty {
                Text(data.altText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func calculateDisplayHeight(for image: NSImage) -> CGFloat {
        let imageSize = image.size
        // Estimate based on typical viewport width if we don't have geometry yet
        let estimatedWidth: CGFloat = maxWidth ?? 700
        let scale = min(1.0, estimatedWidth / imageSize.width)
        return imageSize.height * scale
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading image...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 60)
        .padding()
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
        .cornerRadius(6)
    }

    private var errorView: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title3)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(data.altText.isEmpty ? "Failed to load image" : data.altText)
                    .font(.callout)
                    .foregroundColor(.primary)
                Text(data.source)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
        .cornerRadius(6)
    }

    private func loadImage() async {
        isLoading = true
        loadedImage = nil

        let image = await ImageLoader.shared.loadImage(
            source: data.source,
            documentURL: documentURL
        )

        await MainActor.run {
            self.loadedImage = image
            self.isLoading = false
        }
    }
}

/// Full-window overlay for viewing images at full size.
struct ImageExpandedOverlay: View {
    let image: NSImage
    let altText: String
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }

                // Image with pan/zoom
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(0.5, min(5.0, value))
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .frame(maxWidth: geo.size.width * 0.9, maxHeight: geo.size.height * 0.9)

                // Controls overlay
                VStack {
                    // Top bar
                    HStack {
                        // Reset zoom button
                        if scale != 1.0 || offset != .zero {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Text("Pinch to zoom • Drag to pan")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        // Close button
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()

                    Spacer()

                    // Alt text caption
                    if !altText.isEmpty {
                        Text(altText)
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding()
                    }
                }
            }
        }
        .onExitCommand {
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
    }
}

// MARK: - Convenience initializer for backward compatibility

extension ImageBlockView {
    /// Creates an ImageBlockView without document context (for previews/testing).
    init(data: ImageData) {
        self.data = data
        self.documentURL = nil
        self.maxWidth = nil
    }
}

#Preview("Remote Image") {
    ImageBlockView(data: ImageData(
        source: "https://picsum.photos/800/600",
        altText: "A random image from Picsum"
    ))
    .frame(width: 600)
    .padding()
}

#Preview("Missing Image") {
    ImageBlockView(data: ImageData(
        source: "./missing-image.png",
        altText: "This image doesn't exist"
    ))
    .frame(width: 600)
    .padding()
}
