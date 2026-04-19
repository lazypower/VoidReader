import Testing
@testable import VoidReaderCore

@Suite("Block Renderer Segmentation")
struct BlockRendererSegmentationTests {

    private func codeBlocks(in blocks: [MarkdownBlock]) -> [CodeBlockData] {
        blocks.compactMap { if case .codeBlock(let data) = $0 { return data } else { return nil } }
    }

    private func lineBlock(lines: Int) -> String {
        (0..<lines).map { "line \($0)" }.joined(separator: "\n")
    }

    @Test("Under-threshold block renders as a single non-segmented block")
    func underThresholdSingleBlock() {
        let code = lineBlock(lines: 10)
        let markdown = "```swift\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count == 1)
        #expect(result[0].segment == nil)
        #expect(result[0].isSegmented == false)
        #expect(result[0].code == code)
    }

    @Test("Exact-boundary block (threshold lines) stays a single block")
    func exactBoundaryStaysSingle() {
        let code = lineBlock(lines: BlockRenderer.segmentationLineThreshold)
        let markdown = "```\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count == 1)
        #expect(result[0].segment == nil)
    }

    @Test("Threshold + 1 splits into two segments")
    func thresholdPlusOneSplitsIntoTwo() {
        let totalLines = BlockRenderer.segmentationLineThreshold + 1
        let code = lineBlock(lines: totalLines)
        let markdown = "```\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count == 2)
        for (i, segment) in result.enumerated() {
            #expect(segment.segment != nil)
            #expect(segment.segment?.indexInGroup == i)
            #expect(segment.segment?.totalInGroup == 2)
        }
        #expect(result[0].segment?.isFirst == true)
        #expect(result[0].segment?.isLast == false)
        #expect(result[1].segment?.isFirst == false)
        #expect(result[1].segment?.isLast == true)
    }

    @Test("All segments of one block share a groupID")
    func segmentsShareGroupID() {
        let code = lineBlock(lines: BlockRenderer.segmentationLineThreshold * 3)
        let markdown = "```python\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count >= 3)
        let firstID = result[0].segment?.groupID
        #expect(firstID != nil)
        for segment in result {
            #expect(segment.segment?.groupID == firstID)
        }
    }

    @Test("10× threshold produces N segments")
    func tenXThresholdProducesN() {
        let factor = 10
        let totalLines = BlockRenderer.segmentationLineThreshold * factor
        let code = lineBlock(lines: totalLines)
        let markdown = "```\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count == factor)
        for (i, segment) in result.enumerated() {
            #expect(segment.segment?.indexInGroup == i)
            #expect(segment.segment?.totalInGroup == factor)
        }
    }

    @Test("fullCode round-trips: join of segment codes == original")
    func fullCodeRoundTrips() {
        let code = lineBlock(lines: BlockRenderer.segmentationLineThreshold * 2 + 57)
        let markdown = "```swift\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count >= 2)
        let joined = result.map(\.code).joined(separator: "\n")
        #expect(joined == code)
        // And every segment carries the same `fullCode`.
        for segment in result {
            #expect(segment.segment?.fullCode == code)
        }
    }

    @Test("Language is preserved across every segment")
    func languagePreservedPerSegment() {
        let code = lineBlock(lines: BlockRenderer.segmentationLineThreshold + 200)
        let markdown = "```rust\n\(code)\n```"
        let result = codeBlocks(in: BlockRenderer.render(markdown))
        #expect(result.count >= 2)
        for segment in result {
            #expect(segment.language == "rust")
        }
    }

    @Test("Mermaid blocks are never segmented")
    func mermaidNotSegmented() {
        let lines = lineBlock(lines: BlockRenderer.segmentationLineThreshold + 100)
        let markdown = "```mermaid\n\(lines)\n```"
        let blocks = BlockRenderer.render(markdown)
        let mermaid = blocks.compactMap { if case .mermaid(let d) = $0 { return d } else { return nil } }
        #expect(mermaid.count == 1)
        #expect(codeBlocks(in: blocks).isEmpty)
    }
}
