import Foundation

/// 色の計算（画面の部品に頼らない。テストできるよう、Foundation だけで書く）。
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1); self.g = min(max(g, 0), 1); self.b = min(max(b, 0), 1)
    }

    init(_ hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    /// 「#RRGGBB」または「RRGGBB」。それ以外は nil。
    init?(hex text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }), let value = UInt32(s, radix: 16) else { return nil }
        self.init(value)
    }

    var value: UInt32 {
        (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }

    /// 「#RRGGBB」（大文字）
    var hex: String { String(format: "#%06X", value) }

    /// 相対輝度（WCAG）。0（黒）〜1（白）
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// `other` を `amount`（0〜1）だけ混ぜた色
    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// 色相・彩度・明るさ（それぞれ 0〜1）
    var hsb: (h: Double, s: Double, b: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b), d = maxV - minV
        var h = 0.0
        if d > 0 {
            if maxV == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxV == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxV == 0 ? 0 : d / maxV, maxV)
    }

    init(h: Double, s: Double, b: Double) {
        let h = h - floor(h), s = min(max(s, 0), 1), v = min(max(b, 0), 1)
        let c = v * s, x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, bl): (Double, Double, Double)
        switch Int(h * 6) {
        case 0: (r, g, bl) = (c, x, 0)
        case 1: (r, g, bl) = (x, c, 0)
        case 2: (r, g, bl) = (0, c, x)
        case 3: (r, g, bl) = (0, x, c)
        case 4: (r, g, bl) = (x, 0, c)
        default: (r, g, bl) = (c, 0, x)
        }
        self.init(r: r + m, g: g + m, b: bl + m)
    }
}

/// 好きな色から、アプリの配色（アクセント・背景・カード・淡い面）を作る。
/// 既存の4色と同じ考え方：背景は温かい生成り色（ダークは、やわらかい灰色）に、選んだ色をほんのり混ぜる。
enum CustomPalette {
    /// 生成り色の上の文字（ボタンの文字など）。アクセントの上に載せるので、アクセントは、これが読めるだけの濃さにする
    static let onAccent = RGB(0xFFFEFA)

    /// 文字が読める濃さまで、色を暗くする（明るすぎる色を選ばれても、ボタンの文字が読める）
    static func readableAccent(_ picked: RGB) -> RGB {
        var color = picked
        var guardCount = 0
        // コントラスト比 4.5 以上：(1.05) / (L + 0.05) >= 4.5 → L <= 0.183
        while color.luminance > 0.183, guardCount < 40 {
            let hsb = color.hsb
            color = RGB(h: hsb.h, s: hsb.s, b: hsb.b * 0.94)
            guardCount += 1
        }
        return color
    }

    /// ダークの、文字・細い線用のアクセント：同じ色相のまま、くすませて明るくする
    static func darkTextAccent(_ accent: RGB) -> RGB {
        let hsb = accent.hsb
        return RGB(h: hsb.h, s: min(hsb.s, 0.42), b: 0.82)
    }

    struct Colors {
        var accent: UInt32
        var textAccentDark: UInt32
        var backgroundTopLight: UInt32, backgroundBottomLight: UInt32, cardLight: UInt32, softLight: UInt32
        var backgroundTopDark: UInt32, backgroundBottomDark: UInt32, cardDark: UInt32, softDark: UInt32
    }

    static func colors(for picked: RGB) -> Colors {
        let accent = readableAccent(picked)
        let white = RGB(0xFFFFFF)
        return Colors(
            accent: accent.value,
            textAccentDark: darkTextAccent(accent).value,
            backgroundTopLight: RGB(0xFCF8F0).value,
            backgroundBottomLight: white.mixed(with: accent, 0.09).value,
            cardLight: RGB(0xFFFEFA).value,
            softLight: white.mixed(with: accent, 0.14).value,
            backgroundTopDark: RGB(0x2A2B2D).mixed(with: accent, 0.10).value,
            backgroundBottomDark: RGB(0x222324).mixed(with: accent, 0.10).value,
            cardDark: RGB(0x333537).mixed(with: accent, 0.10).value,
            softDark: RGB(0x303234).mixed(with: accent, 0.18).value)
    }
}
