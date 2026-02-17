import Foundation

/// User preferences for markdown formatting.
public struct FormatterOptions: Equatable {
    /// Style for unordered list markers.
    public var listMarker: ListMarkerStyle = .dash

    /// Style for emphasis markers.
    public var emphasisMarker: EmphasisMarkerStyle = .star

    /// Ensure file ends with a single newline.
    public var ensureTrailingNewline: Bool = true

    /// Collapse multiple blank lines to single blank line.
    public var collapseBlankLines: Bool = true

    /// Remove trailing whitespace from lines.
    public var trimTrailingWhitespace: Bool = true

    public init(
        listMarker: ListMarkerStyle = .dash,
        emphasisMarker: EmphasisMarkerStyle = .star,
        ensureTrailingNewline: Bool = true,
        collapseBlankLines: Bool = true,
        trimTrailingWhitespace: Bool = true
    ) {
        self.listMarker = listMarker
        self.emphasisMarker = emphasisMarker
        self.ensureTrailingNewline = ensureTrailingNewline
        self.collapseBlankLines = collapseBlankLines
        self.trimTrailingWhitespace = trimTrailingWhitespace
    }

    /// List marker style options.
    public enum ListMarkerStyle: String, CaseIterable, Identifiable {
        case dash = "-"
        case star = "*"
        case plus = "+"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .dash: return "Dash (-)"
            case .star: return "Asterisk (*)"
            case .plus: return "Plus (+)"
            }
        }

        /// The character to use for list markers.
        public var character: Character {
            Character(rawValue)
        }
    }

    /// Emphasis marker style options.
    public enum EmphasisMarkerStyle: String, CaseIterable, Identifiable {
        case star = "*"
        case underscore = "_"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .star: return "Asterisk (*)"
            case .underscore: return "Underscore (_)"
            }
        }

        /// The character to use for emphasis.
        public var character: Character {
            Character(rawValue)
        }
    }
}
