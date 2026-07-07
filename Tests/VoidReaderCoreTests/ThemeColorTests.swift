import Testing
import SwiftUI
import AppKit
@testable import VoidReaderCore

/// The hex validator (ThemeLoader) and the hex parser (Color(hex:)) used to
/// disagree: the validator accepted #RGB shorthand the parser rendered as black,
/// and the parser handled #AARRGGBB the validator rejected. They must agree.
@Suite("Theme hex color parsing")
struct ThemeColorTests {

    private func rgb(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    @Test("3-digit shorthand expands instead of rendering black")
    func shorthandExpands() {
        let white = rgb(Color(hex: "#fff"))
        #expect(white.r > 0.9 && white.g > 0.9 && white.b > 0.9)

        let red = rgb(Color(hex: "#f00"))
        #expect(red.r > 0.9 && red.g < 0.1 && red.b < 0.1)
    }

    @Test("6-digit still parses correctly")
    func sixDigitParses() {
        let green = rgb(Color(hex: "#00ff00"))
        #expect(green.r < 0.1 && green.g > 0.9 && green.b < 0.1)
    }

    @Test("8-digit ARGB parses to its RGB (alpha ignored)")
    func argbParses() {
        // AA=ff, RR=ff, GG=00, BB=00 → red
        let red = rgb(Color(hex: "#ffff0000"))
        #expect(red.r > 0.9 && red.g < 0.1 && red.b < 0.1)
    }

    @Test("Validator accepts exactly what the parser can render")
    func validatorMatchesParser() {
        #expect("#fff".isValidHexColor)
        #expect("#ffffff".isValidHexColor)
        #expect("#ff0000ff".isValidHexColor)   // 8-digit now accepted
        #expect(!"#gg".isValidHexColor)         // non-hex
        #expect(!"#12345".isValidHexColor)      // unsupported length
    }
}
