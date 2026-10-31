import XCTest
@testable import Futo

final class ColorMathTests: XCTestCase {
    func testHexParsingAndFormatting() {
        XCTAssertEqual(RGB(hex: "#196459")?.value, 0x196459)
        XCTAssertEqual(RGB(hex: "196459")?.hex, "#196459")
        XCTAssertEqual(RGB(hex: " #aBcDeF ")?.hex, "#ABCDEF", "大文字小文字・前後の空白は問わない")
        for bad in ["", "#12345", "#1234567", "#GGGGGG", "red", "#12 456"] { XCTAssertNil(RGB(hex: bad), bad) }
    }

    func testHSBRoundTrip() {
        for value: UInt32 in [0x196459, 0xA25A72, 0x6F5CA3, 0xFFD400, 0x808080, 0x000000, 0xFFFFFF] {
            let rgb = RGB(value)
            let hsb = rgb.hsb
            let back = RGB(h: hsb.h, s: hsb.s, b: hsb.b)
            XCTAssertEqual(back.value, value, String(format: "%06X", value))
        }
    }

    func testMixing() {
        let white = RGB(0xFFFFFF), black = RGB(0x000000)
        XCTAssertEqual(black.mixed(with: white, 0).value, 0x000000)
        XCTAssertEqual(black.mixed(with: white, 1).value, 0xFFFFFF)
        XCTAssertEqual(black.mixed(with: white, 0.5).hex, "#808080")
    }

    func testBrightColorsAreDarkenedUntilButtonTextIsReadable() {
        for value: UInt32 in [0xFFD400, 0xFFFFFF, 0x7CFC00, 0x00FFFF, 0xFFC0CB] {
            let accent = CustomPalette.readableAccent(RGB(value))
            let ratio = (CustomPalette.onAccent.luminance + 0.05) / (accent.luminance + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, String(format: "%06X", value))
        }
        // すでに濃い色は、変えない
        XCTAssertEqual(CustomPalette.readableAccent(RGB(0x196459)).value, 0x196459)
    }

    func testDarkTextAccentIsBrightAndMuted() {
        let text = CustomPalette.darkTextAccent(RGB(0x196459))
        XCTAssertGreaterThan(text.luminance, 0.25, "暗い地の上で、文字として読める")
        XCTAssertLessThanOrEqual(text.hsb.s, 0.42 + 0.001, "蛍光っぽくならないよう、彩度を抑える")
    }

    func testCustomPaletteKeepsTheWarmBaseAndTintsOnlySlightly() {
        let c = CustomPalette.colors(for: RGB(0x6F5CA3))
        XCTAssertEqual(c.backgroundTopLight, 0xFCF8F0)
        XCTAssertEqual(c.cardLight, 0xFFFEFA)
        XCTAssertNotEqual(c.backgroundBottomLight, c.softLight)
        // ダークの地は暗いまま（選んだ色で、明るくなりすぎない）
        for dark in [c.backgroundTopDark, c.backgroundBottomDark, c.cardDark, c.softDark] {
            XCTAssertLessThan(RGB(dark).luminance, 0.06)
        }
    }
}
