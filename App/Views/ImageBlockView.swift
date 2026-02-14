import SwiftUI
import VoidReaderCore

/// Renders an image with async loading and zoom capability.
struct ImageBlockView: View {
    let data: ImageData
    @State private var isZoomed = false
    @State private var loadedImage: NSImage?
    @State private var isLoading = true
    @State private var loadError: Error?

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
        .task {
            await loadImage()
        }
        .sheet(isPresented: $isZoomed) {
            if let image = loadedImage {
                ImageZoomView(image: image, altText: data.altText, isPresented: $isZoomed)
            }
        }
    }

    private func imageContent(_ image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 600, maxHeight: 400)
                .cornerRadius(8)
                .onTapGesture {
                    isZoomed = true
                }
                .help("Click to zoom")

            if !data.altText.isEmpty {
                Text(data.altText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading image...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
    }

    private var errorView: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
            Text(data.altText.isEmpty ? "Failed to load image" : data.altText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .cornerRadius(8)
    }

    private func loadImage() async {
        isLoading = true
        loadError = nil

        // Try as URL first
        if let url = data.url {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    await MainActor.run {
                        self.loadedImage = image
                        self.isLoading = false
                    }
                    return
                }
            } catch {
                // Fall through to try as file path
            }
        }

        // Try as local file path
        if let image = NSImage(contentsOfFile: data.source) {
            await MainActor.run {
                self.loadedImage = image
                self.isLoading = false
            }
            return
        }

        // Failed to load
        await MainActor.run {
            self.isLoading = false
        }
    }
}

/// Fullscreen zoom view for images.
struct ImageZoomView: View {
    let image: NSImage
    let altText: String
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                Spacer()

                if !altText.isEmpty {
                    Text(altText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onExitCommand {
            isPresented = false
        }
    }
}

#Preview("Loading") {
    ImageBlockView(data: ImageData(
        source: "https://picsum.photos/800/600",
        altText: "A random image"
    ))
    .padding()
}

#Preview("Error") {
    ImageBlockView(data: ImageData(
        source: "invalid-url",
        altText: "This image won't load"
    ))
    .padding()
}
