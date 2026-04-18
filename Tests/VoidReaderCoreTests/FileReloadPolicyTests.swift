import Testing
import Foundation
@testable import VoidReaderCore

@Suite("External Change Detector Tests")
struct ExternalChangeDetectorTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_000_100)

    @Test("Suppression wins over a detected change")
    func suppressionWins() {
        let r = ExternalChangeDetector.resolve(
            currentModDate: Self.t1,
            lastKnownModDate: Self.t0,
            isOwnSaveInProgress: true
        )
        #expect(r == .ownSaveInProgress)
    }

    @Test("External change when disk is newer than last-known")
    func detectsExternalChange() {
        let r = ExternalChangeDetector.resolve(
            currentModDate: Self.t1,
            lastKnownModDate: Self.t0,
            isOwnSaveInProgress: false
        )
        #expect(r == .externalChange)
    }

    @Test("No change when disk date equals last-known")
    func noChangeWhenEqual() {
        let r = ExternalChangeDetector.resolve(
            currentModDate: Self.t0,
            lastKnownModDate: Self.t0,
            isOwnSaveInProgress: false
        )
        #expect(r == .noChange)
    }

    @Test("No change when disk date is older than last-known (clock skew / mtime reset)")
    func noChangeWhenDiskOlder() {
        let r = ExternalChangeDetector.resolve(
            currentModDate: Self.t0,
            lastKnownModDate: Self.t1,
            isOwnSaveInProgress: false
        )
        #expect(r == .noChange)
    }

    @Test("No change when current modification date is missing")
    func noChangeWhenCurrentMissing() {
        let r = ExternalChangeDetector.resolve(
            currentModDate: nil,
            lastKnownModDate: Self.t0,
            isOwnSaveInProgress: false
        )
        #expect(r == .noChange)
    }

    @Test("No change when last-known is missing (first-time watch)")
    func noChangeWhenLastKnownMissing() {
        let r = ExternalChangeDetector.resolve(
            currentModDate: Self.t1,
            lastKnownModDate: nil,
            isOwnSaveInProgress: false
        )
        #expect(r == .noChange)
    }
}

@Suite("Save Conflict Policy Tests")
struct SaveConflictPolicyTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_000_100)

    @Test("Safe to save when disk is unchanged since last observed")
    func safeWhenEqual() {
        #expect(SaveConflictPolicy.isSafeToSave(currentModDate: Self.t0, lastKnownModDate: Self.t0))
    }

    @Test("Unsafe to save when disk is newer than last observed")
    func unsafeWhenDiskNewer() {
        #expect(!SaveConflictPolicy.isSafeToSave(currentModDate: Self.t1, lastKnownModDate: Self.t0))
    }

    @Test("Safe to save when disk is older than last observed")
    func safeWhenDiskOlder() {
        #expect(SaveConflictPolicy.isSafeToSave(currentModDate: Self.t0, lastKnownModDate: Self.t1))
    }

    @Test("Safe to save when current mod date is missing (no conflict detectable)")
    func safeWhenCurrentMissing() {
        #expect(SaveConflictPolicy.isSafeToSave(currentModDate: nil, lastKnownModDate: Self.t0))
    }

    @Test("Safe to save when last-known is missing (first save)")
    func safeWhenLastKnownMissing() {
        #expect(SaveConflictPolicy.isSafeToSave(currentModDate: Self.t0, lastKnownModDate: nil))
    }
}
