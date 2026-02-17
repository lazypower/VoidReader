import Foundation

/// A warning produced by a lint rule.
public struct LintWarning: Identifiable, Equatable {
    public let id: UUID
    public let line: Int
    public let column: Int
    public let message: String
    public let ruleID: String
    public let severity: Severity

    public init(
        line: Int,
        column: Int,
        message: String,
        ruleID: String,
        severity: Severity = .warning
    ) {
        self.id = UUID()
        self.line = line
        self.column = column
        self.message = message
        self.ruleID = ruleID
        self.severity = severity
    }

    /// Warning severity level.
    public enum Severity: String, CaseIterable {
        case warning
        case error

        public var displayName: String {
            switch self {
            case .warning: return "Warning"
            case .error: return "Error"
            }
        }
    }
}

// MARK: - Comparable for sorting

extension LintWarning: Comparable {
    public static func < (lhs: LintWarning, rhs: LintWarning) -> Bool {
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }
}
