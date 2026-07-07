import Foundation

/// Decision returned by `ExternalChangeDetector` given the current file-system state
/// and our own save-in-progress flag.
public enum ExternalChangeResolution: Equatable {
    /// File has not changed since we last observed it. No action required.
    case noChange
    /// File was modified externally. Caller should prompt the user to reload.
    case externalChange
    /// Our own save is in progress; treat the filesystem event as ours and
    /// simply refresh the last-known modification date.
    case ownSaveInProgress
}

/// Pure decision function for reacting to file-system change events.
///
/// Extracted from ContentView so the policy can be unit-tested without SwiftUI state.
public enum ExternalChangeDetector {
    public static func resolve(
        currentModDate: Date?,
        lastKnownModDate: Date?,
        isOwnSaveInProgress: Bool
    ) -> ExternalChangeResolution {
        if isOwnSaveInProgress { return .ownSaveInProgress }

        guard let current = currentModDate, let last = lastKnownModDate else {
            // Missing information — conservatively treat as no change.
            return .noChange
        }

        // Any difference in modification date is an external change — not just a
        // *newer* one. `git checkout`, `cp -p`, and mtime-preserving editors can
        // set an equal-or-older mtime; a strict `>` missed those and left the
        // buffer silently stale. (An edit that preserves the mtime exactly still
        // slips through; catching that needs size or content hashing — a follow-up.)
        return current != last ? .externalChange : .noChange
    }
}

/// Pure decision function for the save-time conflict check.
///
/// Returns whether it is safe to overwrite the on-disk file with our current buffer.
public enum SaveConflictPolicy {
    /// Returns `true` if saving is safe (no external change since we last observed).
    public static func isSafeToSave(
        currentModDate: Date?,
        lastKnownModDate: Date?
    ) -> Bool {
        guard let current = currentModDate, let last = lastKnownModDate else {
            // No baseline → cannot detect conflict → allow save.
            return true
        }
        // Safe only if the file is exactly as we last observed it. `current <= last`
        // used to green-light overwriting a *backdated* external change (e.g. a
        // `git checkout` that restored an older mtime), silently clobbering it.
        return current == last
    }
}
