import Foundation
import AppKit

/// Handles image loading with path resolution and caching.
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let cache = ImageCache()
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {}

    /// Loads an image, resolving relative paths against the document URL.
    /// - Parameters:
    ///   - source: The image source (relative path, absolute path, or URL)
    ///   - documentURL: The URL of the document containing the image reference
    /// - Returns: The loaded NSImage, or nil if loading failed
    public func loadImage(source: String, documentURL: URL?) async -> NSImage? {
        let resolvedURL = resolveImageURL(source: source, documentURL: documentURL)

        guard let url = resolvedURL else {
            return nil
        }

        let cacheKey = url.absoluteString

        // Check cache first
        if let cached = await cache.image(for: cacheKey) {
            return cached
        }

        // Check if already loading
        if let existingTask = inFlightTasks[cacheKey] {
            return await existingTask.value
        }

        // Start new load task
        let task = Task<NSImage?, Never> {
            let image = await fetchImage(from: url)
            if let image = image {
                await cache.store(image, for: cacheKey, isRemote: !url.isFileURL)
            }
            return image
        }

        inFlightTasks[cacheKey] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: cacheKey)

        return result
    }

    /// Resolves an image source to a full URL.
    private func resolveImageURL(source: String, documentURL: URL?) -> URL? {
        // Try as absolute URL first (http://, https://, file://)
        if let url = URL(string: source), url.scheme != nil {
            return url
        }

        // Try as absolute file path
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        // Resolve relative to document
        guard let docURL = documentURL else {
            // No document context, can't resolve relative path
            return nil
        }

        let documentDirectory = docURL.deletingLastPathComponent()
        let resolved = documentDirectory.appendingPathComponent(source).standardized
        return resolved
    }

    /// Fetches an image from a URL.
    private func fetchImage(from url: URL) async -> NSImage? {
        if url.isFileURL {
            // Local file
            return NSImage(contentsOf: url)
        } else {
            // Remote URL
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                // Verify we got an image content type
                if let httpResponse = response as? HTTPURLResponse {
                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                    let validTypes = ["image/", "application/octet-stream"]
                    guard validTypes.contains(where: { contentType.contains($0) }) || httpResponse.statusCode == 200 else {
                        return nil
                    }
                }

                return NSImage(data: data)
            } catch {
                return nil
            }
        }
    }

    /// Clears the image cache.
    public func clearCache() async {
        await cache.clear()
    }
}

/// Disk-backed image cache.
actor ImageCache {
    private var memoryCache: [String: NSImage] = [:]
    private let cacheDirectory: URL
    private let maxMemoryCacheCount = 50
    private let cacheExpiration: TimeInterval = 24 * 60 * 60 // 24 hours
    private let maxDiskCacheSize: Int = 100 * 1024 * 1024 // 100 MB

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("VoidReader/images", isDirectory: true)

        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Called on first cache access to prune stale entries.
    private var hasPrunedOnStartup = false
    private func pruneOnStartupIfNeeded() {
        guard !hasPrunedOnStartup else { return }
        hasPrunedOnStartup = true
        pruneIfNeeded()
    }

    /// Retrieves an image from cache.
    func image(for key: String) -> NSImage? {
        // Prune on first access
        pruneOnStartupIfNeeded()

        // Check memory cache
        if let image = memoryCache[key] {
            return image
        }

        // Check disk cache
        let fileURL = cacheFileURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check expiration
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > cacheExpiration {
            // Expired, remove it
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        // Load from disk
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        // Store in memory cache
        storeInMemory(image, for: key)

        return image
    }

    /// Stores an image in cache.
    func store(_ image: NSImage, for key: String, isRemote: Bool) {
        // Always store in memory
        storeInMemory(image, for: key)

        // Only cache remote images to disk
        if isRemote {
            storeToDisk(image, for: key)
        }
    }

    /// Clears the cache.
    func clear() {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func storeInMemory(_ image: NSImage, for key: String) {
        // Evict oldest if at capacity
        if memoryCache.count >= maxMemoryCacheCount {
            memoryCache.removeValue(forKey: memoryCache.keys.first!)
        }
        memoryCache[key] = image
    }

    private func storeToDisk(_ image: NSImage, for key: String) {
        let fileURL = cacheFileURL(for: key)

        // Convert to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        try? pngData.write(to: fileURL)

        // Prune if over size limit
        pruneIfNeeded()
    }

    /// Prunes cache if total size exceeds limit, deleting oldest files first.
    private func pruneIfNeeded() {
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        // Get file info sorted by modification date (oldest first)
        var fileInfos: [(url: URL, size: Int, date: Date)] = []
        var totalSize = 0

        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attrs.fileSize,
                  let date = attrs.contentModificationDate else { continue }
            fileInfos.append((url: file, size: size, date: date))
            totalSize += size
        }

        // If under limit, nothing to do
        guard totalSize > maxDiskCacheSize else { return }

        // Sort by date (oldest first) and delete until under limit
        fileInfos.sort { $0.date < $1.date }

        for info in fileInfos {
            guard totalSize > maxDiskCacheSize else { break }
            try? fm.removeItem(at: info.url)
            totalSize -= info.size
        }
    }

    private func cacheFileURL(for key: String) -> URL {
        // Hash the key to create a valid filename
        let hash = key.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(64)
        return cacheDirectory.appendingPathComponent(String(hash) + ".png")
    }
}
