import Foundation

/// Caches block heights for virtual scrolling with type-based estimates and measured values.
public final class BlockHeightCache: ObservableObject {
    /// Default height estimates by block type
    /// Larger estimates = fewer views created during scroll = better performance
    public static let defaultEstimates: [BlockType: CGFloat] = [
        .text: 80,           // Single paragraph (conservative estimate)
        .codeBlock: 200,     // Medium code block
        .table: 250,         // Small table
        .taskList: 120,      // Few task items
        .image: 300,         // Placeholder for images
        .mermaid: 400,       // Diagram placeholder
        .mathBlock: 120      // Math equation
    ]

    /// Block type classification for height estimation
    public enum BlockType {
        case text
        case codeBlock
        case table
        case taskList
        case image
        case mermaid
        case mathBlock
    }

    /// Type-based estimates (can be tuned)
    private var estimates: [BlockType: CGFloat]

    /// Measured heights by block index
    @Published private var measured: [Int: CGFloat] = [:]

    /// Total count for progress calculation
    public private(set) var blockCount: Int = 0

    public init(estimates: [BlockType: CGFloat] = defaultEstimates) {
        self.estimates = estimates
    }

    /// Get height for a block, preferring measured value over estimate
    public func height(for blockType: BlockType, at index: Int) -> CGFloat {
        if let cached = measured[index] {
            return cached
        }
        return estimates[blockType] ?? 44
    }

    /// Record a measured height for a block
    public func record(index: Int, height: CGFloat) {
        // Only update if significantly different (avoid noise)
        if let existing = measured[index], abs(existing - height) < 2 {
            return
        }
        measured[index] = height
    }

    /// Set the total block count
    public func setBlockCount(_ count: Int) {
        blockCount = count
    }

    /// Get cumulative heights up to (not including) the given index
    public func cumulativeHeight(upTo index: Int, types: [BlockType]) -> CGFloat {
        var total: CGFloat = 0
        for i in 0..<min(index, types.count) {
            total += height(for: types[i], at: i)
        }
        return total
    }

    /// Find the block index at a given scroll offset
    public func findBlock(at scrollOffset: CGFloat, types: [BlockType], spacing: CGFloat = 16) -> Int {
        var cumulative: CGFloat = 0
        for (index, blockType) in types.enumerated() {
            let blockHeight = height(for: blockType, at: index) + spacing
            if cumulative + blockHeight > scrollOffset {
                return index
            }
            cumulative += blockHeight
        }
        return max(0, types.count - 1)
    }

    /// Clear all cached measurements (e.g., when document changes)
    public func clear() {
        measured.removeAll()
    }
}

// MARK: - MarkdownBlock Extension

extension MarkdownBlock {
    /// Get the block type for height estimation
    public var heightType: BlockHeightCache.BlockType {
        switch self {
        case .text: return .text
        case .codeBlock: return .codeBlock
        case .table: return .table
        case .taskList: return .taskList
        case .image: return .image
        case .mermaid: return .mermaid
        case .mathBlock: return .mathBlock
        }
    }

    /// Get estimated height for this block (used for LazyVStack sizing)
    public var estimatedHeight: CGFloat {
        BlockHeightCache.defaultEstimates[heightType] ?? 44
    }
}
