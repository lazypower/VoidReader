import Testing
import Foundation
@testable import VoidReaderCore

@Suite("Scroll position store")
struct ScrollPositionStoreTests {

    @Test("Storage key is a stable SHA256 hex, not a per-process hashValue")
    func stableSHA256Key() {
        let store = ScrollPositionStore.shared
        let k1 = store.storageKey(for: "/Users/me/doc.md")
        let k2 = store.storageKey(for: "/Users/me/doc.md")
        #expect(k1 == k2)                                          // deterministic
        #expect(store.storageKey(for: "/Users/me/other.md") != k1) // path-specific
        // SHA256 = 32 bytes = 64 hex chars; a hashValue Int would not be.
        let hex = k1.replacingOccurrences(of: "scrollPosition_", with: "")
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { $0.isHexDigit })
    }

    @Test("Round-trips a saved position and removes it")
    func roundTrip() {
        let store = ScrollPositionStore.shared
        let path = "/tmp/voidreader-scrolltest-\(UUID().uuidString).md"
        store.savePosition(0.37, for: path)
        #expect(store.position(for: path) == 0.37)
        store.removePosition(for: path)
        #expect(store.position(for: path) == nil)
    }
}
