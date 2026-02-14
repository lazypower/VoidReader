import Foundation

/// Stores and retrieves scroll positions per document.
/// Uses UserDefaults with document path as key.
public final class ScrollPositionStore {
    public static let shared = ScrollPositionStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "scrollPosition_"
    private let maxStoredPositions = 100

    private init() {}

    /// Saves the scroll position for a document.
    /// - Parameters:
    ///   - position: The scroll offset (0.0 to 1.0 normalized, or absolute pixels)
    ///   - documentPath: The file path of the document
    public func savePosition(_ position: Double, for documentPath: String) {
        let key = storageKey(for: documentPath)
        defaults.set(position, forKey: key)

        // Optionally prune old entries
        pruneOldEntriesIfNeeded()
    }

    /// Retrieves the saved scroll position for a document.
    /// - Parameter documentPath: The file path of the document
    /// - Returns: The saved position, or nil if none saved
    public func position(for documentPath: String) -> Double? {
        let key = storageKey(for: documentPath)
        let value = defaults.double(forKey: key)
        // UserDefaults returns 0 for missing keys, but 0 is also a valid position
        // Check if the key actually exists
        return defaults.object(forKey: key) != nil ? value : nil
    }

    /// Removes the saved position for a document.
    /// - Parameter documentPath: The file path of the document
    public func removePosition(for documentPath: String) {
        let key = storageKey(for: documentPath)
        defaults.removeObject(forKey: key)
    }

    /// Clears all saved positions.
    public func clearAll() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Private

    private func storageKey(for documentPath: String) -> String {
        // Use a hash of the path for shorter keys
        let hash = documentPath.hashValue
        return "\(keyPrefix)\(hash)"
    }

    private func pruneOldEntriesIfNeeded() {
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(keyPrefix) }

        // Only prune if we have more than maxStoredPositions
        if allKeys.count > maxStoredPositions {
            // Remove oldest entries (this is a simple approach - in practice you might want timestamps)
            let keysToRemove = allKeys.prefix(allKeys.count - maxStoredPositions)
            for key in keysToRemove {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
