import Testing
import CoreGraphics
@testable import VoidReaderCore

@Suite("Scroll Percentage Calculation")
struct ScrollPercentageTests {

    @Test("0% at top of document")
    func zeroAtTop() {
        let percent = ScrollPercentage.calculate(offset: 0, contentHeight: 5000, visibleHeight: 800)
        #expect(percent == 0)
    }

    @Test("100% at bottom of document")
    func hundredAtBottom() {
        // Scrolled to the very end: offset == contentHeight - visibleHeight
        let percent = ScrollPercentage.calculate(offset: 4200, contentHeight: 5000, visibleHeight: 800)
        #expect(percent == 100)
    }

    @Test("50% at midpoint")
    func fiftyAtMidpoint() {
        let percent = ScrollPercentage.calculate(offset: 2100, contentHeight: 5000, visibleHeight: 800)
        #expect(percent == 50)
    }

    @Test("25% at quarter point — the original bug scenario")
    func twentyFiveAtQuarter() {
        // With the old bug (estimatedBlockHeight=60, 100 blocks → totalHeight=6000),
        // a real document with contentHeight=24000 would hit 100% at offset=6000,
        // which is only 25% of the way through.
        // With the fix, 25% of scrollable range should report ~25%.
        let contentHeight: CGFloat = 24000
        let visibleHeight: CGFloat = 800
        let scrollableHeight = contentHeight - visibleHeight  // 23200
        let quarterOffset = scrollableHeight * 0.25  // 5800

        let percent = ScrollPercentage.calculate(
            offset: quarterOffset,
            contentHeight: contentHeight,
            visibleHeight: visibleHeight
        )
        #expect(percent == 25)
    }

    @Test("Content fits in viewport returns 0%")
    func contentFitsInViewport() {
        let percent = ScrollPercentage.calculate(offset: 0, contentHeight: 500, visibleHeight: 800)
        #expect(percent == 0)
    }

    @Test("Content exactly equals viewport returns 0%")
    func contentEqualsViewport() {
        let percent = ScrollPercentage.calculate(offset: 0, contentHeight: 800, visibleHeight: 800)
        #expect(percent == 0)
    }

    @Test("Clamps negative offset to 0%")
    func clampsNegativeOffset() {
        let percent = ScrollPercentage.calculate(offset: -50, contentHeight: 5000, visibleHeight: 800)
        #expect(percent == 0)
    }

    @Test("Clamps overshoot to 100%")
    func clampsOvershoot() {
        // Rubber-band / bounce can produce offset > scrollableHeight
        let percent = ScrollPercentage.calculate(offset: 5000, contentHeight: 5000, visibleHeight: 800)
        #expect(percent == 100)
    }

    @Test("Scales linearly across full range")
    func linearScaling() {
        let contentHeight: CGFloat = 10000
        let visibleHeight: CGFloat = 1000
        let scrollable = contentHeight - visibleHeight  // 9000

        for expected in stride(from: 0, through: 100, by: 10) {
            let offset = scrollable * CGFloat(expected) / 100.0
            let percent = ScrollPercentage.calculate(
                offset: offset,
                contentHeight: contentHeight,
                visibleHeight: visibleHeight
            )
            #expect(percent == expected, "At \(expected)% offset, got \(percent)%")
        }
    }
}
