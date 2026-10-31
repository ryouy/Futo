import Foundation
import Observation
import SwiftUI

/// 自分のアイコンの設定。この端末に保存し、フレンドに見せるため、サーバーにも送る（変えたときに、反映される）。
/// 何も描かない無印（初期設定）か、山・海・魚などの9個から選ぶ（無印を含めて10個）。色は、テーマの4色から選ぶ（選ばなければ、いまのテーマ色）。
@MainActor
@Observable
final class AvatarSettings {
    static let shared = AvatarSettings()

    /// 色の選択肢の数（テーマ色と同じ4色）
    static let colorCount = 4

    /// 選べるアイコン（山・海・魚など9個。これに、何も描かない無印を加えて10個）。名前は、読み上げ用。
    static let symbols: [(name: String, label: String)] = [
        ("mountain.2.fill", "山"), ("water.waves", "海"), ("fish.fill", "魚"), ("leaf.fill", "葉"), ("tree.fill", "木"),
        ("sun.max.fill", "太陽"), ("moon.stars.fill", "月"), ("bird.fill", "鳥"), ("tortoise.fill", "亀"),
    ]

    private static let colorKey = "avatar.colorIndex"
    private static let symbolKey = "avatar.symbolIndex"
    private static let hexKey = "avatar.customHex"
    @ObservationIgnored private let defaults: UserDefaults

    /// 選んだアイコン（`symbols` の番号）。nil は、何も描かない無印（初期設定）
    var symbolIndex: Int? {
        didSet {
            if let symbolIndex { defaults.set(symbolIndex, forKey: Self.symbolKey) } else { defaults.removeObject(forKey: Self.symbolKey) }
        }
    }

    /// 選んだ色（テーマの4色の番号）。nil は、いまのテーマ色
    var colorIndex: Int? {
        didSet {
            if let colorIndex { defaults.set(colorIndex, forKey: Self.colorKey) } else { defaults.removeObject(forKey: Self.colorKey) }
        }
    }

    /// 好きな色（「#RRGGBB」）。選んでいれば、`colorIndex` より、こちらを使う
    var customHex: String? {
        didSet {
            if let customHex { defaults.set(customHex, forKey: Self.hexKey) } else { defaults.removeObject(forKey: Self.hexKey) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let color = defaults.object(forKey: Self.colorKey) as? Int
        colorIndex = color.flatMap { (0..<Self.colorCount).contains($0) ? $0 : nil }
        customHex = defaults.string(forKey: Self.hexKey).flatMap { RGB(hex: $0) != nil ? $0 : nil }
        let symbol = defaults.object(forKey: Self.symbolKey) as? Int
        symbolIndex = symbol.flatMap { Self.symbols.indices.contains($0) ? $0 : nil }
    }

    /// アイコンの丸の色。`choices` はテーマの4色、`themeColor` はいまのテーマ色。
    func fill(choices: [Color], themeColor: Color) -> Color {
        if let customHex, let rgb = RGB(hex: customHex) { return Color(red: rgb.r, green: rgb.g, blue: rgb.b) }
        if let colorIndex, choices.indices.contains(colorIndex) { return choices[colorIndex] }
        return themeColor
    }

    /// サーバーに送る、いまのアイコン。色を選んでいなければ、いまのテーマ色の番号。
    /// `themeHex` は、アプリの色が「好きな色」のとき、その色（色を選んでいなければ、フレンドにも、その色で見せる）
    func spec(themeIndex: Int, themeHex: String? = nil) -> AvatarSpec {
        if let customHex { return AvatarSpec(symbol: symbolIndex, color: colorIndex ?? themeIndex, hex: customHex) }
        if colorIndex == nil, let themeHex { return AvatarSpec(symbol: symbolIndex, color: themeIndex, hex: themeHex) }
        return AvatarSpec(symbol: symbolIndex, color: colorIndex ?? themeIndex)
    }

    /// サーバーのアイコンを、この端末に取り込む（別の端末で変えたとき）。
    func adopt(_ spec: AvatarSpec) {
        symbolIndex = spec.symbol.flatMap { Self.symbols.indices.contains($0) ? $0 : nil }
        if let hex = spec.hex, RGB(hex: hex) != nil {
            customHex = RGB(hex: hex)?.hex
            colorIndex = nil
        } else {
            customHex = nil
            colorIndex = (0..<Self.colorCount).contains(spec.color) ? spec.color : nil
        }
    }

    func selectPlain() { symbolIndex = nil }

    func selectSymbol(_ index: Int) {
        guard Self.symbols.indices.contains(index) else { return }
        symbolIndex = index
    }

    /// ログアウト・アカウント削除のとき、アイコンの設定を初期に戻す。
    func reset() {
        symbolIndex = nil
        colorIndex = nil
        customHex = nil
    }
}

/// 最後に確認した表示名の控え（この端末だけ）。アプリを開いた直後、サーバーの応答を待たずに、自分のアイコンを出すために使う。
enum ProfileCache {
    private static func key(_ uid: String) -> String { "profile.name.\(uid)" }

    static func name(uid: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(uid)).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func save(name: String, uid: String, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: key(uid))
    }

    static func clear(uid: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(uid))
    }
}
