import Testing
@testable import VoidReaderCore

@Suite("Rendering thresholds")
struct RenderingThresholdsTests {

    @Test("Thresholds are ordered and positive")
    func thresholdsSane() {
        #expect(RenderingThresholds.syncRenderMaxChars > 0)
        #expect(RenderingThresholds.editorVisibleHighlightChars > 0)
        #expect(RenderingThresholds.codeBlockSwiftUITextMaxChars > 0)
        // The no-highlight ceiling is far above the strategy-switch thresholds.
        #expect(RenderingThresholds.maxHighlightChars > RenderingThresholds.syncRenderMaxChars)
    }
}
